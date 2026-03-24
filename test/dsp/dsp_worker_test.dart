// test/dsp/dsp_worker_test.dart
// Tests for DspWorker busy-flag transitions.
// Verifies that:
//   - busy is false before any work is started.
//   - busy becomes true while process() is running, false once it returns.
//   - busyStream emits true then false in order.
//   - calling process() while busy throws StateError.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/dsp/dsp_worker.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';

// ─── Fixture ──────────────────────────────────────────────────────────────────

/// Minimal pipeline input that exercises the full pipeline quickly.
DspPipelineInput _minimalInput() {
  const sr = 48000;
  const dur = 0.1; // 4 800 samples — tiny but valid
  // Flat H_chain: real=1, imag=0 everywhere.
  final hReal = Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0);
  final hImag = Float64List(kHChainBins);
  // Captured samples: random-ish but non-zero so the pipeline has something
  // to deconvolve (all-zero would give -∞ dB everywhere).
  final n = (sr * dur).round();
  final samples = Float32List(n);
  for (int i = 0; i < n; i++) {
    samples[i] = (i % 100 < 50) ? 0.01 : -0.01; // square wave at 480 Hz
  }
  return DspPipelineInput(
    capturedSamples: samples,
    sampleRate: sr,
    f1Hz: 20.0,
    f2Hz: 20000.0,
    durationSeconds: dur,
    preRollMs: 0,
    postRollMs: 0,
    hChainReal: hReal,
    hChainImag: hImag,
    searchBandLowHz: 200.0,
    searchBandHighHz: 15000.0,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late DspWorker worker;

  setUp(() async {
    worker = DspWorker();
    await worker.init();
  });

  tearDown(() {
    worker.dispose();
  });

  test('busy is false before any process() call', () {
    expect(worker.busy, isFalse);
  });

  test('busyStream emits true then false across a process() call',
      () async {
    final emissions = <bool>[];
    final sub = worker.busyStream.listen(emissions.add);

    await worker.process(_minimalInput());

    // Pump the microtask/event queue so the queued `false` emission is
    // delivered to the listener before we cancel the subscription.
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emissions, containsAllInOrder([true, false]));
  });

  test('busy is true while process() is awaited, false after it returns',
      () async {
    final states = <bool>[];

    // Capture busy state immediately before and after.
    states.add(worker.busy); // should be false — not started yet
    final future = worker.process(_minimalInput());
    states.add(worker.busy); // should be true — work dispatched
    await future;
    states.add(worker.busy); // should be false — work done

    expect(states, equals([false, true, false]));
  });

  test('process() while busy throws StateError', () async {
    // Start a process but do not await — fire and forget.
    final first = worker.process(_minimalInput());
    // Immediately try to start another while the first is in flight.
    expect(
      () => worker.process(_minimalInput()),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('busy'),
      )),
    );
    // Let the first complete so tearDown can dispose cleanly.
    await first;
  });
}
