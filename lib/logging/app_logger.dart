// lib/logging/app_logger.dart
// Global logger instance. Import and call appLog.d/i/w/e throughout the app.
//
// In release builds, level is set to Level.warning so debug/info output is
// suppressed automatically.

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final Logger appLog = Logger(
  level: kReleaseMode ? Level.warning : Level.debug,
  printer: PrettyPrinter(
    methodCount: 0,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    colors: true,
    printEmojis: false,
    noBoxingByDefault: true,
  ),
);
