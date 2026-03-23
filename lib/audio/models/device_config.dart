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
        resonanceSearchBand: resonanceSearchBand ?? this.resonanceSearchBand,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        activeCalibrationId: activeCalibrationId ?? this.activeCalibrationId,
        lastCompletedOnboardingStep:
            lastCompletedOnboardingStep ?? this.lastCompletedOnboardingStep,
      );
}
