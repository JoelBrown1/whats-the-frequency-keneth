// lib/dsp/dsp_worker.dart
// Persistent DSP worker Isolate — two-port design (work + cancel).
// Initialized once at app startup, reused for all measurements.
// Cancel signal is sent to a dedicated cancel port to ensure it arrives
// immediately, not queued behind pending work.

import 'dart:async';
import 'dart:isolate';

import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';
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

  Future<FrequencyResponse> process(DspPipelineInput input) async {
    if (_busy) {
      throw StateError('DspWorker is busy — await previous process() call first');
    }
    _busy = true;
    _busyController.add(true);
    try {
      final reply = ReceivePort();
      _sendPort.send((input, reply.sendPort));
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

  workReceivePort.listen((message) {
    if (message is (DspPipelineInput, SendPort)) {
      final (input, replyPort) = message;
      try {
        final result = runPipeline(input);
        replyPort.send(result);
      } catch (e) {
        replyPort.send(StateError(e.toString()));
      }
    }
  });
}
