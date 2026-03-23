// lib/data/measurement_repository.dart
// Two-stage loading: loadSummaries() at launch (fast), loadFull(id) on demand.
// All writes are atomic (write-then-rename) and serialised with a per-repo Lock.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import 'models/measurement.dart';
import 'models/measurement_summary.dart';

class MeasurementRepository {
  final _lock = Lock();
  Directory? _dir;

  Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/measurements');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String id) =>
      File('${dir.path}/$id.json');

  /// Stage 1: Load metadata only — sufficient for the history list.
  Future<List<MeasurementSummary>> loadSummaries() async {
    final dir = await _getDir();
    if (!await dir.exists()) return [];
    final summaries = <MeasurementSummary>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          summaries.add(MeasurementSummary.fromJson(json));
        } catch (_) {
          // Corrupt file — skip, do not crash.
        }
      }
    }
    summaries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return summaries;
  }

  /// Stage 2: Load full measurement data on demand.
  Future<Measurement> loadFull(String id) async {
    final dir = await _getDir();
    final file = _fileFor(dir, id);
    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return Measurement.fromJson(json);
  }

  /// Save a measurement atomically. Serialised via Lock.
  Future<void> save(Measurement measurement) async {
    final dir = await _getDir();
    await _lock.synchronized(() async {
      await _writeAtomic(_fileFor(dir, measurement.id),
          jsonEncode(measurement.toJson()));
    });
  }

  /// Delete a measurement by id.
  Future<void> delete(String id) async {
    final dir = await _getDir();
    await _lock.synchronized(() async {
      final file = _fileFor(dir, id);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  /// Atomic write-then-rename. Prevents corrupt JSON on force-quit mid-write.
  Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(target.path);
  }
}
