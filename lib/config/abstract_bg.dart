import 'package:flutter/material.dart';
import 'colors.dart';

/// Decorative layered organic wave / blob background.
/// Inspired by overlapping curved shapes that flow across the screen.
/// Uses only the app blue palette at subtle opacities.
class AbstractBgShapes extends StatelessWidget {
  const AbstractBgShapes({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _WaveBlobPainter(),
      ),
    );
  }
}

class _WaveBlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // --- Layer 1: large blob flowing from top-right to mid-left ---
    final p1 = Path()
      ..moveTo(w * 0.35, 0)
      ..quadraticBezierTo(w * 1.05, h * 0.08, w * 1.0, h * 0.38)
      ..quadraticBezierTo(w * 0.95, h * 0.55, w * 0.45, h * 0.48)
      ..quadraticBezierTo(w * -0.05, h * 0.40, w * 0.0, h * 0.15)
      ..quadraticBezierTo(w * 0.03, 0, w * 0.35, 0)
      ..close();

    canvas.drawPath(
      p1,
      Paint()
        ..color = AppColors.primary.withOpacity(0.06)
        ..style = PaintingStyle.fill,
    );

    // --- Layer 2: mid-screen organic curve from left ---
    final p2 = Path()
      ..moveTo(0, h * 0.30)
      ..quadraticBezierTo(w * 0.25, h * 0.22, w * 0.55, h * 0.35)
      ..quadraticBezierTo(w * 0.90, h * 0.50, w * 0.80, h * 0.68)
      ..quadraticBezierTo(w * 0.70, h * 0.82, w * 0.30, h * 0.72)
      ..quadraticBezierTo(w * -0.10, h * 0.60, 0, h * 0.30)
      ..close();

    canvas.drawPath(
      p2,
      Paint()
        ..color = AppColors.primary.withOpacity(0.045)
        ..style = PaintingStyle.fill,
    );

    // --- Layer 3: bottom-right wave flowing upward ---
    final p3 = Path()
      ..moveTo(w * 0.50, h)
      ..quadraticBezierTo(w * 1.15, h * 0.85, w, h * 0.60)
      ..quadraticBezierTo(w * 0.88, h * 0.50, w * 0.60, h * 0.58)
      ..quadraticBezierTo(w * 0.30, h * 0.68, w * 0.20, h * 0.82)
      ..quadraticBezierTo(w * 0.12, h * 0.95, w * 0.50, h)
      ..close();

    canvas.drawPath(
      p3,
      Paint()
        ..color = AppColors.primaryDark.withOpacity(0.05)
        ..style = PaintingStyle.fill,
    );

    // --- Layer 4: small accent blob top-left ---
    final p4 = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.30, 0)
      ..quadraticBezierTo(w * 0.28, h * 0.12, w * 0.12, h * 0.18)
      ..quadraticBezierTo(w * -0.02, h * 0.20, 0, h * 0.10)
      ..close();

    canvas.drawPath(
      p4,
      Paint()
        ..color = AppColors.primary.withOpacity(0.07)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
