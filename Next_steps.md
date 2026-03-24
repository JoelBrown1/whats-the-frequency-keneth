# Next Steps — What's the Frequency, Kenneth

> Written 2026-03-23. Based on Architecture.md, ARCHITECTURE_AUDIT.md, and full codebase review.

---

## The Honest Verdict

The architecture is sound and the implementation is further along than most projects at this stage. But **the entire DSP pipeline and WASAPI plugin have zero hardware validation**. Every algorithm, timing constant, and error threshold was designed for a Scarlett 2i2 but has never been run against one. The first hardware session will surface real numbers for the look-ahead margin, pre-roll depth, Tikhonov ε, and alignment threshold — all of which are currently educated guesses.

**The next engineering priority is a hardware validation sprint on macOS before building anything else.**

---

## Tier 1 — Blocking a first real measurement

These must work before the app can produce a valid pickup resonance measurement on real hardware.

### Audio hardware validation (macOS)
The Swift plugin is implemented but completely untested against physical hardware. Critical risks:
- `AVAudioTime` co-start — both nodes must start in the same render cycle
- 100 ms look-ahead margin for USB scheduling jitter — may need tuning per interface
- 8-step engine reconnection sequence after hot-plug — any deviation produces silence with no clear error

Any of these can fail silently. The app returns data that looks valid but is time-shifted or corrupt.

### Sweep clipping check (Step 0 of capture)
Architecture.md specifies: play a 1-second excerpt at max amplitude before every measurement; abort with `RecoverableError(OUTPUT_CLIPPING)` if any sample exceeds −1 dBFS. Confirm this is wired in `MeasureScreen` / `AudioEngineService`. Without it the user gets a corrupt capture with no explanation.

### Mains frequency measurement
`DeviceConfig.measuredMainsHz` defaults to 50.0 Hz but is never measured at runtime unless the user explicitly runs the mains measurement step. Both the golden-ratio hum cancellation and Stage 7b spectral hum suppression depend on the *measured* value. On a 60 Hz grid (US, Japan) the defaults are wrong and hum suppression lands on the wrong harmonics.

### Sample rate verification
After `AVAudioEngine` starts, verify the active hardware rate equals 48 kHz. Surface `DeviceError` with an explicit instruction if it does not. A 44.1 kHz or 96 kHz system produces systematically frequency-shifted results with no warning and no obvious error.

---

## Tier 2 — Blocking a complete user flow

The app can take a measurement, but the surrounding flow is incomplete.

### Onboarding flow
Architecture.md specifies: Welcome → Hardware Checklist → Device Selection → **Mains Frequency** → Level Check → Chain Calibration → First Measurement.

- Mains frequency step is not wired into the flow
- `OnboardingStep` enum is scaffolded but `OnboardingScreen` still uses magic integers
- `lastCompletedOnboardingStep` resume-mid-flow field: confirm implemented so users interrupted after device selection don't restart from step 1

### History screen
Listed as "functional but incomplete." Two issues that cannot be retrofitted:

- **Two-stage loading** — `loadSummaries()` (metadata only, fast) and `loadFull(id)` (on demand). If all measurement JSON is loaded at launch the screen lags badly at modest measurement counts.
- **By-pickup grouping** — alongside the flat date-sorted list.

### Results screen — Overlay and Export
- **Overlay action:** up to 5 measurements with distinct colours; `sweepConfig` comparability guard warns when configs differ. Confirm wired.
- **Export action:** `CsvExporter` class not yet implemented. Requires locale-safe decimal formatting (`toStringAsFixed(4)`, not `toString()`) and REW-compatible headers (`Freq(Hz),SPL(dB)`).

### DspWorker backpressure
If the user triggers a second measurement while DSP is running, a message queues silently on the `SendPort` with no cancellation path. Required:
- `bool get busy` stream exposed by `DspWorker`
- `AudioEngineService` rejects `Armed` transition while `busy == true`
- Measure screen button disabled while `busy`

### Calibration orphan reconciliation
On reinstall or after clearing app data, `activeCalibrationId` in SharedPreferences resets but calibration files on disk survive. `CalibrationService.init()` must:
1. If `activeCalibrationId` is null, scan `calibrations/` directory
2. If one valid non-expired file exists, restore it as active
3. If multiple exist, take the most recent
4. If none, proceed uncalibrated

Without this, users who reinstall lose calibration with no diagnostic.

---

## Tier 3 — Required before any distribution

### macOS App Sandbox file access
`com.apple.security.files.user-selected.read-write` and `downloads.read-write` entitlements are required for CSV export via file picker and `~/Downloads` write. Without them the save panel is silently blocked under App Sandbox. Both must be declared in `Release.entitlements` and `DebugProfile.entitlements`.

### `PrivacyInfo.xcprivacy`
App Store Connect has rejected binaries without this since May 2024. Add to `macos/Runner/` and `ios/Runner/`:

| API category | Usage | Reason code |
|---|---|---|
| `UserDefaults` | `SharedPreferences` for `DeviceConfig` | `CA92.1` |
| File timestamp APIs | Calibration age check | `C617.1` |

Cannot be added retroactively after submission.

### macOS notarization
An un-notarized `.dmg` is Gatekeeper-blocked for all users without explicit override. Add to CI after `flutter build macos --release`:

```yaml
- run: xcrun notarytool submit ... --wait
- run: xcrun stapler staple ...
```

### WASAPI EventSink thread safety (Windows)
`EmitLevel` and `EmitDeviceEvent` in `audio_engine_plugin.cpp` are called directly from `level_thread_`, `capture_thread_`, and the COM notification thread. Works at low emission rates but races on sink teardown. Marshal to the Flutter engine thread via `PostMessage` before Windows build goes to end-users.

---

## Tier 4 — Important but deferrable

### DSP integration tests
Highest-value missing tests. Feed a synthetic impulse response (known resonance frequency, known Q) through the full 10-stage pipeline; assert reported resonance is within ±50 Hz of ground truth and Q is within ±0.2. Validates the entire measurement path in a single automated assertion.

### Checkpoint resume tests
`CaptureCheckpointService` write/reload cycle and `MeasureScreen` resume offer have no test coverage. A crash mid-measurement that silently discards progress is a poor user experience.

### `TransferableTypedData` for PCM transfer
Sending a 576 KB `Float32List` through `SendPort` copies the buffer on each of N sweeps (2.3 MB of copies per measurement plus GC pressure). Use `TransferableTypedData` to transfer ownership without copying — the buffer is discarded after transfer anyway.

### Dynamic pre-roll (audio I/O buffer size)
Pre-roll is currently hardcoded for ~512-sample buffers. Users with Focusrite Control set to 4096-sample buffers see dropout false positives. After `AVAudioEngine` starts, read `kAudioDevicePropertyBufferFrameSize` and compute pre-roll as `bufferSize × 4`.

### App lifecycle / background handling
If the OS suspends audio mid-sweep (incoming call, home button on iOS), the app must abort and transition to `RecoverableError(AppBackgrounded)`. Subscribe to:
- `UIApplication.willResignActiveNotification` (iOS)
- `NSApplication.willResignActiveNotification` (macOS)

On receipt: if state is `Playing` or `Capturing`, abort immediately. On `didBecomeActiveNotification`: re-activate audio session and offer retry.

### Dark / workshop theme
`ThemeMode.system` with chart colours designed for dark background. Coloured curves on dark grey are significantly more readable in dim studio environments. Chart background colour must come from `AppTheme`, not be hardcoded.

### Accessibility
Wrap `FrequencyResponseChart` in `Semantics`:
```dart
Semantics(
  label: 'Frequency response chart. '
         'Resonance frequency: ${result.resonanceHz.toStringAsFixed(0)} Hz. '
         'Q-factor: ${result.qFactor.toStringAsFixed(1)}.',
  child: FrequencyResponseChart(data: result),
)
```

### `OnboardingStep` enum
The enum is scaffolded. Wire it into `OnboardingScreen` and `DeviceConfigProvider` to replace the remaining magic integer comparisons. Low effort, prevents step-ordering regressions.

### `ResonancePeak` doc comment
Add a comment to `frequency_response.dart` explaining the Q-factor convention used (`Q = f₀ / (f_high − f_low)`, −3 dB points). Extract to its own file if it grows.

---

## Tier 5 — Future platforms

### iOS
Gated on macOS hardware validation. USB audio class 2 reliability via Camera Connection Kit requires physical verification with a Scarlett 2i2 before any iOS-specific work begins. Do not start iOS until at least three full measurement sessions on macOS have completed without audio session errors.

### Android
Tier 3 stretch goal. Oboe + USB audio class 2 support is fragmented across manufacturers. Not planned until iOS is validated.

---

## Hardware Validation Sprint Checklist

The first session with a physical Scarlett 2i2 should verify and record the following. Results feed back into code constants and Architecture.md.

- [ ] `AVAudioTime` co-start confirmed — both nodes start in the same render cycle (verify via render timestamp delta on first buffer)
- [ ] Look-ahead margin of 100 ms sufficient — log actual achieved start delta; if >10 ms consistently, increase margin
- [ ] Cross-correlation alignment offset within ±500 samples on sweep 0
- [ ] Sweep 1–N offsets within ±2 samples of baseline
- [ ] Dropout detection fires correctly on deliberate disconnect mid-sweep
- [ ] Level meter EventChannel emitting at ~10 Hz (not flooding at buffer callback rate)
- [ ] `startLevelCheckTone` plays 1 kHz sine audibly through headphone output
- [ ] Chain calibration pre-check correctly rejects a connected pickup (signal above −40 dBFS)
- [ ] Chain calibration pre-check passes with 10 kΩ resistor substituted
- [ ] Full measurement produces a resonance frequency within ±50 Hz of a reference tool (REW or Pickup Wizard) on the same pickup
- [ ] Hot-plug disconnect mid-sweep transitions to `DeviceError` (not hang)
- [ ] Reconnect after hot-plug recovers to `Idle` without engine restart required
