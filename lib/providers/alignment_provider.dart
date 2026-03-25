// lib/providers/alignment_provider.dart
// Provider that wraps the cross-correlation alignment computation so widget
// tests can override it with a synchronous stub instead of a real Isolate.run.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/dsp/dsp_isolate.dart';

typedef AlignmentComputer = Future<int> Function(
    Float32List capture, Float64List inverseFilter);

final alignmentComputerProvider = Provider<AlignmentComputer>(
  (_) => (capture, inverseFilter) =>
      Isolate.run(() => computeAlignmentOffset(capture, inverseFilter)),
);
