// lib/ui/screens/onboarding_screen.dart
// Linear first-launch onboarding flow.
// Steps: Welcome, Hardware, Device, Mains, Level, Calibration.
// Resumes mid-flow using lastCompletedOnboardingStep from DeviceConfig.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:whats_the_frequency/l10n/l10n.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/available_devices_provider.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/level_meter_provider.dart';
import 'package:whats_the_frequency/providers/sweep_config_provider.dart';
import 'package:whats_the_frequency/ui/screens/onboarding_step.dart';
import 'package:whats_the_frequency/ui/widgets/calibration_flow_widget.dart';
import 'package:whats_the_frequency/ui/widgets/device_picker.dart';
import 'package:whats_the_frequency/ui/widgets/level_meter.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingStep _currentStep = OnboardingStep.welcome;
  bool _levelConfirmed = false;
  bool _calibrationDone = false;
  bool _stepRestored = false;

  Future<void> _advance() async {
    final notifier = ref.read(deviceConfigProvider.notifier);
    if (_currentStep == OnboardingStep.calibration) {
      await notifier.completeOnboarding();
      if (mounted) context.go('/home');
      return;
    }
    final nextStep = OnboardingStep.values[_currentStep.index + 1];
    await notifier.setOnboardingStep(nextStep);
    setState(() {
      _currentStep = nextStep;
      _levelConfirmed = false;
    });
  }

  bool _canAdvance() {
    return switch (_currentStep) {
      OnboardingStep.level => _levelConfirmed,
      OnboardingStep.calibration => _calibrationDone ||
          ref.read(calibrationProvider).isCalibrationValid(),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Restore the persisted step once when deviceConfigProvider first loads.
    ref.listen<AsyncValue<DeviceConfig>>(deviceConfigProvider, (_, next) {
      if (!_stepRestored && next.hasValue && mounted) {
        _stepRestored = true;
        final step = next.value!.lastCompletedOnboardingStep;
        if (step > 0) {
          setState(() {
            _currentStep = OnboardingStep.fromIndex(
              step.clamp(0, OnboardingStep.values.length - 1),
            );
          });
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(_stepTitle(l10n))),
      body: _buildStep(l10n),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentStep != OnboardingStep.welcome)
              TextButton(
                onPressed: () async {
                  final prevStep = OnboardingStep.values[_currentStep.index - 1];
                  await ref
                      .read(deviceConfigProvider.notifier)
                      .setOnboardingStep(prevStep);
                  setState(() => _currentStep = prevStep);
                },
                child: Text(l10n.back),
              )
            else
              const SizedBox.shrink(),
            ElevatedButton(
              onPressed: _canAdvance() ? _advance : null,
              child: Text(_currentStep == OnboardingStep.calibration
                  ? l10n.startMeasuring
                  : l10n.next),
            ),
          ],
        ),
      ),
    );
  }

  String _stepTitle(AppLocalizations l10n) => switch (_currentStep) {
        OnboardingStep.welcome => l10n.onboardingWelcomeTitle,
        OnboardingStep.hardware => l10n.onboardingHardwareTitle,
        OnboardingStep.device => l10n.onboardingDeviceTitle,
        OnboardingStep.mains => l10n.onboardingMainsTitle,
        OnboardingStep.level => l10n.onboardingLevelTitle,
        OnboardingStep.calibration => l10n.onboardingCalibrationTitle,
      };

  Widget _buildStep(AppLocalizations l10n) => switch (_currentStep) {
        OnboardingStep.welcome => _WelcomeStep(l10n: l10n),
        OnboardingStep.hardware => const _HardwareChecklistStep(),
        OnboardingStep.device => const _DeviceSelectionStep(),
        OnboardingStep.mains => const _MainsFrequencyStep(),
        OnboardingStep.level => _LevelCheckStep(
            onConfirmed: (v) => setState(() => _levelConfirmed = v),
          ),
        OnboardingStep.calibration => _ChainCalibrationStep(
            onSuccess: () => setState(() => _calibrationDone = true),
          ),
      };
}

// ─── Step widgets ─────────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  final AppLocalizations l10n;
  const _WelcomeStep({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.onboardingWelcomeTitle,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(l10n.onboardingWelcomeSubtitle,
              style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _HardwareChecklistStep extends StatefulWidget {
  const _HardwareChecklistStep();

  @override
  State<_HardwareChecklistStep> createState() => _HardwareChecklistStepState();
}

class _HardwareChecklistStepState extends State<_HardwareChecklistStep> {
  final Map<String, bool> _items = {
    'Air mode: OFF (both channels)': false,
    'Direct monitoring: DISABLED': false,
    'OS audio enhancements: DISABLED': false,
    'Headphone knob: set via level check': false,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _items.entries.map((entry) {
        return CheckboxListTile(
          title: Text(entry.key),
          value: entry.value,
          onChanged: (v) => setState(() => _items[entry.key] = v ?? false),
        );
      }).toList(),
    );
  }
}

class _DeviceSelectionStep extends ConsumerWidget {
  const _DeviceSelectionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(availableDevicesProvider);
    final config = ref.watch(deviceConfigProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select your audio interface from the list below.',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          devicesAsync.when(
            data: (devices) => DevicePicker(
              devices: devices,
              selectedUid: config?.deviceUid,
              onChanged: (uid) async {
                if (uid == null) return;
                final device = devices.firstWhere((d) => d.uid == uid);
                await ref
                    .read(audioEnginePlatformProvider)
                    .setDevice(uid);
                await ref.read(deviceConfigProvider.notifier).setDevice(
                    uid, device.name, device.nativeSampleRate.toInt());
              },
            ),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Error loading devices: $e',
                style: const TextStyle(color: Colors.red)),
          ),
          if (config != null && config.deviceUid.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Selected: ${config.deviceName}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _MainsFrequencyStep extends ConsumerStatefulWidget {
  const _MainsFrequencyStep();

  @override
  ConsumerState<_MainsFrequencyStep> createState() =>
      _MainsFrequencyStepState();
}

class _MainsFrequencyStepState extends ConsumerState<_MainsFrequencyStep> {
  bool _measuring = false;
  String? _result;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    setState(() { _measuring = true; _result = null; });
    try {
      final hz = await ref
          .read(calibrationProvider)
          .measureMainsFrequency(ref.read(sweepConfigProvider));
      await ref.read(deviceConfigProvider.notifier).setMainsHz(hz);
      setState(() => _result = '${hz.toStringAsFixed(1)} Hz detected');
    } catch (e) {
      setState(() => _result = 'Could not detect — using default');
    } finally {
      setState(() => _measuring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(deviceConfigProvider).valueOrNull;
    final current = config?.measuredMainsHz ?? 50.0;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Measure your local mains frequency for accurate hum suppression.',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          Row(children: [
            _FreqChip(
                label: '50 Hz',
                selected: current == 50.0,
                onTap: () async => ref
                    .read(deviceConfigProvider.notifier)
                    .setMainsHz(50.0)),
            const SizedBox(width: 8),
            _FreqChip(
                label: '60 Hz',
                selected: current == 60.0,
                onTap: () async => ref
                    .read(deviceConfigProvider.notifier)
                    .setMainsHz(60.0)),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _measuring
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.graphic_eq),
            label: Text(_measuring ? 'Measuring…' : 'Auto-detect'),
            onPressed: _measuring ? null : _measure,
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(_result!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text('Current: ${current.toStringAsFixed(1)} Hz',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FreqChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FreqChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _LevelCheckStep extends ConsumerWidget {
  final ValueChanged<bool> onConfirmed;
  const _LevelCheckStep({required this.onConfirmed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final levelAsync = ref.watch(levelCheckToneProvider);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.levelCheckTarget, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          levelAsync.when(
            data: (dbfs) => LevelMeter(dbfs: dbfs),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Level meter error: $e',
                style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            title: const Text('Level is correct (−12 dBFS)'),
            value: false,
            onChanged: (v) => onConfirmed(v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }
}

class _ChainCalibrationStep extends StatelessWidget {
  final VoidCallback? onSuccess;
  const _ChainCalibrationStep({this.onSuccess});

  @override
  Widget build(BuildContext context) {
    return CalibrationFlowWidget(onSuccess: onSuccess);
  }
}
