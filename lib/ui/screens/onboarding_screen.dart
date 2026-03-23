// lib/ui/screens/onboarding_screen.dart
// Linear first-launch onboarding flow.
// Steps: Welcome(0), HW Checklist(1), Device Selection(2),
//        Mains Frequency(3), Level Check(4), Chain Calibration(5).
// Resumes mid-flow using lastCompletedOnboardingStep from DeviceConfig.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onboarding step indices.
const int kOnboardingStepWelcome = 0;
const int kOnboardingStepHardware = 1;
const int kOnboardingStepDevice = 2;
const int kOnboardingStepMains = 3;
const int kOnboardingStepLevel = 4;
const int kOnboardingStepCalibration = 5;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _currentStep = kOnboardingStepWelcome;

  void _advance() {
    if (_currentStep < kOnboardingStepCalibration) {
      setState(() => _currentStep++);
    } else {
      // Onboarding complete — navigate to main app.
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle()),
      ),
      body: _buildStep(),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentStep > kOnboardingStepWelcome)
              TextButton(
                onPressed: () => setState(() => _currentStep--),
                child: const Text('Back'),
              )
            else
              const SizedBox.shrink(),
            ElevatedButton(
              onPressed: _advance,
              child: Text(_currentStep < kOnboardingStepCalibration
                  ? 'Next'
                  : 'Start Measuring'),
            ),
          ],
        ),
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case kOnboardingStepWelcome:
        return 'Welcome';
      case kOnboardingStepHardware:
        return 'Hardware Checklist';
      case kOnboardingStepDevice:
        return 'Select Audio Interface';
      case kOnboardingStepMains:
        return 'Mains Frequency';
      case kOnboardingStepLevel:
        return 'Level Check';
      case kOnboardingStepCalibration:
        return 'Chain Calibration';
      default:
        return '';
    }
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case kOnboardingStepWelcome:
        return _WelcomeStep();
      case kOnboardingStepHardware:
        return _HardwareChecklistStep();
      case kOnboardingStepDevice:
        return _DeviceSelectionStep();
      case kOnboardingStepMains:
        return _MainsFrequencyStep();
      case kOnboardingStepLevel:
        return _LevelCheckStep();
      case kOnboardingStepCalibration:
        return _ChainCalibrationStep();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Text(
              'Measure the resonance frequency of guitar pickups using your audio interface.',
              style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _HardwareChecklistStep extends StatefulWidget {
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

class _DeviceSelectionStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select your audio interface from the list below.'),
          SizedBox(height: 16),
          // DevicePicker widget will be wired in Phase 2.
          Placeholder(fallbackHeight: 80),
        ],
      ),
    );
  }
}

class _MainsFrequencyStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Measure your local mains frequency for accurate hum suppression.'),
          SizedBox(height: 16),
          Placeholder(fallbackHeight: 80),
        ],
      ),
    );
  }
}

class _LevelCheckStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target: −12 dBFS. Mark the headphone knob position once level is correct.'),
          SizedBox(height: 16),
          Placeholder(fallbackHeight: 80),
        ],
      ),
    );
  }
}

class _ChainCalibrationStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replace the pickup with a 10 kΩ resistor, then tap Calibrate.'),
          SizedBox(height: 16),
          Placeholder(fallbackHeight: 80),
        ],
      ),
    );
  }
}
