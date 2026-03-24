// lib/ui/screens/calibration_screen.dart
// Calibration screen — prompts user to attach 10 kΩ resistor and runs
// chain calibration. Navigates back with true on success.

import 'package:flutter/material.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/ui/widgets/calibration_flow_widget.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calibrationTitle)),
      body: CalibrationFlowWidget(
        onSuccess: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        },
      ),
    );
  }
}
