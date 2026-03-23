// lib/data/csv_exporter.dart
// REW-compatible CSV export of a FrequencyResponse.
// Always uses period decimal separator regardless of locale (toStringAsFixed).

import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

class CsvExporter {
  /// Export a FrequencyResponse as a REW-compatible CSV string.
  /// Header: Freq(Hz),SPL(dB)
  /// Decimal separator is always a period (locale-independent via toStringAsFixed).
  String export(FrequencyResponse response, String pickupLabel) {
    final buffer = StringBuffer();
    buffer.writeln('Freq(Hz),SPL(dB)');
    final n = response.frequencyHz.length;
    for (int i = 0; i < n; i++) {
      final freq = response.frequencyHz[i].toStringAsFixed(4);
      final spl = response.magnitudeDb[i].toStringAsFixed(4);
      buffer.writeln('$freq,$spl');
    }
    return buffer.toString();
  }
}
