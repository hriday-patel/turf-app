import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../../../app/routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';

/// Verification Pending Screen
/// Shown after owner submits a new turf for verification
class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
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
  
  void _refreshTurfs() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    if (authProvider.currentUserId != null) {
      turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              // Success Animation Container
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hourglass_top_rounded,
                      size: 50,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Title
              const Text(
                'Verification Pending',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Description
              Text(
                AppStrings.verificationMessage,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.timer_outlined,
                      'Typical Review Time',
                      '24-48 hours',
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      Icons.notifications_outlined,
                      'Notification',
                      "We'll notify you once approved",
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      Icons.support_agent_outlined,
                      'Need Help?',
                      'Contact our support team',
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Go to Dashboard Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    // Refresh data before navigating to dashboard
                    _refreshTurfs();
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.ownerDashboard,
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    AppStrings.goToDashboard,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Add Another Turf
              TextButton(
                onPressed: () {
                  // Use push instead of pushReplacement so back navigation works
                  Navigator.pushNamed(context, AppRoutes.addTurf);
                },
                child: const Text(
                  'Add Another Turf',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
