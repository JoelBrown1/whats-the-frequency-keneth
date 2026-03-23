// lib/ui/screens/history_screen.dart
// History screen: flat list and by-pickup grouping toggle.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/data/models/measurement_summary.dart';
import 'package:whats_the_frequency/providers/measurement_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _groupByPickup = false;
  List<MeasurementSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    final repo = ref.read(measurementRepositoryProvider);
    final summaries = await repo.loadSummaries();
    setState(() => _summaries = summaries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          Row(
            children: [
              const Text('By pickup'),
              Switch(
                value: _groupByPickup,
                onChanged: (v) => setState(() => _groupByPickup = v),
              ),
            ],
          ),
        ],
      ),
      body: _summaries.isEmpty
          ? const Center(
              child: Text(
                'No measurements yet. Complete a measurement to see results here.',
                textAlign: TextAlign.center,
              ),
            )
          : _groupByPickup
              ? _GroupedList(summaries: _summaries)
              : _FlatList(summaries: _summaries),
    );
  }
}

class _FlatList extends StatelessWidget {
  final List<MeasurementSummary> summaries;

  const _FlatList({required this.summaries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: summaries.length,
      itemBuilder: (ctx, i) {
        final s = summaries[i];
        return ListTile(
          title: Text(s.pickupLabel.isEmpty ? 'Unnamed pickup' : s.pickupLabel),
          subtitle: Text('${s.resonanceFrequencyHz.toStringAsFixed(0)} Hz · Q=${s.qFactor.toStringAsFixed(1)}'),
          trailing: Text(s.timestamp.toLocal().toString().substring(0, 16)),
          onTap: () {
            // Open full measurement — implemented in Phase 4.
          },
        );
      },
    );
  }
}

class _GroupedList extends StatelessWidget {
  final List<MeasurementSummary> summaries;

  const _GroupedList({required this.summaries});

  @override
  Widget build(BuildContext context) {
    // Group by pickupId.
    final groups = <String?, List<MeasurementSummary>>{};
    for (final s in summaries) {
      groups.putIfAbsent(s.pickupId, () => []).add(s);
    }

    return ListView(
      children: groups.entries.map((entry) {
        final items = entry.value;
        final label = items.first.pickupLabel.isEmpty
            ? 'Unnamed pickup'
            : items.first.pickupLabel;
        return ExpansionTile(
          title: Text(label),
          subtitle: Text('${items.length} measurement(s)'),
          children: items.map((s) {
            return ListTile(
              title: Text(
                  '${s.resonanceFrequencyHz.toStringAsFixed(0)} Hz · Q=${s.qFactor.toStringAsFixed(1)}'),
              subtitle: Text(s.timestamp.toLocal().toString().substring(0, 16)),
              onTap: () {
                // Open full measurement — implemented in Phase 4.
              },
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
