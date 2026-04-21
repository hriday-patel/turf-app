import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';

/// Splash Screen - App entry point
/// Shows branding and checks authentication status
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkAuth();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();
  }

  Future<void> _checkAuth() async {
    // Wait for animation and minimum splash time
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkAuthState();

    if (!mounted) return;

    final hasSession = authProvider.currentUserId != null;
    if (!hasSession) {
      Navigator.pushReplacementNamed(context, AppRoutes.loginSelection);
      return;
    }

    if (authProvider.currentUserRole == UserRole.owner) {
      Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
      return;
    }

    if (authProvider.currentUserRole == UserRole.player) {
      Navigator.pushReplacementNamed(context, AppRoutes.playerHome);
      return;
    }

    if (authProvider.hasPendingSignup && !authProvider.isPendingSignupExpired) {
      if (authProvider.pendingSignupRole == UserRole.owner) {
        Navigator.pushReplacementNamed(context, AppRoutes.ownerAuth);
        return;
      }
      if (authProvider.pendingSignupRole == UserRole.player) {
        Navigator.pushReplacementNamed(context, AppRoutes.playerAuth);
        return;
      }
    }

    await authProvider.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.loginSelection);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: c.scaffoldGradient,
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo and App Name
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    // App Icon — glass card with neon glow
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: c.glassFill,
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: c.primary.withValues(alpha: 0.3)),
                        boxShadow: AppColors.neonGlow(blur: 28, spread: 2),
                      ),
                      child: Icon(
                        Icons.sports_cricket,
                        size: 60,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // App Name
                    Text(
                      AppStrings.appName,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tagline
                    Text(
                      AppStrings.appTagline,
                      style: TextStyle(
                        fontSize: 16,
                        color: c.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Loading Indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
