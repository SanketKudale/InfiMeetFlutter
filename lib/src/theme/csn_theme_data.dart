import 'package:flutter/material.dart';

@immutable
class CsnThemeData extends ThemeExtension<CsnThemeData> {
  const CsnThemeData({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color success;
  final Color warning;
  final Color danger;

  factory CsnThemeData.light() => const CsnThemeData(
        primary: Color(0xFF1E5BFF),
        accent: Color(0xFF00C2A8),
        background: Color(0xFFF7F8FA),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF0F172A),
        mutedText: Color(0xFF64748B),
        success: Color(0xFF16A34A),
        warning: Color(0xFFF59E0B),
        danger: Color(0xFFEF4444),
      );

  factory CsnThemeData.dark() => const CsnThemeData(
        primary: Color(0xFF4C7DFF),
        accent: Color(0xFF21D1B7),
        background: Color(0xFF0B1020),
        surface: Color(0xFF111827),
        text: Color(0xFFE5E7EB),
        mutedText: Color(0xFF94A3B8),
        success: Color(0xFF22C55E),
        warning: Color(0xFFFBBF24),
        danger: Color(0xFFF87171),
      );

  @override
  CsnThemeData copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? text,
    Color? mutedText,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return CsnThemeData(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  ThemeExtension<CsnThemeData> lerp(ThemeExtension<CsnThemeData>? other, double t) {
    if (other is! CsnThemeData) return this;
    return CsnThemeData(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
