// lib/ui/widgets/calibration_flow_widget.dart
// Reusable calibration flow widget — used by CalibrationScreen and
// OnboardingScreen._ChainCalibrationStep.
//
// Drives: idle → running → success | error.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/sweep_config_provider.dart';

enum _CalibrationState { idle, running, success, error }

class CalibrationFlowWidget extends ConsumerStatefulWidget {
  /// Called when calibration succeeds. Parent can navigate or update state.
  final VoidCallback? onSuccess;

  const CalibrationFlowWidget({super.key, this.onSuccess});

  @override
  ConsumerState<CalibrationFlowWidget> createState() =>
      _CalibrationFlowWidgetState();
}

class _CalibrationFlowWidgetState
    extends ConsumerState<CalibrationFlowWidget> {
  _CalibrationState _state = _CalibrationState.idle;
  String? _errorMessage;
  String? _successTimestamp;
  int _sweepPass = 0;
  int _sweepTotal = 1;

  Future<void> _runCalibration() async {
    final service = ref.read(calibrationProvider);
    final config = ref.read(sweepConfigProvider);
    _sweepTotal = config.sweepCount;

    setState(() {
      _state = _CalibrationState.running;
      _errorMessage = null;
      _sweepPass = 0;
    });

    service.sweepProgress.addListener(_onSweepProgress);
    try {
      final cal = await service.runChainCalibration(config);
      // Persist calibration ID so it survives app restart.
      await ref
          .read(deviceConfigProvider.notifier)
          .setCalibrationId(cal.id);
      setState(() {
        _state = _CalibrationState.success;
        _successTimestamp =
            DateFormat('dd MMM yyyy HH:mm').format(cal.timestamp.toLocal());
      });
      widget.onSuccess?.call();
    } on CalibrationError catch (e) {
      setState(() {
        _state = _CalibrationState.error;
        _errorMessage = e.code == 'PICKUP_STILL_CONNECTED'
            ? null // handled specially in build()
            : e.message;
      });
    } catch (e) {
      setState(() {
        _state = _CalibrationState.error;
        _errorMessage = e.toString();
      });
    } finally {
      service.sweepProgress.removeListener(_onSweepProgress);
    }
  }

  void _onSweepProgress() {
    if (!mounted) return;
    setState(() => _sweepPass = ref.read(calibrationProvider).sweepProgress.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final existing = ref.watch(calibrationProvider).activeCalibration;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: switch (_state) {
        _CalibrationState.idle => _buildIdle(l10n, existing?.timestamp),
        _CalibrationState.running => _buildRunning(l10n),
        _CalibrationState.success => _buildSuccess(l10n),
        _CalibrationState.error => _buildError(l10n),
      },
    );
  }

  Widget _buildIdle(AppLocalizations l10n, DateTime? lastCalTime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.calibrationResistorPrompt,
            style: const TextStyle(fontSize: 16)),
        if (lastCalTime != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last calibrated: ${DateFormat('dd MMM yyyy HH:mm').format(lastCalTime.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.tune),
          label: Text(l10n.calibrateButton),
          onPressed: _runCalibration,
        ),
      ],
    );
  }

  Widget _buildRunning(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.calibrationSweeping(_sweepPass + 1, _sweepTotal),
            style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 24),
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.cancel_outlined),
          label: Text(l10n.cancel),
          onPressed: () => setState(() => _state = _CalibrationState.idle),
        ),
      ],
    );
  }

  Widget _buildSuccess(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 32),
          const SizedBox(width: 12),
          Text(l10n.calibrationComplete,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        if (_successTimestamp != null) ...[
          const SizedBox(height: 8),
          Text('Calibrated at $_successTimestamp',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => setState(() => _state = _CalibrationState.idle),
          child: Text(l10n.recalibrate),
        ),
      ],
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    final isPickupConnected = _errorMessage == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.error_outline, color: Colors.orange, size: 32),
          const SizedBox(width: 12),
          Text(l10n.calibrationFailed,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        Text(
          isPickupConnected
              ? l10n.calibrationPickupStillConnected
              : (_errorMessage ?? 'Unknown error'),
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        if (!isPickupConnected)
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l10n.measureRetry),
            onPressed: _runCalibration,
          ),
        if (isPickupConnected)
          OutlinedButton(
            onPressed: () => setState(() => _state = _CalibrationState.idle),
            child: Text(l10n.calibrationTryAgain),
          ),
      ],
    );
  }
}
