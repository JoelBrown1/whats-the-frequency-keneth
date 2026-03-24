// lib/data/capture_checkpoint_service.dart
// Persists in-progress sweep captures to disk so a force-quit mid-measurement
// doesn't lose all work.
//
// Layout under {appSupportDir}/checkpoints/:
//   meta.json          — SweepConfig JSON
//   0.f32, 1.f32, …   — Float32LE raw PCM per capture

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';

class CaptureCheckpointService {
  Directory? _dir;

  Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/checkpoints');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Persist [config] so a resume can reconstruct the SweepConfig.
  Future<void> writeConfig(SweepConfig config) async {
    final dir = await _getDir();
    final tmp = File('${dir.path}/meta.json.tmp');
    await tmp.writeAsString(jsonEncode(config.toJson()));
    await tmp.rename('${dir.path}/meta.json');
  }

  /// Persist a single capture at [index]. Safe to call multiple times for the
  /// same index (overwrites).
  Future<void> writeCapture(int index, CaptureResult capture) async {
    final dir = await _getDir();
    final bytes = capture.samples.buffer
        .asUint8List(capture.samples.offsetInBytes, capture.samples.lengthInBytes);
    final tmp = File('${dir.path}/$index.f32.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${dir.path}/$index.f32');
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the persisted [SweepConfig], or null if no checkpoint exists.
  Future<SweepConfig?> readConfig() async {
    final dir = await _getDir();
    final file = File('${dir.path}/meta.json');
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return SweepConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns the persisted captures in sweep order, or an empty list.
  Future<List<CaptureResult>> readCaptures(SweepConfig config) async {
    final dir = await _getDir();
    final results = <MapEntry<int, CaptureResult>>[];

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.f32')) continue;
      final idx = int.tryParse(name.replaceAll('.f32', ''));
      if (idx == null) continue;
      try {
        final bytes = await entity.readAsBytes();
        final samples = bytes.buffer.asFloat32List();
        results.add(MapEntry(
          idx,
          CaptureResult(
            samples: Float32List.fromList(samples),
            sampleRate: config.sampleRate,
            sweepIndex: idx,
            capturedAt: DateTime.fromMillisecondsSinceEpoch(
                entity.statSync().modified.millisecondsSinceEpoch),
          ),
        ));
      } catch (_) {
        // Corrupt file — skip it.
      }
    }

    results.sort((a, b) => a.key.compareTo(b.key));
    return results.map((e) => e.value).toList();
  }

  /// True if at least one capture file and a meta.json exist on disk.
  Future<bool> hasCheckpoint() async {
    final dir = await _getDir();
    if (!await dir.exists()) return false;
    if (!await File('${dir.path}/meta.json').exists()) return false;
    return await dir
        .list()
        .any((e) => e is File && e.path.endsWith('.f32'));
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  /// Delete all checkpoint files. Call on successful completion or user cancel.
  Future<void> clear() async {
    final dir = await _getDir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }
}
