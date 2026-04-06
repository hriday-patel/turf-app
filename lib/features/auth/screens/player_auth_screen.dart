import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/app_toast.dart';

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

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

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
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPhoneController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  bool _isStrongPassword(String password) {
    final hasMinLength = password.length >= 8;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    return hasMinLength && hasUpper && hasLower && hasNumber && hasSpecial;
  }

  bool _isValidEmail(String email) {
    final normalized = email.trim();
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(normalized);
  }

  bool _isValidIndianPhone(String phone) {
    return RegExp(r'^\d{10}$').hasMatch(phone.trim());
  }

  String _normalizeIndianPhone(String phone) {
    final compact = phone.trim();
    if (compact.startsWith('+')) {
      return compact;
    }
    return '+91$compact';
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
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.playerHome,
        (route) => false,
      );
    }
  }

  Future<void> _handleEmailLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signInPlayer(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text.trim(),
    );

    if (success && mounted) {
      await _continueToPlayerHomeOrPhoneGate(authProvider);
    } else if (mounted && authProvider.errorMessage != null) {
      await _showProviderError(authProvider);
    }
  }

  Future<void> _handleGoogleContinue() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signInPlayerWithGoogle();

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
      phone: _normalizeIndianPhone(_signupPhoneController.text),
      password: _signupPasswordController.text.trim(),
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

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.playerHome,
      (route) => false,
    );
  }

  Future<bool> _completePendingPlayerSignupIfNeeded(
      AuthProvider authProvider) async {
    if (!authProvider.hasPendingSignup ||
        authProvider.pendingSignupRole != UserRole.player) {
      return true;
    }

    final phoneController = TextEditingController(
      text: authProvider.deferredSignupPhone.replaceFirst('+91', ''),
    );
    final otpController = TextEditingController();

    bool otpSent = false;
    bool busy = false;
    String? dialogError;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendOtp() async {
              final phone = phoneController.text.trim();
              if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                setDialogState(() {
                  dialogError = 'Enter a valid 10-digit phone number.';
                });
                return;
              }

              final normalizedPhone = '+91$phone';
              setDialogState(() {
                busy = true;
                dialogError = null;
              });

              final phoneError =
                  await authProvider.checkPhoneAvailability(normalizedPhone);
              if (phoneError != null) {
                setDialogState(() {
                  busy = false;
                  dialogError = phoneError;
                });
                return;
              }

              final sent = await authProvider.verifyPhone(
                normalizedPhone,
                role: UserRole.player,
              );

              setDialogState(() {
                busy = false;
                otpSent = sent;
                dialogError = sent
                    ? null
                    : (authProvider.errorMessage ??
                        'Could not send OTP. Please try again.');
              });
            }

            Future<void> verifyOtpAndFinalize() async {
              final otp = otpController.text.trim();
              if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
                setDialogState(() {
                  dialogError = 'Enter a valid 6-digit OTP.';
                });
                return;
              }

              setDialogState(() {
                busy = true;
                dialogError = null;
              });

              final verified = await authProvider.verifyOTP(otp);
              if (!verified || authProvider.currentPlayer == null) {
                setDialogState(() {
                  busy = false;
                  dialogError = authProvider.errorMessage ??
                      'OTP verification failed. Please try again.';
                });
                return;
              }

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            }

            return AlertDialog(
              title: const Text('Complete Phone Verification'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    enabled: !otpSent && !busy,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixText: '+91 ',
                    ),
                  ),
                  if (otpSent)
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      enabled: !busy,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Enter OTP',
                      ),
                    ),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await authProvider.cancelDeferredSignup();
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!otpSent) {
                            await sendOtp();
                          } else {
                            await verifyOtpAndFinalize();
                          }
                        },
                  child: Text(
                    busy
                        ? 'Please wait...'
                        : (otpSent ? 'Verify OTP' : 'Send OTP'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    phoneController.dispose();
    otpController.dispose();

    return result == true;
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

  @override
  Widget build(BuildContext context) {
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
                            'Player Zone',
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
                    'FieldPass Player',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Discover. Book. Play.',
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
                        Tab(text: 'LOGIN'),
                        Tab(text: 'SIGN UP'),
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
      child: Form(
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
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Email is required';
                }
                return _isValidEmail(val)
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
            _buildSubmitButton('Login', _handleEmailLogin),
            const SizedBox(height: 12),
            _buildGoogleButton(
              text: 'Continue with Google',
              onPressed: _handleGoogleContinue,
            ),
          ],
        ),
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
                    context,
                    'Full Name',
                    Icons.person_outline,
                  ),
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
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Email is required';
                    }
                    return _isValidEmail(val)
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
                    return _isValidIndianPhone(val)
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
                    if (!_isStrongPassword(val)) {
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
                  'Phone OTP verification is required before account access.',
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
            'Name and email are fetched from Google. Phone OTP verification is mandatory.',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _buildGoogleButton(
            text: 'Sign up with Google',
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
