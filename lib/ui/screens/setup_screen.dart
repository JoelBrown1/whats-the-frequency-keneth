// lib/ui/screens/setup_screen.dart
// Setup screen: device picker, hardware checklist, live level check.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/available_devices_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/level_meter_provider.dart';
import 'package:whats_the_frequency/ui/widgets/device_picker.dart';
import 'package:whats_the_frequency/ui/widgets/level_meter.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _levelMeterActive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final devicesAsync = ref.watch(availableDevicesProvider);
    final config = ref.watch(deviceConfigProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Audio Interface ──────────────────────────────────────────────
          Text(l10n.setupAudioInterfaceSection,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          devicesAsync.when(
            data: (devices) => DevicePicker(
              devices: devices,
              selectedUid: config?.deviceUid,
              onChanged: (uid) async {
                if (uid == null) return;
                final device = devices.firstWhere((d) => d.uid == uid);
                await ref.read(audioEnginePlatformProvider).setDevice(uid);
                await ref.read(deviceConfigProvider.notifier).setDevice(
                    uid, device.name, device.nativeSampleRate.toInt());
              },
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(l10n.noDevicesFound,
                style: const TextStyle(color: Colors.orange)),
          ),
          const Divider(height: 32),

          // ── Hardware Checklist ───────────────────────────────────────────
          Text(l10n.onboardingHardwareTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _ChecklistItem(label: 'Air mode: OFF (both channels)'),
          _ChecklistItem(label: 'Direct monitoring: DISABLED'),
          _ChecklistItem(label: 'OS audio enhancements: DISABLED'),
          const Divider(height: 32),

          // ── Level Check ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.onboardingLevelTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Switch(
                value: _levelMeterActive,
                onChanged: (v) => setState(() => _levelMeterActive = v),
              ),
            ],
          ),
          if (_levelMeterActive) ...[
            const SizedBox(height: 8),
            Text(l10n.levelCheckTarget,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            _LiveLevelMeter(),
          ],
        ],
      ),
    );
  }
}

class _LiveLevelMeter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelAsync = ref.watch(levelCheckToneProvider);
    return levelAsync.when(
      data: (dbfs) => LevelMeter(dbfs: dbfs),
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('Level meter error: $e',
          style: const TextStyle(color: Colors.red)),
    );
  }
}

class _ChecklistItem extends StatefulWidget {
  final String label;
  const _ChecklistItem({required this.label});

  @override
  State<_ChecklistItem> createState() => _ChecklistItemState();
}

class _ChecklistItemState extends State<_ChecklistItem> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      title: Text(widget.label),
      value: _checked,
      onChanged: (v) => setState(() => _checked = v ?? false),
    );
  }
}
