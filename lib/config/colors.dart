import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors - Modern Green Theme (for Sports/Turf)
  static const Color primary = Color(0xFF2E7D32);           // Forest Green
  static const Color primaryLight = Color(0xFF60AD5E);
  static const Color primaryDark = Color(0xFF005005);
  
  // Secondary Colors - Accent
  static const Color secondary = Color(0xFFFF6B35);         // Vibrant Orange
  static const Color secondaryLight = Color(0xFFFF9D66);
  static const Color secondaryDark = Color(0xFFC53A00);
  
  // Success / Available
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  
  // Warning / Reserved
  static const Color warning = Color(0xFFFFC107);
  static const Color warningLight = Color(0xFFFFF8E1);
  
  // Error / Booked
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFFFEBEE);
  
  // Info
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD);
  
  // Background Colors - Light Theme
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color inputBackground = Color(0xFFF8F9FA);
  static const Color inputBorder = Color(0xFFE0E0E0);
  
  // Background Colors - Dark Theme
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkCardBackground = Color(0xFF2D2D2D);
  
  // Text Colors - Light Theme
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFBDBDBD);
  
  // Text Colors - Dark Theme
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFFB0B0B0);
  
  // UI Elements
  static const Color divider = Color(0xFFE0E0E0);
  static const Color disabled = Color(0xFFE0E0E0);
  static const Color chipBackground = Color(0xFFE8F5E9);
  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  
  // Slot Status Colors
  static const Color slotAvailable = Color(0xFF4CAF50);
  static const Color slotReserved = Color(0xFFFFC107);
  static const Color slotBooked = Color(0xFFE53935);
  static const Color slotBlocked = Color(0xFF9E9E9E);
  
  // Payment Status Colors
  static const Color paymentPaid = Color(0xFF4CAF50);
  static const Color paymentPending = Color(0xFFFFC107);
  static const Color paymentFailed = Color(0xFFE53935);
  
  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFFB347)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
