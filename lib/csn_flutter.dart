import 'package:flutter/material.dart';

import 'src/api/csn_api_client.dart';
import 'src/signaling/csn_signaling_client.dart';
import 'src/theme/csn_theme_data.dart';

export 'src/api/csn_api_client.dart';
export 'src/api/models.dart';
export 'src/signaling/csn_signaling_client.dart';
export 'src/signaling/messages.dart';
export 'src/theme/csn_theme.dart';
export 'src/theme/csn_theme_data.dart';
export 'src/ui/csn_call_controller.dart';
export 'src/ui/csn_call_models.dart';
export 'src/ui/csn_call_screen.dart';
export 'src/ui/csn_basic_call_controller.dart';
export 'src/ui/csn_request_mode_picker.dart';
export 'src/ui/csn_request_controllers.dart';
export 'src/utils/debug_log.dart';

/// Helper to create ThemeData with CSN theme extension.
ThemeData csnTheme({
  Brightness brightness = Brightness.light,
  CsnThemeData? override,
}) {
  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final csn = override ??
      (brightness == Brightness.dark
          ? CsnThemeData.dark()
          : CsnThemeData.light());
  return base.copyWith(extensions: [csn]);
}

/// Convenience builder for API + signaling.
class CsnSdk {
  CsnSdk({
    required this.baseUrl,
    required this.wsUrl,
    this.jwt,
  });

  final String baseUrl;
  final String wsUrl;
  final String? jwt;

  CsnApiClient get api => CsnApiClient(baseUrl: baseUrl, jwt: jwt);

  CsnSignalingClient signaling() => CsnSignalingClient(wsUrl: wsUrl, jwt: jwt);
}
