import 'package:flutter/material.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../../core/constants/strings.dart';
import '../../../app/routes.dart';

/// Phase 5 Iter 18 LS-09: Login selection screen.
///
/// Entry point after splash for unauthenticated users. Shows branding +
/// feature highlights and routes to:
///   * [AppRoutes.playerAuth] via the primary button (player-first UX)
///   * [AppRoutes.ownerAuth] via the secondary "turf owner" link
/// Rapid double-taps are guarded to prevent duplicate route pushes.
class LoginSelectionScreen extends StatefulWidget {
  const LoginSelectionScreen({super.key});

  @override
  State<LoginSelectionScreen> createState() => _LoginSelectionScreenState();
}

/// Phase 5 Iter 18 LS-02: static highlight data — keeps the build method
/// declarative and makes future additions (new feature row) a one-line
/// change rather than a copy-paste.
class _Feature {
  const _Feature(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

const List<_Feature> _features = <_Feature>[
  _Feature(
    Icons.calendar_today_outlined,
    AppStrings.loginSelectionFeatureBookingTitle,
    AppStrings.loginSelectionFeatureBookingSubtitle,
  ),
  _Feature(
    Icons.payments_outlined,
    AppStrings.loginSelectionFeaturePaymentsTitle,
    AppStrings.loginSelectionFeaturePaymentsSubtitle,
  ),
  _Feature(
    Icons.location_on_outlined,
    AppStrings.loginSelectionFeatureNearbyTitle,
    AppStrings.loginSelectionFeatureNearbySubtitle,
  ),
];

class _LoginSelectionScreenState extends State<LoginSelectionScreen> {
  // Phase 5 Iter 18 LS-01: single-shot nav guard against rapid double-taps.
  bool _isNavigating = false;

  Future<void> _navigate(String route) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.pushNamed(context, route);
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            // Phase 5 Iter 18 LS-07: isolate background repaints from the
            // interactive foreground subtree.
            const RepaintBoundary(child: AbstractBgShapes()),
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
        // App Icon — glass + neon glow.
        // Phase 5 Iter 18 LS-04: a11y label for the brand icon.
        Semantics(
          label: '${AppStrings.appName} logo',
          image: true,
          child: Container(
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
      onPressed: () => _navigate(AppRoutes.playerAuth),
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
            AppStrings.loginSelectionQuickFeatures,
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
    // Phase 5 Iter 18 LS-02: iterate over the static feature list.
    final rows = <Widget>[];
    for (var i = 0; i < _features.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 16));
      rows.add(_buildFeatureRow(context, _features[i]));
    }
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: rows),
    );
  }

  Widget _buildFeatureRow(BuildContext context, _Feature feature) {
    final c = AppColors.of(context);
    return Row(
      children: [
        // Phase 5 Iter 18 LS-05: decorative icon, exclude from semantics —
        // the text row already conveys the feature.
        ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.primary.withValues(alpha: 0.15)),
            ),
            child: Icon(feature.icon, color: c.primary, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feature.subtitle,
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
          AppStrings.loginSelectionOwnerPrompt,
          style: TextStyle(
            fontSize: 14,
            color: c.textSecondary,
          ),
        ),
        // Phase 5 Iter 18 LS-06: expand tap target vertically to ≥48dp.
        TextButton(
          onPressed: () => _navigate(AppRoutes.ownerAuth),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            minimumSize: const Size(64, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
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
