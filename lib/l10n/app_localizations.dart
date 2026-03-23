import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'What\'s the Frequency, Kenneth'**
  String get appTitle;

  /// Onboarding welcome screen title
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get onboardingWelcomeTitle;

  /// Onboarding welcome screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Measure the resonance frequency of guitar pickups using your audio interface.'**
  String get onboardingWelcomeSubtitle;

  /// Onboarding hardware checklist step title
  ///
  /// In en, this message translates to:
  /// **'Hardware Checklist'**
  String get onboardingHardwareTitle;

  /// Onboarding device selection step title
  ///
  /// In en, this message translates to:
  /// **'Select Audio Interface'**
  String get onboardingDeviceTitle;

  /// Onboarding mains frequency step title
  ///
  /// In en, this message translates to:
  /// **'Measure Mains Frequency'**
  String get onboardingMainsTitle;

  /// Onboarding level check step title
  ///
  /// In en, this message translates to:
  /// **'Level Check'**
  String get onboardingLevelTitle;

  /// Onboarding chain calibration step title
  ///
  /// In en, this message translates to:
  /// **'Chain Calibration'**
  String get onboardingCalibrationTitle;

  /// Error: dropout detected during capture
  ///
  /// In en, this message translates to:
  /// **'Dropout detected — audio interface glitch. Please retry.'**
  String get errorDropoutDetected;

  /// Error: output clipping detected
  ///
  /// In en, this message translates to:
  /// **'Output is clipping — turn the headphone knob down slightly and recalibrate.'**
  String get errorOutputClipping;

  /// Error: device not found
  ///
  /// In en, this message translates to:
  /// **'Audio device not found. Please check connections and try again.'**
  String get errorDeviceNotFound;

  /// Error: sample rate mismatch
  ///
  /// In en, this message translates to:
  /// **'Sample rate mismatch — set the Scarlett 2i2 to 48 kHz in Focusrite Control.'**
  String get errorSampleRateMismatch;

  /// Error: app backgrounded during capture
  ///
  /// In en, this message translates to:
  /// **'Measurement interrupted — app moved to background. Please retry.'**
  String get errorAppBackgrounded;

  /// Error: audio session interrupted
  ///
  /// In en, this message translates to:
  /// **'Audio session interrupted. Please retry.'**
  String get errorInterrupted;

  /// Calibration completed successfully
  ///
  /// In en, this message translates to:
  /// **'Calibration complete'**
  String get calibrationComplete;

  /// Warning banner when calibration has expired
  ///
  /// In en, this message translates to:
  /// **'Calibration has expired. Tap to recalibrate.'**
  String get calibrationExpiredWarning;

  /// Prompt to replace pickup with resistor for calibration
  ///
  /// In en, this message translates to:
  /// **'Replace the pickup with a 10 kΩ resistor, then tap Calibrate.'**
  String get calibrationResistorPrompt;

  /// Error: pickup still connected during calibration pre-check
  ///
  /// In en, this message translates to:
  /// **'A pickup signal is still present — replace the pickup with the 10 kΩ resistor before calibrating.'**
  String get calibrationPickupStillConnected;

  /// Level check target instruction
  ///
  /// In en, this message translates to:
  /// **'Target: −12 dBFS. Mark the headphone knob position once level is correct.'**
  String get levelCheckTarget;

  /// Button to start a measurement
  ///
  /// In en, this message translates to:
  /// **'Start Measurement'**
  String get measureStart;

  /// Button to retry a failed measurement
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get measureRetry;

  /// Button to discard the current measurement result
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get measureDiscard;

  /// Button to save the current measurement result
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get measureSave;

  /// Button to export the current measurement as CSV
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get measureExport;

  /// Message when no valid calibration exists
  ///
  /// In en, this message translates to:
  /// **'No valid calibration. Please calibrate before measuring.'**
  String get measureNoCalibration;

  /// Empty state message for history screen
  ///
  /// In en, this message translates to:
  /// **'No measurements yet. Complete a measurement to see results here.'**
  String get historyEmptyState;

  /// Toggle label for history grouping
  ///
  /// In en, this message translates to:
  /// **'Group by pickup'**
  String get historyGroupByPickup;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Setup screen title
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setupTitle;

  /// Calibration screen title
  ///
  /// In en, this message translates to:
  /// **'Calibration'**
  String get calibrationTitle;

  /// Measure screen title
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get measureTitle;

  /// Results screen title
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get resultsTitle;

  /// Placeholder when no audio devices are available
  ///
  /// In en, this message translates to:
  /// **'No audio devices found'**
  String get noDevicesFound;

  /// Button to overlay a previous measurement
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get overlayMeasurement;

  /// Warning when overlaying measurements with different sweep configs
  ///
  /// In en, this message translates to:
  /// **'This measurement used different sweep settings and may not be directly comparable.'**
  String get sweepConfigMismatchWarning;

  /// Button to trigger recalibration
  ///
  /// In en, this message translates to:
  /// **'Recalibrate'**
  String get recalibrate;

  /// Next button in onboarding flow
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Back button
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Confirm button
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
