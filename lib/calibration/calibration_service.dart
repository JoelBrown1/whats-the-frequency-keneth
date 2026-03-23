// lib/calibration/calibration_service.dart
// Stub CalibrationService — full implementation in Phase 2.
// Manages chain calibration lifecycle: storage, validation, expiry.

import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';

class CalibrationService {
  static const Duration calibrationExpiryDuration = Duration(minutes: 30);

  ChainCalibration? _activeCalibration;

  ChainCalibration? get activeCalibration => _activeCalibration;

  /// Initialise: reconcile SharedPreferences state against disk.
  /// If activeCalibrationId is null but calibration files exist, restore most recent.
  Future<void> init() async {
    // Phase 0 stub — full implementation in Phase 2.
  }

  /// Run a full chain calibration sweep and store H_chain.
  /// Phase 0 stub — returns mock calibration.
  Future<ChainCalibration> runChainCalibration(SweepConfig config) async {
    // Phase 0 stub.
    throw UnimplementedError('runChainCalibration — implemented in Phase 2');
  }

  /// Returns true if a calibration exists and has not expired.
  bool isCalibrationValid() {
    final cal = _activeCalibration;
    if (cal == null) return false;
    final age = DateTime.now().difference(cal.timestamp);
    return age <= calibrationExpiryDuration;
  }

  /// Measure mains frequency from an idle capture.
  /// Phase 0 stub.
  Future<double> measureMainsFrequency() async {
    // Phase 0 stub.
    throw UnimplementedError('measureMainsFrequency — implemented in Phase 2');
  }
}
