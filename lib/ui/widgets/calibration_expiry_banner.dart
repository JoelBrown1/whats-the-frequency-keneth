// lib/ui/widgets/calibration_expiry_banner.dart
// Banner displayed on the Measure screen when calibration has expired.
// Provides a one-tap shortcut to recalibrate.

import 'package:flutter/material.dart';

class CalibrationExpiryBanner extends StatelessWidget {
  final VoidCallback onRecalibrate;

  const CalibrationExpiryBanner({super.key, required this.onRecalibrate});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: const Text('Calibration has expired. Tap to recalibrate.'),
      backgroundColor: Colors.orange.shade900,
      actions: [
        TextButton(
          onPressed: onRecalibrate,
          child: const Text('Recalibrate',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
