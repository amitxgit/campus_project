import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ===========================================================================
/// BATCHWISE DESIGN SYSTEM
/// ===========================================================================
///
/// Monochrome base (ink on paper; inverted in dark mode) with a single blue
/// accent. Rules of thumb:
///  • Primary actions are ink-filled (black in light, white in dark).
///  • Blue marks focus, selection, links and the one number that matters.
///  • Green / amber / red only ever mean good / careful / bad.
///  • Surfaces are separated by tone, not shadows.
class AppTheme {
  static ThemeData lightTheme = _build(Palette.light);
  static ThemeData darkTheme = _build(Palette.dark);
}

/// Colour tokens, reachable anywhere via `context.palette`.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color background;
  final Color surface; // cards, tiles
  final Color surfaceRaised; // inputs, chips, pressed tiles
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;

  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  static const light = Palette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F7),
    surfaceRaised: Color(0xFFECECEF),
    ink: Color(0xFF0B0B0D),
    inkMuted: Color(0xFF62626C),
    inkFaint: Color(0xFFA1A1AA),
    line: Color(0xFFE4E4E8),
    accent: Color(0xFF2A5BFF),
    accentSoft: Color(0xFFE9EFFF),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF14965A),
    successSoft: Color(0xFFE3F5EC),
    warning: Color(0xFFC27A00),
    warningSoft: Color(0xFFFFF3DC),
    danger: Color(0xFFDC3B42),
    dangerSoft: Color(0xFFFDE8E9),
  );

  static const dark = Palette(
    background: Color(0xFF09090B),
    surface: Color(0xFF151518),
    surfaceRaised: Color(0xFF202024),
    ink: Color(0xFFF5F5F6),
    inkMuted: Color(0xFFA0A0AB),
    inkFaint: Color(0xFF63636D),
    line: Color(0xFF26262B),
    accent: Color(0xFF6D8BFF),
    accentSoft: Color(0xFF17204A),
    onAccent: Color(0xFF09090B),
    success: Color(0xFF3CCB86),
    successSoft: Color(0xFF0F2A1E),
    warning: Color(0xFFF2B544),
    warningSoft: Color(0xFF2E2310),
    danger: Color(0xFFFF6B70),
    dangerSoft: Color(0xFF341517),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
    );
  }
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// Shared motion values so every animation in the app feels related.
class Motion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const curve = Curves.easeOutCubic;
}

ThemeData _build(Palette p) {
  final isDark = p == Palette.dark;
  final brightness = isDark ? Brightness.dark : Brightness.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.ink,
    onPrimary: p.background,
    primaryContainer: p.accentSoft,
    onPrimaryContainer: p.accent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.accentSoft,
    onSecondaryContainer: p.accent,
    tertiary: p.accent,
    onTertiary: p.onAccent,
    tertiaryContainer: p.accentSoft,
    onTertiaryContainer: p.accent,
    error: p.danger,
    onError: Colors.white,
    errorContainer: p.dangerSoft,
    onErrorContainer: p.danger,
    surface: p.background,
    onSurface: p.ink,
    onSurfaceVariant: p.inkMuted,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceRaised,
    surfaceContainerHighest: p.surfaceRaised,
    outline: p.inkFaint,
    outlineVariant: p.line,
    inverseSurface: p.ink,
    onInverseSurface: p.background,
    inversePrimary: p.accent,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: p.ink, displayColor: p.ink);

  final radius12 = BorderRadius.circular(12);
  final radius14 = BorderRadius.circular(14);
  final radius20 = BorderRadius.circular(20);

  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2),
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      bodySmall: text.bodySmall?.copyWith(color: p.inkMuted),
      labelSmall: text.labelSmall?.copyWith(color: p.inkMuted, letterSpacing: 0.4),
    ),

    // Fade-through on Android, native slide on iOS.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3, color: p.ink),
      iconTheme: IconThemeData(color: p.ink),
    ),

    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: radius20),
      clipBehavior: Clip.antiAlias,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.inkFaint),
      labelStyle: TextStyle(color: p.inkMuted),
      floatingLabelStyle: TextStyle(color: p.accent),
      prefixIconColor: p.inkMuted,
      suffixIconColor: p.inkMuted,
      border: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: p.accent, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: p.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: p.danger, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.background,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        elevation: 0,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.background,
        disabledBackgroundColor: p.surfaceRaised,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: p.line, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.background,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: radius20),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accentSoft,
      side: BorderSide(color: p.line),
      labelStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
      secondaryLabelStyle: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
      checkmarkColor: p.accent,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius12)),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.inkFaint),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceRaised),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null),
      checkColor: WidgetStatePropertyAll(p.onAccent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.inkFaint),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.surfaceRaised,
      circularTrackColor: Colors.transparent,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: p.ink,
      unselectedLabelColor: p.inkMuted,
      indicatorColor: p.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: p.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.background,
      indicatorColor: p.accentSoft,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.inkMuted),
      ),
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: p.ink),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.background, fontWeight: FontWeight.w500),
      actionTextColor: p.accent,
      shape: RoundedRectangleBorder(borderRadius: radius14),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: p.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius14, side: BorderSide(color: p.line)),
    ),

    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),

    iconTheme: IconThemeData(color: p.ink),

    listTileTheme: ListTileThemeData(
      iconColor: p.inkMuted,
      textColor: p.ink,
      shape: RoundedRectangleBorder(borderRadius: radius14),
    ),
  );
}
