import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';

/// Phase 5 Iter 17 SS-10: Splash screen — app entry point.
///
/// Routing matrix (applied in order):
///   1. Live session + [UserRole.owner]  -> owner dashboard
///   2. Live session + [UserRole.player] -> player home
///   3. Pending non-expired signup       -> owner/player auth screen
///   4. Anything else (including admin,
///      expired pending, errors)         -> login selection
///
/// Auth-check races a minimum-splash delay so we never block longer
/// than the auth check itself (SS-03).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Phase 5 Iter 17 SS-06/SS-07: tightened animation — 800ms full range,
  // driven by FadeTransition/ScaleTransition instead of AnimatedBuilder.
  static const Duration _animationDuration = Duration(milliseconds: 800);
  static const Duration _minimumSplashDuration = Duration(milliseconds: 1200);

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  // Phase 5 Iter 17 SS-05: single-shot nav guard.
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkAuth();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _animationController.forward();
  }

  /// Phase 5 Iter 17 SS-03: race minimum splash against auth check; whichever
  /// takes longer wins. Means auth-checks >1.2s never pay a double-wait.
  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final minSplash = Future<void>.delayed(_minimumSplashDuration);

    // Phase 5 Iter 17 SS-01: catch unexpected failures so the user is never
    // stuck on splash forever. Any error routes to login selection.
    try {
      await Future.wait<void>([
        authProvider.checkAuthState(),
        minSplash,
      ]);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SplashScreen] auth check failed: $e\n$st');
      }
      await _safeNavigate(AppRoutes.loginSelection);
      return;
    }

    if (!mounted) return;

    final hasSession = authProvider.currentUserId != null;
    if (!hasSession) {
      await _safeNavigate(AppRoutes.loginSelection);
      return;
    }

    final role = authProvider.currentUserRole;
    if (role == UserRole.owner) {
      await _safeNavigate(AppRoutes.ownerDashboard);
      return;
    }

    if (role == UserRole.player) {
      await _safeNavigate(AppRoutes.playerHome);
      return;
    }

    // Phase 5 Iter 17 SS-02: resume live pending signup if still valid.
    if (authProvider.hasPendingSignup && !authProvider.isPendingSignupExpired) {
      if (authProvider.pendingSignupRole == UserRole.owner) {
        await _safeNavigate(AppRoutes.ownerAuth);
        return;
      }
      if (authProvider.pendingSignupRole == UserRole.player) {
        await _safeNavigate(AppRoutes.playerAuth);
        return;
      }
    }

    // Phase 5 Iter 17 SS-04: admin, expired pending, or stale session fall
    // through here. We sign out defensively so no stale cookies/tokens linger,
    // but route regardless even if signOut throws.
    try {
      await authProvider.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('[SplashScreen] signOut failed: $e');
    }
    await _safeNavigate(AppRoutes.loginSelection);
  }

  /// Phase 5 Iter 17 SS-05: idempotent navigation guard.
  Future<void> _safeNavigate(String route) async {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    Navigator.pushReplacementNamed(context, route);
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

              // Phase 5 Iter 17 SS-07: FadeTransition + ScaleTransition are
              // lighter than AnimatedBuilder; they only rebuild their own
              // RenderObject instead of the whole subtree each frame.
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    children: [
                      // App Icon — glass card with neon glow.
                      // Phase 5 Iter 17 SS-08: a11y label for the brand icon.
                      Semantics(
                        label: '${AppStrings.appName} logo',
                        image: true,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: c.glassFill,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                                color: c.primary.withValues(alpha: 0.3)),
                            boxShadow: AppColors.neonGlow(blur: 28, spread: 2),
                          ),
                          child: Icon(
                            Icons.sports_cricket,
                            size: 60,
                            color: c.primary,
                          ),
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
              ),

              const Spacer(),

              // Phase 5 Iter 17 SS-09: announce loading state to screen readers.
              Semantics(
                label: 'Loading',
                liveRegion: true,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                  ),
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
