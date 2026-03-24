// lib/providers/available_devices_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine_platform_interface.dart';
import 'audio_engine_platform_provider.dart';

final availableDevicesProvider =
    FutureProvider<List<AudioDeviceDescriptor>>((ref) {
  return ref.watch(audioEnginePlatformProvider).getAvailableDevices();
});
