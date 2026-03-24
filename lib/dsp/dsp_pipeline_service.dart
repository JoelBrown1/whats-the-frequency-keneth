// lib/dsp/dsp_pipeline_service.dart
// DSP pipeline service — dispatches work to an isolate via Isolate.run().
//
// Pipeline stages (implemented in dsp_isolate.dart):
// 1. Deconvolution  2. Hann window  3. FFT → H_dut
// 4. Chain correction (Tikhonov)  5. Magnitude (dB)
// 6. Log-freq interpolation → 361 bins  7. Freq taper (>15 kHz)
// 8. 1/3-octave smoothing  9. Peak detection  10. Q-factor

import 'dart:isolate';

import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

class DspPipelineService {
  /// Process a single captured signal through the full 10-stage pipeline.
  Future<FrequencyResponse> process(
    CaptureResult capture,
    ChainCalibration calibration,
    SweepConfig sweepConfig,
    ResonanceSearchBand searchBand,
  ) {
    return processMultiple([capture], calibration, sweepConfig, searchBand);
  }

  /// Process multiple captures, averaging complex spectra before converting
  /// to dB. Better noise reduction than averaging the final dB values.
  Future<FrequencyResponse> processMultiple(
    List<CaptureResult> captures,
    ChainCalibration calibration,
    SweepConfig sweepConfig,
    ResonanceSearchBand searchBand,
  ) async {
    assert(captures.isNotEmpty, 'At least one capture required');

    // Build per-capture inputs. All are the same config; only samples differ.
    final inputs = captures
        .map((c) => DspPipelineInput(
              capturedSamples: c.samples,
              sampleRate: sweepConfig.sampleRate,
              f1Hz: sweepConfig.f1Hz,
              f2Hz: sweepConfig.f2Hz,
              durationSeconds: sweepConfig.durationSeconds,
              preRollMs: sweepConfig.preRollMs,
              postRollMs: sweepConfig.postRollMs,
              hChainReal: calibration.hChainReal,
              hChainImag: calibration.hChainImag,
              searchBandLowHz: searchBand.lowHz,
              searchBandHighHz: searchBand.highHz,
            ))
        .toList();

    return Isolate.run(() => runPipelineMultiple(inputs));
  }
}
