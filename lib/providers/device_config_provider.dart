// lib/providers/device_config_provider.dart
// Persists DeviceConfig to SharedPreferences key 'device_config'.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/models/device_config.dart';
import '../dsp/models/resonance_search_band.dart';
import '../ui/screens/onboarding_step.dart';

const _kDeviceConfigKey = 'device_config';

/// Default config used on first launch.
const _kDefaultConfig = DeviceConfig(
  deviceUid: '',
  deviceName: '',
  sampleRate: 48000,
);

class DeviceConfigNotifier extends AsyncNotifier<DeviceConfig> {
  @override
  Future<DeviceConfig> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDeviceConfigKey);
    if (raw == null) return _kDefaultConfig;
    try {
      return DeviceConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _kDefaultConfig;
    }
  }

  Future<void> _save(DeviceConfig config) async {
    state = AsyncData(config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceConfigKey, jsonEncode(config.toJson()));
  }

  Future<void> setDevice(String uid, String name, int sampleRate) async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    await _save(current.copyWith(
        deviceUid: uid, deviceName: name, sampleRate: sampleRate));
  }

  Future<void> setMainsHz(double hz) async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    await _save(current.copyWith(measuredMainsHz: hz, mainsMeasured: true));
  }

  Future<void> setCalibrationId(String? id) async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    // copyWith cannot clear a nullable field to null; use explicit constructor.
    await _save(DeviceConfig(
      deviceUid: current.deviceUid,
      deviceName: current.deviceName,
      sampleRate: current.sampleRate,
      measuredMainsHz: current.measuredMainsHz,
      mainsMeasured: current.mainsMeasured,
      resonanceSearchBand: current.resonanceSearchBand,
      onboardingComplete: current.onboardingComplete,
      activeCalibrationId: id,
      lastCompletedOnboardingStep: current.lastCompletedOnboardingStep,
    ));
  }

  Future<void> setOnboardingStep(OnboardingStep step) async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    await _save(current.copyWith(lastCompletedOnboardingStep: step.index));
  }

  Future<void> setResonanceSearchBand(ResonanceSearchBand band) async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    await _save(current.copyWith(resonanceSearchBand: band));
  }

  Future<void> completeOnboarding() async {
    final current = state.valueOrNull ?? _kDefaultConfig;
    await _save(current.copyWith(onboardingComplete: true));
  }
}

final deviceConfigProvider =
    AsyncNotifierProvider<DeviceConfigNotifier, DeviceConfig>(
  DeviceConfigNotifier.new,
);
