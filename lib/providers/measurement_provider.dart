// lib/providers/measurement_provider.dart
// AutoDispose provider — cleared when Results screen is popped.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/data/measurement_repository.dart';

final measurementRepositoryProvider =
    Provider<MeasurementRepository>((ref) {
  return MeasurementRepository();
});

/// AutoDispose provider for the current in-progress measurement session.
/// Cleared when the Results screen is popped.
final measurementProvider =
    StateProvider.autoDispose<String?>((ref) => null);
