// test/data/device_config_test.dart
// Pass criteria:
// - JSON round-trip preserves all fields exactly.
// - Missing optional fields deserialize to documented defaults.
// - lastCompletedOnboardingStep defaults to 0 when absent.
// - mainsMeasured defaults to false when absent.

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

void main() {
  group('DeviceConfig', () {
    test('JSON round-trip preserves all fields', () {
      const config = DeviceConfig(
        deviceUid: 'test-uid-123',
        deviceName: 'Scarlett 2i2 USB',
        sampleRate: 48000,
        measuredMainsHz: 49.97,
        mainsMeasured: true,
        resonanceSearchBand: ResonanceSearchBand(lowHz: 500.0, highHz: 12000.0),
        onboardingComplete: true,
        activeCalibrationId: 'cal-uuid-456',
        lastCompletedOnboardingStep: 3,
      );

      final json = config.toJson();
      final restored = DeviceConfig.fromJson(json);

      expect(restored.deviceUid, equals(config.deviceUid));
      expect(restored.deviceName, equals(config.deviceName));
      expect(restored.sampleRate, equals(config.sampleRate));
      expect(restored.measuredMainsHz, equals(config.measuredMainsHz));
      expect(restored.mainsMeasured, isTrue);
      expect(restored.resonanceSearchBand.lowHz,
          equals(config.resonanceSearchBand.lowHz));
      expect(restored.resonanceSearchBand.highHz,
          equals(config.resonanceSearchBand.highHz));
      expect(restored.onboardingComplete, equals(config.onboardingComplete));
      expect(restored.activeCalibrationId, equals(config.activeCalibrationId));
      expect(restored.lastCompletedOnboardingStep,
          equals(config.lastCompletedOnboardingStep));
    });

    test('missing optional fields deserialize to documented defaults', () {
      // Minimal JSON with only required fields.
      final minimalJson = <String, dynamic>{
        'deviceUid': 'uid',
        'deviceName': 'Device',
        'sampleRate': 48000,
      };

      final config = DeviceConfig.fromJson(minimalJson);

      // Pass criteria: defaults match spec.
      expect(config.measuredMainsHz, equals(50.0));
      expect(config.mainsMeasured, isFalse);
      expect(config.resonanceSearchBand.lowHz, equals(1000.0));
      expect(config.resonanceSearchBand.highHz, equals(15000.0));
      expect(config.onboardingComplete, isFalse);
      expect(config.activeCalibrationId, isNull);
      expect(config.lastCompletedOnboardingStep, equals(0));
    });

    test('mainsMeasured defaults to false when absent from JSON', () {
      final json = <String, dynamic>{
        'deviceUid': 'uid',
        'deviceName': 'Device',
        'sampleRate': 48000,
        'measuredMainsHz': 60.0,
        // mainsMeasured intentionally absent — simulates old stored JSON
      };
      final config = DeviceConfig.fromJson(json);
      expect(config.mainsMeasured, isFalse,
          reason: 'Old configs without mainsMeasured must default to false '
              'so the warning banner appears after upgrade');
    });

    test('lastCompletedOnboardingStep defaults to 0 when absent', () {
      final json = <String, dynamic>{
        'deviceUid': 'uid',
        'deviceName': 'Device',
        'sampleRate': 48000,
      };
      final config = DeviceConfig.fromJson(json);
      expect(config.lastCompletedOnboardingStep, equals(0));
    });

    test('activeCalibrationId is null when JSON value is null', () {
      final json = <String, dynamic>{
        'deviceUid': 'uid',
        'deviceName': 'Device',
        'sampleRate': 48000,
        'activeCalibrationId': null,
      };
      final config = DeviceConfig.fromJson(json);
      expect(config.activeCalibrationId, isNull);
    });
  });
}
