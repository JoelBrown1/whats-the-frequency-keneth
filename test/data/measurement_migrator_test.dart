// test/data/measurement_migrator_test.dart
// Pass criteria:
// - v0 JSON (no schemaVersion) is migrated to v1 with all required fields.
// - Future schema version (v99) passes through without crash.
// - All required v1 fields are present after migration.

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/data/measurement_migrator.dart';

void main() {
  group('MeasurementMigrator', () {
    test('v0 JSON migrated to v1 with all required fields', () {
      // Minimal v0 JSON — no schemaVersion field.
      final v0Json = <String, dynamic>{
        'id': 'test-id',
        'timestamp': '2026-01-01T10:00:00.000Z',
        'pickupLabel': 'PAF neck',
        'magnitudeDB': <double>[0.0, 1.0, 2.0],
        'resonanceFrequencyHz': 4000.0,
        'qFactor': 3.0,
      };

      final migrated = MeasurementMigrator.migrate(v0Json);

      // Pass criteria: schemaVersion set to current version.
      expect(migrated['schemaVersion'],
          equals(MeasurementMigrator.currentSchemaVersion));

      // Pass criteria: hardware block present with all required sub-fields.
      expect(migrated.containsKey('hardware'), isTrue);
      final hardware = migrated['hardware'] as Map<String, dynamic>;
      expect(hardware.containsKey('interfaceDeviceName'), isTrue);
      expect(hardware.containsKey('interfaceUID'), isTrue);
      expect(hardware.containsKey('calibrationId'), isTrue);
      expect(hardware.containsKey('calibrationTimestamp'), isTrue);
      expect(hardware.containsKey('appVersion'), isTrue);

      // Pass criteria: pickupId field present (may be null).
      expect(migrated.containsKey('pickupId'), isTrue);

      // Pass criteria: resonanceSearchBand present.
      expect(migrated.containsKey('resonanceSearchBand'), isTrue);

      // Pass criteria: sweepConfig present.
      expect(migrated.containsKey('sweepConfig'), isTrue);
    });

    test('future schema version (v99) passes through without crash', () {
      final futureJson = <String, dynamic>{
        'schemaVersion': 99,
        'id': 'future-id',
        'timestamp': '2030-01-01T00:00:00.000Z',
        'pickupLabel': 'Test',
        'magnitudeDB': <double>[],
        'resonanceFrequencyHz': 5000.0,
        'qFactor': 2.0,
        'hardware': {},
        'sweepConfig': {},
        'resonanceSearchBand': {},
      };

      // Pass criteria: does not throw.
      expect(() => MeasurementMigrator.migrate(futureJson), returnsNormally);

      final result = MeasurementMigrator.migrate(futureJson);
      // Pass criteria: schemaVersion preserved as-is (not downgraded).
      expect(result['schemaVersion'], equals(99));
    });

    test('currentSchemaVersion is 1', () {
      expect(MeasurementMigrator.currentSchemaVersion, equals(1));
    });
  });
}
