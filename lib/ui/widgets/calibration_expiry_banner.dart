// lib/ui/widgets/calibration_expiry_banner.dart
// Banner displayed on the Measure screen when calibration has expired.
// Provides a one-tap shortcut to recalibrate.

import 'package:flutter/material.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';

class CalibrationExpiryBanner extends StatelessWidget {
  final VoidCallback onRecalibrate;

  const CalibrationExpiryBanner({super.key, required this.onRecalibrate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MaterialBanner(
      content: Text(l10n.calibrationExpiredWarning),
      backgroundColor: Colors.orange.shade900,
      actions: [
        TextButton(
          onPressed: onRecalibrate,
          child: Text(l10n.recalibrate,
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
