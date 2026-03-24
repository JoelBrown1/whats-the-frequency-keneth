// lib/dsp/models/dsp_pipeline_input.dart
// Sendable input struct for the DSP isolate pipeline.
// All fields are primitives or TypedData — safe to pass across Isolate.run().

import 'dart:typed_data';

class DspPipelineInput {
  final Float32List capturedSamples;
  final int sampleRate;
  final double f1Hz;
  final double f2Hz;
  final double durationSeconds;
  final int preRollMs;
  final int postRollMs;

  /// H_chain real part — kHChainBins uniformly-spaced bins (0–kHChainMaxHz).
  final Float64List hChainReal;

  /// H_chain imaginary part — kHChainBins uniformly-spaced bins.
  final Float64List hChainImag;

  final double searchBandLowHz;
  final double searchBandHighHz;

  const DspPipelineInput({
    required this.capturedSamples,
    required this.sampleRate,
    required this.f1Hz,
    required this.f2Hz,
    required this.durationSeconds,
    required this.preRollMs,
    required this.postRollMs,
    required this.hChainReal,
    required this.hChainImag,
    required this.searchBandLowHz,
    required this.searchBandHighHz,
  });
}
