import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/app_toast.dart';
import '../utils/auth_form_utils.dart';
import '../widgets/pending_signup_verification_dialog.dart';

class OwnerAuthScreen extends StatefulWidget {
  const OwnerAuthScreen({super.key});

  @override
  State<OwnerAuthScreen> createState() => _OwnerAuthScreenState();
}

class _OwnerAuthScreenState extends State<OwnerAuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoginWithEmail = true; // Toggle for Login Tab
  bool _otpSent = false;
  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureSignupConfirmPassword = true;
  bool _obscureForgotNewPassword = true;
  bool _obscureForgotConfirmPassword = true;

  // Forgot password flow state
  bool _showForgotPassword = false;
  int _forgotPasswordStep = 0; // 0=email, 1=otp, 2=new password
  final _forgotEmailController = TextEditingController();
  final _forgotOtpController = TextEditingController();
  final _forgotNewPasswordController = TextEditingController();
  final _forgotConfirmPasswordController = TextEditingController();

  // Controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginPhoneController = TextEditingController();
  final _loginOtpController = TextEditingController();

  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  // Form Keys
  final _loginEmailFormKey = GlobalKey<FormState>();
  final _loginPhoneFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();
  final _forgotPasswordFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // Reset OTP state when switching tabs
          if (_tabController.index == 1) _otpSent = false;
        });
      }
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
    _forgotEmailController.dispose();
    _forgotOtpController.dispose();
    _forgotNewPasswordController.dispose();
    _forgotConfirmPasswordController.dispose();
    super.dispose();
  }

  // ==================== ACTIONS ====================

  Future<void> _handleEmailLogin() async {
    if (!_loginEmailFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signIn(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text.trim(),
    );

    if (success && mounted) {
      await _continueToOwnerDashboardOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handlePhoneLoginSendOtp() async {
    if (!_loginPhoneFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final phone =
        AuthFormUtils.normalizeIndianPhone(_loginPhoneController.text);

    final success = await authProvider.verifyPhone(phone);
    if (success && mounted) {
      setState(() => _otpSent = true);
      final isPhoneVerificationGate = authProvider.currentOwner != null;
      _showSuccess(
        isPhoneVerificationGate
            ? 'OTP sent for phone verification'
            : 'OTP sent to $phone',
      );
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handlePhoneLoginVerifyOtp() async {
    if (!AuthFormUtils.isValidOtp(_loginOtpController.text)) {
      _showError('Please enter a valid 6-digit OTP');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success =
        await authProvider.verifyOTP(_loginOtpController.text.trim());

    if (success && mounted) {
      await _continueToOwnerDashboardOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final phone =
        AuthFormUtils.normalizeIndianPhone(_signupPhoneController.text);

    final success = await authProvider.signUp(
      name: _signupNameController.text.trim(),
      email: _signupEmailController.text.trim(),
      phone: phone,
      password: _signupPasswordController.text.trim(),
      role: UserRole.owner,
    );

    if (success && mounted) {
      await _continueToOwnerDashboardOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handleGoogleLogin() async {
    await _handleGoogleContinue();
  }

  Future<void> _handleGoogleSignup() async {
    await _handleGoogleContinue();
  }

  Future<void> _handleGoogleContinue() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signInOwnerWithGoogle();

    if (success && mounted) {
      await _continueToOwnerDashboardOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  // ==================== FORGOT PASSWORD HANDLERS ====================

  void _startForgotPassword() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearForgotPasswordState();
    setState(() {
      _showForgotPassword = true;
      _forgotPasswordStep = 0;
      _obscureForgotNewPassword = true;
      _obscureForgotConfirmPassword = true;
      _forgotEmailController.clear();
      _forgotOtpController.clear();
      _forgotNewPasswordController.clear();
      _forgotConfirmPasswordController.clear();
    });
  }

  void _cancelForgotPassword() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearForgotPasswordState();
    setState(() {
      _showForgotPassword = false;
      _forgotPasswordStep = 0;
    });
  }

  Future<void> _handleForgotPasswordEmailSubmit() async {
    if (!_forgotPasswordFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success =
        await authProvider.initForgotPassword(_forgotEmailController.text);

    if (success && mounted) {
      // Found user with phone, now send OTP
      final otpSent = await authProvider.sendForgotPasswordOtp();
      if (otpSent && mounted) {
        setState(() => _forgotPasswordStep = 1);
        _showSuccess(
            'OTP sent to ${_maskPhone(authProvider.forgotPasswordPhone ?? '')}');
      } else if (mounted && authProvider.errorMessage != null) {
        _showError(authProvider.errorMessage!);
      }
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _handleForgotPasswordOtpVerify() async {
    if (!AuthFormUtils.isValidOtp(_forgotOtpController.text)) {
      _showError('Please enter a valid 6-digit OTP');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success =
        await authProvider.verifyForgotPasswordOtp(_forgotOtpController.text);

    if (success && mounted) {
      setState(() => _forgotPasswordStep = 2);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _handleForgotPasswordSetNew() async {
    if (!_forgotPasswordFormKey.currentState!.validate()) return;

    if (_forgotNewPasswordController.text !=
        _forgotConfirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider
        .setNewPasswordAfterOtpVerification(_forgotNewPasswordController.text);

    if (success && mounted) {
      _showSuccess('Password updated successfully! Please login.');
      _cancelForgotPassword();
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  String _maskPhone(String phone) {
    final compact = phone.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return compact;
    final last4 = compact.substring(compact.length - 4);
    return 'xxxxxx$last4';
  }

  Future<void> _continueToOwnerDashboardOrPhoneGate(
      AuthProvider authProvider) async {
    final pendingCompleted =
        await _completePendingOwnerSignupIfNeeded(authProvider);
    if (!mounted || !pendingCompleted) return;

    final ready = await authProvider.ensureOwnerReadyForDashboard();
    if (!mounted) return;

    if (!ready) {
      _showError(
        authProvider.errorMessage ??
            'Could not load your owner profile. Please try again.',
      );
      return;
    }

    Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
  }

  Future<bool> _completePendingOwnerSignupIfNeeded(
      AuthProvider authProvider) async {
    if (!authProvider.isInDeferredSignupFlow ||
        authProvider.pendingSignupRole != UserRole.owner) {
      return true;
    }

    return await showPendingSignupVerificationDialog(
      context: context,
      authProvider: authProvider,
      role: UserRole.owner,
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
        title: const Text('Action Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    showAppToast(context, message, type: ToastType.error);
  }

  void _showSuccess(String message) {
    showAppToast(context, message, type: ToastType.success);
  }

  // ==================== UI BUILDERS ====================

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    // Show forgot password flow if active
    if (_showForgotPassword) {
      return _buildForgotPasswordScreen();
    }

    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const AbstractBgShapes(),
            SafeArea(
              child: Column(
                children: [
                  // Custom glass app bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios,
                              color: c.textPrimary, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            'Owner Portal',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48), // balance the back button
                      ],
                    ),
                  ),
                  // Branding
                  const SizedBox(height: 8),
                  Text(
                    'FieldPass Business',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pitch Perfect Management',
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tab bar
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
                        Tab(text: 'LOGIN'),
                        Tab(text: 'SIGN UP'),
                      ],
                    ),
                  ),
                  // Body
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
          // Login Method Toggle
          Row(
            children: [
              Expanded(
                child: _buildMethodToggle(
                  context: context,
                  title: 'Email',
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
                  title: 'Phone',
                  isSelected: !_isLoginWithEmail,
                  onTap: () => setState(() => _isLoginWithEmail = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          if (_isLoginWithEmail)
            _buildEmailLoginForm()
          else
            _buildPhoneLoginForm(),
        ],
      ),
    );
  }

  Widget _buildMethodToggle(
      {required BuildContext context,
      required String title,
      required bool isSelected,
      required VoidCallback onTap}) {
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
    final c = AppColors.of(context);
    return Form(
      key: _loginEmailFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _loginEmailController,
            decoration: _inputDecoration(
                context, 'Email Address', Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
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
          _buildSubmitButton('Login with Email', _handleEmailLogin),
          const SizedBox(height: 12),
          _buildGoogleButton(
            text: 'Continue with Google',
            onPressed: _handleGoogleLogin,
          ),
          TextButton(
            onPressed: _startForgotPassword,
            child: Text('Forgot Password?',
                style: TextStyle(color: c.textSecondary)),
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
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            enabled: !_otpSent,
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
                  context, 'Enter 6-digit OTP', Icons.security),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary),
            ),
            const SizedBox(height: 24),
            _buildSubmitButton('Verify & Continue', _handlePhoneLoginVerifyOtp),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _otpSent = false),
              child:
                  Text('Change Number', style: TextStyle(color: c.secondary)),
            ),
          ] else ...[
            const SizedBox(height: 24),
            _buildSubmitButton('Send OTP', _handlePhoneLoginSendOtp),
          ],
        ],
      ),
    );
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
            'OR SIGN UP MANUALLY',
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
                      context, 'Full Name', Icons.person_outline),
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
                      context, 'Email Address', Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
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
                  ),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
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
                _buildSubmitButton('Sign Up', _handleSignup),
                const SizedBox(height: 24),
                Text(
                  'By signing up, you agree to our Terms & Conditions',
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
            'Quick Sign Up',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Name and email will be pulled from Google. Phone OTP verification is required.',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _buildGoogleButton(
            text: 'Sign up with Google',
            onPressed: _handleGoogleSignup,
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
            icon: Icon(Icons.g_mobiledata_rounded,
                color: c.textPrimary, size: 26),
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

  // ==================== FORGOT PASSWORD UI ====================

  Widget _buildForgotPasswordScreen() {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const AbstractBgShapes(),
            SafeArea(
              child: Column(
                children: [
                  // App bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios,
                              color: c.textPrimary, size: 20),
                          onPressed: _cancelForgotPassword,
                        ),
                        Expanded(
                          child: Text(
                            'Reset Password',
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
                  const SizedBox(height: 24),
                  // Step indicator
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        _buildStepIndicator(0, 'Email'),
                        _buildStepConnector(0),
                        _buildStepIndicator(1, 'OTP'),
                        _buildStepConnector(1),
                        _buildStepIndicator(2, 'Password'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Form content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildForgotPasswordStepContent(),
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

  Widget _buildStepIndicator(int step, String label) {
    final c = AppColors.of(context);
    final isActive = _forgotPasswordStep >= step;
    final isCurrent = _forgotPasswordStep == step;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? c.primary.withValues(alpha: isCurrent ? 1.0 : 0.7)
                  : c.glassFill,
              border: Border.all(color: isActive ? c.primary : c.glassBorder),
            ),
            child: Center(
              child: isActive && !isCurrent
                  ? Icon(Icons.check, color: c.onPrimary, size: 18)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? c.onPrimary : c.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isCurrent ? c.primary : c.textSecondary,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepConnector(int afterStep) {
    final c = AppColors.of(context);
    final isActive = _forgotPasswordStep > afterStep;

    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: isActive ? c.primary : c.glassBorder,
    );
  }

  Widget _buildForgotPasswordStepContent() {
    switch (_forgotPasswordStep) {
      case 0:
        return _buildForgotPasswordEmailStep();
      case 1:
        return _buildForgotPasswordOtpStep();
      case 2:
        return _buildForgotPasswordNewPasswordStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildForgotPasswordEmailStep() {
    final c = AppColors.of(context);
    return Form(
      key: _forgotPasswordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter your email',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll send an OTP to your registered phone number to verify your identity.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _forgotEmailController,
            decoration: _inputDecoration(
                context, 'Email Address', Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Email is required';
              }
              return AuthFormUtils.isValidEmail(val)
                  ? null
                  : 'Enter a valid email address';
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton('Continue', _handleForgotPasswordEmailSubmit),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _cancelForgotPassword,
              child: Text('Back to Login',
                  style: TextStyle(color: c.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordOtpStep() {
    final c = AppColors.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final maskedPhone = _maskPhone(authProvider.forgotPasswordPhone ?? '');

    return Form(
      key: _forgotPasswordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify OTP',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit OTP sent to $maskedPhone',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _forgotOtpController,
            decoration:
                _inputDecoration(context, 'Enter 6-digit OTP', Icons.security),
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSubmitButton('Verify OTP', _handleForgotPasswordOtpVerify),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () async {
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                final success = await authProvider.sendForgotPasswordOtp();
                if (success && mounted) {
                  _showSuccess('OTP resent to $maskedPhone');
                } else if (mounted && authProvider.errorMessage != null) {
                  _showError(authProvider.errorMessage!);
                }
              },
              child: Text('Resend OTP', style: TextStyle(color: c.secondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordNewPasswordStep() {
    final c = AppColors.of(context);
    return Form(
      key: _forgotPasswordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set New Password',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a strong password with at least 8 characters including uppercase, lowercase, number, and special character.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _forgotNewPasswordController,
            decoration: _inputDecoration(
              context,
              'New Password',
              Icons.lock_outline,
              suffixIcon: _passwordVisibilitySuffix(
                isObscured: _obscureForgotNewPassword,
                onPressed: () => setState(
                  () => _obscureForgotNewPassword = !_obscureForgotNewPassword,
                ),
              ),
            ),
            obscureText: _obscureForgotNewPassword,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Password is required';
              if (!AuthFormUtils.isStrongPassword(val)) {
                return 'Min 8 chars, upper, lower, number, special';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _forgotConfirmPasswordController,
            decoration: _inputDecoration(
              context,
              'Confirm Password',
              Icons.lock_outline,
              suffixIcon: _passwordVisibilitySuffix(
                isObscured: _obscureForgotConfirmPassword,
                onPressed: () => setState(
                  () => _obscureForgotConfirmPassword =
                      !_obscureForgotConfirmPassword,
                ),
              ),
            ),
            obscureText: _obscureForgotConfirmPassword,
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Confirm password is required';
              }
              if (val != _forgotNewPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton('Set Password', _handleForgotPasswordSetNew),
        ],
      ),
    );
  }
}
