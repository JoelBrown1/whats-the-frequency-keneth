// lib/audio/models/device_config.dart
// Persisted device configuration — stored in SharedPreferences.
// Includes calibration state, measured mains frequency, and onboarding progress.

import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

class DeviceConfig {
  final String deviceUid;
  final String deviceName;
  final int sampleRate;

  /// Measured from an idle capture; defaults to 50.0 Hz until measured.
  final double measuredMainsHz;

  /// True once the user has explicitly set mains frequency (auto-detect or
  /// manual chip selection). False means the 50 Hz default has never been
  /// confirmed and hum suppression may be mistuned.
  final bool mainsMeasured;

  final ResonanceSearchBand resonanceSearchBand;
  final bool onboardingComplete;

  /// UUID of current ChainCalibration; null if none.
  final String? activeCalibrationId;

  /// Tracks resume point for mid-flow restarts.
  /// 0 = not started, 5 = complete (Welcome=0, HW Checklist=1,
  /// Device=2, Mains=3, Level=4, Calibration=5).
  final int lastCompletedOnboardingStep;

  const DeviceConfig({
    required this.deviceUid,
    required this.deviceName,
    required this.sampleRate,
    this.measuredMainsHz = 50.0,
    this.mainsMeasured = false,
    this.resonanceSearchBand = const ResonanceSearchBand(),
    this.onboardingComplete = false,
    this.activeCalibrationId,
    this.lastCompletedOnboardingStep = 0,
  });

  Map<String, dynamic> toJson() => {
        'deviceUid': deviceUid,
        'deviceName': deviceName,
        'sampleRate': sampleRate,
        'measuredMainsHz': measuredMainsHz,
        'mainsMeasured': mainsMeasured,
        'resonanceSearchBand': resonanceSearchBand.toJson(),
        'onboardingComplete': onboardingComplete,
        'activeCalibrationId': activeCalibrationId,
        'lastCompletedOnboardingStep': lastCompletedOnboardingStep,
      };

  factory DeviceConfig.fromJson(Map<String, dynamic> json) => DeviceConfig(
        deviceUid: json['deviceUid'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? '',
        sampleRate: (json['sampleRate'] as int?) ?? 48000,
        measuredMainsHz:
            (json['measuredMainsHz'] as num?)?.toDouble() ?? 50.0,
        mainsMeasured: json['mainsMeasured'] as bool? ?? false,
        resonanceSearchBand: json['resonanceSearchBand'] != null
            ? ResonanceSearchBand.fromJson(
                json['resonanceSearchBand'] as Map<String, dynamic>)
            : const ResonanceSearchBand(),
        onboardingComplete: json['onboardingComplete'] as bool? ?? false,
        activeCalibrationId: json['activeCalibrationId'] as String?,
        lastCompletedOnboardingStep:
            (json['lastCompletedOnboardingStep'] as int?) ?? 0,
      );

  DeviceConfig copyWith({
    String? deviceUid,
    String? deviceName,
    int? sampleRate,
    double? measuredMainsHz,
    bool? mainsMeasured,
    ResonanceSearchBand? resonanceSearchBand,
    bool? onboardingComplete,
    String? activeCalibrationId,
    int? lastCompletedOnboardingStep,
  }) =>
      DeviceConfig(
        deviceUid: deviceUid ?? this.deviceUid,
        deviceName: deviceName ?? this.deviceName,
        sampleRate: sampleRate ?? this.sampleRate,
        measuredMainsHz: measuredMainsHz ?? this.measuredMainsHz,
        mainsMeasured: mainsMeasured ?? this.mainsMeasured,
        resonanceSearchBand: resonanceSearchBand ?? this.resonanceSearchBand,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        activeCalibrationId: activeCalibrationId ?? this.activeCalibrationId,
        lastCompletedOnboardingStep:
            lastCompletedOnboardingStep ?? this.lastCompletedOnboardingStep,
      );
}
