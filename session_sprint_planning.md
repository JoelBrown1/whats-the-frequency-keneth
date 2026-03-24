# Session Sprint Planning — What's the Frequency, Kenneth

> Written 2026-03-23. Derived from Next_steps.md.
> Each session is designed to fit within a single Claude Code context window.
> Reference Next_steps.md for full rationale and implementation detail on each item.

---

## Constraint: Hardware Validation Cannot Be Coded

Tier 1 of Next_steps.md requires a physical Scarlett 2i2, exciter coil, test pickup, and a reference measurement tool (REW or Pickup Wizard). No coding session can substitute for this. Run the hardware validation sprint checklist in Next_steps.md before any Tier 2 session that touches the measurement path.

---

## Session 1 — Tier 3 Quick Wins (Distribution Blockers) ✓ COMPLETE

**Goal:** Unblock App Store submission and Windows distribution. All small, self-contained changes.

- [x] `PrivacyInfo.xcprivacy` — already present in `macos/Runner/` with correct reason codes (CA92.1, C617.1)
- [x] `macos/Runner/Release.entitlements` + `DebugProfile.entitlements` — `user-selected.read-write` and `downloads.read-write` already present
- [x] GitHub Actions CI — `xcrun notarytool submit` + `xcrun stapler staple` added; gated to `main` branch push only
- [x] WASAPI EventSink thread safety — `EmitLevel` and `EmitDeviceEvent` now marshal via `pending_` queue + `PostMessage(flutter_hwnd_, kWmDrainQueue, ...)`; drained on UI thread via `RegisterTopLevelWindowProcDelegate`

**Implementation note — WASAPI marshalling:**
Background threads push a `std::function<void()>` onto `pending_` (mutex-protected `std::deque`) then `PostMessage` `kWmDrainQueue = WM_APP + 1` to the Flutter HWND. A `TopLevelWindowProcDelegate` registered in the constructor handles `kWmDrainQueue` on the UI thread and calls `DrainQueue()`. The Flutter HWND is cached on the first delegate invocation. Delegate is unregistered in the destructor.

---

## Session 2 — Tier 4 Small Items (Low Effort, High Value) ✓ COMPLETE

**Goal:** Clean up technical debt that is individually small but collectively meaningful.

- [x] `OnboardingStep` enum — `setOnboardingStep(int)` → `setOnboardingStep(OnboardingStep)` in `DeviceConfigProvider`; `_advance()` and back-button in `OnboardingScreen` now pass enum values; `.index` called only at persistence boundary
- [x] `ResonancePeak` — class-level doc comment added explaining `Q = f₀ / (fHighHz − fLowHz)`, −3 dB points, and typical pickup Q range (1–5)
- [x] `FrequencyResponseChart` Semantics — already implemented; no changes needed
- [x] Dark / workshop theme — `app_theme.dart` already has full light/dark variants with `AppChartTheme` extension; `main.dart` changed from `ThemeMode.dark` to `ThemeMode.system`
- [x] Sample rate verification — added to `handleRunCapture` in `AudioEnginePlugin.swift` after `engine.start()`; checks `engine.inputNode.outputFormat(forBus: 0).sampleRate`; surfaces `SAMPLE_RATE_MISMATCH` with explicit Focusrite Control instruction if rate != expected

**Implementation notes:**
- `DeviceConfig.lastCompletedOnboardingStep` remains `int` for JSON serialisation; `.index` conversion happens inside `setOnboardingStep`.
- `SAMPLE_RATE_MISMATCH` from Swift arrives as `PlatformException`, caught in `AudioEngineService.runCapture` → `_transitionToRecoverableError`; `MeasureScreen._ErrorBlock` already maps the code to `l10n.errorSampleRateMismatch`.

---

## Session 3 — CSV Export + Results Screen Export Action ✓ COMPLETE

**Goal:** Complete the Results screen export action end-to-end.

- [x] `CsvExporter` class — already implemented at `lib/data/csv_exporter.dart`; REW header `Freq(Hz),SPL(dB)`, `toStringAsFixed(4)` throughout
- [x] Results screen Export action — already wired in `_export()`; writes to `getDownloadsDirectory()` with fallback to documents; filename `wtfk_{Hz}Hz_Q{q}_{date}.csv`
- [x] `sweepConfig` comparability guard — already wired in `_pickOverlay()`; SnackBar shown with `l10n.sweepConfigMismatchWarning` when configs differ
- [x] Results screen Overlay action — already implemented; `_overlayResponse` / `_overlayLabel` state managed; overlay chart rendered via `FrequencyResponseChart`
- [x] `CsvExporter` tests — 8 tests written in `test/data/csv_exporter_test.dart`; covers header, first/last data lines, line count, period separator, zero formatting, label exclusion
- [x] `device_config_provider_test.dart` — updated `setOnboardingStep` call site to pass `OnboardingStep.mains` (type-safe, carries forward Session 2 change)

**Test count: 74 passing (was 66 + 8 new)**

---

## Session 4 — History Screen

**Goal:** Make the History screen production-ready.

- [ ] Two-stage loading — implement `loadSummaries()` (metadata only: id, timestamp, pickupLabel, pickupId, resonanceFrequencyHz, qFactor) and `loadFull(id)` on `MeasurementRepository`
- [ ] `MeasurementSummary` model — new lightweight model; add `fromJson` constructor reading only summary fields
- [ ] History screen — bind to `loadSummaries()`; call `loadFull()` only when a measurement is opened for display or overlay
- [ ] By-pickup grouping — add grouping view alongside flat date-sorted list
- [ ] History screen lazy load test — assert `loadFull` is not called during list render

**Files likely touched:**
`lib/data/measurement_repository.dart`, `lib/models/measurement_summary.dart` (new), `lib/ui/screens/history_screen.dart`, `test/data/measurement_repository_test.dart`

---

## Session 5 — DspWorker Backpressure + Calibration Orphan Reconciliation ✓ COMPLETE

**Goal:** Prevent silent data corruption from concurrent operations and lost calibration state.

- [x] `DspWorker.busy` stream — already implemented (`_busyController`, `busyStream`, `busy` getter, toggled in `process()`)
- [x] Measure screen button guard — guarded by engine state machine: `_ActiveMeasurement` shown (not the button) while engine is in `armed`/`playing`/`capturing`/`analyzing`; `arm()` throws if not `Idle`
- [x] `AudioEngineService` — rejects `Armed` transition while DSP is busy (engine in `Analyzing` state; `arm()` throws `StateError`)
- [x] `CalibrationService.init()` orphan reconciliation — `_loadLatest()` already scans `calibrations/`; `init()` updated to use `_setActiveCalibration()` so `notifyListeners()` fires on load
- [x] `CalibrationService` extended `ChangeNotifier`; `calibrationProvider` changed to `ChangeNotifierProvider` and calls `init()` in background; `setCalibrationId()` called after successful calibration in `CalibrationFlowWidget`
- [x] Tests — `DspWorker` busy flag: 4 tests in `test/dsp/dsp_worker_test.dart`; orphan reconciliation: 5 tests added to `test/calibration/calibration_service_test.dart`

**Implementation notes:**
- `DspPipelineService` uses `Isolate.run()` directly (not `DspWorker`); `DspWorker` is tested as a standalone persistent-isolate alternative.
- `CalibrationService extends ChangeNotifier` → `ChangeNotifierProvider` gives reactive rebuilds to `MeasureScreen` when orphan calibration loads.
- `calibrationProvider` fires `init()` via `ref.read(deviceConfigProvider.future).then(...)` — background init, no startup delay.
- Orphan reconciliation surfaces to `DeviceConfig`: if `activeCalibrationId` was null but a file was found, `setCalibrationId(id)` is called so future restarts use the ID path, not the scan path.
- `calibration_flow_widget.dart` now calls `setCalibrationId(cal.id)` after `runChainCalibration()` succeeds.

**Test count: 88 passing (was 79 + 9 new)**

**Files likely touched:**
`lib/dsp/dsp_worker.dart`, `lib/dsp/dsp_pipeline_service.dart`, `lib/audio/audio_engine_service.dart`, `lib/ui/screens/measure_screen.dart`, `lib/calibration/calibration_service.dart`, `test/dsp/`, `test/calibration/`

---

## Session 6 — Onboarding Completion + Mains Frequency Wiring

**Goal:** Complete the onboarding flow as specified in Architecture.md.

Full flow: Welcome → Hardware Checklist → Device Selection → **Mains Frequency** → Level Check → Chain Calibration → First Measurement

- [ ] Mains frequency measurement step — wire into `OnboardingScreen`; trigger `CalibrationService.measureMainsFrequency()`; store result in `DeviceConfig.measuredMainsHz`
- [ ] Resume mid-flow — confirm `lastCompletedOnboardingStep` persisted in `SharedPreferences`; `OnboardingScreen` resumes from correct step on relaunch
- [ ] Calibration orphan reconciliation (if not done in Session 5) — `CalibrationService.init()` restore
- [ ] Sweep clipping check (Step 0) — confirm wired in `MeasureScreen` / `AudioEngineService` before every measurement run
- [ ] `DeviceConfig` default mains Hz — confirm that `50.0 Hz` default is clearly marked as a placeholder; UI warns if mains step has not been run

**Files likely touched:**
`lib/ui/screens/onboarding_screen.dart`, `lib/calibration/calibration_service.dart`, `lib/providers/device_config_provider.dart`, `lib/ui/screens/measure_screen.dart`, `lib/audio/audio_engine_service.dart`

---

## Session 7 — DSP Integration Tests

**Goal:** Validate the full 10-stage DSP pipeline against a synthetic known input.

- [ ] Synthetic impulse response fixture — generate a known resonance (e.g. 4 kHz, Q=3) as a `Float32List`; store as a test fixture or generate in test setup
- [ ] Full pipeline integration test — feed fixture through `DspPipelineService.processMultiple`; assert reported resonance within ±50 Hz of 4000 Hz; assert Q within ±0.2 of 3.0
- [ ] Hum suppression test — inject synthetic mains tone at 50 Hz harmonics into fixture; confirm Stage 7b reduces harmonic amplitude
- [ ] Chain correction test — apply known `H_chain`; assert division produces flat response when input equals chain response
- [ ] Tikhonov regularisation test — assert pipeline does not produce infinite or NaN values at band edges with near-zero sweep energy

**Files likely touched:**
`test/dsp/dsp_pipeline_integration_test.dart` (new), `test/dsp/fixtures/` (new)

---

## Session 8 — Checkpoint Resume Tests + TransferableTypedData

**Goal:** Cover the checkpoint resume flow and reduce PCM copy overhead.

- [ ] `CaptureCheckpointService` tests — write N sweeps; reload; assert sample count and config match; assert resume offered when config matches; assert discard when config differs
- [ ] `MeasureScreen` resume flow test — mock checkpoint service returning pre-loaded sweeps; assert screen offers resume; assert sweep loop starts at `pass = preloaded.length`
- [ ] `TransferableTypedData` — replace `SendPort.send(Float32List)` with `TransferableTypedData.fromList([samples])` in `AudioEngineMethodChannel` → `DspWorker` transfer path; update receiving side in `dsp_isolate.dart`
- [ ] Dynamic pre-roll (stretch) — read `kAudioDevicePropertyBufferFrameSize` after engine start; compute pre-roll as `bufferSize × 4` rather than hardcoded value

**Files likely touched:**
`test/audio/capture_checkpoint_test.dart` (new), `test/ui/measure_screen_resume_test.dart` (new), `lib/audio/audio_engine_method_channel.dart`, `lib/dsp/dsp_isolate.dart`

---

## Session 9 — App Lifecycle / Background Handling

**Goal:** Prevent silent corrupt captures when the OS suspends audio mid-sweep.

- [ ] macOS — subscribe to `NSApplication.willResignActiveNotification`; if state is `Playing` or `Capturing`, abort and transition to `RecoverableError(AppBackgrounded)`
- [ ] macOS — subscribe to `NSApplication.didBecomeActiveNotification`; re-activate audio session and offer retry
- [ ] iOS (when iOS work begins) — same pattern via `UIApplication` notifications
- [ ] `RecoverableError(AppBackgrounded)` — confirm localised message wired in `MeasureScreen._ErrorBlock`
- [ ] Audio session interruptions — subscribe to `AVAudioEngine` configuration change notifications; transition to `RecoverableError(Interrupted)` on receipt

**Files likely touched:**
macOS Swift plugin, `lib/audio/audio_engine_service.dart`, `lib/ui/screens/measure_screen.dart`, `lib/l10n/app_en.arb`

---

## Hardware Validation Sprint (Not a Coding Session)

Run after Session 1 or 2 and before any further Measure screen work. See checklist in `Next_steps.md`.

**Required equipment:**
- Focusrite Scarlett 2i2 (USB connected)
- Exciter coil (41–44 AWG, 100–200 turns, DCR 118–177 Ω)
- Test pickup (any known pickup)
- 10 kΩ resistor (for chain calibration pre-check)
- Reference tool — REW or Pickup Wizard — measuring same pickup

**What to record from this session:**
- Actual look-ahead margin needed (target: 100 ms; adjust if co-start misses consistently)
- Actual alignment offset on sweep 0 (expected: within ±500 samples)
- Offset drift on sweeps 1–N (expected: within ±2 samples of baseline)
- Measured resonance vs reference tool (expected: within ±50 Hz)
- Any `AUDCLNT_E_DEVICE_IN_USE` errors (if Focusrite Control is running)

Update `Architecture.md` timing constants and `Next_steps.md` with findings.

---

## Platform Sessions (Future — Gated on macOS Validation)

### iOS Sprint (2–3 sessions)
Do not start until three full macOS measurement sessions have completed without audio session errors. Risks: USB audio class 2 reliability via Camera Connection Kit; AVAudioSession category conflicts.

### Android Sprint (Future — Stretch Goal)
Not planned. Oboe + USB audio class 2 is fragmented across manufacturers. Revisit after iOS is validated.

---

## Session Order Recommendation

```
Session 1  →  Session 2  →  Hardware Validation
                                    ↓
              Session 3  →  Session 4  →  Session 5
                                               ↓
              Session 6  →  Session 7  →  Session 8  →  Session 9
                                               ↓
                                    iOS Sprint (future)
```

Sessions 1 and 2 are independent of hardware and can be done immediately. Sessions 3–9 benefit from hardware validation findings but are not strictly blocked by it except where noted.
