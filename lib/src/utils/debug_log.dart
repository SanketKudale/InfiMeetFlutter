import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

void debugLog(String message, [Object? error, StackTrace? stackTrace]) {
  const enableLogs =
      bool.fromEnvironment('CSN_ENABLE_LOGS', defaultValue: true);
  if (!enableLogs || kReleaseMode) return;
  developer.log(
    message,
    name: 'csn_flutter',
    error: error,
    stackTrace: stackTrace,
  );
}
