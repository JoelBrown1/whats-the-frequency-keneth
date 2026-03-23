// lib/ui/screens/setup_screen.dart
// Setup screen: device picker, hardware checklist, level check button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Audio Interface', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // DevicePicker — wired in Phase 2.
          const Placeholder(fallbackHeight: 60),
          const Divider(),
          const Text('Hardware Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _ChecklistItem(label: 'Air mode: OFF (both channels)'),
          _ChecklistItem(label: 'Direct monitoring: DISABLED'),
          _ChecklistItem(label: 'OS audio enhancements: DISABLED'),
          const Divider(),
          const Text('Level Check', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              // Level check — implemented in Phase 2.
            },
            child: const Text('Start Level Check'),
          ),
        ],
      ),
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
