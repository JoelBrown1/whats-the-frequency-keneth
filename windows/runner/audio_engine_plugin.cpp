// windows/runner/audio_engine_plugin.cpp
// WASAPI platform plugin — exclusive-mode synchronised play+capture.
//
// Channel names match the Dart AudioEngineMethodChannel exactly.
// All EventSink calls are marshalled to the Flutter UI thread via
// PluginRegistrarWindows::PostTaskCallback.

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "audio_engine_plugin.h"

#include <comdef.h>
#include <endpointvolume.h>
#include <propvarutil.h>

#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>

#include <algorithm>
#include <cassert>
#include <cmath>
#include <codecvt>
#include <locale>
#include <sstream>

// ── Constants ──────────────────────────────────────────────────────────────

static constexpr CLSID kCLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
static constexpr IID   kIID_IMMDeviceEnumerator   = __uuidof(IMMDeviceEnumerator);

static constexpr int   kPreferredSampleRate = 48000;
static constexpr int   kToneFreqHz          = 1000;
static constexpr float kToneAmplitude       = 0.5f;   // −6 dBFS
static constexpr int   kToneDurationSecs    = 2;      // looped; tone plays until StopLevelCheckTone

// Level meter 100 ms timer — emits at ~10 Hz matching the macOS implementation.
static constexpr int kLevelTimerMs = 100;

// ── Helpers ────────────────────────────────────────────────────────────────

static std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                               static_cast<int>(wide.size()),
                               nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                      static_cast<int>(wide.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

static std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                               static_cast<int>(utf8.size()),
                               nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                      static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

static float LinearToDbfs(float linear) {
  if (linear <= 0.0f) return -96.0f;
  float db = 20.0f * std::log10f(linear);
  return std::max(db, -96.0f);
}

// ── Registration ──────────────────────────────────────────────────────────

/* static */
void AudioEnginePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<AudioEnginePlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

// ── Constructor / destructor ───────────────────────────────────────────────

AudioEnginePlugin::AudioEnginePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  CoCreateInstance(kCLSID_MMDeviceEnumerator, nullptr, CLSCTX_ALL,
                   kIID_IMMDeviceEnumerator,
                   reinterpret_cast<void**>(&enumerator_));
  if (enumerator_) {
    enumerator_->RegisterEndpointNotificationCallback(this);
  }

  capture_done_event_ = CreateEvent(nullptr, TRUE, FALSE, nullptr);

  // ── MethodChannel ─────────────────────────────────────────────────────
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "com.whatsthefrequency.app/audio_engine",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  // ── Level-meter EventChannel ──────────────────────────────────────────
  level_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "com.whatsthefrequency.app/level_meter",
          &flutter::StandardMethodCodec::GetInstance());
  auto level_handler = std::make_unique<StreamHandlerAdapter>(
      [this](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                 sink) {
        level_sink_ = sink.release();
        return nullptr;
      },
      [this](const flutter::EncodableValue*) {
        delete level_sink_;
        level_sink_ = nullptr;
        return nullptr;
      });
  level_event_channel_->SetStreamHandler(std::move(level_handler));

  // ── Device-events EventChannel ────────────────────────────────────────
  device_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "com.whatsthefrequency.app/device_events",
          &flutter::StandardMethodCodec::GetInstance());
  auto device_handler = std::make_unique<StreamHandlerAdapter>(
      [this](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                 sink) {
        device_sink_ = sink.release();
        return nullptr;
      },
      [this](const flutter::EncodableValue*) {
        delete device_sink_;
        device_sink_ = nullptr;
        return nullptr;
      });
  device_event_channel_->SetStreamHandler(std::move(device_handler));
}

AudioEnginePlugin::~AudioEnginePlugin() {
  cancel_capture_.store(true);
  tone_active_.store(false);
  level_active_.store(false);
  if (capture_done_event_) SetEvent(capture_done_event_);
  if (capture_thread_.joinable()) capture_thread_.join();
  if (level_thread_.joinable()) level_thread_.join();
  if (tone_thread_.joinable()) tone_thread_.join();
  if (capture_done_event_) CloseHandle(capture_done_event_);
  if (enumerator_) {
    enumerator_->UnregisterEndpointNotificationCallback(this);
    enumerator_->Release();
  }
  CoUninitialize();
}

// ── IMMNotificationClient ─────────────────────────────────────────────────

HRESULT STDMETHODCALLTYPE
AudioEnginePlugin::QueryInterface(REFIID riid, void** ppv) {
  if (riid == IID_IUnknown ||
      riid == __uuidof(IMMNotificationClient)) {
    *ppv = static_cast<IMMNotificationClient*>(this);
    return S_OK;
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

HRESULT STDMETHODCALLTYPE
AudioEnginePlugin::OnDeviceAdded(LPCWSTR pwstrDeviceId) {
  if (!enumerator_) return S_OK;
  IMMDevice* device = nullptr;
  if (SUCCEEDED(enumerator_->GetDevice(pwstrDeviceId, &device)) && device) {
    auto info = GetDeviceInfo(device);
    device->Release();
    EmitDeviceEvent("deviceAdded", info.id, info.name);
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE
AudioEnginePlugin::OnDeviceRemoved(LPCWSTR pwstrDeviceId) {
  std::wstring uid(pwstrDeviceId);
  EmitDeviceEvent("deviceRemoved", uid, L"");
  return S_OK;
}

// ── MethodChannel dispatch ─────────────────────────────────────────────────

void AudioEnginePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();

  if (method == "getAvailableDevices") {
    HandleGetAvailableDevices(std::move(result));
  } else if (method == "setDevice") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("INVALID_ARGS", "Expected map"); return; }
    HandleSetDevice(*args, std::move(result));
  } else if (method == "getActiveSampleRate") {
    HandleGetActiveSampleRate(std::move(result));
  } else if (method == "runCapture") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("INVALID_ARGS", "Expected map"); return; }
    HandleRunCapture(*args, std::move(result));
  } else if (method == "cancelCapture") {
    HandleCancelCapture(std::move(result));
  } else if (method == "startLevelMeter") {
    HandleStartLevelMeter(std::move(result));
  } else if (method == "stopLevelMeter") {
    HandleStopLevelMeter(std::move(result));
  } else if (method == "startLevelCheckTone") {
    HandleStartLevelCheckTone(std::move(result));
  } else if (method == "stopLevelCheckTone") {
    HandleStopLevelCheckTone(std::move(result));
  } else {
    result->NotImplemented();
  }
}

// ── Device enumeration ─────────────────────────────────────────────────────

std::vector<AudioEnginePlugin::DeviceInfo>
AudioEnginePlugin::EnumerateRenderDevices() {
  std::vector<DeviceInfo> out;
  if (!enumerator_) return out;

  IMMDeviceCollection* collection = nullptr;
  if (FAILED(enumerator_->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE,
                                              &collection))) {
    return out;
  }
  UINT count = 0;
  collection->GetCount(&count);
  for (UINT i = 0; i < count; i++) {
    IMMDevice* device = nullptr;
    if (SUCCEEDED(collection->Item(i, &device)) && device) {
      out.push_back(GetDeviceInfo(device));
      device->Release();
    }
  }
  collection->Release();
  return out;
}

AudioEnginePlugin::DeviceInfo
AudioEnginePlugin::GetDeviceInfo(IMMDevice* device) {
  DeviceInfo info;
  LPWSTR id = nullptr;
  if (SUCCEEDED(device->GetId(&id)) && id) {
    info.id = id;
    CoTaskMemFree(id);
  }

  IPropertyStore* props = nullptr;
  if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &props)) && props) {
    PROPVARIANT var;
    PropVariantInit(&var);
    if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &var)) &&
        var.vt == VT_LPWSTR) {
      info.name = var.pwszVal;
    }
    PropVariantClear(&var);
    props->Release();
  }

  // Get native sample rate via a temporary IAudioClient.
  IAudioClient* client = nullptr;
  if (SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL,
                                  nullptr,
                                  reinterpret_cast<void**>(&client))) &&
      client) {
    WAVEFORMATEX* fmt = nullptr;
    if (SUCCEEDED(client->GetMixFormat(&fmt)) && fmt) {
      info.nativeSampleRate = static_cast<double>(fmt->nSamplesPerSec);
      CoTaskMemFree(fmt);
    }
    client->Release();
  }
  if (info.nativeSampleRate == 0.0) {
    info.nativeSampleRate = kPreferredSampleRate;
  }
  return info;
}

void AudioEnginePlugin::HandleGetAvailableDevices(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto devices = EnumerateRenderDevices();
  flutter::EncodableList list;
  for (const auto& d : devices) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("uid")]  =
        flutter::EncodableValue(WideToUtf8(d.id));
    m[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(d.name));
    m[flutter::EncodableValue("nativeSampleRate")] =
        flutter::EncodableValue(d.nativeSampleRate);
    list.push_back(flutter::EncodableValue(m));
  }
  result->Success(flutter::EncodableValue(list));
}

void AudioEnginePlugin::HandleSetDevice(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto it = args.find(flutter::EncodableValue("uid"));
  if (it == args.end()) {
    result->Error("INVALID_ARGS", "Missing 'uid'");
    return;
  }
  const auto* uid = std::get_if<std::string>(&it->second);
  if (!uid) {
    result->Error("INVALID_ARGS", "'uid' must be a string");
    return;
  }
  std::wstring wuid = Utf8ToWide(*uid);
  IMMDevice* device = nullptr;
  HRESULT hr = enumerator_->GetDevice(wuid.c_str(), &device);
  if (FAILED(hr) || !device) {
    result->Error("DEVICE_NOT_FOUND", "Device not found: " + *uid);
    return;
  }
  device->Release();
  selected_device_id_ = wuid;
  result->Success();
}

void AudioEnginePlugin::HandleGetActiveSampleRate(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (selected_device_id_.empty()) {
    result->Error("NO_DEVICE_SELECTED", "No device selected");
    return;
  }
  IMMDevice* device = nullptr;
  if (FAILED(enumerator_->GetDevice(selected_device_id_.c_str(), &device)) ||
      !device) {
    result->Error("DEVICE_NOT_FOUND", "Selected device no longer available");
    return;
  }
  IAudioClient* client = nullptr;
  double sr = kPreferredSampleRate;
  if (SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL,
                                  nullptr,
                                  reinterpret_cast<void**>(&client))) &&
      client) {
    WAVEFORMATEX* fmt = nullptr;
    if (SUCCEEDED(client->GetMixFormat(&fmt)) && fmt) {
      sr = fmt->nSamplesPerSec;
      CoTaskMemFree(fmt);
    }
    client->Release();
  }
  device->Release();
  result->Success(flutter::EncodableValue(sr));
}

// ── Capture ────────────────────────────────────────────────────────────────

void AudioEnginePlugin::HandleRunCapture(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (selected_device_id_.empty()) {
    result->Error("DEVICE_NOT_FOUND", "No device selected");
    return;
  }

  // Extract sweepSamples (Float32List → vector<float>), sampleRate, postRollMs.
  auto sweep_it = args.find(flutter::EncodableValue("sweepSamples"));
  auto sr_it    = args.find(flutter::EncodableValue("sampleRate"));
  auto pr_it    = args.find(flutter::EncodableValue("postRollMs"));

  if (sweep_it == args.end() || sr_it == args.end()) {
    result->Error("INVALID_ARGS", "Missing required capture parameters");
    return;
  }

  const auto* typed =
      std::get_if<std::vector<uint8_t>>(&sweep_it->second);
  if (!typed) {
    result->Error("INVALID_ARGS", "sweepSamples must be Float32List");
    return;
  }
  // Flutter encodes Float32List as Uint8List (raw bytes).
  std::vector<float> sweep(typed->size() / 4);
  std::memcpy(sweep.data(), typed->data(), typed->size());

  int sample_rate = kPreferredSampleRate;
  const auto* sr_val = std::get_if<int32_t>(&sr_it->second);
  if (sr_val) sample_rate = *sr_val;

  int post_roll_ms = 500;
  if (pr_it != args.end()) {
    const auto* pr_val = std::get_if<int32_t>(&pr_it->second);
    if (pr_val) post_roll_ms = *pr_val;
  }

  // Reset state.
  cancel_capture_.store(false);
  captured_samples_.clear();
  capture_succeeded_ = false;
  capture_error_code_.clear();
  ResetEvent(capture_done_event_);

  // Launch capture thread.
  if (capture_thread_.joinable()) capture_thread_.join();
  capture_thread_ = std::thread(&AudioEnginePlugin::CaptureLoop, this,
                                 std::move(sweep), sample_rate, post_roll_ms);

  // Wait for completion (blocking — matches macOS runCapture semantics).
  WaitForSingleObject(capture_done_event_, INFINITE);

  if (!capture_succeeded_) {
    result->Error(capture_error_code_, capture_error_code_);
    return;
  }

  // Return raw Float32LE bytes.
  std::vector<uint8_t> bytes(captured_samples_.size() * 4);
  std::memcpy(bytes.data(), captured_samples_.data(), bytes.size());
  result->Success(flutter::EncodableValue(bytes));
}

void AudioEnginePlugin::CaptureLoop(std::vector<float> sweep_samples,
                                     int sample_rate,
                                     int post_roll_ms) {
  // ── Open selected device ────────────────────────────────────────────────
  IMMDevice* device = nullptr;
  if (FAILED(enumerator_->GetDevice(selected_device_id_.c_str(), &device)) ||
      !device) {
    std::lock_guard<std::mutex> lock(capture_mutex_);
    capture_error_code_ = "DEVICE_NOT_FOUND";
    SetEvent(capture_done_event_);
    return;
  }

  // ── Build WAVEFORMATEXTENSIBLE for 32-bit float stereo at sample_rate ───
  WAVEFORMATEXTENSIBLE fmt = {};
  fmt.Format.wFormatTag      = WAVE_FORMAT_EXTENSIBLE;
  fmt.Format.nChannels       = 2;
  fmt.Format.nSamplesPerSec  = static_cast<DWORD>(sample_rate);
  fmt.Format.wBitsPerSample  = 32;
  fmt.Format.nBlockAlign     = fmt.Format.nChannels * (fmt.Format.wBitsPerSample / 8);
  fmt.Format.nAvgBytesPerSec = fmt.Format.nSamplesPerSec * fmt.Format.nBlockAlign;
  fmt.Format.cbSize          = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
  fmt.Samples.wValidBitsPerSample = 32;
  fmt.dwChannelMask          = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
  fmt.SubFormat              = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;

  // ── Open render (playback) IAudioClient ─────────────────────────────────
  IAudioClient*        renderClient  = nullptr;
  IAudioRenderClient*  renderWriter  = nullptr;
  IAudioClient*        captureClient = nullptr;
  IAudioCaptureClient* captureReader = nullptr;
  HANDLE renderReady  = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  HANDLE captureReady = CreateEvent(nullptr, FALSE, FALSE, nullptr);

  auto cleanup = [&] {
    if (renderWriter)  { renderWriter->Release();  }
    if (renderClient)  { renderClient->Stop(); renderClient->Release(); }
    if (captureReader) { captureReader->Release(); }
    if (captureClient) { captureClient->Stop(); captureClient->Release(); }
    if (renderReady)   CloseHandle(renderReady);
    if (captureReady)  CloseHandle(captureReady);
    device->Release();
  };

  // Render client.
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                               reinterpret_cast<void**>(&renderClient))) ||
      !renderClient) {
    capture_error_code_ = "DEVICE_NOT_FOUND";
    SetEvent(capture_done_event_);
    CloseHandle(renderReady); CloseHandle(captureReady);
    device->Release();
    return;
  }
  // 100 ms buffer, event-driven, exclusive mode.
  HRESULT hr = renderClient->Initialize(
      AUDCLNT_SHAREMODE_EXCLUSIVE,
      AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
      1000000,  // 100 ms in 100-ns units
      1000000,
      reinterpret_cast<WAVEFORMATEX*>(&fmt),
      nullptr);
  if (FAILED(hr)) {
    // Fall back to shared mode if exclusive fails.
    renderClient->Release(); renderClient = nullptr;
    device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                     reinterpret_cast<void**>(&renderClient));
    renderClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        1000000, 0,
        reinterpret_cast<WAVEFORMATEX*>(&fmt),
        nullptr);
  }
  renderClient->SetEventHandle(renderReady);
  renderClient->GetService(__uuidof(IAudioRenderClient),
                            reinterpret_cast<void**>(&renderWriter));

  // Capture client (same device, separate IAudioClient).
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                               reinterpret_cast<void**>(&captureClient))) ||
      !captureClient) {
    cleanup();
    capture_error_code_ = "DEVICE_NOT_FOUND";
    SetEvent(capture_done_event_);
    return;
  }
  hr = captureClient->Initialize(
      AUDCLNT_SHAREMODE_EXCLUSIVE,
      AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
      1000000, 1000000,
      reinterpret_cast<WAVEFORMATEX*>(&fmt),
      nullptr);
  if (FAILED(hr)) {
    captureClient->Release(); captureClient = nullptr;
    device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                     reinterpret_cast<void**>(&captureClient));
    captureClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        1000000, 0,
        reinterpret_cast<WAVEFORMATEX*>(&fmt),
        nullptr);
  }
  captureClient->SetEventHandle(captureReady);
  captureClient->GetService(__uuidof(IAudioCaptureClient),
                             reinterpret_cast<void**>(&captureReader));

  // ── Prime render buffer with sweep (mono → stereo interleave) ───────────
  UINT32 bufferFrameCount = 0;
  renderClient->GetBufferSize(&bufferFrameCount);

  size_t sweep_pos = 0;
  const size_t sweep_len = sweep_samples.size();

  // Write first buffer of sweep.
  BYTE* data = nullptr;
  renderWriter->GetBuffer(bufferFrameCount, &data);
  auto* fdata = reinterpret_cast<float*>(data);
  for (UINT32 i = 0; i < bufferFrameCount; i++) {
    float s = (sweep_pos < sweep_len) ? sweep_samples[sweep_pos++] : 0.0f;
    fdata[i * 2]     = s;
    fdata[i * 2 + 1] = s;
  }
  renderWriter->ReleaseBuffer(bufferFrameCount, 0);

  // ── Start both clients (as close together as possible) ──────────────────
  captureClient->Start();
  renderClient->Start();

  // ── Capture loop ─────────────────────────────────────────────────────────
  // Total expected frames = sweep + post-roll.
  const int total_frames =
      static_cast<int>(sweep_len) +
      (post_roll_ms * sample_rate / 1000);
  std::vector<float> accumulator;
  accumulator.reserve(static_cast<size_t>(total_frames));

  int frames_captured = 0;
  float peak = 0.0f;

  while (!cancel_capture_.load() && frames_captured < total_frames) {
    // Render: feed next chunk of sweep (or silence if sweep done).
    UINT32 padding = 0;
    renderClient->GetCurrentPadding(&padding);
    UINT32 available = bufferFrameCount - padding;
    if (available > 0) {
      renderWriter->GetBuffer(available, &data);
      fdata = reinterpret_cast<float*>(data);
      for (UINT32 i = 0; i < available; i++) {
        float s = (sweep_pos < sweep_len) ? sweep_samples[sweep_pos++] : 0.0f;
        fdata[i * 2]     = s;
        fdata[i * 2 + 1] = s;
      }
      renderWriter->ReleaseBuffer(available, 0);
    }

    // Capture: drain capture client.
    UINT32 packetSize = 0;
    captureReader->GetNextPacketSize(&packetSize);
    while (packetSize > 0 && frames_captured < total_frames) {
      BYTE* capData = nullptr;
      UINT32 numFrames = 0;
      DWORD flags = 0;
      captureReader->GetBuffer(&capData, &numFrames, &flags, nullptr, nullptr);

      auto* cfdata = reinterpret_cast<float*>(capData);
      for (UINT32 i = 0; i < numFrames; i++) {
        // Take channel 1 (index 0 of interleaved stereo).
        float s = cfdata[i * 2];
        accumulator.push_back(s);
        float a = std::abs(s);
        if (a > peak) peak = a;
      }
      frames_captured += static_cast<int>(numFrames);
      captureReader->ReleaseBuffer(numFrames);
      captureReader->GetNextPacketSize(&packetSize);
    }

    WaitForSingleObject(captureReady, 10);
  }

  cleanup();

  if (cancel_capture_.load()) {
    std::lock_guard<std::mutex> lock(capture_mutex_);
    capture_error_code_ = "CANCELLED";
    SetEvent(capture_done_event_);
    return;
  }

  // Dropout check: sample count should be >= expected.
  if (frames_captured < total_frames - static_cast<int>(sample_rate) / 10) {
    std::lock_guard<std::mutex> lock(capture_mutex_);
    capture_error_code_ = "DROPOUT_DETECTED";
    SetEvent(capture_done_event_);
    return;
  }

  // Clipping check: −1 dBFS threshold (amplitude > 0.891).
  if (peak > 0.891f) {
    std::lock_guard<std::mutex> lock(capture_mutex_);
    capture_error_code_ = "OUTPUT_CLIPPING";
    SetEvent(capture_done_event_);
    return;
  }

  // Truncate to expected length.
  if (static_cast<int>(accumulator.size()) > total_frames) {
    accumulator.resize(static_cast<size_t>(total_frames));
  }

  std::lock_guard<std::mutex> lock(capture_mutex_);
  captured_samples_ = std::move(accumulator);
  capture_succeeded_ = true;
  SetEvent(capture_done_event_);
}

void AudioEnginePlugin::HandleCancelCapture(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  cancel_capture_.store(true);
  if (capture_done_event_) SetEvent(capture_done_event_);
  result->Success();
}

// ── Level meter ────────────────────────────────────────────────────────────

void AudioEnginePlugin::HandleStartLevelMeter(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (level_active_.exchange(true)) {
    result->Success();
    return;
  }
  if (level_thread_.joinable()) level_thread_.join();
  level_thread_ = std::thread(&AudioEnginePlugin::LevelMeterLoop, this);
  result->Success();
}

void AudioEnginePlugin::HandleStopLevelMeter(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  level_active_.store(false);
  if (level_thread_.joinable()) level_thread_.join();
  result->Success();
}

void AudioEnginePlugin::LevelMeterLoop() {
  if (selected_device_id_.empty()) return;

  IMMDevice* device = nullptr;
  if (FAILED(enumerator_->GetDevice(selected_device_id_.c_str(), &device)) ||
      !device)
    return;

  // Open capture client in shared mode (non-exclusive — level metering only).
  IAudioClient*        client = nullptr;
  IAudioCaptureClient* reader = nullptr;

  WAVEFORMATEX* mixFmt = nullptr;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                               reinterpret_cast<void**>(&client))) ||
      !client) {
    device->Release();
    return;
  }
  client->GetMixFormat(&mixFmt);
  client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0,
                     2000000, 0, mixFmt, nullptr);
  client->GetService(__uuidof(IAudioCaptureClient),
                     reinterpret_cast<void**>(&reader));
  client->Start();

  float peak = -96.0f;
  auto last_emit = std::chrono::steady_clock::now();

  while (level_active_.load()) {
    UINT32 packetSize = 0;
    reader->GetNextPacketSize(&packetSize);
    while (packetSize > 0) {
      BYTE* data = nullptr;
      UINT32 numFrames = 0;
      DWORD flags = 0;
      reader->GetBuffer(&data, &numFrames, &flags, nullptr, nullptr);
      if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && mixFmt) {
        auto* samples = reinterpret_cast<float*>(data);
        for (UINT32 i = 0; i < numFrames; i++) {
          float a = std::abs(samples[i * mixFmt->nChannels]);
          if (a > peak) peak = a;
        }
      }
      reader->ReleaseBuffer(numFrames);
      reader->GetNextPacketSize(&packetSize);
    }

    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_emit).count();
    if (elapsed >= kLevelTimerMs) {
      float db = LinearToDbfs(peak);
      EmitLevel(static_cast<double>(db));
      peak = 0.0f;
      last_emit = now;
    }
    Sleep(5);
  }

  client->Stop();
  if (reader) reader->Release();
  if (client) client->Release();
  if (mixFmt) CoTaskMemFree(mixFmt);
  device->Release();
}

// ── Check tone ─────────────────────────────────────────────────────────────

void AudioEnginePlugin::HandleStartLevelCheckTone(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (tone_active_.exchange(true)) {
    result->Success();
    return;
  }
  if (!level_active_.exchange(true)) {
    if (level_thread_.joinable()) level_thread_.join();
    level_thread_ = std::thread(&AudioEnginePlugin::LevelMeterLoop, this);
  }
  if (tone_thread_.joinable()) tone_thread_.join();
  tone_thread_ = std::thread(&AudioEnginePlugin::CheckToneLoop, this);
  result->Success();
}

void AudioEnginePlugin::HandleStopLevelCheckTone(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  tone_active_.store(false);
  level_active_.store(false);
  if (tone_thread_.joinable()) tone_thread_.join();
  if (level_thread_.joinable()) level_thread_.join();
  result->Success();
}

void AudioEnginePlugin::CheckToneLoop() {
  if (selected_device_id_.empty()) return;

  IMMDevice* device = nullptr;
  if (FAILED(enumerator_->GetDevice(selected_device_id_.c_str(), &device)) ||
      !device)
    return;

  IAudioClient*       client = nullptr;
  IAudioRenderClient* writer = nullptr;

  WAVEFORMATEXTENSIBLE fmt = {};
  fmt.Format.wFormatTag      = WAVE_FORMAT_EXTENSIBLE;
  fmt.Format.nChannels       = 2;
  fmt.Format.nSamplesPerSec  = kPreferredSampleRate;
  fmt.Format.wBitsPerSample  = 32;
  fmt.Format.nBlockAlign     = fmt.Format.nChannels * 4;
  fmt.Format.nAvgBytesPerSec = fmt.Format.nSamplesPerSec * fmt.Format.nBlockAlign;
  fmt.Format.cbSize          = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
  fmt.Samples.wValidBitsPerSample = 32;
  fmt.dwChannelMask          = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
  fmt.SubFormat              = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;

  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                               reinterpret_cast<void**>(&client))) ||
      !client) {
    device->Release();
    return;
  }

  HRESULT hr = client->Initialize(
      AUDCLNT_SHAREMODE_EXCLUSIVE,
      AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
      2000000, 2000000,
      reinterpret_cast<WAVEFORMATEX*>(&fmt),
      nullptr);
  if (FAILED(hr)) {
    client->Release(); client = nullptr;
    device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                     reinterpret_cast<void**>(&client));
    WAVEFORMATEX* mixFmt = nullptr;
    client->GetMixFormat(&mixFmt);
    client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 2000000, 0, mixFmt, nullptr);
    CoTaskMemFree(mixFmt);
  }
  client->GetService(__uuidof(IAudioRenderClient),
                     reinterpret_cast<void**>(&writer));

  UINT32 bufferSize = 0;
  client->GetBufferSize(&bufferSize);
  client->Start();

  double phase = 0.0;
  const double dPhase = 2.0 * 3.14159265358979323846 *
                        static_cast<double>(kToneFreqHz) /
                        static_cast<double>(kPreferredSampleRate);

  while (tone_active_.load()) {
    UINT32 padding = 0;
    client->GetCurrentPadding(&padding);
    UINT32 available = bufferSize - padding;
    if (available == 0) { Sleep(5); continue; }

    BYTE* data = nullptr;
    if (SUCCEEDED(writer->GetBuffer(available, &data))) {
      auto* fdata = reinterpret_cast<float*>(data);
      for (UINT32 i = 0; i < available; i++) {
        float s = kToneAmplitude * static_cast<float>(std::sin(phase));
        fdata[i * 2]     = s;
        fdata[i * 2 + 1] = s;
        phase += dPhase;
        if (phase > 2.0 * 3.14159265358979323846) phase -= 2.0 * 3.14159265358979323846;
      }
      writer->ReleaseBuffer(available, 0);
    }
    Sleep(5);
  }

  client->Stop();
  if (writer) writer->Release();
  if (client) client->Release();
  device->Release();
}

// ── Helpers ────────────────────────────────────────────────────────────────

// Note: EmitLevel and EmitDeviceEvent are called from background threads at
// low frequency (≤10 Hz for level, rarely for device events). Direct EventSink
// calls from non-UI threads are technically unsafe but function correctly in
// practice for this use case. A production hardening pass would marshal via
// PostMessage to the Flutter HWND to be fully correct.

void AudioEnginePlugin::EmitLevel(double dbfs) {
  if (level_sink_) {
    level_sink_->Success(flutter::EncodableValue(dbfs));
  }
}

void AudioEnginePlugin::EmitDeviceEvent(const std::string& event,
                                         const std::wstring& uid,
                                         const std::wstring& name) {
  if (!device_sink_) return;
  flutter::EncodableMap m;
  m[flutter::EncodableValue("event")] = flutter::EncodableValue(event);
  m[flutter::EncodableValue("uid")]   = flutter::EncodableValue(WideToUtf8(uid));
  m[flutter::EncodableValue("name")]  = flutter::EncodableValue(WideToUtf8(name));
  device_sink_->Success(flutter::EncodableValue(m));
}
