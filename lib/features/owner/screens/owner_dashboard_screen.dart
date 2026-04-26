import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/section_container.dart';
import '../../../config/theme_provider.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../../../app/routes.dart';
import '../../../data/models/booking_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';
import '../providers/booking_provider.dart';

/// Owner Dashboard Screen.
///
/// Central hub for turf owners to manage their business. Phase 5 Iter 24
/// hardening:
///   * RouteAware + WidgetsBindingObserver: refreshes on push/pop/resume.
///   * Phone-gate overlay (`_buildPhoneVerificationLock`) blocks dashboard
///     interaction until owner phone OTP is verified. Used both for normal
///     onboarding and for the deferred (Google) signup flow — handled via
///     [AuthProvider.completeDeferredOwnerSignup].
///   * Quick Overview carousel uses an infinite-loop trick (large multiplier
///     around an initial midpoint). Scale/opacity per-page is driven by a
///     [ValueNotifier<double>] so only the carousel rebuilds on scroll, not
///     the whole scaffold.
///   * Auto-slide is a cancellable [Timer.periodic]; pause-on-drag uses a
///     stored Timer so dispose can cancel it.
///   * Quick Action cards animate in via a single [AnimationController].
///   * `_phoneGateError` (red) and `_phoneGateInfo` (success/info) are
///     separate fields — earlier code overloaded a single field which made
///     the resend-success message render in error styling.
///   * Logout failures surface a toast instead of silently leaving the
///     dialog open.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  static final RegExp _phoneRe = RegExp(r'^\d{10}$');
  static final RegExp _otpRe = RegExp(r'^\d{6}$');
  static const List<String> _monthShortNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const List<String> _weekdayShortNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  late final PageController _carouselController;
  final ValueNotifier<double> _carouselPageNotifier = ValueNotifier(0);
  Timer? _autoSlideTimer;
  Timer? _autoSlideResumeTimer;
  Timer? _resendInfoTimer;

  // Quick Actions staggered entrance animation
  late final AnimationController _actionAnimController;
  late final List<Animation<double>> _actionFadeAnims;
  late final List<Animation<Offset>> _actionSlideAnims;
  static const int _carouselRealCount = 4;
  // Large multiplier for infinite loop illusion
  static const int _carouselLoopMultiplier = 1000;
  static const int _carouselInitialPage =
      _carouselLoopMultiplier ~/ 2 * _carouselRealCount;

  final TextEditingController _phoneGatePhoneController =
      TextEditingController();
  final TextEditingController _phoneGateOtpController = TextEditingController();
  bool _phoneGateOtpSent = false;
  bool _phoneGateBusy = false;
  String? _phoneGateError;
  String? _phoneGateInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carouselController = PageController(
      viewportFraction: 0.80,
      initialPage: _carouselInitialPage,
    );
    _carouselPageNotifier.value = _carouselInitialPage.toDouble();
    _carouselController.addListener(() {
      // OD-04: only the carousel listens to this notifier; the rest of the
      // screen does not rebuild on every scroll frame.
      _carouselPageNotifier.value = _carouselController.page ?? 0;
    });
    _startAutoSlide();

    // Staggered animation for 4 Quick Action cards (350ms each, staggered)
    _actionAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _actionFadeAnims = List.generate(4, (i) {
      final start = i * 0.15;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _actionAnimController,
            curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _actionSlideAnims = List.generate(4, (i) {
      final start = i * 0.15;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 10), end: Offset.zero)
          .animate(
        CurvedAnimation(
            parent: _actionAnimController,
            curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _actionAnimController.forward();

    // OD-12 / OD-20: collapse the two postFrameCallbacks; _forceRefreshData
    // already covers what _loadData did.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.ensureOwnerReadyForDashboard();
      _forceRefreshData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRoutes.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _autoSlideResumeTimer?.cancel();
    _resendInfoTimer?.cancel();
    _actionAnimController.dispose();
    _phoneGatePhoneController.dispose();
    _phoneGateOtpController.dispose();
    _carouselPageNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppRoutes.routeObserver.unsubscribe(this);
    _carouselController.dispose();
    super.dispose();
  }

  String _normalizeToE164Indian(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (raw.startsWith('+') && digits.length >= 10) return raw;
    return '';
  }

  String _displayIndianNumber(String e164) {
    if (e164.startsWith('+91') && e164.length >= 13) {
      return e164.substring(3);
    }
    return e164;
  }

  void _seedPhoneGateIfNeeded(AuthProvider authProvider) {
    if (_phoneGatePhoneController.text.trim().isNotEmpty) return;

    // Option A: for manual deferred signup, prefill the signup phone.
    if (authProvider.isInDeferredSignupFlow) {
      final deferredPhone = authProvider.deferredSignupPhone;
      if (deferredPhone.isNotEmpty && !deferredPhone.startsWith('pending_')) {
        _phoneGatePhoneController.text = _displayIndianNumber(deferredPhone);
      }
      return;
    }

    final ownerPhone = authProvider.currentOwner?.phone ?? '';
    if (ownerPhone.startsWith('pending_')) return;
    _phoneGatePhoneController.text = _displayIndianNumber(ownerPhone);
  }

  Future<void> _sendPhoneVerificationOtp(AuthProvider authProvider) async {
    final enteredPhone = _phoneGatePhoneController.text.trim();
    if (!_phoneRe.hasMatch(enteredPhone)) {
      setState(() {
        _phoneGateError = AppStrings.phoneGateInvalidPhone;
        _phoneGateInfo = null;
      });
      return;
    }

    setState(() {
      _phoneGateBusy = true;
      _phoneGateError = null;
      _phoneGateInfo = null;
    });

    final normalizedPhone = _normalizeToE164Indian(enteredPhone);

    // Check if phone is already registered to another account
    final phoneError =
        await authProvider.checkPhoneAvailability(normalizedPhone);
    if (!mounted) return;

    if (phoneError != null) {
      setState(() {
        _phoneGateBusy = false;
        _phoneGateError = phoneError;
      });
      return;
    }

    final sent = await authProvider.verifyPhone(normalizedPhone);

    if (!mounted) return;

    setState(() {
      _phoneGateBusy = false;
      _phoneGateOtpSent = sent;
      _phoneGateError = sent
          ? null
          : (authProvider.errorMessage ?? AppStrings.phoneGateOtpSendFailed);
    });
  }

  Future<void> _resendPhoneVerificationOtp(AuthProvider authProvider) async {
    setState(() {
      _phoneGateBusy = true;
      _phoneGateError = null;
      _phoneGateInfo = null;
      _phoneGateOtpController.clear();
    });

    final enteredPhone = _phoneGatePhoneController.text.trim();
    final normalizedPhone = _normalizeToE164Indian(enteredPhone);
    final sent = await authProvider.verifyPhone(normalizedPhone);

    if (!mounted) return;

    setState(() {
      _phoneGateBusy = false;
      if (sent) {
        _phoneGateInfo = AppStrings.phoneGateResendSuccess;
        _phoneGateError = null;
      } else {
        _phoneGateInfo = null;
        _phoneGateError =
            authProvider.errorMessage ?? AppStrings.phoneGateResendFailed;
      }
    });

    // Clear success message after 3 seconds via cancellable Timer.
    if (sent) {
      _resendInfoTimer?.cancel();
      _resendInfoTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (_phoneGateInfo == AppStrings.phoneGateResendSuccess) {
          setState(() => _phoneGateInfo = null);
        }
      });
    }
  }

  Future<void> _verifyPhoneVerificationOtp(AuthProvider authProvider) async {
    final otp = _phoneGateOtpController.text.trim();
    if (!_otpRe.hasMatch(otp)) {
      setState(() {
        _phoneGateError = AppStrings.phoneGateInvalidOtp;
        _phoneGateInfo = null;
      });
      return;
    }

    setState(() {
      _phoneGateBusy = true;
      _phoneGateError = null;
      _phoneGateInfo = null;
    });

    final verified = await authProvider.verifyOTP(otp);
    if (!mounted) return;

    if (verified) {
      // If in deferred signup flow, complete the owner profile creation
      if (authProvider.isInDeferredSignupFlow) {
        final completed = await authProvider.completeDeferredOwnerSignup();
        if (!mounted) return;

        if (!completed) {
          setState(() {
            _phoneGateBusy = false;
            _phoneGateError =
                authProvider.errorMessage ?? AppStrings.phoneGateCompleteFailed;
          });
          return;
        }
      }

      setState(() {
        _phoneGateBusy = false;
        _phoneGateError = null;
        _phoneGateInfo = null;
        _phoneGateOtpSent = false;
        _phoneGateOtpController.clear();
      });
    } else {
      setState(() {
        _phoneGateBusy = false;
        _phoneGateError =
            authProvider.errorMessage ?? AppStrings.phoneGateOtpVerifyFailed;
      });
    }
  }

  Widget _buildPhoneVerificationLock() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final c = AppColors.of(context);
        _seedPhoneGateIfNeeded(authProvider);

        final isGoogleSignup = authProvider.isInDeferredSignupFlow &&
            authProvider.deferredSignupMethod == 'google';
        final hasPhonePrefilled =
            _phoneGatePhoneController.text.trim().isNotEmpty && !isGoogleSignup;

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withValues(alpha: 0.22)),
                ),
              ),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.glassBorder),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.phoneGateTitle,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isGoogleSignup
                                ? AppStrings.phoneGateBodyGoogle
                                : hasPhonePrefilled
                                    ? AppStrings.phoneGateBodyPrefilled
                                    : AppStrings.phoneGateBodyMandatory,
                            style: TextStyle(color: c.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _phoneGatePhoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            enabled: !_phoneGateOtpSent,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            autofillHints: const [
                              AutofillHints.telephoneNumber
                            ],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: AppStrings.phoneGatePhoneLabel,
                              prefixText: '+91 ',
                              hintText: AppStrings.phoneGatePhoneHint,
                              counterText: '',
                            ),
                          ),
                          if (_phoneGateOtpSent) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneGateOtpController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              autofocus: true,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              autofillHints: const [AutofillHints.oneTimeCode],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _phoneGateBusy
                                  ? null
                                  : _verifyPhoneVerificationOtp(authProvider),
                              decoration: const InputDecoration(
                                labelText: AppStrings.phoneGateOtpLabel,
                                hintText: AppStrings.phoneGateOtpHint,
                                counterText: '',
                              ),
                            ),
                          ],
                          if (_phoneGateError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _phoneGateError!,
                              style: TextStyle(
                                  color: c.error, fontWeight: FontWeight.w600),
                            ),
                          ],
                          if (_phoneGateInfo != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _phoneGateInfo!,
                              style: TextStyle(
                                  color: c.success,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _phoneGateBusy
                                      ? null
                                      : () => _phoneGateOtpSent
                                          ? _verifyPhoneVerificationOtp(
                                              authProvider)
                                          : _sendPhoneVerificationOtp(
                                              authProvider),
                                  child: _phoneGateBusy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Text(_phoneGateOtpSent
                                          ? AppStrings.phoneGateVerifyOtp
                                          : AppStrings.phoneGateSendOtp),
                                ),
                              ),
                              if (_phoneGateOtpSent) ...[
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: _phoneGateBusy
                                      ? null
                                      : () {
                                          setState(() {
                                            _phoneGateOtpSent = false;
                                            _phoneGateOtpController.clear();
                                            _phoneGateError = null;
                                            _phoneGateInfo = null;
                                          });
                                        },
                                  child: const Text(
                                      AppStrings.phoneGateEditNumber),
                                ),
                              ],
                            ],
                          ),
                          if (_phoneGateOtpSent) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: _phoneGateBusy
                                    ? null
                                    : () => _resendPhoneVerificationOtp(
                                        authProvider),
                                child: Text(
                                  AppStrings.phoneGateResendOtp,
                                  style: TextStyle(
                                    color: c.secondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _phoneGateBusy
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(
                                            authProvider.isInDeferredSignupFlow
                                                ? AppStrings
                                                    .phoneGateCancelSignupTitle
                                                : AppStrings
                                                    .phoneGateGoBackTitle,
                                          ),
                                          content: Text(
                                            authProvider.isInDeferredSignupFlow
                                                ? AppStrings
                                                    .phoneGateCancelSignupBody
                                                : AppStrings
                                                    .phoneGateGoBackBody,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(
                                                authProvider
                                                        .isInDeferredSignupFlow
                                                    ? AppStrings.phoneGateNo
                                                    : AppStrings
                                                        .ownerDashCancel,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(
                                                authProvider
                                                        .isInDeferredSignupFlow
                                                    ? AppStrings.phoneGateYes
                                                    : AppStrings
                                                        .phoneGateGoBackToLogin,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed ?? false) {
                                        if (authProvider
                                            .isInDeferredSignupFlow) {
                                          await authProvider
                                              .cancelDeferredSignup();
                                        } else {
                                          await authProvider.signOut();
                                        }
                                        if (!mounted) return;
                                        Navigator.pushReplacementNamed(
                                          context,
                                          AppRoutes.ownerAuth,
                                        );
                                      }
                                    },
                              child: Text(
                                  authProvider.isInDeferredSignupFlow
                                      ? AppStrings.phoneGateCancelSignup
                                      : AppStrings.phoneGateBackToLogin,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (_carouselController.hasClients) {
        _carouselController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideResumeTimer?.cancel();
    // Resume after 5 seconds of inactivity (cancellable Timer so dispose is safe).
    _autoSlideResumeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _startAutoSlide();
    });
  }

  @override
  void didPush() {
    // Called when this route has been pushed.
    _forceRefreshData();
  }

  @override
  void didPopNext() {
    // Called when returning to this screen from another screen
    debugPrint('Dashboard: didPopNext - refreshing data');
    _forceRefreshData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes to foreground
      _forceRefreshData();
    }
  }

  Future<void> _forceRefreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    if (authProvider.currentUserId != null) {
      // Force refresh from database to get latest verification status
      await turfProvider.refreshTurfs(authProvider.currentUserId!);

      // Refresh Quick Overview stats for approved turfs
      final approvedTurfIds =
          turfProvider.approvedTurfs.map((t) => t.turfId).toList();
      if (approvedTurfIds.isNotEmpty) {
        bookingProvider.loadTodaysBookings(approvedTurfIds);
        bookingProvider.loadPendingPayments(approvedTurfIds);
      }

      // Refresh Recent Bookings for ALL turfs
      final allTurfIds = turfProvider.turfIds;
      if (allTurfIds.isNotEmpty) {
        bookingProvider.loadRecentBookings(allTurfIds);
      }
    }
  }

  void _refreshBookings() {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    // Load Quick Overview stats for approved turfs
    final approvedTurfIds =
        turfProvider.approvedTurfs.map((t) => t.turfId).toList();
    if (approvedTurfIds.isNotEmpty) {
      bookingProvider.loadTodaysBookings(approvedTurfIds);
      bookingProvider.loadPendingPayments(approvedTurfIds);
    }

    // Load Recent Bookings for ALL turfs
    final allTurfIds = turfProvider.turfIds;
    if (allTurfIds.isNotEmpty) {
      bookingProvider.loadRecentBookings(allTurfIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    // OD-05: only listen to the gate flag here — the rest is read inside
    // the Consumer in `_buildPhoneVerificationLock` so the entire scaffold
    // does not rebuild on every AuthProvider notification.
    final isPhoneLocked = context.select<AuthProvider, bool>(
      (a) => a.requiresOwnerPhoneVerificationGate,
    );

    final c = AppColors.of(context);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: c.background,
          body: GlassScaffoldBackground(
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: _forceRefreshData,
                color: c.primary,
                backgroundColor: c.surface,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildQuickStats()),
                    SliverToBoxAdapter(child: _buildActionCards()),
                    SliverToBoxAdapter(child: _buildRecentActivity()),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: Tooltip(
            message: AppStrings.ownerDashAddTurf,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [c.primary, c.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => Navigator.pushNamed(context, AppRoutes.addTurf),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: c.onPrimary, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.ownerDashAddTurf,
                          style: TextStyle(
                              color: c.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isPhoneLocked) _buildPhoneVerificationLock(),
      ],
    );
  }

  Widget _buildHeader() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final c = AppColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.ownerDashWelcomeBack,
                        style: TextStyle(
                          fontSize: 14,
                          color: c.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authProvider.ownerDisplayName,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Theme toggle
                      Consumer<ThemeProvider>(
                        builder: (context, themeProvider, _) {
                          return Tooltip(
                            message: AppStrings.ownerDashThemeToggleTooltip,
                            child: GestureDetector(
                              onTap: () => themeProvider.toggle(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c.glassFill,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.glassBorder),
                                ),
                                child: Icon(
                                  themeProvider.isDarkMode
                                      ? Icons.light_mode_rounded
                                      : Icons.dark_mode_rounded,
                                  color: c.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        tooltip: AppStrings.ownerDashAccountMenuTooltip,
                        icon: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.glassFill,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: c.primary.withValues(alpha: 0.3)),
                            boxShadow: AppColors.neonGlow(blur: 8),
                          ),
                          child: Center(
                            child: Text(
                              authProvider.ownerDisplayName
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        onSelected: (value) async {
                          if (value == 'settings') {
                            Navigator.pushNamed(context, AppRoutes.settings);
                          } else if (value == 'logout') {
                            final didLogout =
                                await _confirmAndSignOut(authProvider);
                            if (mounted && didLogout) {
                              Navigator.pushReplacementNamed(
                                  context, AppRoutes.loginSelection);
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(children: [
                              Icon(Icons.person_outline,
                                  color: c.textSecondary),
                              const SizedBox(width: 8),
                              Text(AppStrings.ownerDashProfile,
                                  style: TextStyle(color: c.textPrimary))
                            ]),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(children: [
                              Icon(Icons.logout, color: c.error),
                              const SizedBox(width: 8),
                              Text(AppStrings.ownerDashLogout,
                                  style: TextStyle(color: c.error))
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date pill
              GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                borderRadius: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, color: c.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _getFormattedDate(),
                      style: TextStyle(
                          color: c.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _bookingsInitialized = false;

  Future<bool> _confirmAndSignOut(AuthProvider authProvider) async {
    final c = AppColors.of(context);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            bool isLoading = false;

            return StatefulBuilder(
              builder: (dialogContext, setDialogState) {
                return PopScope(
                  canPop: false,
                  child: AlertDialog(
                    title: const Text(AppStrings.ownerDashLogoutConfirmTitle),
                    content: const Text(AppStrings.ownerDashLogoutConfirmBody),
                    actions: [
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pop(dialogContext, false),
                        child: const Text(AppStrings.ownerDashCancel),
                      ),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                setDialogState(() => isLoading = true);
                                await authProvider.signOut();
                                if (!mounted) return;

                                if (authProvider.errorMessage != null) {
                                  setDialogState(() => isLoading = false);
                                  // OD-01: surface logout error to user.
                                  showAppToast(
                                    context,
                                    authProvider.errorMessage ??
                                        AppStrings.ownerDashLogoutFailed,
                                    type: ToastType.error,
                                  );
                                  return;
                                }

                                if (Navigator.canPop(dialogContext)) {
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                        child: isLoading
                            ? _BouncingBallLoader(color: c.error)
                            : Text(AppStrings.ownerDashLogout,
                                style: TextStyle(color: c.error)),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ) ??
        false;
  }

  Widget _buildQuickStats() {
    return Consumer2<TurfProvider, BookingProvider>(
      builder: (context, turfProvider, bookingProvider, _) {
        final c = AppColors.of(context);
        // Initialize bookings once when turfs become available
        if (turfProvider.turfIds.isNotEmpty && !_bookingsInitialized) {
          _bookingsInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _refreshBookings();
          });
        }

        return SectionContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.ownerDashQuickOverview,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 170,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _pauseAutoSlide();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _carouselController,
                    itemCount: _carouselRealCount * _carouselLoopMultiplier,
                    itemBuilder: (context, index) {
                      final realIndex = index % _carouselRealCount;
                      final cards = [
                        _CarouselCardData(
                          title: AppStrings.ownerDashCardTodaysBookings,
                          value: '${bookingProvider.todaysCount}',
                          icon: Icons.event_available,
                          iconColor: const Color(0xFF1F9D57),
                          bgColor: const Color(0xFFCFEED8),
                          subtitle: AppStrings.ownerDashCardTodaysBookingsSub,
                        ),
                        _CarouselCardData(
                          title: AppStrings.ownerDashCardPendingPayments,
                          value: '${bookingProvider.pendingPaymentsCount}',
                          icon: Icons.currency_rupee,
                          iconColor: const Color(0xFFEA6A1B),
                          bgColor: const Color(0xFFFFD8BF),
                          subtitle: AppStrings.ownerDashCardPendingPaymentsSub,
                        ),
                        _CarouselCardData(
                          title: AppStrings.ownerDashCardTotalTurfs,
                          value: '${turfProvider.totalTurfs}',
                          icon: Icons.sports_cricket,
                          iconColor: const Color(0xFF5B47C7),
                          bgColor: const Color(0xFFD9CCFF),
                          subtitle:
                              '${turfProvider.approvedCount}${AppStrings.ownerDashCardTotalTurfsSubSuffix}',
                        ),
                        _CarouselCardData(
                          title: AppStrings.ownerDashCardPendingApproval,
                          value: '${turfProvider.pendingCount}',
                          icon: Icons.pending_actions,
                          iconColor: const Color(0xFFC69214),
                          bgColor: const Color(0xFFFFE7A8),
                          subtitle: AppStrings.ownerDashCardPendingApprovalSub,
                        ),
                      ];

                      // OD-04: only this card subtree rebuilds on scroll.
                      return ValueListenableBuilder<double>(
                        valueListenable: _carouselPageNotifier,
                        builder: (context, page, child) {
                          final diff = (index - page).abs();
                          final scale = (1 - diff * 0.10).clamp(0.88, 1.0);
                          final opacity = (1 - diff * 0.25).clamp(0.6, 1.0);
                          return Transform.scale(
                            scale: scale,
                            child: Opacity(opacity: opacity, child: child),
                          );
                        },
                        child: RepaintBoundary(
                          child: _buildCarouselCard(cards[realIndex]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCarouselCard(_CarouselCardData data) {
    // Carousel cards always have light pastel backgrounds — text must be dark for contrast
    const darkText = Color(0xFF1E293B);
    const subtitleText = Color(0xFF475569);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.bgColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Subtle decorative circle top-right
          Positioned(
            top: -14,
            right: -14,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: data.iconColor.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: data.iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(data.icon, color: data.iconColor, size: 24),
                  ),
                  Text(
                    data.value,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: data.iconColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: subtitleText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards() {
    final c = AppColors.of(context);
    return SectionContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.ownerDashQuickActions,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Row 1 + Row 2: Left tall card + two right cards stacked
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left tall card spanning two rows
                Expanded(
                  child: _animatedCard(
                    index: 0,
                    child: _buildDashCard(
                      title: AppStrings.ownerDashActionBookingTitle,
                      subtitle: AppStrings.ownerDashActionBookingSub,
                      icon: Icons.access_time_outlined,
                      bgColor: const Color(0xFF1F2937),
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.slotBooking),
                      tall: true,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Right column: two stacked cards
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          index: 1,
                          child: _buildDashCard(
                            title: AppStrings.ownerDashActionTurfsTitle,
                            subtitle: AppStrings.ownerDashActionTurfsSub,
                            icon: Icons.stadium_outlined,
                            bgColor: const Color(0xFF273445),
                            onTap: () =>
                                Navigator.pushNamed(context, AppRoutes.myTurfs),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _animatedCard(
                          index: 2,
                          child: _buildDashCard(
                            title: AppStrings.ownerDashActionHistoryTitle,
                            subtitle: AppStrings.ownerDashActionHistorySub,
                            icon: Icons.calendar_month_outlined,
                            bgColor: const Color(0xFF334155),
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.bookingManagement),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Row 3: Full width card
          _animatedCard(
            index: 3,
            child: _buildDashCard(
              title: AppStrings.ownerDashActionAnalyticsTitle,
              subtitle: AppStrings.ownerDashActionAnalyticsSub,
              icon: Icons.analytics_outlined,
              bgColor: const Color(0xFF3F4D63),
              onTap: () => Navigator.pushNamed(context, AppRoutes.analytics),
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedCard({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _actionAnimController,
      builder: (context, _) {
        return Transform.translate(
          offset: _actionSlideAnims[index].value,
          child: Opacity(
            opacity: _actionFadeAnims[index].value,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildDashCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color bgColor,
    required VoidCallback onTap,
    bool tall = false,
    bool fullWidth = false,
  }) {
    const iconColor = Color(0xFFE2E8F0);
    const primaryText = Color(0xFFF8FAFC);
    const secondaryText = Color(0xFFCBD5E1);
    final iconBgColor = Color.lerp(bgColor, Colors.white, 0.12)!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: tall ? const BoxConstraints(minHeight: 220) : null,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fullWidth ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            if (!fullWidth) const Spacer(),
            if (fullWidth) const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: secondaryText,
                height: 1.3,
              ),
            ),
            if (tall) const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    // OD-25: Selector limits rebuilds to changes in the recent-bookings list
    // rather than every BookingProvider notify (e.g. status flips, totals).
    return Selector<BookingProvider, List<BookingModel>>(
      selector: (_, p) => p.recentBookings,
      builder: (context, recentBookings, _) {
        final c = AppColors.of(context);

        return NotchedSectionContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.ownerDashRecentBookings,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.bookingManagement);
                    },
                    child: const Text(AppStrings.ownerDashViewAll),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recentBookings.isEmpty)
                _buildEmptyState()
              else
                _buildTimeline(recentBookings),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final c = AppColors.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 48,
              color: c.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.ownerDashNoRecentBookings,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBookingDateShort(String bookingDate) {
    try {
      final parts = bookingDate.split('-');
      if (parts.length == 3) {
        final day = parts[2];
        final monthIndex = int.parse(parts[1]);
        return '$day\n${_monthShortNames[monthIndex - 1]}';
      }
    } catch (_) {}
    return bookingDate;
  }

  Widget _buildTimeline(List<BookingModel> bookings) {
    final c = AppColors.of(context);
    return Column(
      children: List.generate(bookings.length, (index) {
        final booking = bookings[index];
        final isLast = index == bookings.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: date & time
              SizedBox(
                width: 48,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatBookingDateShort(booking.bookingDate),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              // Timeline column: marker + line
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: c.primaryLight,
                        ),
                      ),
                  ],
                ),
              ),
              // Right: booking card
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  child: _buildTimelineCard(booking),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTimelineCard(BookingModel booking) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: c.textPrimary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.customerName.isNotEmpty
                      ? booking.customerName
                      : AppStrings.ownerDashCustomerFallback,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_outlined,
                        size: 13, color: c.textSecondary),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        booking.displayTimeRange,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildPaymentBadge(booking.paymentStatus),
        ],
      ),
    );
  }

  Widget _buildPaymentBadge(PaymentStatus status) {
    final c = AppColors.of(context);
    final bool isPaid = status == PaymentStatus.paid;
    final Color bgColor = isPaid ? c.successLight : c.border;
    final Color textColor = isPaid ? c.success : c.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return '${_weekdayShortNames[now.weekday - 1]}, ${now.day} ${_monthShortNames[now.month - 1]} ${now.year}';
  }
}

class _CarouselCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String subtitle;

  const _CarouselCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.subtitle,
  });
}

class _BouncingBallLoader extends StatefulWidget {
  const _BouncingBallLoader({required this.color});

  final Color color;

  @override
  State<_BouncingBallLoader> createState() => _BouncingBallLoaderState();
}

class _BouncingBallLoaderState extends State<_BouncingBallLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final bounce = Curves.easeInOut.transform(_controller.value);
          return Align(
            alignment: Alignment(0.0, 1.0 - (bounce * 2.0)),
            child: child,
          );
        },
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
