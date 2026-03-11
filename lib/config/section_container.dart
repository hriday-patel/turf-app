import 'package:flutter/material.dart';

/// Premium SaaS-style gradient section container.
/// Wraps dashboard sections with a visible rounded gradient background.
class SectionContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;

  const SectionContainer({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFAFC6FF), Color(0xFFD7E4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFC2D5FF), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Variant with a downward central notch on the top edge,
/// styled like a transaction / statistics panel.
class NotchedSectionContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;

  const NotchedSectionContainer({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipPath(
        clipper: _NotchClipper(),
        child: Container(
          padding: padding.add(const EdgeInsets.only(top: 18)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFAFC6FF), Color(0xFFD7E4FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Clips a smooth downward notch/dip at the top-center of the container.
class _NotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const double r = 28;
    const double notchW = 80;
    const double notchD = 16;

    final path = Path();

    // Bottom-left corner
    path.moveTo(0, size.height - r);
    path.quadraticBezierTo(0, size.height, r, size.height);

    // Bottom edge
    path.lineTo(size.width - r, size.height);

    // Bottom-right corner
    path.quadraticBezierTo(size.width, size.height, size.width, size.height - r);

    // Right edge
    path.lineTo(size.width, r);

    // Top-right corner
    path.quadraticBezierTo(size.width, 0, size.width - r, 0);

    // Top edge – right side leading to notch
    final notchStart = (size.width - notchW) / 2;
    final notchEnd = (size.width + notchW) / 2;
    path.lineTo(notchEnd, 0);

    // Downward dip
    path.quadraticBezierTo(size.width / 2, notchD * 2, notchStart, 0);

    // Top edge – left side
    path.lineTo(r, 0);

    // Top-left corner
    path.quadraticBezierTo(0, 0, 0, r);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
