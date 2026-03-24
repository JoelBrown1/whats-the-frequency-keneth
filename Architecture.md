# Architecture: What's the Frequency, Kenneth

Flutter application for measuring the resonance frequency of guitar pickups using an exciter coil and audio interface.

---

## Overview

A unidirectional signal processing pipeline from hardware I/O to scientific visualization:

```
Scarlett 2i2 (Hardware)
        ↓
Platform Audio Plugin (native Swift / WASAPI)
        ↓
AudioEngineService  →  sweep out / capture in
        ↓
DspPipelineService  →  FFT → transfer function → peak detection
        ↓
MeasurementRepository  →  persistence
        ↓
Flutter UI  →  Setup | Measure | Results | History
```

---

## Hardware Context

- **Audio interface:** Focusrite Scarlett 2i2 (24-bit, 48 kHz, 2-in/2-out USB)
- **Exciter coil:** 41–44 AWG, 100–200 turns, DCR 118–177 Ω, inductance 0.6–1.4 mH
- **Pickup resonance range:** typically 1–15 kHz (user-configurable search band)

**Signal chain:**

```
Scarlett 2i2 headphone out (L channel)
        ↓
Exciter coil (positioned over pickup)
        ↓
Pickup output
        ↓
Scarlett 2i2 input (channel 1)
```

The Scarlett 2i2 headphone output is used as the exciter coil driver. It is suited to this role without external hardware:

| Headphone amp spec | Value | Requirement | Status |
|---|---|---|---|
| Designed load range | 32–300 Ω | 118–177 Ω coil DCR | Pass |
| Output impedance | <10 Ω | <10 Ω for voltage-source drive | Pass |
| Frequency response | ±0.5 dB, 20 Hz–20 kHz | Flat across measurement band | Pass |
| THD+N | <0.01% | Minimal harmonic contamination | Pass |
| Level control | Front panel knob (analog) | Must be set manually — see setup checklist | Note |

> **Headphone knob consistency:** The knob has no digital readback to the host. Its position must remain identical between chain calibration and all subsequent pickup measurements. Mark the knob position with tape or a marker after the level check step. Any adjustment invalidates the calibration and requires a full recalibration.

**Required interface settings before use:**
- Air mode: **off** (both channels)
- Direct monitoring: **disabled**
- OS-level audio enhancements: **disabled**
- Headphone knob: **set via level check tool, then marked and left untouched**

---

## Platform Targets

| Platform | Priority | Audio Backend |
|---|---|---|
| macOS | Tier 1 | Core Audio / AVAudioEngine |
| Windows | Tier 2 | WASAPI |
| iOS | Tier 2 | AVAudioEngine — gated on macOS validation; USB class 2 audio reliability with Camera Connection Kit requires hardware verification |
| Android | Tier 3 | Oboe (USB audio class 2 support fragmented — stretch goal) |

> **iOS note:** Demoted from Tier 1. USB audio class 2 (required by the Scarlett 2i2) on iOS via Camera Connection Kit has historically been unreliable. iOS development is gated on the macOS audio plugin being fully validated against reference hardware first.

**Bundle identifier:** `com.whatsthefrequency.app`
Set this in Xcode (macOS and iOS targets) and in `pubspec.yaml` from Phase 0. All entitlements, notarization certificates, and App Store provisioning profiles are tied to this ID — changing it later requires re-signing and re-provisioning every target.

---

## Key Packages

| Role | Package | Notes |
|---|---|---|
| Audio I/O | Custom platform channel plugin | See critical decision below |
| FFT | `fftea` | Pure Dart; run in persistent worker Isolate |
| Charting | `fl_chart` | Log-axis via data transform |
| State management | `flutter_riverpod` | Scoped providers per screen |
| Persistence | `path_provider` + `dart:io` | JSON per measurement |
| Export | `csv` | CSV compatible with REW / MATLAB / Excel |
| App version | `package_info_plus` | Reads `appVersion` from `pubspec.yaml` at runtime for `Measurement` JSON |
| File write mutex | `synchronized` | Per-repository `Lock` prevents concurrent write races in `MeasurementRepository` and `PickupRepository` |

> **Critical decision:** Do not combine `flutter_pcm_sound` + `flutter_audio_capture`. They use separate audio sessions and will drift relative to each other, corrupting the transfer function. A single `AVAudioEngine` session managing both play and record nodes is required.

---

## Platform Channel API

The Dart facade (`AudioEngineMethodChannel`) and the native implementations (Swift / WASAPI) communicate over two named channels. Both sides must agree on these names and signatures exactly.

### MethodChannel — `com.whatsthefrequency.app/audio_engine`

| Method | Dart args | Returns | Throws |
|---|---|---|---|
| `getAvailableDevices` | — | `List<Map>` — each map: `{'uid': String, 'name': String, 'nativeSampleRate': double}` | — |
| `setDevice` | `{'uid': String}` | `void` | `DEVICE_NOT_FOUND` |
| `getActiveSampleRate` | — | `double` (Hz) | `NO_DEVICE_SELECTED` |
| `runCapture` | `{'sweepSamples': Float32List, 'sampleRate': int, 'postRollMs': int}` | `Uint8List` (Float32LE mono PCM, input channel 1) | `DROPOUT_DETECTED`, `DEVICE_DISCONNECTED`, `SAMPLE_RATE_MISMATCH`, `OUTPUT_CLIPPING` |
| `cancelCapture` | — | `void` | — |
| `startLevelMeter` | — | `void` | — |
| `stopLevelMeter` | — | `void` | — |
| `startLevelCheckTone` | — | `void` | — |
| `stopLevelCheckTone` | — | `void` | — |

> `startLevelCheckTone` plays a 2-second looped 1 kHz sine at −6 dBFS through the headphone output while simultaneously enabling the level meter tap on input channel 1. Use this during the onboarding level check step and the setup screen live meter. `startLevelMeter` alone (no tone) is used during calibration pre-checks where the exciter should be silent.

> `runCapture` is a synchronous-style call that blocks until capture is complete (sweep duration + post-roll). The native side manages the full play+record lifecycle. Dart awaits the `Future` — no polling required.

### EventChannel — `com.whatsthefrequency.app/level_meter`

Streams `double` values (dBFS, input channel 1 peak) at ~10 Hz while the level meter is active. Active between `startLevelMeter` and `stopLevelMeter` calls only.

### EventChannel — `com.whatsthefrequency.app/device_events`

Streams device change notifications as `Map<String, dynamic>`:

```dart
{'event': 'deviceAdded' | 'deviceRemoved', 'uid': String, 'name': String}
```

`AudioEngineService` subscribes to this stream at startup and transitions to `DeviceError` if the active device UID appears in a `deviceRemoved` event.

---

## Core Models

These types form the data contracts between layers. Define them fully in Phase 0 even when values are mocked.

### `SweepConfig`

```dart
class SweepConfig {
  final double f1Hz;            // default: 20.0
  final double f2Hz;            // default: 20000.0
  final double durationSeconds; // default: 3.0
  final int sampleRate;         // default: 48000
  final int sweepCount;         // N sweeps to average; default: 4 (minimum for hum cancellation)
  final int preRollMs;          // default: 512
  final int postRollMs;         // default: 500
}
```

Two `SweepConfig` instances are considered comparable if all fields match. The `sweepConfig` comparability guard compares these field-by-field on overlay.

### `CaptureResult`

```dart
class CaptureResult {
  final Float32List samples;    // mono Float32 PCM, input channel 1
  final int sampleRate;         // Hz — must equal SweepConfig.sampleRate; verify before processing
  final int sweepIndex;         // 0-based index within the N-sweep average
  final DateTime capturedAt;
}
```

The native layer returns raw `Uint8List` (Float32LE). `AudioEngineMethodChannel` reinterprets it as `Float32List` and wraps it in `CaptureResult` before passing to `AudioEngineService`.

### `FrequencyResponse`

```dart
class FrequencyResponse {
  final List<double> frequencyHz;    // 361 log-spaced bins, 20–20000 Hz — computed from constants, not persisted
  final List<double> magnitudeDb;    // magnitude at each bin in dB — persisted in Measurement JSON
  final List<ResonancePeak> peaks;   // all peaks detected above -20 dB relative threshold
  final ResonancePeak primaryPeak;   // highest peak within ResonanceSearchBand
  final SweepConfig sweepConfig;     // config used — stored with result for comparability guard
  final DateTime analyzedAt;
}

class ResonancePeak {
  final double frequencyHz;
  final double magnitudeDb;
  final double qFactor;
  final double fLowHz;               // lower -3 dB point
  final double fHighHz;              // upper -3 dB point
}
```

### `DeviceConfig`

```dart
class DeviceConfig {
  final String deviceUid;
  final String deviceName;
  final int sampleRate;                         // Hz
  final double measuredMainsHz;                 // from idle capture; default 50.0 until measured
  final ResonanceSearchBand resonanceSearchBand; // default: 1000–15000 Hz
  final bool onboardingComplete;
  final String? activeCalibrationId;            // UUID of current ChainCalibration, null if none
}
```

### `ResonanceSearchBand`

```dart
class ResonanceSearchBand {
  final double lowHz;   // default: 1000.0
  final double highHz;  // default: 15000.0
}
```

### `Pickup`

```dart
class Pickup {
  final String id;               // UUID
  final String name;             // user-assigned, e.g. "PAF neck"
  final String? notes;
  final DateTime createdAt;
  final List<String> measurementIds; // ordered by date ascending
}
```

---

## Features

### 1. Device Setup and Calibration

- Enumerate USB audio devices; expose Scarlett 2i2 selection via `getAvailableDevices()` / `setDevice()`
- Store device UID, sample rate, and headphone knob calibration state in `DeviceConfig` (persisted via `SharedPreferences`)
- Hardware setup checklist presented before first measurement:
  - Air mode off (both channels)
  - Direct monitoring disabled
  - OS audio enhancements disabled
  - Headphone knob set and marked

**Level check tool:** Calls `startLevelCheckTone` (`AudioEnginePlatformInterface`), which plays a 2-second looped 1 kHz sine at −6 dBFS through the headphone output while simultaneously tapping input channel 1 for level metering. The `levelCheckToneProvider` (Riverpod `StreamProvider.autoDispose`) starts the tone on subscribe and stops it on dispose, feeding the `LevelMeter` widget via the `levelMeterStream` EventChannel. Guide the user to ~-12 dBFS. Once the correct level is confirmed the user marks the knob and proceeds to chain calibration.

**Chain calibration (`CalibrationService`):**

The full signal chain (headphone amp + exciter coil) has its own frequency-dependent response. This is calibrated out before pickup measurements:

1. Replace the pickup with a known resistive load (10 kΩ) at the coil position
2. **Pre-calibration signal check:** with the exciter active, verify that input signal is below -40 dBFS. A pickup still connected produces a response well above this floor; the resistor does not. If the check fails, surface a `RecoverableError`: *"A pickup signal is still present — replace the pickup with the 10 kΩ resistor before calibrating."* Without this check, running calibration with the pickup connected silently embeds the pickup's resonance into `H_chain`, producing an inverted ghost peak in every subsequent measurement.
3. Run a full log-sine sweep; capture `Y_ref(f)`
3. Compute chain response: `H_chain(f) = Y_ref(f) / X(f)`
4. Store `H_chain(f)` with timestamp and a UUID `calibrationId` in `DeviceConfig`

During pickup measurement, the chain response is divided out:

```
H_pickup(f) = H_measured(f) / H_chain(f)
```

Calibration is invalidated and must be re-run if:
- The headphone knob is adjusted
- Cables are changed
- The coil is repositioned
- Calibration is older than 30 minutes (configurable warning threshold)

### 2. Sweep Signal Generation

Log-sine sweep pre-computed as `Float64List` at startup:

```
θ(t) = 2π * f1 * T/ln(f2/f1) * (exp(t * ln(f2/f1) / T) - 1)
x(t) = sin(θ(t))
```

| Parameter | Value |
|---|---|
| f1 | 20 Hz |
| f2 | 20 kHz |
| Duration (T) | 3 seconds |
| Sample rate (Fs) | 48,000 Hz |
| Total samples | 144,000 (~1.1 MB) |

The inverse filter for deconvolution is pre-computed at the same time (time-reversed sweep with amplitude envelope correction `~exp(-t * ln(f2/f1) / T)`).

### 3. Measurement Capture

**State machine:**

```
Idle ←──────────── reset() ──────────────────────────┐
  ↓                                                    │
Armed → Playing → Capturing → Analyzing → Complete   Error
                                               ↑       │
                                       RecoverableError │
                                       DeviceError ─────┘
```

Error types:

| Type | Examples | Recovery |
|---|---|---|
| `RecoverableError` | Dropout, level too low, sweep misaligned, output clipping, `AppBackgrounded`, `Interrupted` | Prompt retry → back to `Armed` |
| `DeviceError` | Device disconnected, sample rate mismatch | Prompt reconnect → back to `Idle` |
| `FatalError` | Plugin crash, OOM | Log diagnostic, require app restart |

**Checkpoint persistence:** `CaptureCheckpointService` writes each accepted capture atomically to `{appSupportDir}/checkpoints/{index}.f32` (raw Float32LE PCM) plus `meta.json` (serialised `SweepConfig`). On measurement start, if a checkpoint exists and the stored config matches the current config, previously-captured sweeps are loaded and the loop resumes from `pass = preloaded.length`. If the config has changed the checkpoint is discarded. The checkpoint is cleared on successful DSP completion and on user cancel.

Capture flow:

0. **Sweep clipping check:** play a 1-second excerpt of the sweep at maximum amplitude and capture on input channel 1; if any sample exceeds -1 dBFS, abort with `RecoverableError` — prompt the user to turn the headphone knob down slightly and recalibrate
1. Pre-roll silence (512 ms) to flush interface buffers
2. Schedule playback and input tap to start on the same `AVAudioTime` render cycle (sample-accurate co-start)
3. Stop after sweep duration + post-roll (500 ms)
4. **Cross-correlation alignment** (`computeAlignmentOffset` in `dsp_isolate.dart`, run via `Isolate.run()`): FFT-based cross-correlation `C = IFFT(FFT(capture) × conj(FFT(inverseFilter)))`, peak searched within ±500 samples. **Sweep 0 handling:** the first sweep's offset is validated to be within ±500 samples (plausible USB round-trip range); if outside, sweep 0 is discarded and retried without counting the pass. The validated offset is stored as the baseline. Sweeps 1–N are discarded and retried if offset differs from the baseline by more than ±2 samples.
5. Validate sample count; flag dropouts
6. N-sweep averaging: accumulate aligned captures in time domain before FFT

Dropout detection is mandatory — USB audio devices can glitch. The app must warn the user rather than silently present corrupt data.

**Hum mitigation (N ≥ 4 sweeps):** Use golden-ratio sweep spacing to cancel mains harmonics across the average:

```dart
// mainsHz is DeviceConfig.measuredMainsHz (measured, not a nominal constant)
const phi = 1.6180339887;
final interSweepMs = 1000 + ((1.0 / mainsHz) / phi * 1000).round();
await Future<void>.delayed(Duration(milliseconds: interSweepMs));
```

### 4. DSP Pipeline

Runs in a **persistent worker Isolate** (initialized once at app startup, reused for all measurements and level-check FFT frames):

```dart
class DspWorker {
  late final SendPort _sendPort;
  late final SendPort _cancelSendPort;
  final _receivePort = ReceivePort();

  Future<void> init() async {
    await Isolate.spawn(_workerEntryPoint, _receivePort.sendPort);
    // Worker sends back two ports: work port and cancel port
    final ports = await _receivePort.first as (SendPort, SendPort);
    _sendPort = ports.$1;
    _cancelSendPort = ports.$2;
  }

  Future<FrequencyResponse> process(CaptureResult capture) async {
    final reply = ReceivePort();
    _sendPort.send((capture, reply.sendPort));
    return await reply.first as FrequencyResponse;
  }

  /// Signals the worker to exit the current pipeline early.
  /// The worker polls its cancel port between each of the 10 pipeline stages.
  void cancel() => _cancelSendPort.send(null);
}
```

Pipeline steps:

1. **Deconvolution:** convolve captured signal with pre-computed inverse filter in time domain → causal impulse response `h(t)`
2. **Window:** apply Hann window to `h(t)` over 4096 samples to suppress leakage
3. **FFT:** transform windowed `h(t)` → `H(f)` (complex)
4. **Chain correction:** divide by stored `H_chain(f)` → `H_pickup(f)`
5. **Regularization:** apply Tikhonov regularization at low-energy bins to prevent instability at band edges: `H[i] = Y[i] * conj(X[i]) / (|X[i]|² + ε²)`
6. **Magnitude response:** `|H_pickup(f)|` in dB
7. **Frequency taper:** cosine fade over 20–80 Hz and 10–20 kHz where pickup response and sweep energy are both weakest
8. **Smoothing:** Savitzky-Golay or moving average in log-frequency space
9. **Peak detection:** find all peaks above -20 dB relative to max within the user-configured `ResonanceSearchBand`
10. **Q-factor:** for each peak, find -3 dB points `f_low`, `f_high` → `Q = f₀ / (f_high - f_low)`

FFT size: zero-pad 144,000 samples to 2^18 = 262,144 → ~1.8 Hz frequency resolution.

Swap to `AccelerateFftProvider` via the `FftProvider` abstraction if `fftea` performance is insufficient — no changes outside `fft_provider.dart` are needed.

**Spectral hum suppression (optional, user-configurable):** interpolate linearly across ±10 bins around each of the first 39 mains harmonics before peak detection.

### 5. Results Visualization

- Log-frequency chart: 100 Hz – 20 kHz x-axis, magnitude dB y-axis
- Log-axis implementation: pre-transform x-coords to `log10(f)`; custom label formatter displays `100`, `200`, `500`, `1k`, `2k`, `5k`, `10k`, `20k`
- All detected peaks annotated; primary resonance peak highlighted
- **Cursor readout on tap:** inverse log transform applied at gesture layer to display actual frequency in Hz:

```dart
double chartXToFrequency(double chartX, double chartWidth) {
  final logMin = log10(minFrequency);
  final logMax = log10(maxFrequency);
  final logF = logMin + (chartX / chartWidth) * (logMax - logMin);
  return pow(10, logF).toDouble();
}
```

- Configurable `ResonanceSearchBand` displayed as shaded region on chart
- Up to 5 overlaid measurements with distinct colors for comparison

### 6. History and Export

- Each measurement persisted as JSON in `measurements/<uuid>.json`
- All JSON passed through `MeasurementMigrator` on load to handle schema evolution
- History screen: list sortable by date or resonance frequency
- CSV export: `(frequency_hz, magnitude_db)` per measurement — compatible with REW, MATLAB, Excel

**Measurement JSON fields:**
`schemaVersion`, `id`, `timestamp`, `pickupLabel`, `pickupId`, `sweepConfig`, `resonanceSearchBand`, `magnitudeDB[]`, `resonanceFrequencyHz`, `qFactor`, `hardware` (interface device name, interface UID, calibration ID, calibration timestamp, app version)

> **`frequencyBins[]` is not stored.** The 361 log-spaced frequency values are fully determined by the algorithm constants (`f1=20 Hz`, `f2=20 kHz`, `bins=361`) and are recomputed at load time. Storing them in every file wastes space and creates a schema migration hazard if bin spacing changes in a future release. `MeasurementRepository` reconstructs the frequency axis when deserialising a `FrequencyResponse` for display.

**Hardware metadata block:**
```json
{
  "hardware": {
    "interfaceDeviceName": "Scarlett 2i2 USB",
    "interfaceUID": "AppleUSBAudioEngine:...",
    "calibrationId": "<uuid>",
    "calibrationTimestamp": "2026-03-21T10:32:00Z",
    "appVersion": "1.0.0"
  }
}
```

`appVersion` is read from `pubspec.yaml` at runtime via `package_info_plus`. If a DSP algorithm change shifts resonance values in a future release, stored measurements can be attributed to a specific build without re-analysing every file.

**Schema migration:**

```dart
class MeasurementMigrator {
  static const currentSchemaVersion = 1;
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    final version = json['schemaVersion'] as int? ?? 0;
    if (version < 1) json = _v0ToV1(json);
    return json;
  }
}
```

### 7. Results Screen

The results screen is shown immediately after a successful measurement completes (`Analyzing → Complete` transition). It is the primary output surface of the app.

**Content:**
- `FrequencyResponseChart` — full-width, log-axis, all detected peaks annotated, primary resonance highlighted
- `ResonanceSummaryCard` — resonance frequency in Hz (large), Q-factor, measurement timestamp, pickup label
- `ResonanceSearchBand` shaded region on chart

**Actions:**
- **Save** — prompts for pickup name (pre-filled if a `Pickup` entity was selected before measuring); writes `Measurement` JSON atomically; associates with `Pickup` via `pickupId`; navigates to History screen on confirmation
- **Discard** — returns to Measure screen without saving; requires confirmation if a valid result was produced
- **Overlay** — opens a `Pickup` or date picker to select a previously saved measurement; overlays it on the chart with a distinct colour; up to 5 overlaid measurements; applies `sweepConfig` comparability check before rendering
- **Export** — writes CSV via `CsvExporter`; opens system share sheet

**Navigation:** Reached only from the `Complete` state of `AudioEngineService`. Not reachable from the tab bar directly — use History screen to revisit saved results. Back navigation from Results discards the unsaved result (with confirmation).

---

## Considerations

### Platform

#### Permissions and Entitlements

Microphone access must be explicitly declared on all Apple platforms — without the correct entitlements the app silently fails to capture audio.

**macOS** — add to both `Release.entitlements` and `DebugProfile.entitlements`:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.usb</key>
<true/>
```
The USB entitlement is required for Core Audio device enumeration under App Sandbox. Without it the Scarlett 2i2 may not appear in the device list.

**iOS** — add to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required to capture the pickup response signal.</string>
```
The App Store will reject the binary without this key.

#### Minimum OS Version Targets

Several APIs in the plan (`AVAudioTime` scheduling, Core Audio device enumeration under App Sandbox) require specific minimum OS versions. Without explicit targets, `flutter build` succeeds but the app may crash on older OS versions in the field.

Define in `pubspec.yaml` and Xcode deployment targets:

| Platform | Minimum | Rationale |
|---|---|---|
| macOS | 12.0 (Monterey) | `AVAudioEngine` routing stability; Apple Silicon native builds |
| iOS | 16.0 | USB audio class 2 reliability via Camera Connection Kit |
| Windows | 10 (build 19041) | WASAPI exclusive mode; Flutter Windows stable baseline |

#### App Lifecycle and Background Handling

On iOS, the OS suspends audio sessions when the app moves to the background (home button, incoming call UI). If this happens mid-sweep, capture silently stops — dropout detection catches it, but the `RecoverableError` transition must be triggered before the OS kills the audio session.

- Subscribe to `UIApplication.willResignActiveNotification` (iOS) and `NSApplication.willResignActiveNotification` (macOS)
- On receipt: if state is `Playing` or `Capturing`, immediately abort and transition to `RecoverableError(AppBackgrounded)`
- On `didBecomeActiveNotification`: re-activate the audio session and offer retry

#### iCloud Backup Exclusion (iOS)

On iOS, the app's documents directory is backed up to iCloud by default. A collection of measurements could meaningfully impact the user's iCloud storage quota.

Use `getApplicationSupportDirectory()` instead of `getApplicationDocumentsDirectory()` for measurement storage — the support directory is excluded from iCloud backup by default on iOS. If the documents directory must be used for any reason, apply the `com.apple.MobileBackup` xattr to the `measurements/` folder at creation time.

#### macOS Sandbox File Access for CSV Export

The `com.apple.security.device.audio-input` and `com.apple.security.device.usb` entitlements are already defined. However, allowing the user to choose a CSV save location via a file picker requires an additional entitlement:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

`user-selected.read-write` allows `NSSavePanel`; without it the panel is blocked under App Sandbox. `downloads.read-write` is required for writing directly to `~/Downloads` via `getDownloadsDirectory()` — the app's primary CSV export path. Both are present in `Release.entitlements` and `DebugProfile.entitlements`. If the Mac App Store route is pursued, both entitlements require a usage justification in the App Store review notes.

#### Apple Privacy Manifest (`PrivacyInfo.xcprivacy`)

Since May 2024, App Store Connect rejects binaries that call "required reason" APIs without a privacy manifest declaring the reason codes. This app will call at least two such API categories:

| API category | Usage | Required reason code |
|---|---|---|
| `UserDefaults` | `SharedPreferences` for `DeviceConfig` and `onboardingComplete` | `CA92.1` (app functionality) |
| File timestamp APIs | Calibration age check (`ChainCalibration` timestamp) | `C617.1` (app functionality) |

Add a `PrivacyInfo.xcprivacy` file to both `macos/Runner/` and `ios/Runner/` declaring each accessed API and its reason code. Without this file, both TestFlight upload and App Store submission fail at the binary validation step — it cannot be added retroactively after build.

---

### Audio

#### PCM Transfer Strategy

Streaming raw PCM from native to Dart via `EventChannel` during capture introduces Flutter codec serialization overhead on every audio buffer callback (~every 10 ms). At audio rates this can cause latency spikes and buffer drops.

**Preferred approach:** Capture the full sweep natively into a pre-allocated native buffer, then transfer the completed buffer to Dart as a single `Uint8List` via `MethodChannel` after capture is complete. This keeps the hot audio path entirely native and eliminates codec overhead during recording.

```swift
// Swift — capture into native buffer, transfer once complete
func captureComplete(_ samples: [Float]) -> FlutterStandardTypedData {
    return FlutterStandardTypedData(float32: Data(bytes: samples, count: samples.count * 4))
}
```

#### AVAudioTime Scheduling Look-Ahead Margin

The co-start requires scheduling both playback and capture to a future `AVAudioTime`. USB devices have non-deterministic scheduling latency — if the scheduled time is too close to `now`, the engine silently misses it and starts one render buffer late. Both nodes still start in the same render cycle relative to each other (preserving synchronisation), but the absolute start is shifted by one buffer duration, affecting the cross-correlation baseline on the first sweep.

The look-ahead margin must satisfy:
- **Minimum:** greater than the longest observed USB round-trip scheduling jitter (~20–50 ms for the Scarlett 2i2)
- **Maximum:** small enough not to add perceptible latency to the user experience

**Required:** Set the initial look-ahead to 100 ms (`AVAudioFrameCount` of 4,800 samples at 48 kHz). Measure the actual achieved start time via the render timestamp on the first recorded buffer and log the delta. If the delta exceeds 10 ms on any measurement session, surface a diagnostic warning in the log file. After hot-plug reconnection, double the look-ahead to 200 ms for the first sweep (the engine timeline may be less stable immediately after reconnect).

#### Level Meter EventChannel Rate Limiting

The level meter EventChannel is specified as ~10 Hz. Without explicit throttling, the native audio buffer callback (firing at ~100 Hz at 512 samples/48 kHz) will forward every buffer peak to the Flutter UI thread at the full buffer rate. At 100 Hz, the UI thread is saturated rebuilding the level meter widget during the level check phase, causing jank in the surrounding setup flow.

The native side must debounce to a fixed 100 ms timer before emitting — computing the peak dBFS across all buffers received within the window and emitting a single value:

```swift
// Swift — emit at fixed interval, not on every buffer
var levelTimer: Timer?
var peakDbfs: Float = -96.0

func startLevelTimer() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        self.eventSink?(self.peakDbfs)
        self.peakDbfs = -96.0 // reset after each emit
    }
}
```

#### Audio Session Interruptions

Other apps can take audio focus mid-measurement (phone calls, notifications, Spotlight). Without interruption handling, a mid-sweep interruption produces a corrupt capture that may pass dropout detection.

- Subscribe to `AVAudioSession.interruptionNotification` (iOS) and `AVAudioEngine` configuration change notifications (macOS)
- On interruption: immediately transition to `RecoverableError(Interrupted)`, notify the user, offer retry
- On interruption end: re-activate the audio session before allowing retry

#### Sample Rate Negotiation

The app assumes 48 kHz is available. The OS honours whatever sample rate was last set by another app or the device's native rate. If the system is running at 44.1 kHz or 96 kHz the app will capture at the wrong rate, producing a frequency-shifted result with no obvious error.

After `AVAudioEngine` starts, verify the active hardware sample rate matches 48 kHz. If it does not, surface a `DeviceError` with an explicit instruction to set the Scarlett 2i2 to 48 kHz in Focusrite Control before retrying. Do not attempt silent sample rate conversion — it adds DSP complexity and the user can fix it in 10 seconds.

#### USB Hot-Plug Detection

Without subscribing to device change events, the state machine will hang or produce garbage data if the Scarlett 2i2 is unplugged mid-sweep.

- **macOS:** `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDevices` — fires when any audio device is added or removed
- **iOS:** `AVAudioSession.routeChangeNotification` with reason `oldDeviceUnavailable`

On receipt, check whether the active device UID is still present. If not, cancel the current capture and transition to `DeviceError`.

#### WASAPI Mode — Exclusive vs Shared (Windows)

In WASAPI shared mode, the Windows Audio Session API routes audio through the OS audio engine, which may resample to the system mix format. If the mix rate differs from 48 kHz (e.g. 44.1 kHz or 96 kHz), every frequency in the measurement is shifted proportionally — a systematic error with no obvious warning.

The Windows plugin must request WASAPI exclusive mode at 48 kHz / 24-bit:
- In exclusive mode, the app owns the device directly and the OS does not resample
- If the device is already held in exclusive mode by another app, `AUDCLNT_E_DEVICE_IN_USE` is returned — surface this as a `DeviceError` with the message: *"Close Focusrite Control (or any other app using the Scarlett 2i2) and try again."* Focusrite Control is the most likely culprit and should be named explicitly.
- Shared mode is not acceptable for this application and must not be used as a fallback

#### Audio I/O Buffer Size

Neither the macOS nor Windows plugin specifies the hardware I/O buffer size. The macOS default is ~512 samples (~10.7 ms at 48 kHz), but Focusrite Control can override it to values as large as 4,096 samples (~85 ms). An unexpectedly large buffer increases the effective pre-roll required to flush the interface and changes dropout detection thresholds — but using a hardcoded pre-roll tuned for 512-sample buffers will produce silent failures on other configurations.

**Required:** After the engine starts, read the active hardware buffer size from the device and compute pre-roll dynamically:

```swift
let bufferDuration = AVAudioSession.sharedInstance().ioBufferDuration // iOS
// macOS: query kAudioDevicePropertyBufferFrameSize via CoreAudio HAL
let preRollSamples = bufferSize * 4  // flush at least 4 buffer cycles
```

Use the measured buffer size for pre-roll, dropout detection window, and co-start scheduling headroom.

#### AVAudioEngine Reconnection After Hot-Plug

`AVAudioEngine` cannot be reconfigured while running. After a `deviceRemoved` event, the engine is in an inconsistent state. The reconnection sequence must follow this exact order or the engine produces silence or errors with no clear cause:

1. Stop the engine: `engine.stop()`
2. Detach all nodes: `engine.detach(playerNode)`, `engine.detach(inputNode)` (input node detach is implicit on reset)
3. Reset the engine: `engine.reset()`
4. Wait ~150 ms for Core Audio to settle after the device change notification
5. Re-attach nodes and reconnect the audio graph
6. Set the new device UID via Core Audio HAL property
7. Restart: `try engine.start()`
8. Verify sample rate before allowing `Armed` transition

Skipping step 4 (the settle delay) causes `engine.start()` to succeed but the device to produce no output — a silent failure that is difficult to diagnose.

---

### DSP

#### FFT Provider Abstraction

`fftea` is a small package with limited maintenance history. If it is abandoned or breaks with a future Dart SDK the entire DSP pipeline is blocked.

Wrap all FFT calls behind an abstraction from day one:

```dart
abstract class FftProvider {
  List<Complex> forward(List<double> samples);
  List<double> inverse(List<Complex> spectrum);
}

class FfteaFftProvider implements FftProvider { ... }
class AccelerateFftProvider implements FftProvider { ... } // native, Phase 3+
```

Benchmark `fftea` against the native Accelerate framework (Apple) early in Phase 1. On Apple Silicon the native path may be 20–50× faster, making it the better default for the macOS Tier 1 target.

#### Mains Frequency Measurement

The spectral hum suppression interpolates across ±10 bins around mains harmonics. Mains frequency drifts, and at higher harmonic numbers even small deviations shift a harmonic outside the ±10-bin window, leaving hum uncancelled.

Add a "Measure mains frequency" step to the onboarding flow and setup screen:
- Capture 5 seconds of idle input (no sweep playing)
- FFT the capture and identify the dominant low-frequency peak
- Store the measured value (e.g. 49.97 Hz) in `DeviceConfig`
- Use the measured value — not the nominal — for all hum suppression and golden-ratio spacing calculations

Surface this as a one-tap step in setup, similar to the Pickup Wizard's FFT Analyzer tool.

#### Sweep Clipping Check

The level check tool plays a 1 kHz sine tone, but the actual log-sine sweep has a different amplitude profile. The headphone amp may clip at certain frequencies even if the 1 kHz tone passed cleanly.

Before every full measurement run, play a 1-second excerpt of the sweep at maximum amplitude and capture on input channel 1. If any sample exceeds -1 dBFS, surface a `RecoverableError`:

> "Output is clipping — turn the headphone knob down slightly and recalibrate."

This runs automatically as step 0 of the `Armed` state transition (see Measurement Capture above).

#### DSP Tuning Parameters

Three values are named in the pipeline but never given defaults. All three require empirical tuning against real pickup measurements — but a starting baseline must be documented so all contributors begin from the same point and deviations are intentional.

| Parameter | Role | Starting value | Risk if wrong |
|---|---|---|---|
| Tikhonov ε | Regularization at low-energy bins during chain division | `1e-3` (relative to max `\|X\|`) | Too small → division instability at band edges; too large → real signal suppressed |
| Savitzky-Golay window | Smoothing in log-frequency space | 11 bins (≈ 1/3 octave at mid-frequencies) | Too wide → peak shift and Q underestimate; too narrow → noise not removed |
| Peak detection threshold | Minimum peak height relative to max | -20 dB | Too tight → misses secondary resonances; too loose → noise peaks reported as resonances |

Validate each against the synthetic 4 kHz Q=3 pickup model in Phase 1 unit tests before using real hardware.

#### `TransferableTypedData` for Isolate PCM Transfer

Sending a 144,000-sample `Float32List` (576 KB) through `SendPort` copies the entire buffer on each sweep. At N=4 sweeps that is 2.3 MB of copies per measurement, plus the GC pressure from the discarded originals.

`TransferableTypedData` transfers ownership without copying:

```dart
// Sending side
final transferable = TransferableTypedData.fromList([samples]);
sendPort.send(transferable);
// samples is now invalid — do not read after this line

// Receiving side (in Isolate)
final samples = message.materialize().asFloat32List();
```

Use `TransferableTypedData` for all PCM buffer transfers from `AudioEngineMethodChannel` to `DspWorker`. The buffer is discarded after transfer anyway, so the ownership semantics are a natural fit.

#### SweepConfig Mutation During Measurement

If the user changes sweep parameters from the Settings screen while a measurement is in progress, the pre-computed `Float64List` sweep and its inverse filter become inconsistent with the in-flight `CaptureResult`. The DSP pipeline will produce a corrupted result with no obvious error.

**Required:** `SweepConfig` must be treated as immutable for the duration of a measurement session:
- The Settings screen must disable sweep parameter controls when `AudioEngineService` state is not `Idle`
- `LogSineSweep` regenerates its buffers only when called from `Idle` state
- `DspWorker` retains the `SweepConfig` used to generate the inverse filter and validates it matches the `CaptureResult.sweepConfig` before processing

---

### Data

#### Repository Write Concurrency

Both `MeasurementRepository` and `PickupRepository` use atomic write-then-rename, but if two writes to the same file race concurrently — e.g. a measurement save and a migration pass running simultaneously — the second write wins and the first is silently lost. Dart's `dart:io` provides no file-level locking.

Wrap each repository's write path in a per-file mutex using `package:synchronized`:

```dart
final _lock = Lock();

Future<void> save(Measurement m) async {
  await _lock.synchronized(() async {
    await writeAtomic(_fileFor(m.id), jsonEncode(m.toJson()));
  });
}
```

A single `Lock` per repository is sufficient — writes to different measurement files can still race, but writes to the same file are serialised.

#### Atomic File Writes

`DeviceConfig` and calibration data written via `dart:io` `File.writeAsString()` are not atomic — a force-quit mid-write produces corrupt JSON that breaks on next launch.

Write all persistent data atomically using a write-then-rename pattern:

```dart
Future<void> writeAtomic(File target, String content) async {
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsString(content);
  await tmp.rename(target.path); // atomic on POSIX (macOS); near-atomic on NTFS
}
```

Apply to: `DeviceConfig`, `ChainCalibration`, and all `Measurement` JSON files.

#### H_chain Storage Resolution

`H_chain(f)` is complex-valued. At full FFT resolution (262,144 bins) it is ~4 MB of JSON — slow to serialise and large on disk. At 361 log-resampled bins it is fast but requires interpolation back onto the FFT frequency grid during division; for a chain response with a sharp notch (e.g. a coil self-resonance), interpolation may miss it entirely.

**Recommended:** Store `H_chain` at 4,096 uniformly-spaced bins covering 0–24 kHz (~125 KB). This is fine enough to resolve any feature the headphone amp or exciter coil can produce, fast to read/write, and avoids the accuracy loss of heavy log-resampling. During division, linearly interpolate from this grid onto the FFT frequency axis.

Define the storage grid in `chain_calibration.dart` as a constant so it is consistent across write and read paths:

```dart
const int kHChainBins = 4096;
const double kHChainMaxHz = 24000.0;
```

#### Split Storage Orphan Risk

`DeviceConfig` (including `activeCalibrationId`) lives in `SharedPreferences`. Calibration files live on disk. On Windows, clearing app data wipes `SharedPreferences` but leaves calibration files on disk. On reinstall on any platform, `SharedPreferences` is reset but the app support directory is typically retained.

On next launch after such an event: `activeCalibrationId` is null but valid `ChainCalibration` files exist — the app starts uncalibrated with orphaned data it cannot reach through normal UI.

**Required startup reconciliation in `CalibrationService.init()`:**
1. If `activeCalibrationId` is null, scan the `calibrations/` directory
2. If exactly one valid (non-expired) calibration file exists, restore it as active
3. If multiple exist, take the most recent
4. If none exist, proceed to the uncalibrated state normally

#### CSV Export Format

The CSV export format is underspecified in two ways that will break imports:

**Decimal separator:** On Windows with a European locale, `double.toString()` produces `"4999,8"` not `"4999.8"`. REW and MATLAB both require a period separator. The exporter must use `toStringAsFixed(4)` (not `toString()`) to guarantee locale-independent output.

**Column headers:** REW's text import expects specific headers. Use:
```
Freq(Hz),SPL(dB)
20.0000,−48.2341
...
```

Add a `CsvExporter` class in Phase 4 that owns this format, with a unit test asserting the header row and that a known `FrequencyResponse` produces the expected first data line.

#### `sweepConfig` Comparability Guard

If the user changes sweep parameters between sessions (e.g. extends duration from 3s to 5s), stored measurements made with different configs are not directly comparable. When overlaying measurements in the History/Results screen, compare `sweepConfig` of the incoming measurement against those already displayed. If configs differ, warn:

> "This measurement used different sweep settings and may not be directly comparable."

Allow the user to proceed with explicit acknowledgement.

#### Pickup Entity Model

Currently `Measurement` records are flat and unconnected — each is an island with a free-text `pickupLabel` string. A user measuring the same pickup ten times across multiple sessions has no way to group them, track drift over time, or compare before/after wax potting. This data model decision is harder to retrofit after the History screen is built.

Introduce a lightweight `Pickup` entity in Phase 0 alongside `Measurement`:

```
Pickup
  id: UUID
  name: String          # e.g. "PAF neck", "Strat bridge 2024"
  notes: String?
  createdAt: DateTime
  measurementIds: List<UUID>
```

- `Measurement` gains an optional `pickupId` foreign key
- `PickupRepository` handles CRUD with atomic writes
- History screen gains a "by pickup" grouping view alongside the existing flat list
- A pickup can exist with zero measurements (created before the first measurement session)

The `Pickup` entity does not affect the DSP pipeline or calibration — it is a pure data layer addition.

---

### UX

#### Onboarding and First Launch

On first launch no device is selected, no calibration exists, and the headphone knob has never been set. A linear onboarding flow must run once and block until complete:

```
Welcome → Hardware Checklist → Device Selection → Mains Frequency → Level Check → Chain Calibration → First Measurement
```

Additionally:
- Block the Measure screen tab/route if no valid calibration exists
- Show a persistent banner on the Measure screen if calibration has expired (>30 min), with a one-tap shortcut to re-calibrate
- Store `lastCompletedOnboardingStep: int` (not just `onboardingComplete: bool`) in `SharedPreferences`; resume mid-flow on relaunch rather than restarting from step 1. A user interrupted after device selection but before calibration will repeatedly redo early steps without this field.

#### `fl_chart` Log-Axis Touch with Overlaid Measurements

`fl_chart`'s built-in touch system computes nearest data point using linear chart coordinates. With the log-axis pre-transform applied, "nearest in chart space" diverges from "nearest in Hz space" — particularly at high frequencies where log compression clusters many data points together. With 5 overlaid measurements, the cursor will jump between curves as the user drags near convergent peaks.

**Required:** Bypass `fl_chart`'s touch system entirely for cursor and overlay selection. Implement a `GestureDetector` wrapping the chart that:
1. Converts the tap/drag x-coordinate to Hz using the inverse log transform
2. For each overlaid `FrequencyResponse`, finds the nearest `frequencyHz` bin to the tapped Hz value
3. Selects the curve whose nearest bin is closest in Hz space (not chart space)
4. Displays the cursor readout for that curve

This is a custom implementation — do not attempt to extend `fl_chart`'s `LineTouchData` for this use case. Plan for a full Phase 4 sprint on chart interaction alone.

#### Dark / Workshop Theme

A white-background chart in a dim studio or workshop causes eye strain and makes coloured curves harder to read.

- Implement both light and dark themes in `app_theme.dart`
- Default to `ThemeMode.system` (respects OS setting)
- Design `FrequencyResponseChart` primarily for dark background — coloured curves on dark grey are significantly more readable in low-light environments
- Chart background colour must be part of `AppTheme` (not hardcoded) so it responds to theme changes

#### Localization from Day One

Retrofitting `AppLocalizations` after the UI is built requires touching every widget that displays text — a significant and error-prone refactor.

From Phase 0 scaffold:
- Add `flutter_localizations` and `intl` to `pubspec.yaml`
- Wire `localizationsDelegates` and `supportedLocales` in `MaterialApp`
- Extract all user-facing strings to `lib/l10n/app_en.arb` from the start

Only `en` locale needs to ship initially. Adding further locales later becomes a translation task with no code changes required.

#### Accessibility

The frequency response chart is entirely visual with no accessible description for VoiceOver / TalkBack users. Wrap the chart widget in a `Semantics` widget:

```dart
Semantics(
  label: 'Frequency response chart. '
         'Resonance frequency: ${result.resonanceHz.toStringAsFixed(0)} Hz. '
         'Q-factor: ${result.qFactor.toStringAsFixed(1)}.',
  child: FrequencyResponseChart(data: result),
)
```

The `ResonanceSummaryCard` below the chart already displays this information as readable text — the Semantics label ensures screen readers reach it even if the card is scrolled off screen.

---

### Operations

#### Riverpod Provider Scope Hierarchy

Five providers are listed in the directory structure but their lifetimes and inter-dependencies are not defined. These decisions must be made in Phase 0 before any screen is built — retrofitting provider scopes after screens are wired causes cascading state bugs.

Define the following in `providers/` from Phase 0:

| Provider | Lifetime | Depends on |
|---|---|---|
| `audioEngineProvider` | Global (`keepAlive`) | — |
| `calibrationProvider` | Global (`keepAlive`) | `audioEngineProvider`, `deviceConfigProvider` |
| `deviceConfigProvider` | Global (`keepAlive`) | — |
| `dspProvider` | Global (`keepAlive`) | `calibrationProvider` |
| `measurementProvider` | `AutoDispose` per Results screen instance | `dspProvider` |
| `pickupProvider` | Global (`keepAlive`) | `measurementProvider` |

`calibrationProvider` must invalidate `dspProvider` when calibration changes — a new `H_chain` makes all pending DSP results stale. `measurementProvider` must be `AutoDispose` so the in-progress measurement state is cleared when the Results screen is popped.

#### History Screen Lazy Loading

Loading all measurements at launch reads every JSON file sequentially from disk. At 200 measurements this causes several seconds of startup lag on the main thread.

`MeasurementRepository` must support two-stage loading from Phase 0 — not retrofitted later:

```dart
// Stage 1: fast metadata only — sufficient for history list
Future<List<MeasurementSummary>> loadSummaries();

// Stage 2: full data on demand — called when user opens a measurement
Future<Measurement> loadFull(String id);
```

`MeasurementSummary` contains only: `id`, `timestamp`, `pickupLabel`, `pickupId`, `resonanceFrequencyHz`, `qFactor`. The full `magnitudeDB[]` array is loaded only when the measurement is opened for display or overlay.

#### DSP Worker Backpressure

The persistent `DspWorker` Isolate processes one request at a time. If the user triggers a new measurement while the previous FFT is still running, a second message queues silently on the `SendPort` with no way to cancel it.

- Expose a `bool get busy` stream so the UI can disable the Measure button while processing
- The `AudioEngineService` state machine should reject `Armed` transitions while `DspWorker.busy == true`

**Cancel token implementation:** Dart isolates share no memory — a `bool` flag is invisible across isolate boundaries. The cancel signal must be a message sent to a dedicated second `ReceivePort` inside the worker, polled non-blocking between each of the 10 pipeline stages:

```dart
// Inside worker isolate — poll cancel port between stages
bool _isCancelled(ReceivePort cancelPort) =>
    cancelPort.iterator.moveNext(); // non-blocking peek

// Sending side
void cancel() => _cancelSendPort.send(null);
```

If the cancel signal is sent through the same `SendPort` as work requests, it queues behind pending work and arrives after the pipeline has already completed — too late to interrupt anything.

#### Memory Management for Overlaid Measurements

Each `FrequencyResponse` holding a full 262,144-point complex FFT result consumes ~4 MB. Five overlaid measurements = ~20 MB simultaneously, plus the 144,000-sample capture buffer retained during averaging.

- Discard the raw capture buffer from `CaptureResult` immediately after the DSP pipeline completes
- Store only the final 361 log-resampled frequency/magnitude pairs in memory for display; persist the full FFT result to disk and reload on demand if needed for re-analysis
- Cap the in-memory overlay list at 5 entries; evict oldest when exceeded

#### Error Logging and Crash Reporting — DISABLED

> **Status: Disabled.** Crash reporting and remote telemetry are intentionally excluded from this project. No Sentry, Firebase Crashlytics, or equivalent integration will be added.

`FatalError` transitions write a structured log entry to a local rotating file only (`logs/app.log`, max 3 × 1 MB). On `FatalError`, the app displays a "Copy diagnostic log" button that copies the log to the clipboard for manual sharing. No data leaves the device automatically.

#### CI/CD Pipeline

**Minimum viable CI (GitHub Actions):**

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter test          # DSP + data + audio service unit tests
      - run: flutter analyze       # Lint
      - run: flutter build macos --release   # Verify macOS build integrity
```

The hardware integration test (Phase 3) cannot run in CI — document it as a manual pre-release gate: run against a reference pickup, assert reported resonance frequency is within ±50 Hz of a known ground truth value established from REW or Pickup Wizard.

#### macOS Notarization

The Distribution phase targets `.dmg` for direct distribution, but an un-notarized `.dmg` is blocked by Gatekeeper for all users who have not explicitly disabled it — which is effectively all users outside of development.

Requirements:
- **Developer ID Application** certificate in the build keychain
- **Hardened Runtime** enabled in Xcode signing settings (`ENABLE_HARDENED_RUNTIME = YES`)
- All entitlements must be compatible with hardened runtime (the existing `audio-input` and `usb` entitlements are)
- Add a notarization step to the CI/CD pipeline after `flutter build macos --release`:

```yaml
- run: xcrun notarytool submit build/macos/Build/Products/Release/WtFK.app
         --apple-id ${{ secrets.APPLE_ID }}
         --team-id ${{ secrets.TEAM_ID }}
         --password ${{ secrets.APP_SPECIFIC_PASSWORD }}
         --wait
- run: xcrun stapler staple build/macos/Build/Products/Release/WtFK.app
```

Without notarization, the `.dmg` distribution is limited to users who know how to bypass Gatekeeper — which excludes the non-technical audience this app targets.

---

### Testing

#### Test Coverage and Assertions

The full test suite is specified in the Directory Structure. Key integrity rules:

- Every test file must document its **pass criteria** as inline comments — a test with no assertion specification is not a test, it is a placeholder.
- The synthetic **4 kHz Q=3 pickup model** in `dsp_pipeline_service_test.dart` is the primary correctness oracle for the DSP pipeline. Any change to the pipeline must keep this test green.
- **Tolerance bounds** are fixed: resonance ±10 Hz, Q-factor ±0.5. These are tighter than real-world measurement uncertainty to catch regressions, not to reflect hardware limits.
- **JSON round-trip tests** (`device_config_test.dart`, `sweep_config_test.dart`, `measurement_migrator_test.dart`) are the guard against silent data loss from field renames or serialisation changes.
- **Widget tests** (`test/ui/`) cover the four highest-risk user flows: onboarding completion gate, measure screen blocked state, chart cursor transform accuracy, and history overlay limit enforcement.
- The **manual hardware integration gate** (Phase 3) is not automated: run against a reference pickup, assert reported resonance is within ±50 Hz of a REW or Pickup Wizard ground-truth value. Document the result in the release notes for each build.

#### Estimated Code Coverage by Layer

**Target: 95% Dart, 90% overall (including native)**

| Layer | Files | Baseline | With full suite | What closes the gap |
|---|---|---|---|---|
| DSP | `dsp/` | ~75% | ~93% | Edge cases: all-zero input, short input, non-default sweep config |
| Calibration | `calibration/` | ~75% | ~90% | Concurrent write, I/O failure paths |
| Data | `data/` | ~85% | ~97% | `csv_exporter_test.dart` covers the only untested file |
| Audio service (Dart) | `audio_engine_service.dart` | ~80% | ~95% | Already fully specified |
| Audio channel (Dart) | `audio_engine_method_channel.dart` | ~0% | ~90% | `audio_engine_method_channel_test.dart` (Phase 3) |
| Providers | `providers/` | ~0% | ~90% | `provider_integration_test.dart` (Phase 4) |
| UI screens | `ui/screens/` | ~55% | ~95% | `setup_screen`, `calibration_screen`, `results_screen` tests added |
| UI widgets | `ui/widgets/` | ~20% | ~95% | 5 new widget tests: `LevelMeter`, `DevicePicker`, `SearchBandOverlay`, `CalibrationExpiryBanner`, `ResonanceSummaryCard` |
| Native Swift (macOS/iOS) | `macos/Classes/`, `ios/Classes/` | 0% | ~85% | XCTest suite (see Native Test Framework below) |
| Native C++ (Windows) | `windows/` | 0% | ~80% | Google Test suite (see Native Test Framework below) |
| **Overall Dart** | | **~65%** | **~95%** | |
| **Overall including native** | | **~50%** | **~90%** | |

The remaining ~5% of Dart code that resists coverage: `main.dart` bootstrap, theme switch animation paths, and `FatalError` display paths that require a plugin crash to trigger — none of these affect measurement correctness.

#### Native Test Framework (XCTest + Google Test)

The Flutter test runner does not execute Swift or C++. Reaching 90% overall coverage requires separate native test suites that run as additional CI jobs.

**macOS / iOS — XCTest**

Add a test target to the Xcode project (`WtFKTests`) covering the three Swift classes most likely to regress:

| Class | Key test cases |
|---|---|
| `AudioDeviceEnumerator` | Returns correct device list from mocked Core Audio HAL; active device UID matches after `setDevice`; `deviceRemoved` event fires when active device disappears |
| `SweepPlayer` | Output buffer contains correct number of samples; playback starts on scheduled `AVAudioTime`; cancels cleanly mid-sweep |
| `InputCapture` | Captures correct sample count after stop; dropout flag set when buffer underruns; peak dBFS computed correctly for level meter |

Run in CI as a separate job:
```yaml
xcode-test:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - run: xcodebuild test
             -project macos/Runner.xcodeproj
             -scheme WtFKTests
             -destination 'platform=macOS'
```

**Windows — Google Test**

Add a `tests/` directory to `windows/` with Google Test covering the WASAPI backend:

| Class | Key test cases |
|---|---|
| `AudioEnginePlugin` (WASAPI) | Exclusive mode requested at 48 kHz/24-bit; `AUDCLNT_E_DEVICE_IN_USE` mapped to `DeviceError`; device change notification triggers hot-plug callback |

Run in CI as a separate job:
```yaml
windows-test:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
    - run: cmake -B build -S windows/tests && cmake --build build
    - run: build\Debug\WtFKTests.exe
```

`AudioEnginePlugin.h` must expose a seam for injecting a mock WASAPI `IMMDeviceEnumerator` — this requires the real implementation to accept the enumerator by dependency injection rather than calling `CoCreateInstance` directly.

#### Updated CI/CD Pipeline

Replace the single CI job with three parallel jobs:

```yaml
on: [push, pull_request]
jobs:
  dart-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter test --coverage
      - run: flutter analyze
      - run: flutter build macos --release

  xcode-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild test
               -project macos/Runner.xcodeproj
               -scheme WtFKTests
               -destination 'platform=macOS'

  windows-test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - run: cmake -B build -S windows/tests && cmake --build build
      - run: build\Debug\WtFKTests.exe
```

All three jobs must pass before a PR can merge.

#### Flutter and Dart SDK Version Pinning

Without explicit SDK constraints, `flutter pub get` on a different machine may resolve to an older SDK that doesn't support Dart records syntax (used in `DspWorker` message passing) or other APIs in the plan.

Set in `pubspec.yaml` from Phase 0:

```yaml
environment:
  sdk: '>=3.3.0 <4.0.0'
  flutter: '>=3.19.0'
```

Pin to the minimum version that supports all language features and packages used. Update intentionally rather than allowing drift.

---

## Key Technical Challenges and Mitigations

| Challenge | Mitigation |
|---|---|
| Exciter chain frequency response colors results | `CalibrationService` measures and divides out `H_chain(f)` before every session |
| Headphone knob level drift between cal and measurement | Setup checklist + knob marking; calibration timestamp warning after 30 min |
| Synchronized simultaneous play+record | Single `AVAudioEngine` session; both nodes scheduled to the same `AVAudioTime` |
| Sweep misalignment across averaged captures | Cross-correlation alignment check per sweep; misaligned sweeps discarded |
| FFT spectral leakage | Inverse filter deconvolution + Hann window before FFT |
| Division instability at band edges | Tikhonov regularization + frequency-domain cosine taper |
| Hard-coded resonance band misses outlier pickups | User-configurable `ResonanceSearchBand`; all peaks above threshold shown |
| State machine has no error recovery | Error taxonomy (`Recoverable` / `Device` / `Fatal`) + `reset()` path back to `Idle` |
| USB device enumeration | Platform channel: Core Audio (macOS), `AVAudioSession` (iOS), WASAPI `MMDevice` (Windows) |
| FFT Isolate spawn overhead | Persistent worker Isolate with `SendPort` message loop; initialized once at startup |
| No platform channel test coverage | Mock platform implementation from Phase 0; hardware integration test in Phase 2 |
| Measurement JSON schema evolution | `schemaVersion` field + `MeasurementMigrator` from day one |
| Log-axis cursor returning transformed coordinates | Inverse log transform in `fl_chart` touch callback |
| EMI / mains hum | Golden-ratio sweep spacing; optional spectral hum suppression using measured (not nominal) mains frequency |
| iOS USB class 2 reliability | iOS demoted to Tier 2; gated on macOS validation |
| Round-trip latency (phase) | Does not affect resonance peak location — acceptable for Tier 1. Phase 4+: cross-correlate reference click to measure and compensate |
| App backgrounded or interrupted mid-sweep | `willResignActiveNotification` + interruption notification → `RecoverableError` |
| Sweep output clipping | Step 0 of `Armed` state: 1s clipping check before every full sweep |
| Measurement traceability | `hardware` block in `Measurement` JSON; `calibrationId` UUID links each result to its calibration |
| `fftea` package abandonment | `FftProvider` abstraction; `AccelerateFftProvider` swap-in requires no changes outside `fft_provider.dart` |
| App Store binary rejected for missing privacy declarations | `PrivacyInfo.xcprivacy` in macOS and iOS targets; declare `UserDefaults` and file timestamp API reason codes |
| Windows OS resampling corrupts frequency accuracy | WASAPI exclusive mode at 48 kHz/24-bit; `AUDCLNT_E_DEVICE_IN_USE` → `DeviceError`; shared mode not permitted |
| Flat measurement records hide per-pickup history | `Pickup` entity with `measurementIds`; `PickupRepository`; History screen grouped-by-pickup view |
| Un-notarized `.dmg` blocked by Gatekeeper | Developer ID cert + hardened runtime + `xcrun notarytool` + `xcrun stapler` in CI pipeline |
| Tikhonov ε, S-G window, peak threshold unspecified | Starting values documented in DSP Tuning Parameters; validated against synthetic 4 kHz Q=3 model in Phase 1 |
| H_chain JSON is 4 MB at full FFT resolution | Store at 4,096 uniform bins (0–24 kHz); interpolate onto FFT grid during division |
| Isolate PCM transfer copies 576 KB per sweep | Use `TransferableTypedData` — zero-copy ownership transfer; buffer is discarded after sending anyway |
| SweepConfig changed mid-measurement | Settings controls disabled outside `Idle`; `DspWorker` validates config matches before processing |
| AVAudioEngine state undefined after hot-plug | Eight-step reconnection sequence with 150 ms settle delay; documented in Audio Considerations |
| I/O buffer size assumed 512 samples | Read actual buffer size from hardware after engine start; derive pre-roll and dropout window dynamically |
| WASAPI exclusive mode denied by Focusrite Control | Error message names Focusrite Control explicitly; shared mode fallback explicitly prohibited |
| Concurrent repository writes silently lose data | Per-repository `Lock` from `package:synchronized` serialises all writes to the same file |
| SharedPreferences reset orphans calibration files | Startup reconciliation in `CalibrationService.init()` scans `calibrations/` and restores most-recent valid file |
| Cancel token sent through work `SendPort` arrives too late | Dedicated cancel `ReceivePort` inside worker; polled non-blocking between each of the 10 pipeline stages |
| Level meter fires at audio buffer rate (~100 Hz) | Native side debounces to 100 ms timer before emitting on EventChannel |
| CSV decimal separator locale-dependent | `CsvExporter` uses `toStringAsFixed(4)` with period separator; REW-compatible header row; tested with `csv_exporter_test.dart` |
| App version absent from Measurement JSON | `appVersion` field in `hardware` block via `package_info_plus`; enables per-build attribution of algorithm changes |
| Results screen has no specification | Feature 7 added: content, four actions (Save / Discard / Overlay / Export), and navigation contract fully defined |
| AVAudioTime scheduling misses USB render cycle | 100 ms look-ahead (4,800 samples); doubled to 200 ms after hot-plug reconnect; delta logged per session |
| Cross-correlation sweep 0 anchors to bad offset | Sweep 0 stored only if offset within ±500 samples of expected USB latency; otherwise discard and retry |
| fl_chart touch jumps between curves on log axis | Custom `GestureDetector` bypasses fl_chart touch system; nearest curve in Hz space, not chart space |
| CSV export save location blocked by App Sandbox | `com.apple.security.files.user-selected.read-write` entitlement added in Phase 4 |
| Riverpod provider scopes undefined | Scope table defined in Phase 0: global `keepAlive` for device/calibration/DSP; `AutoDispose` for measurement |
| Onboarding mid-flow restart loses progress | `lastCompletedOnboardingStep: int` in `SharedPreferences` replaces single `onboardingComplete: bool` |
| Calibration runs with pickup still connected | Pre-calibration signal check: input must be below -40 dBFS with exciter active before sweep starts |
| History screen startup lag with many measurements | Two-stage `MeasurementRepository`: `loadSummaries()` at launch, `loadFull(id)` on demand |
| Dart coverage stuck at ~65% | 5 widget tests + DSP edge cases + provider integration test + method channel test → ~95% Dart |
| Native Swift code has 0% automated coverage | XCTest suite (`WtFKTests`) for `AudioDeviceEnumerator`, `SweepPlayer`, `InputCapture`; runs in CI on `macos-latest` |
| Native WASAPI code has 0% automated coverage | Google Test suite in `windows/tests/`; `IMMDeviceEnumerator` injected for testability; runs in CI on `windows-latest` |

---

## Directory Structure

```
lib/
  audio/
    audio_engine_service.dart             # Dart facade + state machine
    audio_engine_platform_interface.dart
    audio_engine_method_channel.dart
    models/
      device_config.dart                  # Device UID, sample rate, headphone cal state, measured mains Hz, ResonanceSearchBand
      sweep_config.dart
      capture_result.dart
  calibration/
    calibration_service.dart              # Chain calibration: H_chain measurement + storage
    models/
      chain_calibration.dart              # H_chain(f) + timestamp + calibrationId + invalidation rules
  dsp/
    log_sine_sweep.dart                   # Sweep + inverse filter generation
    dsp_pipeline_service.dart             # Deconvolution, FFT, chain correction, peak detection
    dsp_worker.dart                       # Persistent Isolate with SendPort message loop + cancel token + busy state
    fft_provider.dart                     # FftProvider abstraction (fftea default; Accelerate swap-in)
    models/
      frequency_response.dart             # 361 log-resampled pairs + all peaks + primary resonance + Q
      resonance_search_band.dart          # Configurable low/high Hz bounds
  data/
    measurement_repository.dart           # Two-stage loading: loadSummaries() at launch, loadFull(id) on demand; atomic writes; write mutex via synchronized
    measurement_migrator.dart             # Schema version migration
    pickup_repository.dart                # Pickup entity CRUD with atomic writes; write mutex via synchronized
    csv_exporter.dart                     # CsvExporter: REW-compatible header, period decimal separator, locale-independent
    models/
      measurement.dart                    # schemaVersion + hardware metadata + pickupId + all result fields; frequencyBins computed on load
      pickup.dart                         # Pickup entity: id, name, notes, createdAt, measurementIds
  ui/
    screens/
      onboarding_screen.dart              # Linear first-launch flow; blocks until calibration complete
      setup_screen.dart                   # Device picker + hardware checklist + level check + mains frequency tool
      calibration_screen.dart             # Chain calibration flow
      measure_screen.dart                 # Blocked + banner if calibration expired
      results_screen.dart
      history_screen.dart
    widgets/
      frequency_response_chart.dart       # fl_chart + log-axis transform + inverse touch transform + Semantics
      level_meter.dart
      resonance_summary_card.dart
      device_picker.dart
      search_band_overlay.dart            # Shaded ResonanceSearchBand region on chart
      calibration_expiry_banner.dart      # Persistent warning + one-tap re-calibrate shortcut
    theme/
      app_theme.dart                      # Light + dark themes; dark default for workshop use
  l10n/
    app_en.arb                            # All user-facing strings; add locales here without code changes
  providers/
    audio_engine_provider.dart
    calibration_provider.dart
    dsp_provider.dart
    measurement_provider.dart
    pickup_provider.dart
  main.dart

macos/
  Runner/
    PrivacyInfo.xcprivacy                 # Required reason API declarations (UserDefaults, file timestamps)
  Classes/
    AudioEnginePlugin.swift
    AudioDeviceEnumerator.swift
    SweepPlayer.swift
    InputCapture.swift

ios/
  Runner/
    PrivacyInfo.xcprivacy                 # Required reason API declarations (UserDefaults, file timestamps)
  Classes/
    AudioEnginePlugin.swift               # Shared implementation with macOS (Tier 2)

windows/
  audio_engine_plugin.cpp                 # WASAPI backend (Phase 5)

android/
  AudioEnginePlugin.kt                    # Oboe backend (Phase 6 / stretch)

test/
  dsp/
    log_sine_sweep_test.dart              # Instantaneous frequency correct at t=0 and t=T; sample count == durationSeconds × sampleRate; inverse filter is time-reversed with correct amplitude envelope
    dsp_pipeline_service_test.dart        # Synthetic 4 kHz Q=3 pickup model; pass criteria: resonance within ±10 Hz of 4000, Q within ±0.5 of 3.0; chain division identity (H_chain == H_measured → flat output ±0.1 dB); no NaN/Inf when any H_chain bin is near zero; DSP tuning defaults (ε=1e-3, S-G window=11, threshold=-20 dB) produce correct results; all-zero input produces flat output not NaN; input shorter than FFT window is zero-padded correctly; non-default f1/f2/duration sweep config produces correct instantaneous frequency
    dsp_worker_test.dart                  # Busy state blocks re-entry; cancel token exits pipeline early; TransferableTypedData round-trip; SweepConfig mismatch between worker and capture result is rejected
    fft_provider_test.dart                # Pure sine at known frequency produces peak at correct bin (±1 bin); fftea and AccelerateFftProvider produce identical output within floating-point tolerance
  calibration/
    calibration_service_test.dart         # Mock chain response divided out correctly; calibration timestamp expiry detected; calibrationId UUID generated and stored; near-zero H_chain bins do not produce NaN after division
    chain_calibration_test.dart           # H_chain written at 4096 bins; read-back produces identical values; interpolation onto FFT frequency axis is monotonic and within tolerance of original
  data/
    measurement_repository_test.dart      # Atomic write succeeds; corrupt .tmp file on launch does not crash; measurements load and round-trip through JSON without data loss
    measurement_migrator_test.dart        # Schema v0 → v1 migration produces all required fields; unknown future version passes through without crash
    device_config_test.dart               # JSON serialisation round-trip preserves all fields; missing optional fields deserialise to documented defaults; field name changes detected immediately
    sweep_config_test.dart                # Two configs with identical fields compare equal; any single differing field compares unequal; used by comparability guard
    pickup_repository_test.dart           # Create/read/update/delete pickup; measurementId association; atomic write; missing file returns empty list not crash
    csv_exporter_test.dart                # Header row matches REW import format; decimal separator is period regardless of locale; known FrequencyResponse produces expected first data line
  audio/
    audio_engine_service_test.dart        # State machine: all valid transitions; DspWorker.busy blocks Armed transition; SweepConfig mutation rejected outside Idle; interruption → RecoverableError; hot-plug → DeviceError; sample rate mismatch → DeviceError; AppBackgrounded → RecoverableError; pre-roll adjusts for non-default buffer size
    audio_engine_method_channel_test.dart # Method name strings correct; argument map keys and types match platform channel contract; return type casts succeed; missing plugin produces clear error not silent null
  ui/
    onboarding_screen_test.dart           # Completion unlocks Measure screen; incomplete onboarding blocks navigation
    setup_screen_test.dart                # Level check meter updates; device picker selection persists; hardware checklist items can be checked and unchecked
    calibration_screen_test.dart          # Calibration flow completes and stores result; abort returns to setup; expired calibration triggers re-run prompt
    measure_screen_test.dart              # Blocked state when no calibration; calibration expiry banner tap navigates to calibration screen
    results_screen_test.dart              # Save flow writes Measurement JSON and navigates to History; Discard requires confirmation; Overlay applies sweepConfig guard; Export produces valid CSV
    frequency_response_chart_test.dart    # Cursor inverse transform returns correct Hz at chart extremes and midpoint; Semantics label contains resonance Hz and Q-factor
    history_screen_test.dart              # Overlay renders up to 5 measurements; sweepConfig mismatch warning shown; 6th measurement evicts oldest
    widgets/
      level_meter_test.dart               # Renders correct dBFS value; clipping indicator shown above -1 dBFS; animates smoothly between values
      device_picker_test.dart             # Renders device list from provider; selection callback fires with correct UID; empty list shows "No devices found" placeholder
      search_band_overlay_test.dart       # Overlay renders at correct fractional chart coordinates for given band; updates position when band changes
      calibration_expiry_banner_test.dart # Shown when calibration age exceeds threshold; hidden when calibration is valid; tap fires recalibrate callback
      resonance_summary_card_test.dart    # Resonance Hz formatted as "5.2 kHz" above 1000 Hz and "820 Hz" below; Q-factor and timestamp both displayed
  providers/
    provider_integration_test.dart        # Full Riverpod provider graph mounted; CalibrationProvider invalidates when DeviceConfig changes; DspProvider busy state observed by AudioEngineService; MeasurementProvider reflects repository writes; PickupProvider groups measurements by pickupId
```

---

## Development Phases

| Phase | Work | Duration |
|---|---|---|
| **0 — Scaffold** | Project structure; mock platform plugin (synthetic 4 kHz resonance); all screens wired to mock data; `MeasurementMigrator` with `schemaVersion` + hardware metadata fields; `Pickup` entity + `PickupRepository`; `MeasurementRepository` with two-stage loading (`loadSummaries()` + `loadFull(id)`); persistent `DspWorker` stub with busy/cancel (two-port design); `FftProvider` abstraction; atomic file write helper; Riverpod provider scope hierarchy defined (global `keepAlive` vs `AutoDispose`); `AppLocalizations` wired with `app_en.arb`; `app_theme.dart` with light + dark themes; SDK version constraints in `pubspec.yaml`; `PrivacyInfo.xcprivacy` stubs in macOS and iOS targets; `lastCompletedOnboardingStep` field in `DeviceConfig`; CI pipeline (GitHub Actions: test + analyze + build macOS); `device_config_test.dart`; `sweep_config_test.dart`; `measurement_repository_test.dart`; `measurement_migrator_test.dart`; `pickup_repository_test.dart` | 1–2 weeks |
| **1 — DSP Engine** | `LogSineSweep` + inverse filter; `DspPipelineService` (deconvolution, chain correction, Tikhonov regularization, configurable search band, all-peaks detection); `FftProvider` benchmark (fftea vs Accelerate); `log_sine_sweep_test.dart`; `fft_provider_test.dart`; `dsp_pipeline_service_test.dart` with full pass criteria (resonance ±10 Hz, Q ±0.5, chain identity, no NaN, tuning defaults validated); `dsp_worker_test.dart` | 1–2 weeks |
| **2 — Calibration** | `CalibrationService` (chain calibration flow, `H_chain` storage at 4,096 bins, atomic writes, invalidation rules, `calibrationId` UUID); level check tool; sweep clipping check; mains frequency measurement tool; onboarding flow; `CalibrationExpiryBanner`; Measure screen blocked state; iCloud backup exclusion; `calibration_service_test.dart`; `chain_calibration_test.dart`; `setup_screen_test.dart`; `calibration_screen_test.dart` | 1–2 weeks |
| **3 — Audio Plugin** | macOS entitlements (`audio-input` + `usb`); Swift `AVAudioEngine` plugin (native buffer capture, single `MethodChannel` transfer); `AVAudioTime` co-start; sample rate negotiation; USB hot-plug detection; audio session interruption + `AppBackgrounded` handling; app lifecycle notifications; cross-correlation alignment check; dropout detection; golden-ratio sweep spacing; local rotating log file for `FatalError`; `audio_engine_method_channel_test.dart`; XCTest suite (`WtFKTests` target) for `AudioDeviceEnumerator`, `SweepPlayer`, `InputCapture`; XCTest CI job added; end-to-end validation against known pickup (manual gate: ±50 Hz of REW reference) | 2–3 weeks |
| **4 — UI & Persistence** | History screen; CSV export (`CsvExporter` + `csv_exporter_test.dart`); `ResonanceSearchBand` UI; all-peaks chart annotation; cursor inverse transform; `sweepConfig` comparability guard; `Semantics` accessibility wrappers; spectral hum suppression toggle; memory management (discard raw buffers post-pipeline); `provider_integration_test.dart`; widget tests for all 5 remaining widgets (`LevelMeter`, `DevicePicker`, `SearchBandOverlay`, `CalibrationExpiryBanner`, `ResonanceSummaryCard`); `results_screen_test.dart`; `history_screen_test.dart`; app polish | 1–2 weeks |
| **5 — Windows** | WASAPI exclusive mode backend (48 kHz/24-bit; `AUDCLNT_E_DEVICE_IN_USE` → `DeviceError`; `IMMDeviceEnumerator` injected for testability); Windows USB device change notification for hot-plug; sample rate negotiation; minimum Windows 10 build 19041 target; Google Test suite (`windows/tests/`); Windows CI job added | 1–2 weeks |
| **6 — iOS** | AVAudioEngine iOS backend; `NSMicrophoneUsageDescription`; app lifecycle background handling; minimum iOS 16.0 target; Camera Connection Kit USB class 2 compatibility matrix testing | 1–2 weeks |
| **7 — Distribution** | macOS: Developer ID signing + hardened runtime + notarization (`xcrun notarytool` + `xcrun stapler`) + `.dmg` packaging; iOS: `PrivacyInfo.xcprivacy` final review + TestFlight → App Store | — |

> **Note on Mac App Store:** Sandboxing may complicate USB audio device access. Direct distribution via .dmg is recommended for initial release.

---

## Build Order — Start Here

Build and validate these files first. Everything else depends on them.

1. `lib/dsp/log_sine_sweep.dart` — sweep math + inverse filter; validate instantaneous frequency vs time analytically
2. `lib/dsp/fft_provider.dart` — abstraction + `fftea` implementation; benchmark against Accelerate before committing to default
3. `lib/dsp/dsp_pipeline_service.dart` — full pipeline including deconvolution, chain correction, and Tikhonov regularization; validate against synthetic 4 kHz Q=3 pickup model
4. `lib/dsp/dsp_worker.dart` — persistent Isolate with busy state, cancel token, and backpressure guard
5. `lib/calibration/calibration_service.dart` — chain calibration with atomic writes; validate that a synthetic `H_chain` is correctly divided out
6. `macos/Classes/AudioEnginePlugin.swift` — macOS entitlements first; then full-duplex I/O with native buffer capture, `AVAudioTime` co-start, sample rate negotiation, USB hot-plug, and interruption handling
7. `lib/audio/audio_engine_service.dart` — state machine with full error taxonomy, interruption handling, and `reset()` path
8. `lib/ui/screens/onboarding_screen.dart` — linear first-launch gate; nothing else is reachable until this completes
9. `lib/ui/widgets/frequency_response_chart.dart` — log-axis chart with inverse touch transform and `Semantics` wrapper
