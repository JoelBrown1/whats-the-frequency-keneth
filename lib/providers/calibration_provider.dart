// lib/providers/calibration_provider.dart
// Global keepAlive provider for CalibrationService.
// Invalidates dspProvider when calibration changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/providers/dsp_provider.dart';

final calibrationProvider = Provider<CalibrationService>((ref) {
  final service = CalibrationService();
  // When this provider is invalidated (e.g. after recalibration),
  // also invalidate dspProvider so stale pipeline results are cleared.
  ref.onDispose(() {
    ref.invalidate(dspProvider);
  });
  return service;
});
