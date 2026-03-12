import 'package:flutter/material.dart';
import '../../config/colors.dart';

enum ToastType { success, error, warning, info }

void showAppToast(BuildContext context, String message, {ToastType type = ToastType.info}) {
  final c = AppColors.of(context);
  Color bg, border, textColor;
  IconData icon;

  switch (type) {
    case ToastType.success:
      bg = c.successLight;
      border = c.success;
      textColor = c.success;
      icon = Icons.check_circle_rounded;
    case ToastType.error:
      bg = c.errorLight;
      border = c.error;
      textColor = c.error;
      icon = Icons.error_outline_rounded;
    case ToastType.warning:
      bg = c.warningLight;
      border = c.warning;
      textColor = c.warning;
      icon = Icons.warning_amber_rounded;
    case ToastType.info:
      bg = c.infoLight;
      border = c.info;
      textColor = c.info;
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
              color: Colors.black.withValues(alpha: 0.08),
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
