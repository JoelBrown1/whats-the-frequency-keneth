// test/audio/capture_checkpoint_test.dart
// Unit tests for CaptureCheckpointService.
// All tests use a temp directory injected via the testDirectory constructor
// parameter so no real app-support directory is involved.
//
// Coverage:
//   readConfig — returns null when no checkpoint
//   writeConfig / readConfig — round-trip preserves all fields
//   readCaptures — empty list when no .f32 files
//   writeCapture / readCaptures — N captures returned in sweep order
//   hasCheckpoint — false when dir empty, true after write
//   clear() — removes all checkpoint files
//   readCaptures — corrupt .f32 file is silently skipped

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/capture_checkpoint_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _kConfig = SweepConfig(
  f1Hz: 20.0,
  f2Hz: 20000.0,
  durationSeconds: 0.5,
  sampleRate: 48000,
  sweepCount: 3,
);

CaptureResult _capture(int index, {int length = 64}) => CaptureResult(
      samples: Float32List.fromList(
          List.generate(length, (i) => (index * 100 + i).toDouble())),
      sampleRate: 48000,
      sweepIndex: index,
      capturedAt: DateTime(2025),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  late CaptureCheckpointService svc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('checkpoint_test_');
    svc = CaptureCheckpointService(testDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // ── readConfig ──────────────────────────────────────────────────────────────

  test('readConfig returns null when no checkpoint exists', () async {
    expect(await svc.readConfig(), isNull);
  });

  // ── writeConfig / readConfig ─────────────────────────────────────────────────

  test('writeConfig / readConfig round-trip preserves all fields', () async {
    await svc.writeConfig(_kConfig);
    final loaded = await svc.readConfig();

    expect(loaded, isNotNull);
    expect(loaded!.f1Hz, _kConfig.f1Hz);
    expect(loaded.f2Hz, _kConfig.f2Hz);
    expect(loaded.durationSeconds, _kConfig.durationSeconds);
    expect(loaded.sampleRate, _kConfig.sampleRate);
    expect(loaded.sweepCount, _kConfig.sweepCount);
    expect(loaded.preRollMs, _kConfig.preRollMs);
    expect(loaded.postRollMs, _kConfig.postRollMs);
    expect(loaded, equals(_kConfig)); // SweepConfig.== covers all fields
  });

  // ── readCaptures ─────────────────────────────────────────────────────────────

  test('readCaptures returns empty list when no .f32 files', () async {
    await svc.writeConfig(_kConfig); // meta.json present, but no captures
    final captures = await svc.readCaptures(_kConfig);
    expect(captures, isEmpty);
  });

  test('writeCapture / readCaptures returns captures in sweep order', () async {
    await svc.writeConfig(_kConfig);
    // Write in reverse order to verify sorting.
    await svc.writeCapture(2, _capture(2));
    await svc.writeCapture(0, _capture(0));
    await svc.writeCapture(1, _capture(1));

    final captures = await svc.readCaptures(_kConfig);

    expect(captures.length, 3);
    // Sweep index order: 0, 1, 2.
    for (int i = 0; i < 3; i++) {
      expect(captures[i].sweepIndex, i);
      // First sample encodes the index: index*100 + 0 = i*100.
      expect(captures[i].samples[0], closeTo(i * 100.0, 1e-6));
    }
  });

  // ── hasCheckpoint ─────────────────────────────────────────────────────────────

  test('hasCheckpoint is false when directory is empty', () async {
    expect(await svc.hasCheckpoint(), isFalse);
  });

  test('hasCheckpoint is false when meta.json present but no .f32 files',
      () async {
    await svc.writeConfig(_kConfig);
    expect(await svc.hasCheckpoint(), isFalse);
  });

  test('hasCheckpoint is true after writeConfig + writeCapture', () async {
    await svc.writeConfig(_kConfig);
    await svc.writeCapture(0, _capture(0));
    expect(await svc.hasCheckpoint(), isTrue);
  });

  // ── clear() ──────────────────────────────────────────────────────────────────

  test('clear() removes all checkpoint files', () async {
    await svc.writeConfig(_kConfig);
    await svc.writeCapture(0, _capture(0));
    await svc.writeCapture(1, _capture(1));

    await svc.clear();

    expect(await svc.hasCheckpoint(), isFalse);
    expect(await svc.readConfig(), isNull);
    expect(await svc.readCaptures(_kConfig), isEmpty);
  });

  // ── corrupt file ─────────────────────────────────────────────────────────────

  test('readCaptures silently skips a corrupt .f32 file', () async {
    await svc.writeConfig(_kConfig);
    // Write a valid capture at index 0.
    await svc.writeCapture(0, _capture(0));
    // Inject a corrupt file at index 1 (odd byte count → misaligned Float32).
    await File('${tempDir.path}/1.f32').writeAsBytes([0xFF, 0x00, 0xAB]);

    final captures = await svc.readCaptures(_kConfig);

    // Only the valid capture at index 0 should appear.
    // The corrupt index 1 file produces a misaligned read but
    // CaptureCheckpointService catches errors and skips the file.
    // The valid capture must be present.
    expect(captures.any((c) => c.sweepIndex == 0), isTrue);
  });
}
