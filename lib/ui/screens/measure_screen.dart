// lib/ui/screens/measure_screen.dart
// Measurement screen. Blocked if no valid calibration exists.
// Shows CalibrationExpiryBanner if calibration has expired.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/ui/widgets/calibration_expiry_banner.dart';

class MeasureScreen extends ConsumerWidget {
  const MeasureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calibrationService = ref.watch(calibrationProvider);
    final hasValidCalibration = calibrationService.isCalibrationValid();
    final isExpired = calibrationService.activeCalibration != null &&
        !calibrationService.isCalibrationValid();

    return Scaffold(
      appBar: AppBar(title: const Text('Measure')),
      body: Column(
        children: [
          if (isExpired)
            CalibrationExpiryBanner(
              onRecalibrate: () =>
                  Navigator.of(context).pushNamed('/calibration'),
            ),
          Expanded(
            child: hasValidCalibration
                ? _MeasureContent()
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.block, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'No valid calibration.\nPlease calibrate before measuring.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pushNamed('/calibration'),
            child: const Text('Calibrate Now'),
          ),
        ],
      ),
    );
  }
}

class _MeasureContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.mic),
        label: const Text('Start Measurement'),
        onPressed: () {
          // Measurement flow — implemented in Phase 3.
        },
      ),
    );
  }
}
