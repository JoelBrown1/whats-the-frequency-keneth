// lib/providers/capture_checkpoint_provider.dart
// Global provider for CaptureCheckpointService.
// Override in tests via captureCheckpointProvider.overrideWithValue(service).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/data/capture_checkpoint_service.dart';

final captureCheckpointProvider = Provider<CaptureCheckpointService>((_) {
  return CaptureCheckpointService();
});
