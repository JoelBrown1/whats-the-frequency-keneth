// lib/ui/screens/measure_screen.dart
// Measurement screen. Blocked if no valid calibration exists.
// Full flow: arm → sweep loop → DSP → navigate to ResultsScreen.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:whats_the_frequency/data/capture_checkpoint_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:whats_the_frequency/audio/audio_engine_service.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/log_sine_sweep.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/audio_engine_provider.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/dsp_provider.dart';
import 'package:whats_the_frequency/providers/sweep_config_provider.dart';
import 'package:whats_the_frequency/ui/widgets/calibration_expiry_banner.dart';

class MeasureScreen extends ConsumerWidget {
  const MeasureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final calibrationService = ref.watch(calibrationProvider);
    final hasValidCalibration = calibrationService.isCalibrationValid();
    final isExpired = calibrationService.activeCalibration != null &&
        !calibrationService.isCalibrationValid();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.measureTitle)),
      body: Column(
        children: [
          if (isExpired)
            CalibrationExpiryBanner(
              onRecalibrate: () => context.push('/calibration'),
            ),
          Expanded(
            child: hasValidCalibration
                ? const _MeasureContent()
                : _NoCalibrationBlock(),
          ),
        ],
      ),
    );
  }
}

class _NoCalibrationBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.block, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          Text(l10n.measureNoCalibration,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.push('/calibration'),
            child: Text(l10n.recalibrate),
          ),
        ],
      ),
    );
  }
}

class _MeasureContent extends ConsumerStatefulWidget {
  const _MeasureContent();

  @override
  ConsumerState<_MeasureContent> createState() => _MeasureContentState();
}

class _MeasureContentState extends ConsumerState<_MeasureContent>
    with WidgetsBindingObserver {
  int _sweepPass = 0;
  int _sweepTotal = 1;
  final _checkpoint = CaptureCheckpointService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive) {
      ref.read(audioEngineProvider.notifier).backgroundInterrupted();
    }
  }

  Future<void> _startMeasurement() async {
    final engine = ref.read(audioEngineProvider.notifier);
    final dsp = ref.read(dspProvider);
    final calibration = ref.read(calibrationProvider).activeCalibration!;
    final config = ref.read(sweepConfigProvider);
    final deviceConfig = ref.read(deviceConfigProvider).valueOrNull;
    final searchBand = deviceConfig?.resonanceSearchBand ??
        const ResonanceSearchBand();

    final sweep = LogSineSweep(
      f1: config.f1Hz,
      f2: config.f2Hz,
      durationSeconds: config.durationSeconds,
      sampleRate: config.sampleRate,
    );
    final sweepSamples = Float32List.fromList(sweep.sweep);

    setState(() {
      _sweepTotal = config.sweepCount;
      _sweepPass = 0;
    });

    // ── Checkpoint resume ────────────────────────────────────────────────────
    // If a previous measurement was interrupted, offer to resume the already-
    // captured sweeps rather than starting from scratch.
    List<CaptureResult> preloadedCaptures = [];
    if (await _checkpoint.hasCheckpoint()) {
      final savedConfig = await _checkpoint.readConfig();
      if (savedConfig == config) {
        preloadedCaptures = await _checkpoint.readCaptures(config);
      } else {
        await _checkpoint.clear();
      }
    }

    // Persist config so a crash mid-loop is resumable.
    await _checkpoint.writeConfig(config);

    try {
      engine.arm();
    } on StateError {
      return; // Already in progress — double-tap guard.
    }

    final captures = <CaptureResult>[...preloadedCaptures];
    final mainsHz = deviceConfig?.measuredMainsHz ?? 50.0;
    const phi = 1.6180339887;
    final interSweepMs = 1000 + ((1.0 / mainsHz) / phi * 1000).round();

    // Sweep-0 baseline alignment offset (in samples).
    int? baselineOffset;

    try {
      int pass = captures.length; // resume from where we left off
      while (captures.length < config.sweepCount) {
        setState(() => _sweepPass = pass);
        final capture = await engine.runCapture(config, sweepSamples);

        // Compute cross-correlation alignment offset in a background isolate.
        final offset = await Isolate.run(() =>
            computeAlignmentOffset(capture.samples, sweep.inverseFilter));

        if (baselineOffset == null) {
          // Sweep 0: validate offset is within plausible USB round-trip range.
          if (offset.abs() > 500) {
            // Bad baseline — discard and retry without counting the pass.
            continue;
          }
          baselineOffset = offset;
        } else {
          // Sweeps 1-N: must be within ±2 samples of baseline.
          if ((offset - baselineOffset).abs() > 2) {
            // Misaligned sweep — discard and retry.
            pass++;
            continue;
          }
        }

        captures.add(capture);
        // Persist each accepted capture immediately.
        await _checkpoint.writeCapture(captures.length - 1, capture);
        pass++;

        // Golden-ratio inter-sweep delay for mains hum cancellation.
        if (captures.length < config.sweepCount) {
          await Future<void>.delayed(Duration(milliseconds: interSweepMs));
        }
      }
    } catch (_) {
      return; // Engine state machine handles error transition.
    }

    FrequencyResponse response;
    try {
      response = await dsp.processMultiple(
          captures, calibration, config, searchBand,
          mainsHz: deviceConfig?.measuredMainsHz);
    } catch (_) {
      engine.processingFailed();
      return;
    }

    engine.completeAnalysis(captures.last);
    // All sweeps successfully processed — checkpoint no longer needed.
    await _checkpoint.clear();

    if (mounted) {
      context.push('/results', extra: response);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engineState = ref.watch(audioEngineProvider);

    // Error states.
    if (engineState.state == AudioEngineState.recoverableError ||
        engineState.state == AudioEngineState.deviceError) {
      return _ErrorBlock(
        error: engineState.error!,
        onRetry: () => ref.read(audioEngineProvider.notifier).reset(),
      );
    }

    // Active states: show spinner and status.
    if (engineState.state != AudioEngineState.idle &&
        engineState.state != AudioEngineState.complete) {
      return _ActiveMeasurement(
        engineState: engineState.state,
        sweepPass: _sweepPass,
        sweepTotal: _sweepTotal,
        onCancel: () async {
          await ref.read(audioEngineProvider.notifier).cancelCapture();
          await _checkpoint.clear();
        },
      );
    }

    // Idle: show start button.
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.mic),
        label: Text(l10n.measureStart),
        onPressed: _startMeasurement,
      ),
    );
  }
}

class _ActiveMeasurement extends StatelessWidget {
  final AudioEngineState engineState;
  final int sweepPass;
  final int sweepTotal;
  final VoidCallback onCancel;

  const _ActiveMeasurement({
    required this.engineState,
    required this.sweepPass,
    required this.sweepTotal,
    required this.onCancel,
  });

  String _label(AppLocalizations l10n) => switch (engineState) {
        AudioEngineState.armed => l10n.measureArming,
        AudioEngineState.playing =>
          l10n.measurePlayingSweep(sweepPass + 1, sweepTotal),
        AudioEngineState.capturing => l10n.measureCapturing,
        AudioEngineState.analyzing => l10n.measureAnalysing,
        _ => l10n.measureWorking,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canCancel = engineState == AudioEngineState.playing ||
        engineState == AudioEngineState.capturing;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(_label(l10n), style: const TextStyle(fontSize: 16)),
          if (canCancel) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: Text(l10n.cancel),
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final AudioEngineError error;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              _localiseError(error.code, l10n),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.measureRetry),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

String _localiseError(String code, AppLocalizations l10n) => switch (code) {
      'DROPOUT_DETECTED' => l10n.errorDropoutDetected,
      'OUTPUT_CLIPPING' => l10n.errorOutputClipping,
      'DEVICE_NOT_FOUND' || 'DEVICE_DISCONNECTED' => l10n.errorDeviceNotFound,
      'SAMPLE_RATE_MISMATCH' => l10n.errorSampleRateMismatch,
      'APP_BACKGROUNDED' => l10n.errorAppBackgrounded,
      'DSP_FAILED' => l10n.errorDspFailed,
      _ => l10n.errorInterrupted,
    };
