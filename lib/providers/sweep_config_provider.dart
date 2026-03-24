// lib/providers/sweep_config_provider.dart
// Derives SweepConfig from the persisted device sample rate.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/sweep_config.dart';
import 'device_config_provider.dart';

final sweepConfigProvider = Provider<SweepConfig>((ref) {
  final config = ref.watch(deviceConfigProvider).valueOrNull;
  if (config == null || config.sampleRate == 0) return const SweepConfig();
  return SweepConfig(sampleRate: config.sampleRate);
});
