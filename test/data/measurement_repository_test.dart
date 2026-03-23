// test/data/measurement_repository_test.dart
// Pass criteria:
// - save() then loadSummaries() returns the correct summary.
// - loadFull(id) returns the full measurement with all fields.
// - A corrupt JSON file does not crash loadSummaries().
// - Atomic write: .tmp file is cleaned up after successful save.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/measurement_repository.dart';
import 'package:whats_the_frequency/data/models/measurement.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

/// Fake path provider that returns a temp directory.
class FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  FakePathProvider(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

Measurement _makeMeasurement(String id) {
  return Measurement(
    schemaVersion: 1,
    id: id,
    timestamp: DateTime.parse('2026-01-15T10:00:00.000Z'),
    pickupLabel: 'PAF neck',
    pickupId: 'pickup-001',
    sweepConfig: const SweepConfig(),
    resonanceSearchBand: const ResonanceSearchBand(),
    magnitudeDB: List.generate(361, (i) => i.toDouble()),
    resonanceFrequencyHz: 4000.0,
    qFactor: 3.0,
    hardware: MeasurementHardware(
      interfaceDeviceName: 'Scarlett 2i2 USB',
      interfaceUID: 'uid-123',
      calibrationId: 'cal-456',
      calibrationTimestamp: DateTime.parse('2026-01-15T09:00:00.000Z'),
      appVersion: '1.0.0',
    ),
  );
}

void main() {
  late Directory tempDir;
  late MeasurementRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wtfk_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
    repo = MeasurementRepository();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('MeasurementRepository', () {
    test('save and loadSummaries returns correct summary', () async {
      final m = _makeMeasurement('test-001');
      await repo.save(m);

      final summaries = await repo.loadSummaries();

      expect(summaries, hasLength(1));
      expect(summaries.first.id, equals('test-001'));
      expect(summaries.first.pickupLabel, equals('PAF neck'));
      expect(summaries.first.resonanceFrequencyHz, equals(4000.0));
      expect(summaries.first.qFactor, equals(3.0));
    });

    test('loadFull returns complete measurement', () async {
      final m = _makeMeasurement('test-002');
      await repo.save(m);

      final loaded = await repo.loadFull('test-002');

      expect(loaded.id, equals('test-002'));
      expect(loaded.magnitudeDB.length, equals(361));
      expect(loaded.hardware.interfaceDeviceName, equals('Scarlett 2i2 USB'));
      expect(loaded.sweepConfig, equals(const SweepConfig()));
    });

    test('corrupt file does not crash loadSummaries', () async {
      // Write a corrupt JSON file directly.
      final corruptFile =
          File('${tempDir.path}/measurements/corrupt-file.json');
      await corruptFile.create(recursive: true);
      await corruptFile.writeAsString('{invalid json{{');

      // Pass criteria: returns empty list (or skips corrupt), does not throw.
      expect(repo.loadSummaries(), completes);
      final summaries = await repo.loadSummaries();
      expect(summaries, isEmpty);
    });

    test('atomic write: .tmp file is cleaned up after successful save',
        () async {
      final m = _makeMeasurement('test-003');
      await repo.save(m);

      final tmpFile = File(
          '${tempDir.path}/measurements/${m.id}.json.tmp');

      // Pass criteria: .tmp file should not exist after successful write.
      expect(await tmpFile.exists(), isFalse);
    });

    test('delete removes measurement from loadSummaries', () async {
      final m = _makeMeasurement('test-004');
      await repo.save(m);
      await repo.delete('test-004');

      final summaries = await repo.loadSummaries();
      expect(summaries.where((s) => s.id == 'test-004'), isEmpty);
    });
  });
}
