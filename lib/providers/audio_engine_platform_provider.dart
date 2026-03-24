// lib/providers/audio_engine_platform_provider.dart
// Riverpod provider for the audio engine platform interface.
// Replaces the previous mutable static singleton on AudioEnginePlatformInterface.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine_method_channel.dart';
import '../audio/audio_engine_platform_interface.dart';
import '../audio/mock_audio_engine_platform.dart';

final audioEnginePlatformProvider =
    Provider<AudioEnginePlatformInterface>((ref) {
  return kDebugMode ? MockAudioEnginePlatform() : AudioEngineMethodChannel();
});
