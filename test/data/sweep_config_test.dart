// test/data/sweep_config_test.dart
// Pass criteria:
// - Two configs with identical fields compare equal (operator ==).
// - Any single differing field makes configs unequal.
// Used by the sweepConfig comparability guard on measurement overlay.

import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';

void main() {
  const defaults = SweepConfig();

  group('SweepConfig equality', () {
    test('identical configs compare equal', () {
      const a = SweepConfig(
        f1Hz: 20.0,
        f2Hz: 20000.0,
        durationSeconds: 3.0,
        sampleRate: 48000,
        sweepCount: 4,
        preRollMs: 512,
        postRollMs: 500,
      );
      const b = SweepConfig(
        f1Hz: 20.0,
        f2Hz: 20000.0,
        durationSeconds: 3.0,
        sampleRate: 48000,
        sweepCount: 4,
        preRollMs: 512,
        postRollMs: 500,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing f1Hz compares unequal', () {
      final a = defaults;
      const b = SweepConfig(f1Hz: 40.0);
      expect(a, isNot(equals(b)));
    });

    test('differing f2Hz compares unequal', () {
      final a = defaults;
      const b = SweepConfig(f2Hz: 18000.0);
      expect(a, isNot(equals(b)));
    });

    test('differing durationSeconds compares unequal', () {
      final a = defaults;
      const b = SweepConfig(durationSeconds: 5.0);
      expect(a, isNot(equals(b)));
    });

    test('differing sampleRate compares unequal', () {
      final a = defaults;
      const b = SweepConfig(sampleRate: 44100);
      expect(a, isNot(equals(b)));
    });

    test('differing sweepCount compares unequal', () {
      final a = defaults;
      const b = SweepConfig(sweepCount: 8);
      expect(a, isNot(equals(b)));
    });

    test('differing preRollMs compares unequal', () {
      final a = defaults;
      const b = SweepConfig(preRollMs: 256);
      expect(a, isNot(equals(b)));
    });

    test('differing postRollMs compares unequal', () {
      final a = defaults;
      const b = SweepConfig(postRollMs: 250);
      expect(a, isNot(equals(b)));
    });
  });

  group('SweepConfig JSON round-trip', () {
    test('serializes and deserializes correctly', () {
      const original = SweepConfig(
        f1Hz: 30.0,
        f2Hz: 18000.0,
        durationSeconds: 4.0,
        sampleRate: 48000,
        sweepCount: 8,
        preRollMs: 256,
        postRollMs: 1000,
      );
      final restored = SweepConfig.fromJson(original.toJson());
      expect(restored, equals(original));
    });
  });
}
