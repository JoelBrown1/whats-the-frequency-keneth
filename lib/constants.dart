// lib/constants.dart
// App-wide constants. Import this file to avoid scattering magic values.

/// Frequency response chart display bounds (Hz).
/// Used by FrequencyResponseChart and SearchBandOverlay.
const double kChartMinFreqHz = 100.0;
const double kChartMaxFreqHz = 20000.0;

/// Default mains frequency until CalibrationService measures the actual value.
const double kDefaultMainsHz = 50.0;

/// Resonance frequency returned by MockAudioEnginePlatform.
const double kMockResonanceHz = 4000.0;
