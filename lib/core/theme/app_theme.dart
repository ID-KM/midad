import 'package:flutter/material.dart';

/// لوحة ألوان "مداد" — بمواصفات PRD حرفياً.
abstract final class AppColors {
  /// البني الفاتح الدافئ — اللون الأساسي
  static const Color lightBrown = Color(0xFF8B5A2B);

  /// البني الداكن — لون النصوص والعناصر القوية
  static const Color darkBrown = Color(0xFF3E2723);

  /// الأصفر الدافئ الذهبي — للتمييز والأيقونات وشريط التقدم
  static const Color warmYellow = Color(0xFFF5D061);

  /// خلفية ورقية دافئة — الوضع الفاتح
  static const Color paperLight = Color(0xFFFDFBF7);

  /// خلفية الوضع الداكن القياسي
  static const Color darkBackground = Color(0xFF121212);

  /// خلفية AMOLED — أسود مطلق لتوفير البطارية
  static const Color amoledBackground = Color(0xFF000000);

  /// سطح داكن لبطاقات الوضع الداكن (أفتح قليلاً من الخلفية)
  static const Color darkSurface = Color(0xFF1E1E1E);

  /// سطح AMOLED للبطاقات (رمادي شديد الدكن، يحافظ على التباين)
  static const Color amoledSurface = Color(0xFF0D0D0D);

  /// نص ثانوي في الوضع الفاتح
  static const Color textMutedLight = Color(0xFF8A7A6A);

  /// نص ثانوي في الوضع الداكن
  static const Color textMutedDark = Color(0xFF9E9E9E);
}

/// أوضاع المظهر المدعومة.
enum AppThemeMode {
  light,
  dark,
  amoled;

  String get label => switch (this) {
        AppThemeMode.light => 'فاتح',
        AppThemeMode.dark => 'داكن',
        AppThemeMode.amoled => 'AMOLED',
      };
}

/// الثيمات الثلاثة المبنية على لوحة ألوان واحدة.
abstract final class AppTheme {
  /// القالب الفاتح — خلفية ورقية دافئة، بني للعناصر، ذهبي للتمييز.
  static ThemeData light() => _base(
        brightness: Brightness.light,
        background: AppColors.paperLight,
        surface: Colors.white,
        primary: AppColors.lightBrown,
        onPrimary: Colors.white,
        onSurface: AppColors.darkBrown,
        muted: AppColors.textMutedLight,
      );

  /// القالب الداكن القياسي.
  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        primary: AppColors.warmYellow,
        onPrimary: AppColors.darkBrown,
        onSurface: const Color(0xFFECECEC),
        muted: AppColors.textMutedDark,
      );

  /// قالب AMOLED — أسود مطلق، يطفئ البكسلات توفيراً للبطارية.
  static ThemeData amoled() => _base(
        brightness: Brightness.dark,
        background: AppColors.amoledBackground,
        surface: AppColors.amoledSurface,
        primary: AppColors.warmYellow,
        onPrimary: AppColors.darkBrown,
        onSurface: const Color(0xFFE8E8E8),
        muted: const Color(0xFF8A8A8A),
      );

  /// إرجاع قالب حسب الوضع المطلوب.
  static ThemeData of(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => light(),
        AppThemeMode.dark => dark(),
        AppThemeMode.amoled => amoled(),
      };

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color primary,
    required Color onPrimary,
    required Color onSurface,
    required Color muted,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppColors.warmYellow,
      onSecondary: AppColors.darkBrown,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.warmYellow,
        foregroundColor: AppColors.darkBrown,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
