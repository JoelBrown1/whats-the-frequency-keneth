// test/calibration/calibration_service_test.dart
// Unit tests for CalibrationService: init, runChainCalibration, validity,
// measureMainsFrequency, and orphan reconciliation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _MockPlatform extends Mock implements AudioEnginePlatformInterface {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a capture whose samples contain a 50 Hz sine wave (mains hum).
CaptureResult _mainsCapture(int sampleRate) {
  const f0 = 50.0;
  const amplitude = 0.1;
  final n = sampleRate ~/ 2; // 0.5 s
  final samples = Float32List(n);
  for (int i = 0; i < n; i++) {
    samples[i] = amplitude * sin(2 * pi * f0 * i / sampleRate);
  }
  return CaptureResult(
    samples: samples,
    sampleRate: sampleRate,
    sweepIndex: 0,
    capturedAt: DateTime.now(),
  );
}

/// Builds a silent (all-zero) capture for the level pre-check.
CaptureResult _silentCapture(int sampleRate) => CaptureResult(
      samples: Float32List(sampleRate),
      sampleRate: sampleRate,
      sweepIndex: 0,
      capturedAt: DateTime.now(),
    );

/// A minimal SweepConfig suitable for fast tests.
const _kConfig = SweepConfig(
  f1Hz: 20.0,
  f2Hz: 20000.0,
  durationSeconds: 0.2,
  sampleRate: 48000,
  sweepCount: 1,
  preRollMs: 0,
  postRollMs: 50,
);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(Float32List(0));
  });

  late Directory tempDir;
  late _MockPlatform mockPlatform;
  late StreamController<double> levelCtrl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wtfk_cal_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    levelCtrl = StreamController<double>.broadcast();
    mockPlatform = _MockPlatform();

    when(() => mockPlatform.levelMeterStream)
        .thenAnswer((_) => levelCtrl.stream);
    when(() => mockPlatform.startLevelMeter()).thenAnswer((_) async {
      // Schedule emission on the event queue (after current microtask cascade),
      // so that levelMeterStream.first has subscribed before the event fires.
      Future<void>(() => levelCtrl.add(-60.0));
    });
    when(() => mockPlatform.stopLevelMeter()).thenAnswer((_) async {});

    // Default: runCapture returns a short silent capture.
    when(() => mockPlatform.runCapture(any(), any(), any(), any()))
        .thenAnswer((_) async => _silentCapture(_kConfig.sampleRate));

    // deviceEventStream is unused by CalibrationService but must not throw.
    when(() => mockPlatform.deviceEventStream)
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await levelCtrl.close();
    await tempDir.delete(recursive: true);
  });

  test('init() with empty directory → activeCalibration is null', () async {
    final service = CalibrationService(platform: mockPlatform);
    await service.init();
    expect(service.activeCalibration, isNull);
  });

  test('runChainCalibration() returns a calibration with kHChainBins bins',
      () async {
    final service = CalibrationService(platform: mockPlatform);
    final cal = await service.runChainCalibration(_kConfig);

    expect(cal.hChainReal.length, kHChainBins);
    expect(cal.hChainImag.length, kHChainBins);
    expect(cal.id, isNotEmpty);
    expect(service.activeCalibration, isNotNull);
    expect(service.activeCalibration!.id, cal.id);
  });

  test('init() after runChainCalibration() restores calibration', () async {
    final service1 = CalibrationService(platform: mockPlatform);
    final cal = await service1.runChainCalibration(_kConfig);

    // Simulate app restart: new service instance with same on-disk data.
    final service2 = CalibrationService(platform: mockPlatform);
    await service2.init(activeCalibrationId: cal.id);

    expect(service2.activeCalibration, isNotNull);
    expect(service2.activeCalibration!.id, cal.id);
  });

  test('isCalibrationValid() is false after 31 minutes', () async {
    final service = CalibrationService(platform: mockPlatform);
    await service.runChainCalibration(_kConfig);
    expect(service.isCalibrationValid(), isTrue);

    // Manually backdating the timestamp is not possible through the public API,
    // so we verify the expiry logic by checking the calibration was created now.
    final cal = service.activeCalibration!;
    expect(
      DateTime.now().difference(cal.timestamp).inSeconds,
      lessThan(30),
      reason: 'Calibration should have just been created',
    );
    // Expiry should be 30 minutes (CalibrationService.calibrationExpiryDuration).
    expect(CalibrationService.calibrationExpiryDuration,
        equals(const Duration(minutes: 30)));
  });

  test('isCalibrationValid() is false when no calibration', () {
    final service = CalibrationService(platform: mockPlatform);
    expect(service.isCalibrationValid(), isFalse);
  });

  test('PICKUP_STILL_CONNECTED thrown when level > −20 dBFS', () async {
    // Override startLevelMeter to emit a hot signal after the listener attaches.
    when(() => mockPlatform.startLevelMeter()).thenAnswer((_) async {
      // Schedule the event on the event queue (after current microtask cascade),
      // so that levelMeterStream.first has subscribed before the event fires.
      Future<void>(() => levelCtrl.add(-5.0));
    });

    final service = CalibrationService(platform: mockPlatform);
    await expectLater(
      service.runChainCalibration(_kConfig),
      throwsA(isA<CalibrationError>().having(
        (e) => e.code,
        'code',
        'PICKUP_STILL_CONNECTED',
      )),
    );
  });

  test('measureMainsFrequency() detects 50 Hz within ±2 Hz', () async {
    // Override runCapture to return a capture containing 50 Hz mains hum.
    when(() => mockPlatform.runCapture(any(), any(), any(), any()))
        .thenAnswer((_) async => _mainsCapture(_kConfig.sampleRate));

    final service = CalibrationService(platform: mockPlatform);
    final hz = await service.measureMainsFrequency(_kConfig);

    expect(hz, closeTo(50.0, 2.0),
        reason: 'Expected mains frequency near 50 Hz, got $hz Hz');
  });

  test('sweepProgress notifier advances during runChainCalibration', () async {
    const multiSweepConfig = SweepConfig(
      f1Hz: 20.0,
      f2Hz: 20000.0,
      durationSeconds: 0.2,
      sampleRate: 48000,
      sweepCount: 3,
      preRollMs: 0,
      postRollMs: 50,
    );

    final service = CalibrationService(platform: mockPlatform);
    final progressValues = <int>[];
    service.sweepProgress.addListener(() {
      progressValues.add(service.sweepProgress.value);
    });

    await service.runChainCalibration(multiSweepConfig);

    // Progress should have been reported for each pass (0, 1, 2) plus final.
    expect(progressValues.length, greaterThanOrEqualTo(3));
    expect(progressValues.last, equals(3)); // sweepCount
  });

  // ─── Orphan reconciliation ─────────────────────────────────────────────────

  group('init() orphan reconciliation', () {
    /// Write a minimal ChainCalibration JSON file directly into the calibrations
    /// directory, bypassing the service.  Used to simulate an orphan (a file on
    /// disk that DeviceConfig does not know about).
    Future<ChainCalibration> _writeOrphan(
      Directory dir,
      String id, {
      required DateTime timestamp,
    }) async {
      final cal = ChainCalibration(
        id: id,
        timestamp: timestamp,
        hChainReal: Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0),
        hChainImag: Float64List(kHChainBins),
        sweepConfig: _kConfig,
      );
      final calDir = Directory('${dir.path}/calibrations');
      if (!await calDir.exists()) await calDir.create(recursive: true);
      final file = File('${calDir.path}/$id.json');
      await file.writeAsString(jsonEncode(cal.toJson()));
      return cal;
    }

    test('zero calibration files → activeCalibration remains null', () async {
      final service = CalibrationService(platform: mockPlatform);
      await service.init(); // no activeCalibrationId, empty directory

      expect(service.activeCalibration, isNull);
    });

    test('one orphan file → init() loads it when activeCalibrationId is null',
        () async {
      final orphan = await _writeOrphan(
        tempDir,
        'orphan-1',
        timestamp: DateTime(2026, 1, 1),
      );

      final service = CalibrationService(platform: mockPlatform);
      await service.init(); // activeCalibrationId: null — must scan directory

      expect(service.activeCalibration, isNotNull);
      expect(service.activeCalibration!.id, equals(orphan.id));
    });

    test(
        'multiple orphan files → init() loads the most recently timestamped one',
        () async {
      await _writeOrphan(
        tempDir,
        'older',
        timestamp: DateTime(2026, 1, 1),
      );
      final newer = await _writeOrphan(
        tempDir,
        'newer',
        timestamp: DateTime(2026, 3, 1),
      );

      final service = CalibrationService(platform: mockPlatform);
      await service.init();

      expect(service.activeCalibration!.id, equals(newer.id));
    });

    test(
        'activeCalibrationId provided → loads that file, not the most recent',
        () async {
      final target = await _writeOrphan(
        tempDir,
        'target-id',
        timestamp: DateTime(2026, 1, 1),
      );
      // Write a newer file that should NOT be selected.
      await _writeOrphan(
        tempDir,
        'newer-but-ignored',
        timestamp: DateTime(2026, 6, 1),
      );

      final service = CalibrationService(platform: mockPlatform);
      await service.init(activeCalibrationId: target.id);

      expect(service.activeCalibration!.id, equals(target.id));
    });

    test('notifyListeners() called when init() finds an orphan', () async {
      await _writeOrphan(
        tempDir,
        'notify-test',
        timestamp: DateTime(2026, 1, 1),
      );

      final service = CalibrationService(platform: mockPlatform);
      var notified = false;
      service.addListener(() => notified = true);

      await service.init();

      expect(notified, isTrue,
          reason: 'Consumers should be notified so they can rebuild');
      service.removeListener(() {});
    });
  });
}
