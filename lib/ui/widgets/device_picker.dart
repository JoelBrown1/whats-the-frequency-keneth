// lib/ui/widgets/device_picker.dart
// Dropdown showing available audio devices from the platform.

import 'package:flutter/material.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';

class DevicePicker extends StatelessWidget {
  final List<AudioDeviceDescriptor> devices;
  final String? selectedUid;
  final ValueChanged<String?> onChanged;

  const DevicePicker({
    super.key,
    required this.devices,
    required this.selectedUid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const Text('No audio device detected',
          style: TextStyle(color: Colors.orange));
    }

    final effectiveValue = devices.any((d) => d.uid == selectedUid) ? selectedUid : null;

    return DropdownButton<String>(
      isExpanded: true,
      value: effectiveValue,
      hint: const Text('Select audio interface'),
      items: devices.map((d) {
        return DropdownMenuItem<String>(
          value: d.uid,
          child: Text(d.name),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
