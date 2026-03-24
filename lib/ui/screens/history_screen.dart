// lib/ui/screens/history_screen.dart
// History screen: flat list and by-pickup grouping toggle.
// Also used in selectionMode to pick a measurement for overlay comparison.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/data/models/measurement_summary.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/measurement_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  /// When true, tapping a measurement pops with its FrequencyResponse
  /// instead of navigating to a detail view.
  final bool selectionMode;

  const HistoryScreen({super.key, this.selectionMode = false});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _groupByPickup = false;
  List<MeasurementSummary> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    final repo = ref.read(measurementRepositoryProvider);
    final summaries = await repo.loadSummaries();
    if (mounted) {
      setState(() {
        _summaries = summaries;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSummary(MeasurementSummary summary) async {
    if (!widget.selectionMode) return;
    final repo = ref.read(measurementRepositoryProvider);
    final measurement = await repo.loadFull(summary.id);
    if (mounted) {
      Navigator.of(context).pop<FrequencyResponse>(
          measurement.toFrequencyResponse());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode
            ? AppLocalizations.of(context)!.historySelectMeasurement
            : AppLocalizations.of(context)!.historyTitle),
        actions: [
          if (!widget.selectionMode)
            Row(
              children: [
                Text(AppLocalizations.of(context)!.historyGroupByPickup),
                Switch(
                  value: _groupByPickup,
                  onChanged: (v) => setState(() => _groupByPickup = v),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
          ? Center(
              child: Text(
                AppLocalizations.of(context)!.historyEmptyState,
                textAlign: TextAlign.center,
              ),
            )
          : _groupByPickup
              ? _GroupedList(
                  summaries: _summaries,
                  onTap: widget.selectionMode ? _selectSummary : null,
                )
              : _FlatList(
                  summaries: _summaries,
                  onTap: widget.selectionMode ? _selectSummary : null,
                ),
    );
  }
}

class _FlatList extends StatelessWidget {
  final List<MeasurementSummary> summaries;
  final void Function(MeasurementSummary)? onTap;

  const _FlatList({required this.summaries, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: summaries.length,
      itemBuilder: (ctx, i) {
        final s = summaries[i];
        return ListTile(
          title: Text(s.pickupLabel.isEmpty
              ? AppLocalizations.of(ctx)!.historyUnnamedPickup
              : s.pickupLabel),
          subtitle: Text(
              '${s.resonanceFrequencyHz.toStringAsFixed(0)} Hz · Q=${s.qFactor.toStringAsFixed(1)}'),
          trailing: Text(s.timestamp.toLocal().toString().substring(0, 16)),
          onTap: onTap != null ? () => onTap!(s) : null,
        );
      },
    );
  }
}

class _GroupedList extends StatelessWidget {
  final List<MeasurementSummary> summaries;
  final void Function(MeasurementSummary)? onTap;

  const _GroupedList({required this.summaries, this.onTap});

  @override
  Widget build(BuildContext context) {
    final groups = <String?, List<MeasurementSummary>>{};
    for (final s in summaries) {
      groups.putIfAbsent(s.pickupId, () => []).add(s);
    }

    return ListView(
      children: groups.entries.map((entry) {
        final items = entry.value;
        final l10n = AppLocalizations.of(context)!;
        final label = items.first.pickupLabel.isEmpty
            ? l10n.historyUnnamedPickup
            : items.first.pickupLabel;
        return ExpansionTile(
          title: Text(label),
          subtitle: Text('${items.length} measurement(s)'),
          children: items.map((s) {
            return ListTile(
              title: Text(
                  '${s.resonanceFrequencyHz.toStringAsFixed(0)} Hz · Q=${s.qFactor.toStringAsFixed(1)}'),
              subtitle:
                  Text(s.timestamp.toLocal().toString().substring(0, 16)),
              onTap: onTap != null ? () => onTap!(s) : null,
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
