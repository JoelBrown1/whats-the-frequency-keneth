// lib/data/measurement_migrator.dart
// Schema migration for Measurement JSON.
// All loaded JSON is passed through migrate() before parsing.

class MeasurementMigrator {
  static const int currentSchemaVersion = 1;

  /// Migrate JSON from any older schema version to currentSchemaVersion.
  /// Unknown future versions (e.g. v99 from a newer app build) pass through
  /// without modification so older app versions degrade gracefully.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    int version = (json['schemaVersion'] as int?) ?? 0;
    if (version < 1) {
      json = _v0ToV1(json);
      version = 1;
    }
    // Future versions: add else-if blocks here.
    return json;
  }

  /// v0 → v1: add schemaVersion, hardware block, and pickupId if missing.
  static Map<String, dynamic> _v0ToV1(Map<String, dynamic> json) {
    final updated = Map<String, dynamic>.from(json);
    updated['schemaVersion'] = 1;

    if (!updated.containsKey('hardware')) {
      updated['hardware'] = {
        'interfaceDeviceName': '',
        'interfaceUID': '',
        'calibrationId': '',
        'calibrationTimestamp': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        'appVersion': '0.0.0',
      };
    }

    if (!updated.containsKey('pickupId')) {
      updated['pickupId'] = null;
    }

    if (!updated.containsKey('resonanceSearchBand')) {
      updated['resonanceSearchBand'] = {'lowHz': 1000.0, 'highHz': 15000.0};
    }

    if (!updated.containsKey('sweepConfig')) {
      updated['sweepConfig'] = {
        'f1Hz': 20.0,
        'f2Hz': 20000.0,
        'durationSeconds': 3.0,
        'sampleRate': 48000,
        'sweepCount': 4,
        'preRollMs': 512,
        'postRollMs': 500,
      };
    }

    return updated;
  }
}
