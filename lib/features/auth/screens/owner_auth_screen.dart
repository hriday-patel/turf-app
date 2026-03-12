import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/app_toast.dart';

class OwnerAuthScreen extends StatefulWidget {
  const OwnerAuthScreen({super.key});

  @override
  State<OwnerAuthScreen> createState() => _OwnerAuthScreenState();
}

class _OwnerAuthScreenState extends State<OwnerAuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoginWithEmail = true; // Toggle for Login Tab
  bool _otpSent = false;

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
    super.dispose();
  }

  // ==================== ACTIONS ====================

  bool _isStrongPassword(String password) {
    final hasMinLength = password.length >= 8;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    return hasMinLength && hasUpper && hasLower && hasNumber && hasSpecial;
  }

  Future<void> _handleEmailLogin() async {
    if (!_loginEmailFormKey.currentState!.validate()) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signIn(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text.trim(),
    );

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _handlePhoneLoginSendOtp() async {
    if (!_loginPhoneFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String phone = _loginPhoneController.text.trim();
    if (!phone.startsWith('+')) phone = '+91$phone'; // Default to India

    final success = await authProvider.verifyPhone(phone);
    if (success && mounted) {
      setState(() => _otpSent = true);
      _showSuccess('OTP Sent to $phone');
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _handlePhoneLoginVerifyOtp() async {
    if (_loginOtpController.text.length != 6) {
      _showError('Please enter a valid 6-digit OTP');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyOTP(_loginOtpController.text.trim());

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String phone = _signupPhoneController.text.trim();
    if (!phone.startsWith('+')) phone = '+91$phone';

    final success = await authProvider.signUp(
      name: _signupNameController.text.trim(),
      email: _signupEmailController.text.trim(),
      phone: phone,
      password: _signupPasswordController.text.trim(),
      role: UserRole.owner,
    );

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, color: c.textPrimary, size: 20),
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

          if (_isLoginWithEmail) _buildEmailLoginForm() else _buildPhoneLoginForm(),
        ],
      ),
    );
  }

  Widget _buildMethodToggle({required BuildContext context, required String title, required bool isSelected, required VoidCallback onTap}) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? c.primary.withValues(alpha: 0.1) : c.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? c.primary.withValues(alpha: 0.5) : c.glassBorder,
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
            decoration: _inputDecoration(context, 'Email Address', Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (val) => val != null && val.contains('@') ? null : 'Invalid email',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            decoration: _inputDecoration(context, 'Password', Icons.lock_outline),
            obscureText: true,
            validator: (val) => val != null && val.length >= 6 ? null : 'Min 6 chars',
          ),
          const SizedBox(height: 24),
          _buildSubmitButton('Login with Email', _handleEmailLogin),
          TextButton(
            onPressed: () {
              // TODO: Implement Forgot Password
            },
            child: Text('Forgot Password?', style: TextStyle(color: c.textSecondary)),
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
            decoration: _inputDecoration(context, 'Phone Number', Icons.phone).copyWith(
              prefixText: '+91 ',
              prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            enabled: !_otpSent,
            validator: (val) => val != null && val.length == 10 ? null : '10 digits required',
          ),
          
          if (_otpSent) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginOtpController,
              decoration: _inputDecoration(context, 'Enter 6-digit OTP', Icons.security),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(letterSpacing: 8, fontWeight: FontWeight.bold, color: c.textPrimary),
            ),
            const SizedBox(height: 24),
            _buildSubmitButton('Verify & Login', _handlePhoneLoginVerifyOtp),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _otpSent = false),
              child: Text('Change Number', style: TextStyle(color: c.secondary)),
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
      child: Form(
        key: _signupFormKey,
        child: Column(
          children: [
            TextFormField(
              controller: _signupNameController,
              decoration: _inputDecoration(context, 'Full Name', Icons.person_outline),
              validator: (val) => val != null && val.length >= 3 ? null : 'Min 3 chars',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signupEmailController,
              decoration: _inputDecoration(context, 'Email Address', Icons.email_outlined),
              keyboardType: TextInputType.emailAddress,
              validator: (val) => val != null && val.contains('@') ? null : 'Invalid email',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signupPhoneController,
              decoration: _inputDecoration(context, 'Phone Number', Icons.phone).copyWith(
                prefixText: '+91 ',
                prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              keyboardType: TextInputType.phone,
              maxLength: 10,
              validator: (val) => val != null && val.length == 10 ? null : '10 digits required',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signupPasswordController,
              decoration: _inputDecoration(context, 'Password', Icons.lock_outline),
              obscureText: true,
              validator: (val) {
                if (val == null || val.isEmpty) return 'Password is required';
                if (!_isStrongPassword(val)) {
                  return 'Min 8 chars, upper, lower, number, special';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _signupConfirmPasswordController,
              decoration: _inputDecoration(context, 'Confirm Password', Icons.lock_outline),
              obscureText: true,
              validator: (val) {
                if (val != _signupPasswordController.text) return 'Passwords do not match';
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
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label, IconData icon) {
    final c = AppColors.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: c.textSecondary, size: 20),
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
}
