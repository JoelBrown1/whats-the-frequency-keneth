// lib/ui/screens/results_screen.dart
// Results screen: shown after Complete state.
// Shows: FrequencyResponseChart, ResonanceSummaryCard.
// Actions: Save, Discard, Overlay, Export CSV.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/ui/widgets/frequency_response_chart.dart';
import 'package:whats_the_frequency/ui/widgets/resonance_summary_card.dart';

class ResultsScreen extends ConsumerWidget {
  final FrequencyResponse? frequencyResponse;

  const ResultsScreen({super.key, this.frequencyResponse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final response = frequencyResponse;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Confirm discard on back navigation.
            _confirmDiscard(context);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FrequencyResponseChart(frequencyResponse: response),
          ),
          if (response != null)
            ResonanceSummaryCard(
              resonanceHz: response.primaryPeak.frequencyHz,
              qFactor: response.primaryPeak.qFactor,
              timestamp: response.analyzedAt,
            ),
          _ActionBar(response: response),
        ],
      ),
    );
  }

  void _confirmDiscard(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard result?'),
        content: const Text(
            'This measurement will not be saved. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              Navigator.of(context).pop();
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final FrequencyResponse? response;

  const _ActionBar({required this.response});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            onPressed: response != null
                ? () {
                    // Save flow — implemented in Phase 4.
                  }
                : null,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.layers),
            label: const Text('Overlay'),
            onPressed: response != null
                ? () {
                    // Overlay flow — implemented in Phase 4.
                  }
                : null,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload),
            label: const Text('Export'),
            onPressed: response != null
                ? () {
                    // CSV export — implemented in Phase 4.
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
