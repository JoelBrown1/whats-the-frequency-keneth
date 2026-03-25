// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'What\'s the Frequency, Kenneth';

  @override
  String get onboardingWelcomeTitle => 'Welcome';

  @override
  String get onboardingWelcomeSubtitle =>
      'Measure the resonance frequency of guitar pickups using your audio interface.';

  @override
  String get onboardingHardwareTitle => 'Hardware Checklist';

  @override
  String get onboardingDeviceTitle => 'Select Audio Interface';

  @override
  String get onboardingMainsTitle => 'Measure Mains Frequency';

  @override
  String get onboardingLevelTitle => 'Level Check';

  @override
  String get onboardingCalibrationTitle => 'Chain Calibration';

  @override
  String get errorDropoutDetected =>
      'Dropout detected — audio interface glitch. Please retry.';

  @override
  String get errorOutputClipping =>
      'Output is clipping — turn the headphone knob down slightly and recalibrate.';

  @override
  String get errorDeviceNotFound =>
      'Audio device not found. Please check connections and try again.';

  @override
  String get errorSampleRateMismatch =>
      'Sample rate mismatch — set the Scarlett 2i2 to 48 kHz in Focusrite Control.';

  @override
  String get errorAppBackgrounded =>
      'Measurement interrupted — app moved to background. Please retry.';

  @override
  String get errorInterrupted => 'Audio session interrupted. Please retry.';

  @override
  String get calibrationComplete => 'Calibration complete';

  @override
  String get calibrationExpiredWarning =>
      'Calibration has expired. Tap to recalibrate.';

  @override
  String get calibrationResistorPrompt =>
      'Replace the pickup with a 10 kΩ resistor, then tap Calibrate.';

  @override
  String get calibrationPickupStillConnected =>
      'A pickup signal is still present — replace the pickup with the 10 kΩ resistor before calibrating.';

  @override
  String get levelCheckTarget =>
      'Target: −12 dBFS. Mark the headphone knob position once level is correct.';

  @override
  String get measureStart => 'Start Measurement';

  @override
  String get measureRetry => 'Retry';

  @override
  String get measureDiscard => 'Discard';

  @override
  String get measureSave => 'Save';

  @override
  String get measureExport => 'Export CSV';

  @override
  String get measureNoCalibration =>
      'No valid calibration. Please calibrate before measuring.';

  @override
  String get historyEmptyState =>
      'No measurements yet. Complete a measurement to see results here.';

  @override
  String get historyGroupByPickup => 'Group by pickup';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get setupTitle => 'Setup';

  @override
  String get calibrationTitle => 'Calibration';

  @override
  String get measureTitle => 'Measure';

  @override
  String get resultsTitle => 'Results';

  @override
  String get noDevicesFound => 'No audio devices found';

  @override
  String get overlayMeasurement => 'Overlay';

  @override
  String get sweepConfigMismatchWarning =>
      'This measurement used different sweep settings and may not be directly comparable.';

  @override
  String get recalibrate => 'Recalibrate';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancel => 'Cancel';

  @override
  String get measureArming => 'Arming…';

  @override
  String get measureCapturing => 'Capturing…';

  @override
  String get measureAnalysing => 'Analysing…';

  @override
  String get measureWorking => 'Working…';

  @override
  String measurePlayingSweep(int pass, int total) {
    return 'Playing sweep $pass of $total…';
  }

  @override
  String get discardResultTitle => 'Discard result?';

  @override
  String get discardResultContent =>
      'This measurement will not be saved. Are you sure?';

  @override
  String get overlayMeasurementClear => 'Clear';

  @override
  String get saveMeasurementTitle => 'Save measurement';

  @override
  String get pickupLabelField => 'Pickup label';

  @override
  String get pickupLabelHint => 'e.g. PAF neck';

  @override
  String get linkExistingPickup => 'Link to existing pickup (optional):';

  @override
  String get noneOption => 'None';

  @override
  String get createNewPickup => 'Create new pickup';

  @override
  String get historyTitle => 'History';

  @override
  String get historySelectMeasurement => 'Select measurement';

  @override
  String get historyUnnamedPickup => 'Unnamed pickup';

  @override
  String get startMeasuring => 'Start Measuring';

  @override
  String get setupAudioInterfaceSection => 'Audio Interface';

  @override
  String get errorDspFailed => 'Signal processing failed. Please retry.';

  @override
  String get calibrateButton => 'Calibrate';

  @override
  String calibrationSweeping(int pass, int total) {
    return 'Sweeping… (pass $pass of $total)';
  }

  @override
  String get calibrationFailed => 'Calibration failed';

  @override
  String get calibrationTryAgain => 'Try again';

  @override
  String get mainsNotMeasuredWarning =>
      'Mains frequency not yet measured — hum suppression is using the 50 Hz default. Tap to measure.';
}
