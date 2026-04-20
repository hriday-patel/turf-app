import 'package:flutter/material.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../../core/constants/strings.dart';
import '../../../app/routes.dart';

/// Login Selection Screen
/// Allows users to choose between Player or Owner login
class LoginSelectionScreen extends StatelessWidget {
  const LoginSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const AbstractBgShapes(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 1),

                    // App Branding
                    _buildBranding(context),

                    const Spacer(flex: 1),

                    // Player Login Button (Primary)
                    _buildPlayerButton(context),

                    const SizedBox(height: 16),

                    // OR Divider
                    _buildDivider(context),

                    const SizedBox(height: 16),

                    // Feature Highlights
                    _buildFeatureHighlights(context),

                    const Spacer(flex: 2),

                    // Owner Login Link
                    _buildOwnerLink(context),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranding(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        // App Icon — glass + neon glow
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: c.glassFill,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.primary.withValues(alpha: 0.3)),
            boxShadow: AppColors.neonGlow(blur: 24, spread: 1),
          ),
          child: Icon(
            Icons.sports_cricket,
            size: 50,
            color: c.primary,
          ),
        ),
        const SizedBox(height: 24),

        // App Name
        Text(
          AppStrings.appName,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: c.textPrimary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),

        // Tagline
        Text(
          AppStrings.appTagline,
          style: TextStyle(
            fontSize: 14,
            color: c.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlayerButton(BuildContext context) {
    return GlassButton(
      label: AppStrings.loginAsPlayer,
      icon: Icons.person_outline,
      onPressed: () => Navigator.pushNamed(context, AppRoutes.playerAuth),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: c.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Quick Features',
            style: TextStyle(
              fontSize: 12,
              color: c.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: c.divider)),
      ],
    );
  }

  Widget _buildFeatureHighlights(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildFeatureRow(
            context,
            Icons.calendar_today_outlined,
            'Easy Slot Booking',
            'Book your favorite turf in seconds',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            context,
            Icons.payments_outlined,
            'Flexible Payments',
            'Pay online or at the turf',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            context,
            Icons.location_on_outlined,
            'Nearby Turfs',
            'Find turfs near your location',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
      BuildContext context, IconData icon, String title, String subtitle) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.primary.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: c.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerLink(BuildContext context) {
    final c = AppColors.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Are you a turf owner? ',
          style: TextStyle(
            fontSize: 14,
            color: c.textSecondary,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.ownerAuth),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            AppStrings.loginAsOwner,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.primary,
            ),
          ),
        ),
      ],
    );
  }
}
