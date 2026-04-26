import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../utils/auth_form_utils.dart';
import '../widgets/pending_signup_verification_dialog.dart';

/// Player-side authentication hub (Phase 5 Iter 20 hardened).
///
/// Hosts three flows behind a tabbed UI:
///   1. Email/password login → `AppRoutes.playerHome`.
///   2. Google login → pending-signup dialog if phone missing → `playerHome`.
///   3. Manual signup (name/email/phone/password) → OTP dialog → `playerHome`.
///
/// Navigation safety:
///   * `_isNavigating` locks re-entry during a push so rapid taps cannot
///     double-navigate the back button.
///   * `_handledPendingOnLoad` is a one-shot flag preventing repeated
///     post-frame resume attempts on rebuild.
class PlayerAuthScreen extends StatefulWidget {
  const PlayerAuthScreen({super.key});

  @override
  State<PlayerAuthScreen> createState() => _PlayerAuthScreenState();
}

class _PlayerAuthScreenState extends State<PlayerAuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureSignupConfirmPassword = true;
  bool _handledPendingOnLoad = false;
  bool _isNavigating = false;
  // Phase 8 Iter 4 AUTH-08: phone-OTP login support for players (mirrors
  // owner_auth_screen). `_isLoginWithEmail` toggles the inner method;
  // `_otpSent` tracks whether we have sent the SMS for the entered phone.
  bool _isLoginWithEmail = true;
  bool _otpSent = false;

  Future<void> _guardedNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await action();
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  // Phase 8 Iter 4 AUTH-08: phone-OTP login controllers.
  final _loginPhoneController = TextEditingController();
  final _loginOtpController = TextEditingController();
  final _loginPhoneFormKey = GlobalKey<FormState>();

  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resumePendingSignupIfNeeded();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _loginPhoneController.dispose();
    _loginOtpController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPhoneController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resumePendingSignupIfNeeded() async {
    if (!mounted || _handledPendingOnLoad) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.hasPendingSignup ||
        authProvider.pendingSignupRole != UserRole.player) {
      _handledPendingOnLoad = true;
      return;
    }

    _handledPendingOnLoad = true;
    final completed = await _completePendingPlayerSignupIfNeeded(authProvider);
    if (!mounted || !completed) return;

    if (authProvider.currentPlayer != null) {
      await _guardedNavigate(() async {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.playerHome,
          (route) => false,
        );
      });
    }
  }

  Future<void> _handleEmailLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signInPlayer(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );

    if (success && mounted) {
      await _continueToPlayerHomeOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handleGoogleContinue() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signInPlayerWithGoogle(
      allowSignup: _tabController.index == 1,
    );

    if (success && mounted) {
      await _continueToPlayerHomeOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final signupSuccess = await authProvider.signUp(
      name: _signupNameController.text.trim(),
      email: _signupEmailController.text.trim(),
      phone: AuthFormUtils.normalizeIndianPhone(_signupPhoneController.text),
      password: _signupPasswordController.text,
      role: UserRole.player,
    );

    if (signupSuccess && mounted) {
      await _continueToPlayerHomeOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _continueToPlayerHomeOrPhoneGate(
      AuthProvider authProvider) async {
    final pendingCompleted =
        await _completePendingPlayerSignupIfNeeded(authProvider);
    if (!mounted || !pendingCompleted) {
      return;
    }

    if (authProvider.currentPlayer == null) {
      _showError(
        authProvider.errorMessage ??
            'Could not load your player profile. Please try again.',
      );
      return;
    }

    await _guardedNavigate(() async {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.playerHome,
        (route) => false,
      );
    });
  }

  Future<bool> _completePendingPlayerSignupIfNeeded(
      AuthProvider authProvider) async {
    if (!authProvider.hasPendingSignup ||
        authProvider.pendingSignupRole != UserRole.player) {
      return true;
    }

    return await showPendingSignupVerificationDialog(
      context: context,
      authProvider: authProvider,
      role: UserRole.player,
      initialPhone: authProvider.deferredSignupPhone,
    );
  }

  Future<void> _showProviderError(AuthProvider authProvider) async {
    final blocking = authProvider.consumeBlockingDialogMessage();
    if (blocking != null && blocking.trim().isNotEmpty) {
      await _showBlockingDialog(blocking);
      return;
    }

    final message = authProvider.errorMessage;
    if (message != null && message.trim().isNotEmpty) {
      _showError(message);
    }
  }

  Future<void> _showBlockingDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.playerAuthActionRequiredTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.playerAuthOkButton),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    showAppToast(context, message, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const RepaintBoundary(child: AbstractBgShapes()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios,
                              color: c.textPrimary, size: 20),
                          tooltip: AppStrings.playerAuthBackTooltip,
                          onPressed: () => _guardedNavigate(() async {
                            Navigator.pop(context);
                          }),
                        ),
                        Expanded(
                          child: Text(
                            AppStrings.playerAuthAppBarTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.playerAuthBrandTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.playerAuthBrandTagline,
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: c.glassFill,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.glassBorder),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: c.primary,
                      unselectedLabelColor: c.textSecondary,
                      indicatorColor: c.primary,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: AppStrings.playerAuthTabLogin),
                        Tab(text: AppStrings.playerAuthTabSignup),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLoginTab(),
                        _buildSignupTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Phase 8 Iter 4 AUTH-08: method toggle (Email vs Phone OTP).
          Row(
            children: [
              Expanded(
                child: _buildMethodToggle(
                  context: context,
                  title: AppStrings.ownerAuthMethodEmail,
                  isSelected: _isLoginWithEmail,
                  onTap: () => setState(() {
                    _isLoginWithEmail = true;
                    _otpSent = false;
                    _loginOtpController.clear();
                  }),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMethodToggle(
                  context: context,
                  title: AppStrings.ownerAuthMethodPhone,
                  isSelected: !_isLoginWithEmail,
                  onTap: () => setState(() => _isLoginWithEmail = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoginWithEmail)
            _buildEmailLoginForm()
          else
            _buildPhoneLoginForm(),
        ],
      ),
    );
  }

  Widget _buildMethodToggle({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? c.primary.withValues(alpha: 0.1) : c.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? c.primary.withValues(alpha: 0.5) : c.glassBorder,
            width: 1.5,
          ),
          boxShadow: isSelected ? AppColors.neonGlow(blur: 10) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? c.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmailLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _loginEmailController,
            decoration: _inputDecoration(
              context,
              'Email Address',
              Icons.email_outlined,
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            textInputAction: TextInputAction.next,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Email is required';
              }
              return AuthFormUtils.isValidEmail(val)
                  ? null
                  : 'Enter a valid email address';
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            decoration: _inputDecoration(
              context,
              'Password',
              Icons.lock_outline,
              suffixIcon: _passwordVisibilitySuffix(
                isObscured: _obscureLoginPassword,
                onPressed: () => setState(
                  () => _obscureLoginPassword = !_obscureLoginPassword,
                ),
              ),
            ),
            obscureText: _obscureLoginPassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleEmailLogin(),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Password is required';
              }
              return val.length >= 8
                  ? null
                  : 'Password must be at least 8 characters';
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(AppStrings.login, _handleEmailLogin),
          const SizedBox(height: 12),
          _buildGoogleButton(
            text: AppStrings.playerAuthContinueWithGoogle,
            onPressed: _handleGoogleContinue,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLoginForm() {
    final c = AppColors.of(context);
    return Form(
      key: _loginPhoneFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _loginPhoneController,
            decoration:
                _inputDecoration(context, 'Phone Number', Icons.phone).copyWith(
              prefixText: '+91 ',
              prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
              counterText: '',
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            enabled: !_otpSent,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Phone number is required';
              }
              return AuthFormUtils.isValidIndianPhoneInput(val)
                  ? null
                  : 'Enter a valid 10-digit phone number';
            },
          ),
          if (_otpSent) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginOtpController,
              decoration: _inputDecoration(
                      context, AppStrings.ownerAuthOtpLabel, Icons.security)
                  .copyWith(counterText: ''),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onFieldSubmitted: (_) => _handlePhoneLoginVerifyOtp(),
              style: TextStyle(
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary),
            ),
            const SizedBox(height: 24),
            _buildSubmitButton(AppStrings.ownerAuthVerifyAndContinue,
                _handlePhoneLoginVerifyOtp),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _otpSent = false;
                _loginOtpController.clear();
              }),
              child: Text(AppStrings.ownerAuthChangeNumber,
                  style: TextStyle(color: c.secondary)),
            ),
          ] else ...[
            const SizedBox(height: 24),
            _buildSubmitButton(
                AppStrings.ownerAuthSendOtp, _handlePhoneLoginSendOtp),
          ],
        ],
      ),
    );
  }

  Future<void> _handlePhoneLoginSendOtp() async {
    if (!_loginPhoneFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final phone =
        AuthFormUtils.normalizeIndianPhone(_loginPhoneController.text);

    final success =
        await authProvider.verifyPhone(phone, role: UserRole.player);

    if (!mounted) return;
    if (success) {
      setState(() => _otpSent = true);
      showAppToast(context, 'OTP sent to $phone', type: ToastType.success);
    } else if (authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handlePhoneLoginVerifyOtp() async {
    final otp = _loginOtpController.text.trim();
    if (otp.length != 6) {
      _showError(AppStrings.ownerAuthInvalidOtp);
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyOTP(otp);

    if (!mounted) return;
    if (success) {
      await _continueToPlayerHomeOrPhoneGate(authProvider);
    } else if (authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Widget _buildSignupTab() {
    final c = AppColors.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildGoogleSignupPathCard(),
          const SizedBox(height: 18),
          Text(
            AppStrings.playerAuthOrSignupManually,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 18),
          Form(
            key: _signupFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _signupNameController,
                  decoration: _inputDecoration(
                    context,
                    'Full Name',
                    Icons.person_outline,
                  ),
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return val.trim().length >= 3
                        ? null
                        : 'Name must be at least 3 characters';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _signupEmailController,
                  decoration: _inputDecoration(
                    context,
                    'Email Address',
                    Icons.email_outlined,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.username
                  ],
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Email is required';
                    }
                    return AuthFormUtils.isValidEmail(val)
                        ? null
                        : 'Enter a valid email address';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _signupPhoneController,
                  decoration:
                      _inputDecoration(context, 'Phone Number', Icons.phone)
                          .copyWith(
                    prefixText: '+91 ',
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
                    counterText: '',
                  ),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    return AuthFormUtils.isValidIndianPhoneInput(val)
                        ? null
                        : 'Enter a valid 10-digit phone number';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _signupPasswordController,
                  decoration: _inputDecoration(
                    context,
                    'Password',
                    Icons.lock_outline,
                    suffixIcon: _passwordVisibilitySuffix(
                      isObscured: _obscureSignupPassword,
                      onPressed: () => setState(
                        () => _obscureSignupPassword = !_obscureSignupPassword,
                      ),
                    ),
                  ),
                  obscureText: _obscureSignupPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Password is required';
                    }
                    if (!AuthFormUtils.isStrongPassword(val)) {
                      return 'Min 8 chars, upper, lower, number, special';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _signupConfirmPasswordController,
                  decoration: _inputDecoration(
                    context,
                    'Confirm Password',
                    Icons.lock_outline,
                    suffixIcon: _passwordVisibilitySuffix(
                      isObscured: _obscureSignupConfirmPassword,
                      onPressed: () => setState(
                        () => _obscureSignupConfirmPassword =
                            !_obscureSignupConfirmPassword,
                      ),
                    ),
                  ),
                  obscureText: _obscureSignupConfirmPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSignup(),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Confirm password is required';
                    }
                    if (val != _signupPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                _buildSubmitButton(AppStrings.signup, _handleSignup),
                const SizedBox(height: 24),
                Text(
                  AppStrings.playerAuthOtpRequiredBlurb,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleSignupPathCard() {
    final c = AppColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.playerAuthQuickSignup,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.playerAuthQuickSignupBlurb,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _buildGoogleButton(
            text: AppStrings.playerAuthSignupWithGoogle,
            onPressed: _handleGoogleContinue,
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    final c = AppColors.of(context);

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: c.textSecondary, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: c.glassFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(16),
      labelStyle: TextStyle(color: c.textSecondary),
    );
  }

  Widget _passwordVisibilitySuffix({
    required bool isObscured,
    required VoidCallback onPressed,
  }) {
    final c = AppColors.of(context);

    return IconButton(
      icon: Icon(
        isObscured ? Icons.visibility_off : Icons.visibility,
        color: c.textSecondary,
      ),
      tooltip: AppStrings.playerAuthPasswordVisibilityTooltip,
      onPressed: onPressed,
    );
  }

  Widget _buildSubmitButton(String text, VoidCallback onPressed) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return GlassButton(
          label: text,
          onPressed: onPressed,
          isLoading: auth.isLoading,
        );
      },
    );
  }

  Widget _buildGoogleButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    final c = AppColors.of(context);

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: auth.isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.glassBorder),
              foregroundColor: c.textPrimary,
              backgroundColor: c.glassFill,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(
              Icons.g_mobiledata_rounded,
              color: c.textPrimary,
              size: 26,
            ),
            label: Text(
              text,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}
