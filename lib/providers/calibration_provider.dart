// lib/providers/calibration_provider.dart
// Global ChangeNotifierProvider for CalibrationService.
// Calls init() in the background when DeviceConfig is ready, restoring any
// previously saved (or orphaned) calibration from disk.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/dsp_provider.dart';

final calibrationProvider =
    ChangeNotifierProvider<CalibrationService>((ref) {
  final platform = ref.watch(audioEnginePlatformProvider);
  final service = CalibrationService(platform: platform);

  // Restore calibration from disk once DeviceConfig has loaded.
  ref.read(deviceConfigProvider.future).then((config) async {
    await service.init(activeCalibrationId: config.activeCalibrationId);

    // Orphan reconciliation: a calibration file was found but DeviceConfig
    // had no record of it. Persist the ID now so future restarts find it.
    if (config.activeCalibrationId == null &&
        service.activeCalibration != null) {
      await ref
          .read(deviceConfigProvider.notifier)
          .setCalibrationId(service.activeCalibration!.id);
    }
  });

  ref.onDispose(() => ref.invalidate(dspProvider));
  return service;
});
