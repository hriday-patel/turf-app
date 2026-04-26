import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../../../app/routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';

/// Verification Pending Screen
/// Shown after owner submits a new turf for verification
class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh turfs when this screen loads to ensure data is up to date
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTurfs();
    });
  }

  Future<void> _refreshTurfs() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId == null) return;
    try {
      turfProvider.loadOwnerTurfs(userId);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString(), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Hourglass icon with neon glow
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: c.secondary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: c.secondary.withValues(alpha: 0.15)),
                    boxShadow: AppColors.neonGlow(color: c.secondary, blur: 24),
                  ),
                  child: Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: c.secondary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.hourglass_top_rounded,
                        size: 50,
                        color: c.secondary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                Text(
                  AppStrings.verificationPendingTitle,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                Text(
                  AppStrings.verificationMessage,
                  style: TextStyle(
                    fontSize: 15,
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Info Card — glass
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildInfoRow(
                        Icons.timer_outlined,
                        AppStrings.verificationPendingReviewTimeLabel,
                        AppStrings.verificationPendingReviewTimeValue,
                      ),
                      const GlassDivider(),
                      _buildInfoRow(
                        Icons.notifications_outlined,
                        AppStrings.verificationPendingNotifyLabel,
                        AppStrings.verificationPendingNotifyValue,
                      ),
                      const GlassDivider(),
                      _buildInfoRow(
                        Icons.support_agent_outlined,
                        AppStrings.verificationPendingHelpLabel,
                        AppStrings.verificationPendingHelpValue,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Tooltip(
                  message: AppStrings.verificationPendingTooltipDashboard,
                  child: GlassButton(
                    label: AppStrings.goToDashboard,
                    onPressed: () {
                      _refreshTurfs();
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRoutes.ownerDashboard,
                        (route) => false,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                Tooltip(
                  message: AppStrings.verificationPendingTooltipAddAnother,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.addTurf),
                    child: Text(
                      AppStrings.verificationPendingAddAnother,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
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
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: c.textSecondary, size: 18),
      ],
    );
  }
}
