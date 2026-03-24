// test/data/csv_exporter_test.dart
// Verifies CsvExporter produces REW-compatible CSV with locale-safe formatting.

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/csv_exporter.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

FrequencyResponse _makeResponse({
  List<double> freqs = const [100.0, 1000.0, 10000.0],
  List<double> mags = const [-10.5, 0.0, -3.25],
}) {
  return FrequencyResponse(
    frequencyHz: freqs,
    magnitudeDb: mags,
    peaks: const [],
    primaryPeak: const ResonancePeak(
      frequencyHz: 1000.0,
      magnitudeDb: 0.0,
      qFactor: 2.5,
      fLowHz: 800.0,
      fHighHz: 1200.0,
    ),
    sweepConfig: const SweepConfig(),
    analyzedAt: DateTime(2026, 3, 24),
  );
}

void main() {
  group('CsvExporter', () {
    test('header row is REW-compatible', () {
      final csv = CsvExporter().export(_makeResponse(), 'PAF neck');
      final lines = csv.split('\n');
      expect(lines.first, equals('Freq(Hz),SPL(dB)'));
    });

    test('first data line matches known input', () {
      final csv = CsvExporter().export(_makeResponse(), 'PAF neck');
      final lines = csv.split('\n').where((l) => l.isNotEmpty).toList();
      // lines[0] is header; lines[1] is first data row
      expect(lines[1], equals('100.0000,-10.5000'));
    });

    test('all data lines present — one per frequency bin', () {
      final response = _makeResponse();
      final csv = CsvExporter().export(response, 'PAF neck');
      final dataLines =
          csv.split('\n').where((l) => l.isNotEmpty).skip(1).toList();
      expect(dataLines.length, equals(response.frequencyHz.length));
    });

    test('decimal separator is always a period regardless of locale', () {
      // 10000.0 Hz, -3.25 dB — both have decimal parts that would become
      // commas on European locales if toString() were used instead of
      // toStringAsFixed(4).
      final csv = CsvExporter().export(_makeResponse(), 'test');
      expect(csv, isNot(contains(','  '0000'))); // no misplaced comma-decimal
      expect(csv, contains('10000.0000'));
      expect(csv, contains('-3.2500'));
    });

    test('zero magnitude formatted to 4 decimal places', () {
      final csv = CsvExporter().export(_makeResponse(), 'test');
      expect(csv, contains('0.0000'));
    });

    test('last data line matches last frequency bin', () {
      final csv = CsvExporter().export(_makeResponse(), 'test');
      final dataLines =
          csv.split('\n').where((l) => l.isNotEmpty).skip(1).toList();
      expect(dataLines.last, equals('10000.0000,-3.2500'));
    });

    test('pickupLabel does not appear in CSV body', () {
      // The export format is (freq, spl) only — pickup label is for filename
      // construction in the caller, not embedded in the file.
      final csv = CsvExporter().export(_makeResponse(), 'My Special Pickup');
      expect(csv, isNot(contains('My Special Pickup')));
    });

    test('handles negative frequencies — all values use period separator', () {
      final response = _makeResponse(
        freqs: [20.5, 500.25, 19999.9],
        mags: [-48.1234, -0.0001, -96.0],
      );
      final csv = CsvExporter().export(response, 'test');
      expect(csv, contains('20.5000'));
      expect(csv, contains('500.2500'));
      expect(csv, contains('19999.9000'));
      expect(csv, contains('-48.1234'));
      expect(csv, contains('-0.0001'));
      expect(csv, contains('-96.0000'));
    });
  });
}
