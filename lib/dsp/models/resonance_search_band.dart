// lib/dsp/models/resonance_search_band.dart
// User-configurable frequency band for resonance peak detection.

class ResonanceSearchBand {
  final double lowHz;
  final double highHz;

  const ResonanceSearchBand({
    this.lowHz = 1000.0,
    this.highHz = 15000.0,
  });

  Map<String, dynamic> toJson() => {
        'lowHz': lowHz,
        'highHz': highHz,
      };

  factory ResonanceSearchBand.fromJson(Map<String, dynamic> json) =>
      ResonanceSearchBand(
        lowHz: (json['lowHz'] as num?)?.toDouble() ?? 1000.0,
        highHz: (json['highHz'] as num?)?.toDouble() ?? 15000.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResonanceSearchBand &&
          runtimeType == other.runtimeType &&
          lowHz == other.lowHz &&
          highHz == other.highHz;

  @override
  int get hashCode => Object.hash(lowHz, highHz);
}
