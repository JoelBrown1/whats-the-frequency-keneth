// lib/data/pickup_repository.dart
// CRUD for Pickup entities. Atomic writes; serialised via per-repo Lock.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import 'models/pickup.dart';

class PickupRepository {
  final _lock = Lock();
  Directory? _dir;

  Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/pickups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String id) =>
      File('${dir.path}/$id.json');

  Future<void> save(Pickup pickup) async {
    final dir = await _getDir();
    await _lock.synchronized(() async {
      await _writeAtomic(_fileFor(dir, pickup.id), jsonEncode(pickup.toJson()));
    });
  }

  Future<List<Pickup>> loadAll() async {
    final dir = await _getDir();
    if (!await dir.exists()) return [];
    final pickups = <Pickup>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          pickups.add(Pickup.fromJson(json));
        } catch (_) {
          // Corrupt file — skip.
        }
      }
    }
    pickups.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pickups;
  }

  Future<Pickup?> loadById(String id) async {
    final dir = await _getDir();
    final file = _fileFor(dir, id);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return Pickup.fromJson(json);
  }

  Future<void> delete(String id) async {
    final dir = await _getDir();
    await _lock.synchronized(() async {
      final file = _fileFor(dir, id);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(target.path);
  }
}
