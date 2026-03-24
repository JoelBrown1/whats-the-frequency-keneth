// test/providers/device_config_provider_test.dart
// Unit tests for DeviceConfigNotifier — the central persistence coordinator.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/ui/screens/onboarding_step.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<DeviceConfigNotifier> _buildNotifier({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Await the async build.
  await container.read(deviceConfigProvider.future);
  return container.read(deviceConfigProvider.notifier);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('DeviceConfigNotifier', () {
    test('build() with no stored value returns default config', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final config = await container.read(deviceConfigProvider.future);
      expect(config.deviceUid, '');
      expect(config.sampleRate, 48000);
      expect(config.onboardingComplete, isFalse);
    });

    test('build() restores previously persisted config', () async {
      final stored = const DeviceConfig(
        deviceUid: 'uid-1',
        deviceName: 'Scarlett 2i2',
        sampleRate: 48000,
        measuredMainsHz: 60.0,
        onboardingComplete: true,
      );
      SharedPreferences.setMockInitialValues({
        'device_config': '{"deviceUid":"uid-1","deviceName":"Scarlett 2i2",'
            '"sampleRate":48000,"measuredMainsHz":60.0,'
            '"resonanceSearchBand":{"lowHz":1000.0,"highHz":15000.0},'
            '"onboardingComplete":true,"activeCalibrationId":null,'
            '"lastCompletedOnboardingStep":0}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final config = await container.read(deviceConfigProvider.future);
      expect(config.deviceUid, 'uid-1');
      expect(config.deviceName, 'Scarlett 2i2');
      expect(config.measuredMainsHz, 60.0);
      expect(config.onboardingComplete, isTrue);
      expect(stored.sampleRate, config.sampleRate);
    });

    test('setDevice() updates uid, name, and sampleRate', () async {
      final notifier = await _buildNotifier();
      await notifier.setDevice('uid-2', 'Apollo Twin', 44100);

      final container = ProviderContainer(overrides: []);
      addTearDown(container.dispose);
      // Read state directly from the notifier (already updated in-memory).
      final config = notifier.state.value!;
      expect(config.deviceUid, 'uid-2');
      expect(config.deviceName, 'Apollo Twin');
      expect(config.sampleRate, 44100);
    });

    test('setMainsHz() persists mains frequency', () async {
      final notifier = await _buildNotifier();
      await notifier.setMainsHz(60.0);

      expect(notifier.state.value!.measuredMainsHz, 60.0);
    });

    test('setCalibrationId() persists calibration id', () async {
      final notifier = await _buildNotifier();
      await notifier.setCalibrationId('cal-abc');

      expect(notifier.state.value!.activeCalibrationId, 'cal-abc');
    });

    test('setCalibrationId(null) clears calibration id', () async {
      final notifier = await _buildNotifier(
        prefs: {
          'device_config': '{"deviceUid":"","deviceName":"","sampleRate":48000,'
              '"measuredMainsHz":50.0,'
              '"resonanceSearchBand":{"lowHz":1000.0,"highHz":15000.0},'
              '"onboardingComplete":false,"activeCalibrationId":"old-id",'
              '"lastCompletedOnboardingStep":0}',
        },
      );
      await notifier.setCalibrationId(null);

      expect(notifier.state.value!.activeCalibrationId, isNull);
    });

    test('setResonanceSearchBand() persists band', () async {
      final notifier = await _buildNotifier();
      const band = ResonanceSearchBand(lowHz: 500.0, highHz: 8000.0);
      await notifier.setResonanceSearchBand(band);

      expect(notifier.state.value!.resonanceSearchBand.lowHz, 500.0);
      expect(notifier.state.value!.resonanceSearchBand.highHz, 8000.0);
    });

    test('setOnboardingStep() updates lastCompletedOnboardingStep', () async {
      final notifier = await _buildNotifier();
      await notifier.setOnboardingStep(OnboardingStep.mains); // index 3

      expect(notifier.state.value!.lastCompletedOnboardingStep,
          OnboardingStep.mains.index);
    });

    test('completeOnboarding() sets onboardingComplete to true', () async {
      final notifier = await _buildNotifier();
      expect(notifier.state.value!.onboardingComplete, isFalse);

      await notifier.completeOnboarding();

      expect(notifier.state.value!.onboardingComplete, isTrue);
    });

    test('mutations persist across a fresh ProviderContainer', () async {
      SharedPreferences.setMockInitialValues({});

      // First container — write.
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      await c1.read(deviceConfigProvider.future);
      await c1.read(deviceConfigProvider.notifier).setMainsHz(55.5);

      // Second container — reads the same SharedPreferences mock.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final restored = await c2.read(deviceConfigProvider.future);

      expect(restored.measuredMainsHz, 55.5);
    });
  });
}
