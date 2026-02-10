import 'dart:developer' as developer;

void debugLog(String message, [Object? error, StackTrace? stackTrace]) {
  developer.log(
    message,
    name: 'csn_flutter',
    error: error,
    stackTrace: stackTrace,
  );
}
