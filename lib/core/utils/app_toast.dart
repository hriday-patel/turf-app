import 'package:flutter/material.dart';

enum ToastType { success, error, warning, info }

void showAppToast(BuildContext context, String message, {ToastType type = ToastType.info}) {
  Color bg, border, textColor;
  IconData icon;

  switch (type) {
    case ToastType.success:
      bg = const Color(0xFFECFDF5);
      border = const Color(0xFF22C55E);
      textColor = const Color(0xFF166534);
      icon = Icons.check_circle_rounded;
    case ToastType.error:
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFEF4444);
      textColor = const Color(0xFF991B1B);
      icon = Icons.error_outline_rounded;
    case ToastType.warning:
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFF59E0B);
      textColor = const Color(0xFF92400E);
      icon = Icons.warning_amber_rounded;
    case ToastType.info:
      bg = const Color(0xFFEFF6FF);
      border = const Color(0xFF3B82F6);
      textColor = const Color(0xFF1D4ED8);
      icon = Icons.info_outline_rounded;
  }

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: const Duration(seconds: 3),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: border, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
