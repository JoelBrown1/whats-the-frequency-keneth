// lib/ui/widgets/resonance_summary_card.dart
// Shows resonance Hz (formatted as "X.X kHz" or "XXX Hz"), Q-factor, timestamp.

import 'package:flutter/material.dart';

class ResonanceSummaryCard extends StatelessWidget {
  final double resonanceHz;
  final double qFactor;
  final DateTime timestamp;
  final String? pickupLabel;

  const ResonanceSummaryCard({
    super.key,
    required this.resonanceHz,
    required this.qFactor,
    required this.timestamp,
    this.pickupLabel,
  });

  String get _formattedFreq {
    if (resonanceHz >= 1000) {
      return '${(resonanceHz / 1000).toStringAsFixed(1)} kHz';
    }
    return '${resonanceHz.toStringAsFixed(0)} Hz';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pickupLabel != null && pickupLabel!.isNotEmpty) ...[
              Text(pickupLabel!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
            ],
            Text(
              _formattedFreq,
              style: const TextStyle(
                  fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Q = ${qFactor.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              timestamp.toLocal().toString().substring(0, 16),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
