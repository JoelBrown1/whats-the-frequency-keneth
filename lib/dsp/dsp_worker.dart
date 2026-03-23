// lib/dsp/dsp_worker.dart
// Persistent DSP worker Isolate — two-port design (work + cancel).
// Initialized once at app startup, reused for all measurements.
// Cancel signal is sent to a dedicated cancel port to ensure it arrives
// immediately, not queued behind pending work.

import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

class DspWorker {
  late final SendPort _sendPort;
  late final SendPort _cancelSendPort;
  final _receivePort = ReceivePort();

  final _busyController = StreamController<bool>.broadcast();

  /// Stream indicating whether the worker is currently processing.
  Stream<bool> get busyStream => _busyController.stream;

  bool _busy = false;
  bool get busy => _busy;

  Future<void> init() async {
    await Isolate.spawn(_workerEntryPoint, _receivePort.sendPort);
    // Worker sends back two ports: work port and cancel port.
    final ports = await _receivePort.first as (SendPort, SendPort);
    _sendPort = ports.$1;
    _cancelSendPort = ports.$2;
  }

  Future<FrequencyResponse> process(CaptureResult capture) async {
    if (_busy) {
      throw StateError('DspWorker is busy — await previous process() call first');
    }
    _busy = true;
    _busyController.add(true);
    try {
      final reply = ReceivePort();
      _sendPort.send((capture, reply.sendPort));
      final result = await reply.first;
      if (result is FrequencyResponse) {
        return result;
      }
      throw StateError('DspWorker returned unexpected type: ${result.runtimeType}');
    } finally {
      _busy = false;
      _busyController.add(false);
    }
  }

  /// Signals the worker to exit the current pipeline early.
  /// The worker polls its cancel port between each of the 10 pipeline stages.
  void cancel() => _cancelSendPort.send(null);

  void dispose() {
    _receivePort.close();
    _busyController.close();
  }
}

/// Entry point for the worker Isolate.
void _workerEntryPoint(SendPort callerSendPort) {
  final workReceivePort = ReceivePort();
  final cancelReceivePort = ReceivePort();

  // Send both ports back to the caller.
  callerSendPort.send((workReceivePort.sendPort, cancelReceivePort.sendPort));

  workReceivePort.listen((message) async {
    if (message is (CaptureResult, SendPort)) {
      final (capture, replyPort) = message;
      final result = await _runPipeline(capture, cancelReceivePort);
      replyPort.send(result);
    }
  });
}

/// Run the DSP pipeline. Polls cancelReceivePort between stages.
/// Phase 0 stub — full implementation in Phase 1.
Future<FrequencyResponse> _runPipeline(
    CaptureResult capture, ReceivePort cancelReceivePort) async {
  final freqAxis = computeFrequencyAxis();
  final magnitudeDb = List<double>.filled(kFrequencyBins, 0.0);

  // Simulate a 4 kHz resonance peak in the synthetic output.
  for (int i = 0; i < kFrequencyBins; i++) {
    final f = freqAxis[i];
    const f0 = 4000.0;
    const q = 3.0;
    const bandwidth = f0 / q;
    final response =
        1.0 / (1.0 + ((f - f0) * (f - f0)) / (bandwidth * bandwidth / 4.0));
    magnitudeDb[i] =
        response > 1e-10 ? 20.0 * log(response) / ln10 : -100.0;
  }

  const primaryPeak = ResonancePeak(
    frequencyHz: 4000.0,
    magnitudeDb: 0.0,
    qFactor: 3.0,
    fLowHz: 4000.0 / (1 + 1 / 6.0),
    fHighHz: 4000.0 * (1 + 1 / 6.0),
  );

  return FrequencyResponse(
    frequencyHz: freqAxis,
    magnitudeDb: magnitudeDb,
    peaks: const [primaryPeak],
    primaryPeak: primaryPeak,
    sweepConfig: const SweepConfig(),
    analyzedAt: DateTime.now(),
  );
}
