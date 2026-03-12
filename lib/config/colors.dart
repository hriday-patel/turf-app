import 'package:flutter/material.dart';

/// Adaptive color scheme — resolves light/dark colors based on brightness.
/// Usage: `AppColors.of(context).background` or static light-mode constants.
class AppColors {
  // ============================================================
  // LIGHT THEME PALETTE
  // ============================================================

  // Primary — Blue
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFFDBEAFE);
  static const Color primaryDark = Color(0xFF1D4ED8);

  // Secondary / Accent — Green
  static const Color secondary = Color(0xFF22C55E);
  static const Color secondaryLight = Color(0xFFDCFCE7);
  static const Color secondaryDark = Color(0xFF16A34A);

  // Status Colors
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFDCFCE7);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);

  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);

  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // ── Backgrounds ──
  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color inputBackground = Color(0xFFF8FAFC);
  static const Color inputBorder = Color(0xFFE2E8F0);

  // Backward compat aliases
  static const Color darkBackground = Color(0xFFF5F7FB);
  static const Color darkSurface = Color(0xFFFFFFFF);
  static const Color darkCardBackground = Color(0xFFFFFFFF);

  // ── Text ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFFCBD5E1);

  static const Color darkTextPrimary = Color(0xFF0F172A);
  static const Color darkTextSecondary = Color(0xFF64748B);

  // ── UI Elements ──
  static const Color divider = Color(0xFFE2E8F0);
  static const Color disabled = Color(0xFFE2E8F0);
  static const Color border = Color(0xFFE2E8F0);
  static const Color chipBackground = Color(0xFFEFF6FF);
  static const Color shimmerBase = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF1F5F9);

  // ── Glass surface helpers ──
  static const Color glassBorder = Color(0xFFE2E8F0);
  static const Color glassFill = Color(0xFFFFFFFF);
  static const Color glassHighlight = Color(0xFFF8FAFC);

  // Slot Status Colors
  static const Color slotAvailable = Color(0xFF22C55E);
  static const Color slotReserved = Color(0xFFF59E0B);
  static const Color slotBooked = Color(0xFFEF4444);
  static const Color slotBlocked = Color(0xFF94A3B8);

  // Payment Status Colors
  static const Color paymentPaid = Color(0xFF22C55E);
  static const Color paymentPending = Color(0xFFF59E0B);
  static const Color paymentFailed = Color(0xFFEF4444);

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient scaffoldGradient = LinearGradient(
    colors: [Color(0xFFF5F7FB), Color(0xFFF5F7FB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static List<BoxShadow> neonGlow({Color? color, double blur = 18, double spread = 0}) {
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // ============================================================
  // DARK THEME PALETTE — Soft dark with lavender accent
  // ============================================================

  static const Color dPrimary = Color(0xFFA78BFA);       // Lavender
  static const Color dPrimaryLight = Color(0xFF2D2640);   // Muted purple bg
  static const Color dPrimaryDark = Color(0xFF8B5CF6);    // Deeper purple

  static const Color dSecondary = Color(0xFF6EE7B7);      // Soft mint
  static const Color dSecondaryLight = Color(0xFF1A2E28);
  static const Color dSecondaryDark = Color(0xFF34D399);

  static const Color dSuccess = Color(0xFF34D399);
  static const Color dSuccessLight = Color(0xFF1A2E28);
  static const Color dWarning = Color(0xFFFBBF24);
  static const Color dWarningLight = Color(0xFF2E2A1A);
  static const Color dError = Color(0xFFF87171);
  static const Color dErrorLight = Color(0xFF2E1A1A);
  static const Color dInfo = Color(0xFF93C5FD);
  static const Color dInfoLight = Color(0xFF1A2240);

  static const Color dBackground = Color(0xFF1A1B2E);     // Soft dark navy
  static const Color dSurface = Color(0xFF222336);         // Card containers
  static const Color dCardBackground = Color(0xFF262840);  // Elevated cards
  static const Color dInputBackground = Color(0xFF1E1F32);
  static const Color dInputBorder = Color(0xFF363952);

  static const Color dTextPrimary = Color(0xFFE2E8F0);    // Soft white
  static const Color dTextSecondary = Color(0xFF94A3B8);   // Muted
  static const Color dTextHint = Color(0xFF64748B);
  static const Color dTextDisabled = Color(0xFF475569);

  static const Color dDivider = Color(0xFF2D3044);
  static const Color dBorder = Color(0xFF2D3044);
  static const Color dChipBackground = Color(0xFF2D2640);
  static const Color dShimmerBase = Color(0xFF2D3044);
  static const Color dShimmerHighlight = Color(0xFF363952);

  static const Color dGlassBorder = Color(0xFF2D3044);
  static const Color dGlassFill = Color(0xFF262840);
  static const Color dGlassHighlight = Color(0xFF2D3044);

  static const LinearGradient dPrimaryGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dSplashGradient = LinearGradient(
    colors: [Color(0xFF1A1B2E), Color(0xFF222336)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dScaffoldGradient = LinearGradient(
    colors: [Color(0xFF1A1B2E), Color(0xFF1A1B2E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Section container gradients
  static const LinearGradient dSectionGradient = LinearGradient(
    colors: [Color(0xFF2D2640), Color(0xFF262840)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get dCardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // ============================================================
  // ADAPTIVE COLOR RESOLVER
  // ============================================================

  /// Get adaptive colors based on current theme brightness.
  static AdaptiveColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkColors : lightColors;
  }

  static final AdaptiveColors lightColors = AdaptiveColors(
    primary: primary,
    primaryLight: primaryLight,
    primaryDark: primaryDark,
    secondary: secondary,
    secondaryLight: secondaryLight,
    success: success,
    successLight: successLight,
    warning: warning,
    warningLight: warningLight,
    error: error,
    errorLight: errorLight,
    info: info,
    infoLight: infoLight,
    background: background,
    surface: surface,
    cardBackground: cardBackground,
    inputBackground: inputBackground,
    inputBorder: inputBorder,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textHint: textHint,
    textDisabled: textDisabled,
    divider: divider,
    border: border,
    chipBackground: chipBackground,
    shimmerBase: shimmerBase,
    shimmerHighlight: shimmerHighlight,
    glassBorder: glassBorder,
    glassFill: glassFill,
    glassHighlight: glassHighlight,
    primaryGradient: primaryGradient,
    scaffoldGradient: scaffoldGradient,
    sectionGradient: const LinearGradient(
      colors: [Color(0xFFAFC6FF), Color(0xFFD7E4FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    sectionBorder: const Color(0xFFC2D5FF),
    cardShadow: cardShadow,
    onPrimary: Colors.white,
  );

  static final AdaptiveColors darkColors = AdaptiveColors(
    primary: dPrimary,
    primaryLight: dPrimaryLight,
    primaryDark: dPrimaryDark,
    secondary: dSecondary,
    secondaryLight: dSecondaryLight,
    success: dSuccess,
    successLight: dSuccessLight,
    warning: dWarning,
    warningLight: dWarningLight,
    error: dError,
    errorLight: dErrorLight,
    info: dInfo,
    infoLight: dInfoLight,
    background: dBackground,
    surface: dSurface,
    cardBackground: dCardBackground,
    inputBackground: dInputBackground,
    inputBorder: dInputBorder,
    textPrimary: dTextPrimary,
    textSecondary: dTextSecondary,
    textHint: dTextHint,
    textDisabled: dTextDisabled,
    divider: dDivider,
    border: dBorder,
    chipBackground: dChipBackground,
    shimmerBase: dShimmerBase,
    shimmerHighlight: dShimmerHighlight,
    glassBorder: dGlassBorder,
    glassFill: dGlassFill,
    glassHighlight: dGlassHighlight,
    primaryGradient: dPrimaryGradient,
    scaffoldGradient: dScaffoldGradient,
    sectionGradient: dSectionGradient,
    sectionBorder: const Color(0xFF363952),
    cardShadow: dCardShadow,
    onPrimary: Colors.white,
  );
}

/// Holds all semantic colors for one theme mode.
class AdaptiveColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color secondary;
  final Color secondaryLight;
  final Color success;
  final Color successLight;
  final Color warning;
  final Color warningLight;
  final Color error;
  final Color errorLight;
  final Color info;
  final Color infoLight;
  final Color background;
  final Color surface;
  final Color cardBackground;
  final Color inputBackground;
  final Color inputBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textDisabled;
  final Color divider;
  final Color border;
  final Color chipBackground;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color glassBorder;
  final Color glassFill;
  final Color glassHighlight;
  final LinearGradient primaryGradient;
  final LinearGradient scaffoldGradient;
  final LinearGradient sectionGradient;
  final Color sectionBorder;
  final List<BoxShadow> cardShadow;
  final Color onPrimary;

  const AdaptiveColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryLight,
    required this.success,
    required this.successLight,
    required this.warning,
    required this.warningLight,
    required this.error,
    required this.errorLight,
    required this.info,
    required this.infoLight,
    required this.background,
    required this.surface,
    required this.cardBackground,
    required this.inputBackground,
    required this.inputBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textDisabled,
    required this.divider,
    required this.border,
    required this.chipBackground,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.glassBorder,
    required this.glassFill,
    required this.glassHighlight,
    required this.primaryGradient,
    required this.scaffoldGradient,
    required this.sectionGradient,
    required this.sectionBorder,
    required this.cardShadow,
    required this.onPrimary,
  });
}
