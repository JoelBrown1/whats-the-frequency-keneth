// lib/dsp/dsp_worker.dart
// Persistent DSP worker Isolate — two-port design (work + cancel).
// Initialized once at app startup, reused for all measurements.
// Cancel signal is sent to a dedicated cancel port to ensure it arrives
// immediately, not queued behind pending work.
//
// TypedData transfer: capturedSamples, hChainReal and hChainImag are wrapped
// in TransferableTypedData before being sent to the worker isolate so the VM
// can transfer ownership (zero-copy) instead of copying the buffers.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

// ─── Wire message ─────────────────────────────────────────────────────────────

/// Message sent from [DspWorker.process] to the worker isolate.
///
/// [TypedData] fields are wrapped as [TransferableTypedData] so the VM can
/// transfer buffer ownership across the isolate boundary without copying.
class _WorkerMessage {
  final TransferableTypedData samples;
  final TransferableTypedData hChainReal;
  final TransferableTypedData hChainImag;
  final int sampleRate;
  final double f1Hz;
  final double f2Hz;
  final double durationSeconds;
  final int preRollMs;
  final int postRollMs;
  final double searchBandLowHz;
  final double searchBandHighHz;
  final double? mainsHz;
  final SendPort replyPort;

  _WorkerMessage._({
    required this.samples,
    required this.hChainReal,
    required this.hChainImag,
    required this.sampleRate,
    required this.f1Hz,
    required this.f2Hz,
    required this.durationSeconds,
    required this.preRollMs,
    required this.postRollMs,
    required this.searchBandLowHz,
    required this.searchBandHighHz,
    required this.mainsHz,
    required this.replyPort,
  });

  factory _WorkerMessage.from(DspPipelineInput input, SendPort reply) =>
      _WorkerMessage._(
        samples: TransferableTypedData.fromList([input.capturedSamples]),
        hChainReal: TransferableTypedData.fromList([input.hChainReal]),
        hChainImag: TransferableTypedData.fromList([input.hChainImag]),
        sampleRate: input.sampleRate,
        f1Hz: input.f1Hz,
        f2Hz: input.f2Hz,
        durationSeconds: input.durationSeconds,
        preRollMs: input.preRollMs,
        postRollMs: input.postRollMs,
        searchBandLowHz: input.searchBandLowHz,
        searchBandHighHz: input.searchBandHighHz,
        mainsHz: input.mainsHz,
        replyPort: reply,
      );

  DspPipelineInput toPipelineInput() => DspPipelineInput(
        capturedSamples: samples.materialize().asFloat32List(),
        hChainReal: hChainReal.materialize().asFloat64List(),
        hChainImag: hChainImag.materialize().asFloat64List(),
        sampleRate: sampleRate,
        f1Hz: f1Hz,
        f2Hz: f2Hz,
        durationSeconds: durationSeconds,
        preRollMs: preRollMs,
        postRollMs: postRollMs,
        searchBandLowHz: searchBandLowHz,
        searchBandHighHz: searchBandHighHz,
        mainsHz: mainsHz,
      );
}

// ─── Worker ───────────────────────────────────────────────────────────────────

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
      _sendPort.send(_WorkerMessage.from(input, reply.sendPort));
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
    if (message is _WorkerMessage) {
      final input = message.toPipelineInput();
      try {
        final result = runPipeline(input);
        message.replyPort.send(result);
      } catch (e) {
        message.replyPort.send(StateError(e.toString()));
      }
    }
  });
}
