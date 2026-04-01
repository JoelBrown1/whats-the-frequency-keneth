// lib/ui/screens/import_csv_screen.dart
// Full-page import flow: pick a CSV file, preview the detected resonance,
// assign a pickup label, then save to MeasurementRepository.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/csv_importer.dart';
import 'package:whats_the_frequency/data/measurement_migrator.dart';
import 'package:whats_the_frequency/data/models/measurement.dart';
import 'package:whats_the_frequency/data/models/pickup.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/measurement_provider.dart';
import 'package:whats_the_frequency/providers/pickup_provider.dart';

class ImportCsvScreen extends ConsumerStatefulWidget {
  const ImportCsvScreen({super.key});

  @override
  ConsumerState<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

enum _Stage { idle, parsing, previewing, saving }

class _ImportCsvScreenState extends ConsumerState<ImportCsvScreen> {
  _Stage _stage = _Stage.idle;
  CsvImportResult? _result;
  String _filename = '';
  String? _parseError;

  final _labelController = TextEditingController();
  String? _selectedPickupId;
  bool _newPickup = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
    } catch (_) {
      // Picker cancelled or unavailable.
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() {
      _stage = _Stage.parsing;
      _parseError = null;
      _filename = file.name;
    });

    try {
      final content = utf8.decode(bytes);
      final result = await Future.microtask(
        () => CsvImporter().parse(content),
      );

      // Pre-populate label from filename (strip extension and wtfk_ prefix).
      var label = file.name.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
      if (label.startsWith('wtfk_')) label = label.substring(5);

      setState(() {
        _result = result;
        _labelController.text = label;
        _stage = _Stage.previewing;
      });
    } on CsvParseException catch (e) {
      setState(() {
        _parseError = e.message;
        _stage = _Stage.idle;
      });
    } catch (e) {
      setState(() {
        _parseError = 'Unexpected error: $e';
        _stage = _Stage.idle;
      });
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null) return;

    final label = _labelController.text.trim();
    if (label.isEmpty) return;

    setState(() => _stage = _Stage.saving);

    final id = const Uuid().v4();
    final now = DateTime.now();

    final pickupId = _newPickup ? const Uuid().v4() : _selectedPickupId;

    final measurement = Measurement(
      schemaVersion: MeasurementMigrator.currentSchemaVersion,
      id: id,
      timestamp: now,
      pickupLabel: label,
      pickupId: pickupId,
      sweepConfig: const SweepConfig(),
      resonanceSearchBand: const ResonanceSearchBand(),
      magnitudeDB: result.magnitudeDB,
      resonanceFrequencyHz: result.resonanceFrequencyHz,
      qFactor: result.qFactor,
      hardware: MeasurementHardware(
        interfaceDeviceName: 'Imported',
        interfaceUID: 'imported',
        calibrationId: 'imported',
        calibrationTimestamp: DateTime.fromMillisecondsSinceEpoch(0),
        appVersion: 'imported',
      ),
    );

    final measurementRepo = ref.read(measurementRepositoryProvider);
    await measurementRepo.save(measurement);

    if (pickupId != null) {
      final pickupRepo = ref.read(pickupRepositoryProvider);
      final existing = await pickupRepo.loadById(pickupId);
      if (existing != null) {
        await pickupRepo.save(existing.copyWith(
          measurementIds: [...existing.measurementIds, id],
        ));
      } else {
        await pickupRepo.save(Pickup(
          id: pickupId,
          name: label,
          createdAt: now,
          measurementIds: [id],
        ));
      }
      ref.invalidate(pickupListProvider);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importCsvTitle)),
      body: switch (_stage) {
        _Stage.parsing || _Stage.saving => const Center(
            child: CircularProgressIndicator(),
          ),
        _Stage.previewing => _PreviewForm(
            result: _result!,
            filename: _filename,
            labelController: _labelController,
            selectedPickupId: _selectedPickupId,
            newPickup: _newPickup,
            onPickupChanged: (id) => setState(() {
              _selectedPickupId = id;
              _newPickup = false;
              if (id != null) {
                final pickupsAsync = ref.read(pickupListProvider);
                final pickups = pickupsAsync.valueOrNull ?? [];
                final p = pickups.where((p) => p.id == id).firstOrNull;
                if (p != null && _labelController.text.isEmpty) {
                  _labelController.text = p.name;
                }
              }
            }),
            onNewPickupChanged: (v) => setState(() {
              _newPickup = v;
              if (v) _selectedPickupId = null;
            }),
            onSelectDifferentFile: _pickFile,
            onSave: _save,
          ),
        _Stage.idle => _IdleBody(
            error: _parseError,
            onSelectFile: _pickFile,
          ),
      },
    );
  }
}

class _IdleBody extends StatelessWidget {
  final String? error;
  final VoidCallback onSelectFile;

  const _IdleBody({this.error, required this.onSelectFile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.importCsvHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onSelectFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.importCsvSelectFile),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewForm extends ConsumerWidget {
  final CsvImportResult result;
  final String filename;
  final TextEditingController labelController;
  final String? selectedPickupId;
  final bool newPickup;
  final void Function(String?) onPickupChanged;
  final void Function(bool) onNewPickupChanged;
  final VoidCallback onSelectDifferentFile;
  final VoidCallback onSave;

  const _PreviewForm({
    required this.result,
    required this.filename,
    required this.labelController,
    required this.selectedPickupId,
    required this.newPickup,
    required this.onPickupChanged,
    required this.onNewPickupChanged,
    required this.onSelectDifferentFile,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pickupsAsync = ref.watch(pickupListProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Detected resonance card.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.importCsvDetectedResonance,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    filename,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: l10n.importCsvFrequency,
                          value:
                              '${result.resonanceFrequencyHz.toStringAsFixed(0)} Hz',
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          label: l10n.importCsvQFactor,
                          value: result.qFactor.isFinite
                              ? 'Q=${result.qFactor.toStringAsFixed(2)}'
                              : 'Q=∞',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Pickup label.
          TextField(
            controller: labelController,
            decoration: InputDecoration(
              labelText: l10n.pickupLabelField,
              hintText: l10n.pickupLabelHint,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Existing pickup dropdown.
          pickupsAsync.when(
            data: (pickups) {
              if (pickups.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.linkExistingPickup),
                  const SizedBox(height: 8),
                  DropdownButton<String?>(
                    value: selectedPickupId,
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
                    onChanged: onPickupChanged,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: Text(l10n.createNewPickup),
                    value: newPickup,
                    onChanged: (v) => onNewPickupChanged(v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: onSelectDifferentFile,
                child: Text(l10n.importCsvSelectFile),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onSave,
                child: Text(l10n.measureSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}
