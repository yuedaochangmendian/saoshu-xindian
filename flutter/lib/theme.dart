import 'package:flutter/material.dart';

/// 五套主题的种子色（与原生版一致的识别色）。
class AppThemeOption {
  final String id;
  final String label;
  final int seed;
  const AppThemeOption(this.id, this.label, this.seed);
}

const appThemes = <AppThemeOption>[
  AppThemeOption('teal', '松石绿', 0xFF009688),
  AppThemeOption('ocean', '海盐蓝', 0xFF1E88E5),
  AppThemeOption('amber', '琥珀棕', 0xFFA66A2E),
  AppThemeOption('rose', '樱雾粉', 0xFFC75B7A),
  AppThemeOption('violet', '暮云紫', 0xFF7E57C2),
  // TiebaLite 官方色板（深海蓝 #4477E0 / 少女粉 #FF9A9E / 新年红 #C51100
  // / 星空紫 #512DA8 / 高级黑主色）——名字与色值取自其 strings/colors 资源。
  AppThemeOption('tieba_blue', '深海蓝', 0xFF4477E0),
  AppThemeOption('tieba_pink', '少女粉', 0xFFFF9A9E),
  AppThemeOption('tieba_red', '新年红', 0xFFC51100),
  AppThemeOption('tieba_purple', '星空紫', 0xFF512DA8),
  AppThemeOption('tieba_black', '高级黑', 0xFF171717),
];

ThemeData buildTheme(String themeId, Brightness brightness) {
  final option = appThemes.firstWhere(
    (t) => t.id == themeId,
    orElse: () => appThemes.first,
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(option.seed),
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainer,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      side: BorderSide.none,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
  );
}
