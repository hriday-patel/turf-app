import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../../core/constants/strings.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/app_toast.dart';

enum AuthStep { phone, otp, profile }

class PlayerAuthScreen extends StatefulWidget {
  const PlayerAuthScreen({super.key});

  @override
  State<PlayerAuthScreen> createState() => _PlayerAuthScreenState();
}

class _PlayerAuthScreenState extends State<PlayerAuthScreen> {
  AuthStep _currentStep = AuthStep.phone;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  
  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) phone = '+91$phone';

    final success = await authProvider.verifyPhone(phone);
    if (success && mounted) {
      setState(() => _currentStep = AuthStep.otp);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _verifyOTP() async {
    if (!_otpFormKey.currentState!.validate()) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyOTP(_otpController.text.trim());
    
    if (success && mounted) {
      if (authProvider.currentPlayer != null) {
        // Existing player
        Navigator.pop(context); // Go back as player home flow is managed by gateway
      } else {
        // New user or no profile
        setState(() => _currentStep = AuthStep.profile);
      }
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  Future<void> _completeProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.completeProfile(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      role: UserRole.player,
    );

    if (success && mounted) {
      Navigator.pop(context);
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
    }
  }

  void _showError(String message) {
    showAppToast(context, message, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const AbstractBgShapes(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
                          onPressed: () {
                            if (_currentStep == AuthStep.otp) {
                              setState(() => _currentStep = AuthStep.phone);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  // Branding
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.glassFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      boxShadow: AppColors.neonGlow(blur: 24, spread: 1),
                    ),
                    child: const Icon(
                      Icons.sports_cricket,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppStrings.appName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.appTagline,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 40),
                          Expanded(child: _buildStepContent()),
                        ],
                      ),
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

  Widget _buildHeader() {
    String title = '';
    String subtitle = '';

    switch (_currentStep) {
      case AuthStep.phone:
        title = 'Player Login';
        subtitle = 'Enter your phone number to get started';
        break;
      case AuthStep.otp:
        title = 'Verification';
        subtitle = 'We sent a code to ${_phoneController.text}';
        break;
      case AuthStep.profile:
        title = 'One last step';
        subtitle = 'Setup your player profile';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case AuthStep.phone:
        return _buildPhoneInput();
      case AuthStep.otp:
        return _buildOTPInput();
      case AuthStep.profile:
        return _buildProfileSetup();
    }
  }

  Widget _buildPhoneInput() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        children: [
          GlassTextField(
            controller: _phoneController,
            hint: 'Phone Number',
            prefixText: '+91 ',
            prefixStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, color: AppColors.textPrimary),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter phone number';
              if (value.length < 10) return 'Enter a valid 10-digit number';
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(text: 'Continue', onPressed: _sendOTP),
        ],
      ),
    );
  }

  Widget _buildOTPInput() {
    return Form(
      key: _otpFormKey,
      child: Column(
        children: [
          GlassTextField(
            controller: _otpController,
            hint: '000000',
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 10, color: AppColors.textPrimary),
            validator: (value) {
              if (value == null || value.length < 6) return 'Enter 6-digit OTP';
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(text: 'Verify Code', onPressed: _verifyOTP),
          TextButton(
            onPressed: () => setState(() => _currentStep = AuthStep.phone),
            child: const Text('Change Number', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSetup() {
    return Form(
      key: _profileFormKey,
      child: Column(
        children: [
          GlassTextField(
            controller: _nameController,
            hint: 'Your Display Name',
            prefixIcon: Icons.person_outline,
            validator: (value) => (value == null || value.isEmpty) ? 'Enter name' : null,
          ),
          const SizedBox(height: 16),
          GlassTextField(
            controller: _emailController,
            hint: 'Email Address',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter email';
              if (!value.contains('@')) return 'Enter valid email';
              return null;
            },
          ),
          const SizedBox(height: 32),
          _buildSubmitButton(text: 'Get Started', onPressed: _completeProfile),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({required String text, required VoidCallback onPressed}) {
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
