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

> **Critical decision:** Do not combine `flutter_pcm_sound` + `flutter_audio_capture`. They use separate audio sessions and will drift relative to each other, corrupting the transfer function. A single `AVAudioEngine` session managing both play and record nodes is required.

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

**Level check tool:** Routes a 1 kHz sine tone through the headphone output, captures on input channel 1, and displays a real-time dBFS meter. Guide the user to ~-12 dBFS. Once the correct level is confirmed the user marks the knob and proceeds to chain calibration.

**Chain calibration (`CalibrationService`):**

The full signal chain (headphone amp + exciter coil) has its own frequency-dependent response. This is calibrated out before pickup measurements:

1. Replace the pickup with a known resistive load (10 kΩ) at the coil position
2. Run a full log-sine sweep; capture `Y_ref(f)`
3. Compute chain response: `H_chain(f) = Y_ref(f) / X(f)`
4. Store `H_chain(f)` with timestamp in `DeviceConfig`

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
| `RecoverableError` | Dropout, level too low, sweep misaligned | Prompt retry → back to `Armed` |
| `DeviceError` | Device disconnected, sample rate mismatch | Prompt reconnect → back to `Idle` |
| `FatalError` | Plugin crash, OOM | Log diagnostic, require app restart |

Capture flow:
1. Pre-roll silence (512 ms) to flush interface buffers
2. Schedule playback and input tap to start on the same `AVAudioTime` render cycle (sample-accurate co-start)
3. Stop after sweep duration + post-roll (500 ms)
4. Cross-correlate captured signal against reference to verify sweep alignment — discard and retry if offset differs from previous sweep by more than ±2 samples
5. Validate sample count; flag dropouts
6. N-sweep averaging: accumulate aligned captures in time domain before FFT

Dropout detection is mandatory — USB audio devices can glitch. The app must warn the user rather than silently present corrupt data.

**Hum mitigation (N ≥ 4 sweeps):** Use golden-ratio sweep spacing to cancel mains harmonics across the average:

```dart
final td = (1 / powerLineHz) / goldenRatio; // ~12.4 ms for 50 Hz
final pauseBetweenSweeps = 1000 + (td * 1000).round(); // ms
```

### 4. DSP Pipeline

Runs in a **persistent worker Isolate** (initialized once at app startup, reused for all measurements and level-check FFT frames):

```dart
class DspWorker {
  late final SendPort _sendPort;
  final _receivePort = ReceivePort();

  Future<void> init() async {
    await Isolate.spawn(_workerEntryPoint, _receivePort.sendPort);
    _sendPort = await _receivePort.first;
  }

  Future<FrequencyResponse> process(CaptureResult capture) async {
    final reply = ReceivePort();
    _sendPort.send((capture, reply.sendPort));
    return await reply.first as FrequencyResponse;
  }
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

If `fftea` performance is insufficient on target hardware, fall back to native Accelerate framework (Apple) via platform channel.

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
`schemaVersion`, `id`, `timestamp`, `pickupLabel`, `sweepConfig`, `resonanceSearchBand`, `frequencyBins[]`, `magnitudeDB[]`, `resonanceFrequencyHz`, `qFactor`

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

---

## Additional Considerations

### 1. Platform Permissions and Entitlements

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

---

### 2. Platform Channel PCM Transfer Strategy

Streaming raw PCM from native to Dart via `EventChannel` during capture introduces Flutter codec serialization overhead on every audio buffer callback (~every 10 ms). At audio rates this can cause latency spikes and buffer drops.

**Preferred approach:** Capture the full sweep natively into a pre-allocated native buffer, then transfer the completed buffer to Dart as a single `Uint8List` via `MethodChannel` after capture is complete. This keeps the hot audio path entirely native and eliminates codec overhead during recording.

```swift
// Swift — capture into native buffer, transfer once complete
func captureComplete(_ samples: [Float]) -> FlutterStandardTypedData {
    return FlutterStandardTypedData(float32: Data(bytes: samples, count: samples.count * 4))
}
```

---

### 3. Audio Session Interruptions

Other apps can take audio focus mid-measurement (phone calls, notifications, Spotlight). Without interruption handling, a mid-sweep interruption produces a corrupt capture that may pass dropout detection.

**Required additions:**
- Subscribe to `AVAudioSession.interruptionNotification` (iOS) and `AVAudioEngine` configuration change notifications (macOS)
- On interruption: immediately transition to `RecoverableError`, notify the user, offer retry
- On interruption end: re-activate the audio session before allowing retry

Add `Interrupted` as a `RecoverableError` subtype in the state machine error taxonomy.

---

### 4. Sample Rate Negotiation

The app assumes 48 kHz is available. The OS honours whatever sample rate was last set by another app or the device's native rate. If the system is running at 44.1 kHz or 96 kHz the app will capture at the wrong rate, producing a frequency-shifted result with no obvious error.

**Required:** After `AVAudioEngine` starts, verify the active hardware sample rate matches 48 kHz. If it does not, surface a `DeviceError` with an explicit instruction to set the Scarlett 2i2 to 48 kHz in Focusrite Control before retrying. Do not attempt silent sample rate conversion — it adds DSP complexity and the user can fix it in 10 seconds.

---

### 5. USB Hot-Plug Detection

The `DeviceError` state exists but no mechanism is defined for detecting USB disconnection. Without subscribing to device change events, the state machine will hang or produce garbage data if the Scarlett 2i2 is unplugged mid-sweep.

**Required subscriptions:**
- **macOS:** `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDevices` — fires when any audio device is added or removed
- **iOS:** `AVAudioSession.routeChangeNotification` with reason `oldDeviceUnavailable`

On receipt, check whether the active device UID is still present. If not, cancel the current capture and transition to `DeviceError`.

---

### 6. DSP Worker Backpressure

The persistent `DspWorker` Isolate processes one request at a time. If the user triggers a new measurement while the previous FFT is still running, a second message queues silently on the `SendPort`. The UI has no way to know the worker is busy, and no way to cancel an in-flight computation.

**Required additions to `DspWorker`:**
- Expose a `bool get busy` stream so the UI can disable the Measure button while processing
- Expose a `cancel()` method that sends a cancellation token to the Isolate; the worker checks the token between pipeline stages and exits early if set
- The `AudioEngineService` state machine should reject `Armed` transitions while `DspWorker.busy == true`

---

### 7. Memory Management for Overlaid Measurements

Each `FrequencyResponse` holding a full 262,144-point complex FFT result consumes ~4 MB. Five overlaid measurements = ~20 MB in memory simultaneously, plus the 144,000-sample capture buffer retained during averaging.

**Mitigations:**
- Discard the raw capture buffer from `CaptureResult` immediately after the DSP pipeline completes — only the processed `FrequencyResponse` needs to be retained
- Store only the final 361 log-resampled frequency/magnitude pairs in memory for display (matching the Pickup Wizard's approach); persist the full FFT result to disk and reload on demand if needed for re-analysis
- Cap the in-memory overlay list at 5 entries; evict oldest when the cap is exceeded

---

### 8. FFT Provider Abstraction

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

---

### 9. Onboarding and First Launch

On first launch no device is selected, no calibration exists, and the headphone knob has never been set. Without a defined first-launch flow the user will reach the Measure screen with nothing configured and produce meaningless or failed measurements.

**Required:** A linear onboarding flow that runs once on first launch and blocks until complete:

```
Welcome → Hardware Checklist → Device Selection → Level Check → Chain Calibration → First Measurement
```

Additionally:
- Block the Measure screen tab/route if no valid calibration exists
- Show a persistent banner on the Measure screen if calibration has expired (>30 min), with a one-tap shortcut to re-calibrate
- Store an `onboardingComplete` flag in `SharedPreferences`; skip onboarding on subsequent launches

---

### 10. Atomic File Writes

`DeviceConfig` and calibration data written via `dart:io` `File.writeAsString()` are not atomic — a force-quit mid-write produces corrupt JSON that breaks on next launch.

**Required:** Write all persistent data atomically using a write-then-rename pattern:

```dart
Future<void> writeAtomic(File target, String content) async {
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsString(content);
  await tmp.rename(target.path); // atomic on POSIX (macOS); near-atomic on NTFS
}
```

Apply to: `DeviceConfig`, `ChainCalibration`, and all `Measurement` JSON files.

---

### 11. CI/CD Pipeline

No automated build or test pipeline is defined. Without CI the test suite written in Phase 0 will drift and break silently.

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

---

### 12. Accessibility

The frequency response chart is entirely visual with no accessible description for VoiceOver / TalkBack users. This blocks App Store compliance in some regions.

**Minimum requirement:** Wrap the chart widget in a `Semantics` widget that describes the key result in plain text:

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
| EMI / mains hum | Golden-ratio sweep spacing for averaging; optional spectral hum suppression |
| iOS USB class 2 reliability | iOS demoted to Tier 2; gated on macOS validation |
| Round-trip latency (phase) | Does not affect resonance peak location — acceptable for Tier 1. Phase 4+: cross-correlate reference click to measure and compensate |

---

## Directory Structure

```
lib/
  audio/
    audio_engine_service.dart             # Dart facade + state machine
    audio_engine_platform_interface.dart
    audio_engine_method_channel.dart
    models/
      device_config.dart                  # Includes headphone cal state + ResonanceSearchBand
      sweep_config.dart
      capture_result.dart
  calibration/
    calibration_service.dart              # Chain calibration: H_chain measurement + storage
    models/
      chain_calibration.dart              # H_chain(f) + timestamp + invalidation rules
  dsp/
    log_sine_sweep.dart                   # Sweep + inverse filter generation
    dsp_pipeline_service.dart             # Deconvolution, FFT, chain correction, peak detection
    dsp_worker.dart                       # Persistent Isolate with SendPort message loop + cancel token
    fft_provider.dart                     # FftProvider abstraction (fftea default; Accelerate swap-in)
    models/
      frequency_response.dart             # 361 log-resampled pairs + all peaks + primary resonance + Q
      resonance_search_band.dart          # Configurable low/high Hz bounds
  data/
    measurement_repository.dart           # Atomic writes via write-then-rename
    measurement_migrator.dart             # Schema version migration
    models/
      measurement.dart                    # Includes schemaVersion field
  ui/
    screens/
      onboarding_screen.dart              # Linear first-launch flow; blocks until calibration complete
      setup_screen.dart                   # Device picker + hardware checklist + level check
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
      app_theme.dart
  providers/
    audio_engine_provider.dart
    calibration_provider.dart
    dsp_provider.dart
    measurement_provider.dart
  main.dart

macos/
  Classes/
    AudioEnginePlugin.swift
    AudioDeviceEnumerator.swift
    SweepPlayer.swift
    InputCapture.swift

ios/
  Classes/
    AudioEnginePlugin.swift               # Shared implementation with macOS (Tier 2)

windows/
  audio_engine_plugin.cpp                 # WASAPI backend (Phase 4)

android/
  AudioEnginePlugin.kt                    # Oboe backend (Phase 5 / stretch)

test/
  dsp/
    log_sine_sweep_test.dart
    dsp_pipeline_service_test.dart        # Synthetic pickup model: 4 kHz, Q=3
    dsp_worker_test.dart                  # Busy state, cancel token, backpressure
    fft_provider_test.dart                # fftea vs known analytic result
  calibration/
    calibration_service_test.dart         # Mock chain response + correction verification
  data/
    measurement_repository_test.dart      # Atomic write + corrupt file recovery
    measurement_migrator_test.dart        # Schema v0 → v1 migration
  audio/
    audio_engine_service_test.dart        # State machine: all transitions, interruption, hot-plug, sample rate mismatch
```

---

## Development Phases

| Phase | Work | Duration |
|---|---|---|
| **0 — Scaffold** | Project structure; mock platform plugin (synthetic 4 kHz resonance); all screens wired to mock data; `MeasurementMigrator` with `schemaVersion`; persistent `DspWorker` stub with busy/cancel; `FftProvider` abstraction; atomic file write helper; CI pipeline (GitHub Actions: test + analyze + build macOS) | 1 week |
| **1 — DSP Engine** | `LogSineSweep` + inverse filter; `DspPipelineService` (deconvolution, chain correction, Tikhonov regularization, configurable search band, all-peaks detection); `FftProvider` benchmark (fftea vs Accelerate); unit tests against synthetic 4 kHz Q=3 pickup model | 1–2 weeks |
| **2 — Calibration** | `CalibrationService` (chain calibration flow, `H_chain` storage, atomic writes, invalidation rules); level check tool; onboarding flow; `CalibrationExpiryBanner`; Measure screen blocked state | 1 week |
| **3 — Audio Plugin** | macOS entitlements; Swift `AVAudioEngine` plugin (native buffer capture, single `MethodChannel` transfer); `AVAudioTime` co-start; sample rate negotiation; USB hot-plug detection; audio session interruption handling; cross-correlation alignment check; dropout detection; golden-ratio sweep spacing; end-to-end validation against known pickup (manual gate: ±50 Hz of REW reference) | 2–3 weeks |
| **4 — UI & Persistence** | History screen; CSV export; `ResonanceSearchBand` UI; all-peaks chart annotation; cursor inverse transform; `Semantics` accessibility wrappers; spectral hum suppression toggle; memory management (discard raw buffers post-pipeline); app polish | 1–2 weeks |
| **5 — Windows** | WASAPI backend; Windows USB device change notification for hot-plug; sample rate negotiation | 1–2 weeks |
| **6 — iOS** | AVAudioEngine iOS backend; `NSMicrophoneUsageDescription`; Camera Connection Kit USB class 2 compatibility matrix testing | 1–2 weeks |
| **7 — Distribution** | macOS .dmg (direct); iOS TestFlight → App Store | — |

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
