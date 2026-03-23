// lib/data/models/measurement.dart
// Full measurement record — persisted as JSON in measurements/<uuid>.json.
// NOTE: frequencyBins[] is NOT stored — computed from constants at load time.
// All JSON is passed through MeasurementMigrator on load.

import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/measurement_migrator.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

class MeasurementHardware {
  final String interfaceDeviceName;
  final String interfaceUID;
  final String calibrationId;
  final DateTime calibrationTimestamp;
  final String appVersion;

  const MeasurementHardware({
    required this.interfaceDeviceName,
    required this.interfaceUID,
    required this.calibrationId,
    required this.calibrationTimestamp,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'interfaceDeviceName': interfaceDeviceName,
        'interfaceUID': interfaceUID,
        'calibrationId': calibrationId,
        'calibrationTimestamp': calibrationTimestamp.toIso8601String(),
        'appVersion': appVersion,
      };

  factory MeasurementHardware.fromJson(Map<String, dynamic> json) =>
      MeasurementHardware(
        interfaceDeviceName: json['interfaceDeviceName'] as String? ?? '',
        interfaceUID: json['interfaceUID'] as String? ?? '',
        calibrationId: json['calibrationId'] as String? ?? '',
        calibrationTimestamp: json['calibrationTimestamp'] != null
            ? DateTime.parse(json['calibrationTimestamp'] as String)
            : DateTime.fromMillisecondsSinceEpoch(0),
        appVersion: json['appVersion'] as String? ?? '0.0.0',
      );
}

class Measurement {
  final int schemaVersion;
  final String id;
  final DateTime timestamp;
  final String pickupLabel;
  final String? pickupId;
  final SweepConfig sweepConfig;
  final ResonanceSearchBand resonanceSearchBand;

  /// Magnitude at each frequency bin in dB — persisted.
  /// The companion frequencyHz axis is computed from constants (kFrequencyBins etc.)
  final List<double> magnitudeDB;

  final double resonanceFrequencyHz;
  final double qFactor;
  final MeasurementHardware hardware;

  const Measurement({
    required this.schemaVersion,
    required this.id,
    required this.timestamp,
    required this.pickupLabel,
    this.pickupId,
    required this.sweepConfig,
    required this.resonanceSearchBand,
    required this.magnitudeDB,
    required this.resonanceFrequencyHz,
    required this.qFactor,
    required this.hardware,
  });

  /// Build a full FrequencyResponse for display — recomputes the frequency axis.
  FrequencyResponse toFrequencyResponse() {
    final freqAxis = computeFrequencyAxis();
    // Build a minimal primary peak from stored data; full peak list not stored.
    final primaryPeak = ResonancePeak(
      frequencyHz: resonanceFrequencyHz,
      magnitudeDb: magnitudeDB.isNotEmpty
          ? magnitudeDB.reduce((a, b) => a > b ? a : b)
          : 0.0,
      qFactor: qFactor,
      fLowHz: resonanceFrequencyHz / (1 + 1 / (2 * qFactor)),
      fHighHz: resonanceFrequencyHz * (1 + 1 / (2 * qFactor)),
    );
    return FrequencyResponse(
      frequencyHz: freqAxis,
      magnitudeDb: magnitudeDB,
      peaks: [primaryPeak],
      primaryPeak: primaryPeak,
      sweepConfig: sweepConfig,
      analyzedAt: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'pickupLabel': pickupLabel,
        'pickupId': pickupId,
        'sweepConfig': sweepConfig.toJson(),
        'resonanceSearchBand': resonanceSearchBand.toJson(),
        'magnitudeDB': magnitudeDB,
        'resonanceFrequencyHz': resonanceFrequencyHz,
        'qFactor': qFactor,
        'hardware': hardware.toJson(),
      };

  factory Measurement.fromJson(Map<String, dynamic> rawJson) {
    // Always migrate before parsing.
    final json = MeasurementMigrator.migrate(rawJson);
    return Measurement(
      schemaVersion: json['schemaVersion'] as int? ?? MeasurementMigrator.currentSchemaVersion,
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      pickupLabel: json['pickupLabel'] as String? ?? '',
      pickupId: json['pickupId'] as String?,
      sweepConfig: SweepConfig.fromJson(
          json['sweepConfig'] as Map<String, dynamic>),
      resonanceSearchBand: ResonanceSearchBand.fromJson(
          json['resonanceSearchBand'] as Map<String, dynamic>),
      magnitudeDB: (json['magnitudeDB'] as List).cast<num>()
          .map((e) => e.toDouble())
          .toList(),
      resonanceFrequencyHz:
          (json['resonanceFrequencyHz'] as num).toDouble(),
      qFactor: (json['qFactor'] as num).toDouble(),
      hardware: MeasurementHardware.fromJson(
          json['hardware'] as Map<String, dynamic>),
    );
  }
}
