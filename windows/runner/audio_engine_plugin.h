// windows/runner/audio_engine_plugin.h
// WASAPI platform plugin implementing the audio_engine MethodChannel and
// the level_meter / device_events EventChannels.
//
// Implements the same Dart-facing API as AudioEnginePlugin.swift on macOS.
// Exclusive-mode WASAPI at 48 kHz / 32-bit float (preferred) or 24-bit int.

#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
#include <functiondiscoverykeys_devpkey.h>

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

// ── StreamHandlerAdapter ────────────────────────────────────────────────────
// Adapts a flutter::StreamHandler to use std::function callbacks so we
// can avoid subclassing in the plugin body.

class StreamHandlerAdapter
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  using OnListenFn = std::function<std::unique_ptr<flutter::StreamHandlerError<
      flutter::EncodableValue>>(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>)>;
  using OnCancelFn = std::function<std::unique_ptr<
      flutter::StreamHandlerError<flutter::EncodableValue>>(
      const flutter::EncodableValue*)>;

  StreamHandlerAdapter(OnListenFn on_listen, OnCancelFn on_cancel)
      : on_listen_(std::move(on_listen)),
        on_cancel_(std::move(on_cancel)) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> events)
      override {
    return on_listen_(arguments, std::move(events));
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue* arguments) override {
    return on_cancel_(arguments);
  }

 private:
  OnListenFn on_listen_;
  OnCancelFn on_cancel_;
};

// ── AudioEnginePlugin ────────────────────────────────────────────────────────

class AudioEnginePlugin : public flutter::Plugin,
                          public IMMNotificationClient {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit AudioEnginePlugin(flutter::PluginRegistrarWindows* registrar);
  ~AudioEnginePlugin() override;

  // Non-copyable.
  AudioEnginePlugin(const AudioEnginePlugin&) = delete;
  AudioEnginePlugin& operator=(const AudioEnginePlugin&) = delete;

 private:
  // ── MethodChannel handlers ───────────────────────────────────────────────
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleGetAvailableDevices(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleSetDevice(
      const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleGetActiveSampleRate(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleRunCapture(
      const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleCancelCapture(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStartLevelMeter(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStopLevelMeter(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStartLevelCheckTone(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStopLevelCheckTone(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── IMMNotificationClient ────────────────────────────────────────────────
  HRESULT STDMETHODCALLTYPE
  OnDeviceStateChanged(LPCWSTR, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR pwstrDeviceId) override;
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR pwstrDeviceId) override;
  HRESULT STDMETHODCALLTYPE
  OnDefaultDeviceChanged(EDataFlow, ERole, LPCWSTR) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE
  OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override { return S_OK; }
  ULONG STDMETHODCALLTYPE AddRef() override { return 1; }
  ULONG STDMETHODCALLTYPE Release() override { return 1; }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                            void** ppv) override;

  // ── UI-thread marshalling ─────────────────────────────────────────────────
  // Background threads (level, capture, COM notification) must not call
  // EventSink directly. They push a callable onto pending_ and PostMessage
  // kWmDrainQueue to the Flutter HWND. The top-level window proc delegate
  // handles kWmDrainQueue on the UI thread and drains the queue.
  static constexpr UINT kWmDrainQueue = WM_APP + 1;
  HWND flutter_hwnd_ = nullptr;
  int proc_delegate_id_ = -1;
  std::mutex queue_mutex_;
  std::deque<std::function<void()>> pending_;
  void DrainQueue();

  // ── Helpers ──────────────────────────────────────────────────────────────
  struct DeviceInfo {
    std::wstring id;
    std::wstring name;
    double nativeSampleRate;
  };
  std::vector<DeviceInfo> EnumerateRenderDevices();
  DeviceInfo GetDeviceInfo(IMMDevice* device);

  /// Emit a level value to the level_meter EventSink.
  void EmitLevel(double dbfs);
  /// Emit a device event to the device_events EventSink (thread-safe).
  void EmitDeviceEvent(const std::string& event,
                       const std::wstring& uid,
                       const std::wstring& name);

  // ── Level meter loop (runs on level_thread_) ─────────────────────────────
  void LevelMeterLoop();

  // ── Capture loop (runs on capture_thread_) ───────────────────────────────
  // Plays sweepSamples via render client, captures input, writes result
  // to captureResult_ then signals capture_done_.
  void CaptureLoop(std::vector<float> sweepSamples,
                   int sampleRate,
                   int postRollMs);

  // ── Check-tone loop (runs on tone_thread_) ───────────────────────────────
  void CheckToneLoop();

  // ── Channels ─────────────────────────────────────────────────────────────
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      level_event_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      device_event_channel_;

  flutter::EventSink<flutter::EncodableValue>* level_sink_ = nullptr;
  flutter::EventSink<flutter::EncodableValue>* device_sink_ = nullptr;

  // ── COM state ────────────────────────────────────────────────────────────
  IMMDeviceEnumerator* enumerator_ = nullptr;
  std::wstring selected_device_id_;

  // ── Capture state ────────────────────────────────────────────────────────
  std::atomic<bool> cancel_capture_{false};
  std::thread capture_thread_;
  std::mutex capture_mutex_;
  // Capture result written by capture thread, read by HandleRunCapture.
  std::vector<float> captured_samples_;
  HANDLE capture_done_event_ = nullptr;
  bool capture_succeeded_ = false;
  std::string capture_error_code_;

  // ── Level meter state ────────────────────────────────────────────────────
  std::atomic<bool> level_active_{false};
  std::thread level_thread_;
  std::atomic<float> level_peak_dbfs_{-96.0f};

  // ── Check-tone state ─────────────────────────────────────────────────────
  std::atomic<bool> tone_active_{false};
  std::thread tone_thread_;

  flutter::PluginRegistrarWindows* registrar_;
};
