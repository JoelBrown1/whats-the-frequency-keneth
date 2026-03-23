// lib/ui/widgets/level_meter.dart
// Shows a dBFS level value and a clipping indicator above -1 dBFS.

import 'package:flutter/material.dart';

class LevelMeter extends StatelessWidget {
  final double dbfs;

  const LevelMeter({super.key, required this.dbfs});

  bool get _isClipping => dbfs > -1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isClipping ? Colors.red.shade900 : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${dbfs.toStringAsFixed(1)} dBFS',
            style: TextStyle(
              color: _isClipping ? Colors.red : Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_isClipping) ...[
            const SizedBox(width: 8),
            const Text(
              'CLIP',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
