import 'package:flutter/material.dart';

import 'csn_theme_data.dart';

class CsnTheme extends InheritedWidget {
  const CsnTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final CsnThemeData data;

  static CsnThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<CsnTheme>();
    if (theme != null) return theme.data;
    final extension = Theme.of(context).extension<CsnThemeData>();
    if (extension != null) return extension;
    return CsnThemeData.light();
  }

  @override
  bool updateShouldNotify(CsnTheme oldWidget) => data != oldWidget.data;
}
