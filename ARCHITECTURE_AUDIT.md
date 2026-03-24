# Architecture Audit — What's the Frequency, Kenneth

> Audited 2026-03-23 against the Phase 0 codebase.
> Updated 2026-03-23 — post-implementation pass. All Phase 0 blockers resolved.

---

## Executive Summary

All critical and significant blockers identified in the initial Phase 0 audit have been resolved. The DSP pipeline is fully implemented (10-stage deconvolution, Tikhonov regularisation, 1/3-octave smoothing, Q-factor extraction). `CalibrationService` is functional. Error states surface correctly to the UI. The service locator anti-pattern has been replaced with Riverpod injection. Placeholder screens are fully wired. Measurement checkpoint persistence, cross-correlation alignment, golden-ratio hum cancellation, and the level check tone are all implemented.

Remaining work is Phase 2+ polish: type-safe navigation, structured logging, magic constant centralisation, and expanded test coverage above the data layer.

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
└─────────────────────────────────────────┘
```

Dependency flow is correctly unidirectional. No circular dependencies observed.

---

## Strengths

### 1. Data Layer — Solid
- **Atomic writes.** Repositories write to `.tmp` then rename, preventing corruption on force-quit. Applies to `MeasurementRepository`, `PickupRepository`, and `CaptureCheckpointService`.
- **Concurrency safety.** `synchronized` package Lock serialises concurrent writes per repository.
- **Forward-compatible schema migration.** `MeasurementMigrator` handles v0→v1 and passes unknown future versions through unchanged.
- **Well-tested.** 26 of 27 tests cover the data layer comprehensively: CRUD, atomic behaviour, corruption recovery, JSON round-trips, and schema migration.

### 2. Audio Engine — Robust State Machine
- Explicit state enum (`Idle → Armed → Playing → Capturing → Analysing → Complete`) prevents invalid operations.
- All state transitions are guarded with assertions.
- Platform abstraction (`AudioEnginePlatformInterface`) is cleanly separated from business logic, with a realistic `MockAudioEnginePlatform` for debug/test builds.
- Device disconnect events are subscribed on initialisation and drive state transitions correctly.
- Error states (`recoverableError`, `deviceError`) are surfaced to the `MeasureScreen` via `_ErrorBlock`.

### 3. DSP Infrastructure — Fully Implemented
- `DspWorker` uses a two-port isolate (work + cancel), ensuring cancellation arrives immediately without blocking.
- `FftProvider` wraps `fftea` behind an abstraction, making the FFT implementation swappable.
- `LogSineSweep` generates mathematically correct logarithmic sweeps with pre-computed inverse filter.
- Full 10-stage pipeline: deconvolution → windowing → FFT → chain correction → Tikhonov regularisation → magnitude → frequency taper → 1/3-octave smoothing → peak detection → Q-factor.
- Cross-correlation alignment (`computeAlignmentOffset`) runs in a background isolate via `Isolate.run()`.

### 4. Measurement Robustness
- **Checkpoint persistence:** `CaptureCheckpointService` writes each accepted capture atomically as `{index}.f32` (raw Float32LE). On next launch, `MeasureScreen` offers to resume from interrupted captures if the `SweepConfig` matches.
- **Hum cancellation:** Golden-ratio inter-sweep delay (`1000 + ((1/mainsHz)/φ) * 1000` ms) mitigates mains harmonics across the N-sweep average.
- **Alignment validation:** Sweep 0 baseline offset validated within ±500 samples; sweeps 1–N discarded and retried if offset drifts by >±2 samples.

### 5. Immutable Models Throughout
- All models use `const` constructors, `copyWith()`, and `==`/`hashCode`.
- Consistent `fromJson`/`toJson` pattern across the codebase.

### 6. Naming Conventions — Consistent
- PascalCase classes, camelCase methods/variables, `k`-prefixed constants, `Provider` suffix on providers, `Screen` suffix on screens.

---

## Resolved Issues

The following issues from the initial audit have been fully resolved.

| # | Issue | Resolution |
|---|-------|------------|
| 1 | DSP pipeline was a stub | Full 10-stage pipeline implemented in `dsp_pipeline_service.dart` |
| 2 | `CalibrationService` threw `UnimplementedError` | `runChainCalibration()` and `measureMainsFrequency()` implemented |
| 3 | Error states never reached the UI | `_ErrorBlock` in `MeasureScreen` watches `audioEngineProvider` and surfaces all error codes with localised messages |
| 4 | Service locator anti-pattern | `audioEnginePlatformProvider` injects the platform via Riverpod; static singleton removed |
| 5 | Placeholder widgets in production screens | All screens are fully wired: onboarding, setup, measure, results, calibration |
| 6 | No measurement lifecycle persistence | `CaptureCheckpointService` persists each accepted sweep; resume offered on next launch |
| 7 | Unused `csv` dependency | Removed from `pubspec.yaml` |
| 8 | `intl: any` unpinned | Pinned to `intl: ^0.19.0` |
| 8b | Localisation strings bypassed | All screens use `AppLocalizations`; calibration widget and error messages fully localised |

---

## Remaining Issues

### Significant

#### 1. Onboarding Step Numbers Are Magic Integers
```dart
const int kOnboardingStepWelcome = 0;
const int kOnboardingStepHardware = 1;
// ...
```
These should be an `enum`. Magic integers make reordering steps error-prone and provide no type safety.

#### 2. Hard-Coded Values Scattered Throughout

| Location | Value | Issue |
|----------|-------|-------|
| `mock_audio_engine_platform.dart` | `const f0 = 4000.0` | Mock always returns 4 kHz resonance |
| `calibration_expiry_banner.dart` | `Duration(minutes: 30)` | Not configurable |
| `frequency_response_chart.dart` | `_minFreq = 100.0`, `_maxFreq = 20000.0` | Chart bounds baked in |
| `device_config.dart` | `measuredMainsHz = 50.0` | Default, not measured |

---

### Minor

#### 3. String-Based Navigation
Routes are registered as string literals in `main.dart` (`'/setup'`, `'/measure'`, etc.). This provides no type safety, no compile-time verification of route existence, and no structured argument passing. `go_router` or equivalent would address this.

#### 4. No Logging Framework
No structured logging is used. Errors and state transitions are silent except where they surface in Riverpod state. Diagnosing production issues will require adding logging retroactively.

#### 5. `mocktail` Imported But Unused
`mocktail: ^1.0.4` is in `dev_dependencies` but no test file imports it. The data layer tests use `FakePathProvider` directly rather than mocks.

#### 6. `ResonancePeak` Lives Inside `frequency_response.dart`
`ResonancePeak` is only used as a field on `FrequencyResponse`. The class deserves a doc comment explaining the Q-factor convention used, or extraction to its own file.

#### 7. `shared_preferences` Still Declared
`shared_preferences: ^2.3.2` remains in `pubspec.yaml`. `DeviceConfig` persistence should confirm whether this is actually used before the next release.

---

## Test Coverage Assessment

| Area | Tests | Quality |
|------|-------|---------|
| Data models (JSON, equality) | 15 | Excellent |
| Repositories (CRUD, atomic, corruption) | 11 | Excellent |
| Schema migration | 3 | Good |
| Widget smoke test | 1 | Minimal |
| DSP pipeline unit tests | ~8 | Good (log sine sweep, resonance band, sweep config) |
| Screen navigation | 0 | Missing |
| AudioEngineService state machine | 0 | Missing |
| DSP pipeline integration (known input/output) | 0 | Missing |
| Error path UI rendering | 0 | Missing |
| Checkpoint service (resume flow) | 0 | Missing |
| Integration (end-to-end) | 0 | Missing |

The data layer is exemplarily tested. Service and UI layers remain untested. The `AudioEngineService` state machine and `DspPipelineService` warrant at minimum 15–20 focused unit tests each.

---

## Prioritised Recommendations

### Phase 2 — Quality and Robustness
1. **Add service-layer tests.** `AudioEngineService` state machine transitions, DSP pipeline with known input/output pairs, calibration service happy path and failure modes, and `CaptureCheckpointService` resume flow.
2. **Replace magic onboarding step integers with an enum.** Low effort, prevents step-ordering regressions.
3. **Add a structured logging framework** (`logger` package or equivalent). Required before any production diagnostic work.

### Phase 3 — Polish
4. **Adopt `go_router` for type-safe navigation.**
5. **Centralise hard-coded constants** into a configuration service or a single `constants.dart`.
6. **Confirm and clean up `shared_preferences` dependency.** Either wire it to `DeviceConfig` persistence or remove it.

---

## File Quality Tier Summary

**Well-implemented:**
`audio_engine_service.dart`, `audio_engine_platform_interface.dart`, `audio_engine_method_channel.dart`, `mock_audio_engine_platform.dart`, `measurement_repository.dart`, `pickup_repository.dart`, `measurement_migrator.dart`, `log_sine_sweep.dart`, `dsp_worker.dart`, `dsp_pipeline_service.dart`, `calibration_service.dart`, `capture_checkpoint_service.dart`, `dsp_isolate.dart`, `measure_screen.dart`, `results_screen.dart`, `calibration_screen.dart`, `onboarding_screen.dart`, `setup_screen.dart`, all model files.

**Functional but incomplete:**
`frequency_response_chart.dart` (chart bounds hardcoded), `resonance_summary_card.dart`, `level_meter.dart`, `history_screen.dart`, `app_theme.dart`.

**Needs attention:**
`main.dart` (string-based routing), `device_config.dart` (default mains frequency not measured at runtime).
