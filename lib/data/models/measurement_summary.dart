// lib/data/models/measurement_summary.dart
// Lightweight summary loaded at startup for the history list.
// Full magnitudeDB[] is loaded on demand via MeasurementRepository.loadFull().

class MeasurementSummary {
  final String id;
  final DateTime timestamp;
  final String pickupLabel;
  final String? pickupId;
  final double resonanceFrequencyHz;
  final double qFactor;

  const MeasurementSummary({
    required this.id,
    required this.timestamp,
    required this.pickupLabel,
    this.pickupId,
    required this.resonanceFrequencyHz,
    required this.qFactor,
  });

  factory MeasurementSummary.fromJson(Map<String, dynamic> json) =>
      MeasurementSummary(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        pickupLabel: json['pickupLabel'] as String? ?? '',
        pickupId: json['pickupId'] as String?,
        resonanceFrequencyHz:
            (json['resonanceFrequencyHz'] as num?)?.toDouble() ?? 0.0,
        qFactor: (json['qFactor'] as num?)?.toDouble() ?? 0.0,
      );
}
