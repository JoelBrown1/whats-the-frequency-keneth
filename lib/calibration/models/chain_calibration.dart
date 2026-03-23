// lib/calibration/models/chain_calibration.dart
// Stores the measured chain frequency response H_chain(f) used to calibrate
// out the exciter coil and headphone amp contribution before pickup measurement.
//
// H_chain is stored at kHChainBins uniformly-spaced bins (0–kHChainMaxHz).
// At full FFT resolution (262,144 bins) it would be ~4 MB of JSON.
// 4,096 bins is fine enough to resolve any feature the headphone amp or
// exciter coil can produce, while remaining fast to read/write.

import 'dart:typed_data';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';

/// Number of uniformly-spaced frequency bins in H_chain storage.
const int kHChainBins = 4096;

/// Maximum frequency covered by the H_chain storage grid.
const double kHChainMaxHz = 24000.0;

class ChainCalibration {
  /// UUID identifying this calibration run.
  final String id;

  final DateTime timestamp;

  /// Real part of H_chain(f), length kHChainBins.
  final Float64List hChainReal;

  /// Imaginary part of H_chain(f), length kHChainBins.
  final Float64List hChainImag;

  final SweepConfig sweepConfig;

  const ChainCalibration({
    required this.id,
    required this.timestamp,
    required this.hChainReal,
    required this.hChainImag,
    required this.sweepConfig,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'hChainReal': hChainReal.toList(),
        'hChainImag': hChainImag.toList(),
        'sweepConfig': sweepConfig.toJson(),
      };

  factory ChainCalibration.fromJson(Map<String, dynamic> json) {
    final realList = (json['hChainReal'] as List).cast<num>();
    final imagList = (json['hChainImag'] as List).cast<num>();
    return ChainCalibration(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      hChainReal: Float64List.fromList(realList.map((e) => e.toDouble()).toList()),
      hChainImag: Float64List.fromList(imagList.map((e) => e.toDouble()).toList()),
      sweepConfig: SweepConfig.fromJson(json['sweepConfig'] as Map<String, dynamic>),
    );
  }
}
