// lib/providers/dsp_provider.dart
// Global keepAlive provider for DspPipelineService.
// Invalidated by calibrationProvider when calibration changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/dsp/dsp_pipeline_service.dart';

final dspProvider = Provider<DspPipelineService>((ref) {
  return DspPipelineService();
});
