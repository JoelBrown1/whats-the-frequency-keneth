// lib/providers/audio_engine_provider.dart
// Global keepAlive provider for AudioEngineService.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/audio/audio_engine_service.dart';

final audioEngineProvider =
    NotifierProvider<AudioEngineService, AudioEngineServiceState>(
  AudioEngineService.new,
);
