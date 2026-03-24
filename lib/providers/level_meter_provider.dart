// lib/providers/level_meter_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine_platform_provider.dart';

/// Raw level meter — no tone playback. Used during calibration pre-check.
final levelMeterProvider = StreamProvider.autoDispose<double>((ref) {
  final platform = ref.watch(audioEnginePlatformProvider);
  platform.startLevelMeter();
  ref.onDispose(() => platform.stopLevelMeter());
  return platform.levelMeterStream;
});

/// Level meter with 1 kHz sine tone routing through the signal chain.
/// Use this during the level-check step so the user adjusts the headphone
/// knob against the actual signal level, not ambient noise.
final levelCheckToneProvider = StreamProvider.autoDispose<double>((ref) {
  final platform = ref.watch(audioEnginePlatformProvider);
  platform.startLevelCheckTone();
  ref.onDispose(() => platform.stopLevelCheckTone());
  return platform.levelMeterStream;
});
