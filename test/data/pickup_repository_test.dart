// test/data/pickup_repository_test.dart
// Pass criteria:
// - save/loadAll/delete cycle works correctly.
// - measurementId added correctly via copyWith.
// - Missing directory returns empty list (not crash).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:whats_the_frequency/data/models/pickup.dart';
import 'package:whats_the_frequency/data/pickup_repository.dart';
import 'package:uuid/uuid.dart';

class FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  FakePathProvider(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  late Directory tempDir;
  late PickupRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wtfk_pickup_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
    repo = PickupRepository();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('PickupRepository', () {
    test('save/loadAll/delete cycle', () async {
      final pickup = Pickup(
        id: const Uuid().v4(),
        name: 'PAF neck',
        notes: 'Original PAF from 1959',
        createdAt: DateTime.now(),
        measurementIds: const [],
      );

      await repo.save(pickup);

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.first.id, equals(pickup.id));
      expect(all.first.name, equals('PAF neck'));
      expect(all.first.notes, equals('Original PAF from 1959'));

      await repo.delete(pickup.id);

      final afterDelete = await repo.loadAll();
      expect(afterDelete, isEmpty);
    });

    test('loadById returns correct pickup', () async {
      final pickup = Pickup(
        id: 'specific-id-123',
        name: 'Strat bridge',
        createdAt: DateTime.now(),
      );
      await repo.save(pickup);

      final loaded = await repo.loadById('specific-id-123');
      expect(loaded, isNotNull);
      expect(loaded!.name, equals('Strat bridge'));
    });

    test('loadById returns null for missing pickup', () async {
      final result = await repo.loadById('nonexistent-id');
      expect(result, isNull);
    });

    test('measurementId added correctly via copyWith', () async {
      final pickup = Pickup(
        id: 'pickup-with-measurements',
        name: 'Humbucker',
        createdAt: DateTime.now(),
        measurementIds: const [],
      );
      await repo.save(pickup);

      // Add a measurement ID via copyWith.
      final updated = pickup.copyWith(
        measurementIds: [...pickup.measurementIds, 'measurement-001'],
      );
      await repo.save(updated);

      final loaded = await repo.loadById('pickup-with-measurements');
      expect(loaded!.measurementIds, contains('measurement-001'));
    });

    test('missing directory returns empty list not crash', () async {
      // Use a fresh repo pointed at a non-existent directory.
      final freshTempDir =
          await Directory.systemTemp.createTemp('wtfk_empty_');
      PathProviderPlatform.instance =
          FakePathProvider(freshTempDir.path);
      final freshRepo = PickupRepository();

      // Pass criteria: does not throw, returns empty list.
      final result = await freshRepo.loadAll();
      expect(result, isEmpty);

      await freshTempDir.delete(recursive: true);
    });
  });
}
