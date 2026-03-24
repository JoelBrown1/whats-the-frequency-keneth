# Architecture Audit — What's the Frequency, Kenneth

> Audited 2026-03-23 against the Phase 0 codebase.
> Updated 2026-03-23 — post-implementation pass. All Phase 0 blockers resolved.
> Updated 2026-03-23 — Phase 2 implementation pass. Navigation, logging, constants, spectral hum suppression, and Windows WASAPI plugin all built.

---

## Executive Summary

All Phase 0 critical blockers and all Phase 2 quality items have been resolved. The codebase is fully implemented across all targeted layers:

- **DSP pipeline**: 10-stage deconvolution, Tikhonov regularisation, spectral hum suppression (Stage 7b), 1/3-octave smoothing, Q-factor extraction.
- **Platform layer**: macOS (`AudioEnginePlugin.swift`) and Windows (`audio_engine_plugin.cpp`, WASAPI exclusive mode) both implemented.
- **Navigation**: `go_router` v14 with type-safe named routes via `routerProvider`.
- **Logging**: `logger` package wired throughout service layer (`AudioEngineService`, `CalibrationService`, `DspPipelineService`).
- **Constants**: Centralised in `lib/constants.dart`; all chart bounds and mock values reference named constants.
- **Test coverage**: 66 tests passing across audio engine state machine, calibration service, DSP pipeline, measure screen widgets, device config provider, and data layer.

Remaining work is Phase 3 polish: onboarding step enum, production WASAPI thread-safety hardening, expanded DSP integration tests, and end-to-end hardware validation.

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│       UI Layer (Screens & Widgets)      │
├─────────────────────────────────────────┤
│   Business Logic Layer (Providers)      │
├─────────────────────────────────────────┤
│       Domain / Service Layer            │
│   AudioEngineService · DspPipeline      │
│   CalibrationService                    │
├─────────────────────────────────────────┤
│       Data / Repository Layer           │
│   MeasurementRepository · Pickup        │
│   MeasurementMigrator                   │
│   CaptureCheckpointService              │
├─────────────────────────────────────────┤
│       Platform / External Layer         │
│   AudioEnginePlatformInterface          │
│   AudioEngineMethodChannel · Mock       │
│   AudioEnginePlugin (Swift / macOS)     │
│   AudioEnginePlugin (WASAPI / Windows)  │
└─────────────────────────────────────────┘
```

Dependency flow is correctly unidirectional. No circular dependencies observed.

---

## Strengths

### 1. Data Layer — Solid
- **Atomic writes.** Repositories write to `.tmp` then rename, preventing corruption on force-quit. Applies to `MeasurementRepository`, `PickupRepository`, and `CaptureCheckpointService`.
- **Concurrency safety.** `synchronized` package Lock serialises concurrent writes per repository.
- **Forward-compatible schema migration.** `MeasurementMigrator` handles v0→v1 and passes unknown future versions through unchanged.
- **Well-tested.** 26 tests cover the data layer comprehensively: CRUD, atomic behaviour, corruption recovery, JSON round-trips, and schema migration.

### 2. Audio Engine — Robust State Machine
- Explicit state enum (`Idle → Armed → Playing → Capturing → Analysing → Complete`) prevents invalid operations.
- All state transitions are guarded with assertions.
- Platform abstraction (`AudioEnginePlatformInterface`) is cleanly separated from business logic, with a realistic `MockAudioEnginePlatform` for debug/test builds.
- Device disconnect events are subscribed on initialisation and drive state transitions correctly.
- Error states (`recoverableError`, `deviceError`) are surfaced to the `MeasureScreen` via `_ErrorBlock`.
- State machine transitions are logged via `appLog` at appropriate severity levels.

### 3. DSP Infrastructure — Fully Implemented
- `DspWorker` uses a two-port isolate (work + cancel), ensuring cancellation arrives immediately without blocking.
- `FftProvider` wraps `fftea` behind an abstraction, making the FFT implementation swappable.
- `LogSineSweep` generates mathematically correct logarithmic sweeps with pre-computed inverse filter.
- Full 10-stage pipeline: deconvolution → windowing → FFT → chain correction → Tikhonov regularisation → magnitude → frequency taper → **spectral hum suppression** → 1/3-octave smoothing → peak detection → Q-factor.
- Cross-correlation alignment (`computeAlignmentOffset`) runs in a background isolate via `Isolate.run()`.
- `DspPipelineService.processMultiple` accepts optional `mainsHz` and passes it through to each `DspPipelineInput`.

### 4. Measurement Robustness
- **Checkpoint persistence:** `CaptureCheckpointService` writes each accepted capture atomically as `{index}.f32` (raw Float32LE). On next launch, `MeasureScreen` offers to resume from interrupted captures if the `SweepConfig` matches.
- **Hum cancellation:** Golden-ratio inter-sweep delay (`1000 + ((1/mainsHz)/φ) * 1000` ms) mitigates mains harmonics across the N-sweep average.
- **Alignment validation:** Sweep 0 baseline offset validated within ±500 samples; sweeps 1–N discarded and retried if offset drifts by >±2 samples.

### 5. Navigation — Type-Safe
- `go_router` v14 replaces string-based `Navigator` calls throughout.
- `routerProvider` exposes `GoRouter` to `MaterialApp.router` via Riverpod.
- All routes are named and listed in a single file (`lib/routing/app_router.dart`); no route strings scattered across screens.
- Typed arguments passed via `state.extra` (e.g. `FrequencyResponse?` to `ResultsScreen`).

### 6. Structured Logging
- `appLog` global (`lib/logging/app_logger.dart`) backed by the `logger` package.
- `Level.warning` in release builds, `Level.debug` in debug/profile builds.
- Wired into `AudioEngineService` (state transitions, device errors), `CalibrationService` (pre-check pass/fail, completion), and `DspPipelineService` (pipeline start, peak result).

### 7. Immutable Models Throughout
- All models use `const` constructors, `copyWith()`, and `==`/`hashCode`.
- Consistent `fromJson`/`toJson` pattern across the codebase.

### 8. Naming Conventions — Consistent
- PascalCase classes, camelCase methods/variables, `k`-prefixed constants, `Provider` suffix on providers, `Screen` suffix on screens.

---

## Resolved Issues

The following issues have been fully resolved.

| # | Issue | Resolution |
|---|-------|------------|
| 1 | DSP pipeline was a stub | Full 10-stage pipeline implemented in `dsp_pipeline_service.dart` and `dsp_isolate.dart` |
| 2 | `CalibrationService` threw `UnimplementedError` | `runChainCalibration()` and `measureMainsFrequency()` implemented |
| 3 | Error states never reached the UI | `_ErrorBlock` in `MeasureScreen` watches `audioEngineProvider` and surfaces all error codes with localised messages |
| 4 | Service locator anti-pattern | `audioEnginePlatformProvider` injects the platform via Riverpod; static singleton removed |
| 5 | Placeholder widgets in production screens | All screens fully wired: onboarding, setup, measure, results, calibration |
| 6 | No measurement lifecycle persistence | `CaptureCheckpointService` persists each accepted sweep; resume offered on next launch |
| 7 | Unused `csv` dependency | Removed from `pubspec.yaml` |
| 8 | `intl: any` unpinned → conflict | Pinned to `intl: ^0.20.2` (matches flutter_localizations SDK requirement) |
| 8b | Localisation strings bypassed | All screens use `AppLocalizations`; calibration widget and error messages fully localised |
| 9 | String-based navigation | `go_router` v14 adopted; all routes type-safe via `routerProvider`; `main.dart` uses `MaterialApp.router` |
| 10 | No structured logging | `logger` package wired; `appLog` global in `lib/logging/app_logger.dart`; level-appropriate calls throughout service layer |
| 11 | Hard-coded chart bounds and mock constants | `lib/constants.dart` centralises `kChartMinFreqHz`, `kChartMaxFreqHz`, `kDefaultMainsHz`, `kMockResonanceHz`; all callsites updated |
| 12 | No Windows audio plugin | `windows/runner/audio_engine_plugin.{h,cpp}` implements full WASAPI exclusive-mode play+capture, level meter, check tone, and device change events; registered in `flutter_window.cpp` |
| 13 | Spectral hum suppression unimplemented | Stage 7b added to `dsp_isolate.dart`; `_applyHumSuppression` interpolates across ±10 bins around first 39 mains harmonics |
| 14 | `mocktail` imported but unused | `mocktail` is used in provider and screen tests |
| 15 | `shared_preferences` status unclear | Confirmed in active use by `DeviceConfigProvider` for `DeviceConfig` persistence |

---

## Remaining Issues

### Significant

#### 1. Onboarding Step Numbers Are Magic Integers
```dart
const int kOnboardingStepWelcome = 0;
const int kOnboardingStepHardware = 1;
// ...
```
These should be an `enum`. Magic integers make reordering steps error-prone and provide no type safety. `OnboardingStep` enum was scaffolded but the provider and screen still compare against raw integers.

#### 2. Some Hard-Coded Values Remain

| Location | Value | Status |
|----------|-------|--------|
| `calibration_expiry_banner.dart` | `Duration(minutes: 30)` | Not configurable |
| `device_config.dart` | `measuredMainsHz = 50.0` | Default only; measured at runtime only if user runs mains step |

`frequency_response_chart.dart` chart bounds and `mock_audio_engine_platform.dart` resonance frequency are resolved (now use `kChartMinFreqHz`, `kChartMaxFreqHz`, `kMockResonanceHz`).

---

### Minor

#### 3. `ResonancePeak` Lives Inside `frequency_response.dart`
`ResonancePeak` is only used as a field on `FrequencyResponse`. The class deserves a doc comment explaining the Q-factor convention used (`Q = f₀ / (f_high − f_low)`), or extraction to its own file.

#### 4. WASAPI EventSink Thread Safety
`EmitLevel` and `EmitDeviceEvent` in `audio_engine_plugin.cpp` are called directly from background threads (`level_thread_`, `capture_thread_`, COM notification thread). Sink calls should be marshalled to the Flutter engine thread via `PostMessage` / `SendMessage` for production hardening against teardown races.

---

## Test Coverage Assessment

| Area | Tests | Quality |
|------|-------|---------|
| Data models (JSON, equality) | 15 | Excellent |
| Repositories (CRUD, atomic, corruption) | 11 | Excellent |
| Schema migration | 3 | Good |
| AudioEngineService state machine | ~8 | Good |
| CalibrationService (happy path, pre-check failure) | ~6 | Good |
| DSP pipeline unit tests | ~8 | Good (log sine sweep, resonance band, sweep config) |
| MeasureScreen widget tests | ~8 | Good |
| DeviceConfigProvider | ~7 | Good |
| Widget smoke test | 1 | Minimal |
| DSP pipeline integration (known input/output) | 0 | Missing |
| Checkpoint service (resume flow) | 0 | Missing |
| go_router navigation tests | 0 | Missing |
| Error path UI rendering | 0 | Missing |
| Integration (end-to-end) | 0 | Missing |

**Total: 66 passing.** The service layer is now meaningfully tested. DSP integration tests with known input/output pairs and checkpoint resume flow tests are the highest-value gaps.

---

## Prioritised Recommendations

### Phase 3 — Polish
1. **Add DSP integration tests.** Feed a synthetic impulse through the full pipeline and assert resonance frequency within ±50 Hz of a known ground truth. This is the highest-value missing test — it validates the entire measurement path in one assertion.
2. **Add checkpoint resume flow tests.** `CaptureCheckpointService` write/reload cycle and `MeasureScreen` resume offer have no test coverage. A crash mid-measurement that silently discards progress is a poor user experience.
3. **Replace magic onboarding step integers with `OnboardingStep` enum.** Low effort, prevents step-ordering regressions. The enum file exists; wire it into `OnboardingScreen` and `DeviceConfigProvider`.
4. **Harden WASAPI EventSink thread safety.** Marshal `EmitLevel` and `EmitDeviceEvent` calls to the Flutter engine thread before the Windows build goes to end-users.

### Phase 4 — Distribution
5. **CSV export.** `CsvExporter` class with locale-safe decimal formatting and REW-compatible column headers (`Freq(Hz),SPL(dB)`). Unit test asserting header row and a known data line.
6. **Accessibility.** Wrap `FrequencyResponseChart` in `Semantics` with resonance frequency and Q-factor in the label.
7. **macOS notarization.** Add `xcrun notarytool` step to CI after `flutter build macos --release`.

---

## File Quality Tier Summary

**Well-implemented:**
`audio_engine_service.dart`, `audio_engine_platform_interface.dart`, `audio_engine_method_channel.dart`, `mock_audio_engine_platform.dart`, `measurement_repository.dart`, `pickup_repository.dart`, `measurement_migrator.dart`, `log_sine_sweep.dart`, `dsp_worker.dart`, `dsp_pipeline_service.dart`, `dsp_isolate.dart`, `calibration_service.dart`, `capture_checkpoint_service.dart`, `measure_screen.dart`, `results_screen.dart`, `calibration_screen.dart`, `onboarding_screen.dart`, `setup_screen.dart`, `main.dart`, `app_router.dart`, `app_logger.dart`, `constants.dart`, `audio_engine_plugin.cpp` (macOS), `audio_engine_plugin.cpp` (Windows), all model files.

**Functional but incomplete:**
`frequency_response_chart.dart` (chart bounds now use constants; cursor interaction not yet implemented), `resonance_summary_card.dart`, `level_meter.dart`, `history_screen.dart`, `app_theme.dart`.

**Needs attention:**
`device_config.dart` (default mains frequency not measured at runtime until user runs mains step; expiry duration hardcoded in banner).
