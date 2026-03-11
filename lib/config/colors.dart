import 'package:flutter/material.dart';

class AppColors {
  // ============================================================
  // CLEAN MODERN LIGHT THEME
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

  // ── Glass surface helpers (now mapped to light equivalents) ──
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

  // ── Gradients (kept for compat, now subtle) ──
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

  /// Scaffold background — flat color via gradient for compat.
  static const LinearGradient scaffoldGradient = LinearGradient(
    colors: [Color(0xFFF5F7FB), Color(0xFFF5F7FB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Subtle card shadow (replaces neonGlow).
  static List<BoxShadow> neonGlow({Color? color, double blur = 18, double spread = 0}) {
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Standard subtle card shadow.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withOpacity(0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}
