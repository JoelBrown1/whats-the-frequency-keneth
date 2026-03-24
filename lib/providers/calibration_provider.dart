// lib/providers/calibration_provider.dart
// Global keepAlive provider for CalibrationService.
// Invalidates dspProvider when calibration changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/dsp_provider.dart';

final calibrationProvider = Provider<CalibrationService>((ref) {
  final platform = ref.watch(audioEnginePlatformProvider);
  final service = CalibrationService(platform: platform);
  ref.onDispose(() {
    service.sweepProgress.dispose();
    ref.invalidate(dspProvider);
  });
  return service;
});
