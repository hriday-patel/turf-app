import 'package:flutter/material.dart';
import 'colors.dart';

// ═══════════════════════════════════════════════════════════════
//  CLEAN UI COMPONENT LIBRARY
//  Simple, modern widgets for the light SaaS theme.
// ═══════════════════════════════════════════════════════════════

/// Screen background wrapper — flat color, no gradient.
class GlassScaffoldBackground extends StatelessWidget {
  final Widget child;
  const GlassScaffoldBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: child,
    );
  }
}

/// Clean white card with subtle shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool glowBorder;
  final Color? glowColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.glowBorder = false,
    this.glowColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.cardShadow,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

/// Primary action button.
class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? color;
  final bool outlined;
  final double height;
  final double borderRadius;

  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
    this.outlined = false,
    this.height = 50,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;

    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: isLoading ? _loader(accent) : _content(accent),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading ? _loader(Colors.white) : _content(Colors.white),
      ),
    );
  }

  Widget _loader(Color c) => SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: c),
      );

  Widget _content(Color c) {
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c)),
        ],
      );
    }
    return Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c));
  }
}

/// Clean text field.
class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int? maxLength;
  final bool enabled;
  final TextAlign textAlign;
  final TextStyle? style;
  final String? prefixText;
  final TextStyle? prefixStyle;
  final int maxLines;

  const GlassTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.maxLength,
    this.enabled = true,
    this.textAlign = TextAlign.start,
    this.style,
    this.prefixText,
    this.prefixStyle,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      maxLength: maxLength,
      enabled: enabled,
      textAlign: textAlign,
      maxLines: maxLines,
      style: style ?? const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20) : null,
        suffixIcon: suffix,
        prefixText: prefixText,
        prefixStyle: prefixStyle ?? const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }
}

/// Section header text.
class GlassSectionTitle extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const GlassSectionTitle(this.title, {super.key, this.padding = const EdgeInsets.only(bottom: 14)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Simple divider.
class GlassDivider extends StatelessWidget {
  const GlassDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppColors.divider, height: 24, thickness: 1);
  }
}

/// Clean AppBar widget.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showBack;
  final Widget? leading;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.showBack = true,
    this.leading,
  });

  @override
  Size get preferredSize => Size.fromHeight(bottom != null ? 100 : 56);

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      backgroundColor: AppColors.surface,
      elevation: 0,
      centerTitle: true,
      leading: leading ??
          (showBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
                  onPressed: () => Navigator.pop(context),
                )
              : null),
      actions: actions,
      bottom: bottom,
    );
    return SizedBox(
      height: preferredSize.height,
      child: appBar,
    );
  }
}
