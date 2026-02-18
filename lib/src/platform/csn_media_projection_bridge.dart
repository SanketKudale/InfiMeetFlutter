import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/debug_log.dart';

class CsnMediaProjectionBridge {
  static const MethodChannel _channel =
      MethodChannel('csn_flutter/media_projection');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> startForegroundService() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startForegroundService');
    } catch (error, stackTrace) {
      debugLog(
        'Failed to start media projection foreground service',
        error,
        stackTrace,
      );
    }
  }

  static Future<void> stopForegroundService() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForegroundService');
    } catch (error, stackTrace) {
      debugLog(
        'Failed to stop media projection foreground service',
        error,
        stackTrace,
      );
    }
  }
}
