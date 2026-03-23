// lib/providers/pickup_provider.dart
// Global keepAlive provider for PickupRepository.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/data/models/pickup.dart';
import 'package:whats_the_frequency/data/pickup_repository.dart';

final pickupRepositoryProvider = Provider<PickupRepository>((ref) {
  return PickupRepository();
});

final pickupListProvider =
    FutureProvider<List<Pickup>>((ref) async {
  final repo = ref.watch(pickupRepositoryProvider);
  return repo.loadAll();
});
