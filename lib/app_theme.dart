import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const _lightPrimary = Color(0xFF2F6BFF);
  static const _darkPrimary = Color(0xFF6D95FF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? _darkPrimary : _lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF17306B)
          : const Color(0xFFE8EFFF),
      onPrimaryContainer: isDark
          ? const Color(0xFFDCE6FF)
          : const Color(0xFF17346F),
      secondary: isDark ? const Color(0xFF8FA8D8) : const Color(0xFF46628F),
      onSecondary: Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF27344D)
          : const Color(0xFFE8EEF8),
      onSecondaryContainer: isDark
          ? const Color(0xFFE0E8F8)
          : const Color(0xFF263A5A),
      tertiary: isDark ? const Color(0xFF78D8A5) : const Color(0xFF178652),
      onTertiary: Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF153B2A)
          : const Color(0xFFE3F6EB),
      onTertiaryContainer: isDark
          ? const Color(0xFFD7F4E4)
          : const Color(0xFF145A3A),
      error: isDark ? const Color(0xFFFF8B8B) : const Color(0xFFD92D20),
      onError: Colors.white,
      errorContainer: isDark
          ? const Color(0xFF512020)
          : const Color(0xFFFFE9E7),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD7)
          : const Color(0xFF7A211B),
      surface: isDark ? const Color(0xFF0F1115) : const Color(0xFFF7F8FA),
      onSurface: isDark ? const Color(0xFFF3F4F6) : const Color(0xFF17191D),
      surfaceContainerLowest: isDark
          ? const Color(0xFF0B0D10)
          : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark
          ? const Color(0xFF15181D)
          : const Color(0xFFFFFFFF),
      surfaceContainer: isDark
          ? const Color(0xFF1A1D22)
          : const Color(0xFFF0F2F5),
      surfaceContainerHigh: isDark
          ? const Color(0xFF20242A)
          : const Color(0xFFE8EBEF),
      surfaceContainerHighest: isDark
          ? const Color(0xFF292D34)
          : const Color(0xFFE1E5EA),
      onSurfaceVariant: isDark
          ? const Color(0xFFB4B8C1)
          : const Color(0xFF626872),
      outline: isDark ? const Color(0xFF464B54) : const Color(0xFFC9CED6),
      outlineVariant: isDark
          ? const Color(0xFF2A2E35)
          : const Color(0xFFE1E5EA),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? const Color(0xFFF1F3F5) : const Color(0xFF202328),
      onInverseSurface: isDark ? const Color(0xFF202328) : const Color(0xFFF4F5F6),
      inversePrimary: isDark ? _lightPrimary : _darkPrimary,
      surfaceTint: Colors.transparent,
    );

    const pageRadius = 14.0;
    const controlRadius = 12.0;

    final textTheme = ThemeData(brightness: brightness).textTheme.copyWith(
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.35, color: scheme.onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: scheme.onSurface),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      fontFamily: 'Roboto',
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(pageRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        showUnselectedLabels: true,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
        disabledColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFFE9EBEF) : const Color(0xFF24272D),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF202328) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: isDark ? _lightPrimary : const Color(0xFFAEC3FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1,
        highlightElevation: 2,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10)
                : scheme.surfaceContainerLow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent;
        }),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant;
        }),
      ),
    );
  }
}
