// lib/ui/screens/results_screen.dart
// Results screen: shown after a completed measurement.
// Actions: Save (to MeasurementRepository + optional Pickup), Discard,
//          Overlay (load prior measurement from history), Export CSV.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:whats_the_frequency/data/csv_exporter.dart';
import 'package:whats_the_frequency/data/models/measurement.dart';
import 'package:whats_the_frequency/data/models/pickup.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/measurement_provider.dart';
import 'package:whats_the_frequency/providers/pickup_provider.dart';
import 'package:whats_the_frequency/providers/sweep_config_provider.dart';
import 'package:whats_the_frequency/ui/screens/history_screen.dart';
import 'package:whats_the_frequency/ui/widgets/frequency_response_chart.dart';
import 'package:whats_the_frequency/ui/widgets/resonance_summary_card.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  final FrequencyResponse? frequencyResponse;

  const ResultsScreen({super.key, this.frequencyResponse});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  FrequencyResponse? _overlayResponse;
  String? _overlayLabel;

  @override
  Widget build(BuildContext context) {
    final response = widget.frequencyResponse;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.resultsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _confirmDiscard(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FrequencyResponseChart(
              frequencyResponse: response,
              overlayResponse: _overlayResponse,
              overlayLabel: _overlayLabel,
              searchBand: ref.read(deviceConfigProvider).valueOrNull?.resonanceSearchBand,
            ),
          ),
          if (response != null)
            ResonanceSummaryCard(
              resonanceHz: response.primaryPeak.frequencyHz,
              qFactor: response.primaryPeak.qFactor,
              timestamp: response.analyzedAt,
            ),
          _ActionBar(
            response: response,
            hasOverlay: _overlayResponse != null,
            onSave: response != null ? () => _save(context, response) : null,
            onDiscard: () => Navigator.of(context).pop(),
            onOverlay: response != null ? () => _pickOverlay(context) : null,
            onClearOverlay: _overlayResponse != null
                ? () => setState(() {
                      _overlayResponse = null;
                      _overlayLabel = null;
                    })
                : null,
            onExport: response != null ? () => _export(context, response) : null,
          ),
        ],
      ),
    );
  }

  void _confirmDiscard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.discardResultTitle),
        content: Text(l10n.discardResultContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              Navigator.of(context).pop();
            },
            child: Text(l10n.measureDiscard),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, FrequencyResponse response) async {
    final navigator = Navigator.of(context);
    final result = await showDialog<_SaveDialogResult>(
      context: context,
      builder: (ctx) => const _SaveDialog(),
    );
    if (result == null || !mounted) return;

    final deviceConfig = ref.read(deviceConfigProvider).valueOrNull;
    final calibration = ref.read(calibrationProvider).activeCalibration;
    final sweepConfig = ref.read(sweepConfigProvider);
    final packageInfo = await PackageInfo.fromPlatform();

    final id = const Uuid().v4();
    final measurement = Measurement(
      schemaVersion: 1,
      id: id,
      timestamp: response.analyzedAt,
      pickupLabel: result.pickupLabel,
      pickupId: result.pickupId,
      sweepConfig: sweepConfig,
      resonanceSearchBand: const ResonanceSearchBand(),
      magnitudeDB: List<double>.from(response.magnitudeDb),
      resonanceFrequencyHz: response.primaryPeak.frequencyHz,
      qFactor: response.primaryPeak.qFactor,
      hardware: MeasurementHardware(
        interfaceDeviceName: deviceConfig?.deviceName ?? '',
        interfaceUID: deviceConfig?.deviceUid ?? '',
        calibrationId: calibration?.id ?? '',
        calibrationTimestamp:
            calibration?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
        appVersion: packageInfo.version,
      ),
    );

    final measurementRepo = ref.read(measurementRepositoryProvider);
    await measurementRepo.save(measurement);

    // Link to Pickup if one was selected or created.
    if (result.pickupId != null) {
      final pickupRepo = ref.read(pickupRepositoryProvider);
      Pickup? existing = await pickupRepo.loadById(result.pickupId!);
      if (existing != null) {
        await pickupRepo.save(existing.copyWith(
          measurementIds: [...existing.measurementIds, id],
        ));
      } else {
        // New pickup.
        await pickupRepo.save(Pickup(
          id: result.pickupId!,
          name: result.pickupLabel,
          createdAt: DateTime.now(),
          measurementIds: [id],
        ));
      }
      ref.invalidate(pickupListProvider);
    }

    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil('/home', (_) => false);
  }

  Future<void> _export(
      BuildContext context, FrequencyResponse response) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = _overlayLabel ?? 'pickup';
    final csv = CsvExporter().export(response, label);

    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }

    final freqStr =
        response.primaryPeak.frequencyHz.toStringAsFixed(0);
    final qStr = response.primaryPeak.qFactor.toStringAsFixed(1);
    final dateStr = response.analyzedAt
        .toLocal()
        .toIso8601String()
        .substring(0, 10);
    final filename = 'wtfk_${freqStr}Hz_Q${qStr}_$dateStr.csv';
    final file = File('${dir!.path}/$filename');
    await file.writeAsString(csv);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Exported to ${file.path}')),
    );
  }

  Future<void> _pickOverlay(BuildContext context) async {
    final result = await Navigator.of(context).push<FrequencyResponse>(
      MaterialPageRoute(
        builder: (_) => const HistoryScreen(selectionMode: true),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _overlayResponse = result;
      _overlayLabel = '${result.primaryPeak.frequencyHz.toStringAsFixed(0)} Hz overlay';
    });
    final primary = widget.frequencyResponse;
    if (primary != null && result.sweepConfig != primary.sweepConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.sweepConfigMismatchWarning),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

// ignore: must_be_immutable
class _ActionBar extends StatelessWidget {
  final FrequencyResponse? response;
  final bool hasOverlay;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final VoidCallback? onOverlay;
  final VoidCallback? onClearOverlay;
  final VoidCallback? onExport;

  const _ActionBar({
    required this.response,
    required this.hasOverlay,
    this.onSave,
    this.onDiscard,
    this.onOverlay,
    this.onClearOverlay,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text(l10n.measureSave),
            onPressed: onSave,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.measureDiscard),
            onPressed: onDiscard,
          ),
          OutlinedButton.icon(
            icon: Icon(hasOverlay ? Icons.layers_clear : Icons.layers),
            label: Text(hasOverlay
                ? l10n.overlayMeasurementClear
                : l10n.overlayMeasurement),
            onPressed: hasOverlay ? onClearOverlay : onOverlay,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload),
            label: Text(l10n.measureExport),
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

class _SaveDialogResult {
  final String pickupLabel;
  final String? pickupId;

  const _SaveDialogResult({required this.pickupLabel, this.pickupId});
}

class _SaveDialog extends ConsumerStatefulWidget {
  const _SaveDialog();

  @override
  ConsumerState<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends ConsumerState<_SaveDialog> {
  final _labelController = TextEditingController();
  String? _selectedPickupId;
  bool _newPickup = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickupsAsync = ref.watch(pickupListProvider);

    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.saveMeasurementTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: l10n.pickupLabelField,
                hintText: l10n.pickupLabelHint,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            pickupsAsync.when(
              data: (pickups) {
                if (pickups.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.linkExistingPickup),
                    const SizedBox(height: 8),
                    DropdownButton<String?>(
                      value: _selectedPickupId,
                      isExpanded: true,
                      hint: Text(l10n.noneOption),
                      items: [
                        DropdownMenuItem(
                            value: null, child: Text(l10n.noneOption)),
                        ...pickups.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            )),
                      ],
                      onChanged: (v) => setState(() {
                        _selectedPickupId = v;
                        _newPickup = false;
                        if (v != null) {
                          final p = pickups.firstWhere((p) => p.id == v);
                          if (_labelController.text.isEmpty) {
                            _labelController.text = p.name;
                          }
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: Text(l10n.createNewPickup),
                      value: _newPickup,
                      onChanged: (v) => setState(() {
                        _newPickup = v ?? false;
                        if (_newPickup) _selectedPickupId = null;
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final label = _labelController.text.trim();
            if (label.isEmpty) return;
            final pickupId = _newPickup
                ? const Uuid().v4()
                : _selectedPickupId;
            Navigator.of(context).pop(
                _SaveDialogResult(pickupLabel: label, pickupId: pickupId));
          },
          child: Text(l10n.measureSave),
        ),
      ],
    );
  }
}
