import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.bgApp,
    required this.bgSurface,
    required this.bgCard,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.navBackground,
    required this.navForeground,
    required this.border,
  });

  final Color bgApp;
  final Color bgSurface;
  final Color bgCard;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color navBackground;
  final Color navForeground;
  final Color border;

  @override
  AppColorTokens copyWith({
    Color? bgApp,
    Color? bgSurface,
    Color? bgCard,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? navBackground,
    Color? navForeground,
    Color? border,
  }) {
    return AppColorTokens(
      bgApp: bgApp ?? this.bgApp,
      bgSurface: bgSurface ?? this.bgSurface,
      bgCard: bgCard ?? this.bgCard,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      primary: primary ?? this.primary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      navBackground: navBackground ?? this.navBackground,
      navForeground: navForeground ?? this.navForeground,
      border: border ?? this.border,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) {
      return this;
    }

    return AppColorTokens(
      bgApp: Color.lerp(bgApp, other.bgApp, t) ?? bgApp,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t) ?? bgSurface,
      bgCard: Color.lerp(bgCard, other.bgCard, t) ?? bgCard,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      navBackground:
          Color.lerp(navBackground, other.navBackground, t) ?? navBackground,
      navForeground:
          Color.lerp(navForeground, other.navForeground, t) ?? navForeground,
      border: Color.lerp(border, other.border, t) ?? border,
    );
  }
}

@immutable
class AppSpacingTokens {
  const AppSpacingTokens();

  final double xxs = 4;
  final double xs = 8;
  final double sm = 12;
  final double md = 16;
  final double lg = 24;
  final double xl = 32;
  final double xxl = 48;
}

@immutable
class AppRadiusTokens {
  const AppRadiusTokens();

  final double sm = 4;
  final double md = 6;
  final double lg = 8;
  final double xl = 12;
  final double pill = 999;
}

@immutable
class AppShadowTokens {
  const AppShadowTokens();

  List<BoxShadow> get card => const [];

  List<BoxShadow> get focused => const [];
}

@immutable
class AppTypographyTokens {
  const AppTypographyTokens();

  TextStyle get navLabel =>
      const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600);

  TextStyle get chipLabel =>
      const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600);

  TextStyle get body =>
      const TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w500);

  TextStyle get bodyStrong =>
      const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600);

  TextStyle get sectionTitle =>
      const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w700);

  TextStyle get heroTitle =>
      const TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w800);

  TextStyle get label =>
      const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600);
}

class AppTheme {
  static const AppColorTokens _tokens = AppColorTokens(
    bgApp: Color(0xFF0B0E11),
    bgSurface: Color(0xFF1E2329),
    bgCard: Color(0xFF1E2329),
    textPrimary: Color(0xFFEAECEF),
    textSecondary: Color(0xFF929AA5),
    primary: Color(0xFFFCD535),
    success: Color(0xFF0ECB81),
    warning: Color(0xFFFCD535),
    danger: Color(0xFFF6465D),
    navBackground: Color(0xFF0B0E11),
    navForeground: Color(0xFFEAECEF),
    border: Color(0xFF2B3139),
  );

  static const AppSpacingTokens spacing = AppSpacingTokens();
  static const AppRadiusTokens radius = AppRadiusTokens();
  static const AppShadowTokens shadows = AppShadowTokens();
  static const AppTypographyTokens typography = AppTypographyTokens();

  static const primaryColor = Color(0xFFFCD535);
  static const primarySoft = Color(0xFFF0B90B);
  static const rewardGold = Color(0xFFFCD535);
  static const goldButtonTop = Color(0xFFFCD535);
  static const goldButtonBottom = Color(0xFFF0B90B);
  static const goldText = Color(0xFF181A20);
  static const goldDisabledTop = Color(0xFF3A3A1F);
  static const goldDisabledBottom = Color(0xFF3A3A1F);
  static const backgroundLight = Color(0xFF1E2329);
  static const backgroundDark = Color(0xFF0B0E11);
  static const surfaceDark = Color(0xFF1E2329);
  static const borderDark = Color(0xFF2B3139);
  static const gameBackground = Color(0xFF0B0E11);
  static const gameSurface = Color(0xFF1E2329);
  static const gameBorder = Color(0xFF2B3139);
  static const textPrimary = Color(0xFFEAECEF);
  static const textSecondary = Color(0xFF929AA5);
  static const bgCard = Color(0xFF1E2329);
  static const navBackground = Color(0xFF0B0E11);
  static const navForeground = Color(0xFFEAECEF);
  static const success = Color(0xFF0ECB81);
  static const warning = Color(0xFFFCD535);
  static const danger = Color(0xFFF6465D);

  static ThemeData get lightTheme {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: primaryColor,
      surface: backgroundLight,
      error: danger,
      onPrimary: Colors.white,
      onSurface: textPrimary,
      onSecondary: Colors.white,
      onError: Colors.white,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: typography.heroTitle.copyWith(color: textPrimary),
      displayMedium: typography.heroTitle.copyWith(color: textPrimary),
      titleLarge: typography.sectionTitle.copyWith(color: textPrimary),
      titleMedium: typography.bodyStrong.copyWith(color: textPrimary),
      titleSmall: typography.label.copyWith(color: textSecondary),
      bodyLarge: typography.bodyStrong.copyWith(color: textPrimary),
      bodyMedium: typography.body.copyWith(color: textPrimary),
      bodySmall: typography.label.copyWith(color: textSecondary),
      labelLarge: typography.bodyStrong.copyWith(color: Colors.white),
      labelMedium: typography.label.copyWith(color: textPrimary),
      labelSmall: typography.label.copyWith(color: textSecondary),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundDark,
      canvasColor: bgCard,
      textTheme: textTheme,
      extensions: const [_tokens],
      dividerColor: borderDark,
      appBarTheme: AppBarTheme(
        backgroundColor: navBackground,
        foregroundColor: navForeground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: navForeground,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.lg),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgCard,
        selectedColor: primaryColor,
        disabledColor: surfaceDark,
        labelStyle: typography.chipLabel.copyWith(color: textSecondary),
        secondaryLabelStyle: typography.chipLabel.copyWith(color: Colors.white),
        side: BorderSide(color: borderDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.pill),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        hintStyle: typography.body.copyWith(color: textSecondary),
        labelStyle: typography.label.copyWith(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.lg),
          borderSide: BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.lg),
          borderSide: BorderSide(color: primaryColor, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return goldDisabledBottom;
            }
            return goldButtonBottom;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return goldText.withValues(alpha: 0.65);
            }
            return goldText;
          }),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(horizontal: spacing.lg, vertical: spacing.sm),
          ),
          minimumSize: WidgetStateProperty.all(const Size(120, 48)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius.lg),
            ),
          ),
          elevation: WidgetStateProperty.all(0),
          textStyle: WidgetStateProperty.all(typography.bodyStrong),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: bgCard,
          foregroundColor: textPrimary,
          side: BorderSide(color: borderDark),
          minimumSize: const Size(120, 48),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.lg),
          ),
          textStyle: typography.bodyStrong,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.xs,
          ),
          textStyle: typography.label.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgCard,
        contentTextStyle: typography.body.copyWith(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.md),
        ),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}

extension AppThemeContext on BuildContext {
  AppColorTokens get colors =>
      Theme.of(this).extension<AppColorTokens>() ?? AppTheme._tokens;

  AppSpacingTokens get space => AppTheme.spacing;

  AppRadiusTokens get radii => AppTheme.radius;

  AppShadowTokens get elevation => AppTheme.shadows;

  AppTypographyTokens get type => AppTheme.typography;
}
