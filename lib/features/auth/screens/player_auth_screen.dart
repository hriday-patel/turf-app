import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () {
            if (_currentStep == AuthStep.otp) {
              setState(() => _currentStep = AuthStep.phone);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              Expanded(
                child: _buildStepContent(),
              ),
            ],
          ),
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
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
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
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'Phone Number',
              prefixText: '+91 ',
              prefixStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              counterText: '',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(18),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter phone number';
              if (value.length < 10) return 'Enter a valid 10-digit number';
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(
            text: 'Continue',
            onPressed: _sendOTP,
          ),
        ],
      ),
    );
  }

  Widget _buildOTPInput() {
    return Form(
      key: _otpFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 10),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(18),
            ),
            validator: (value) {
              if (value == null || value.length < 6) return 'Enter 6-digit OTP';
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(
            text: 'Verify Code',
            onPressed: _verifyOTP,
          ),
          TextButton(
            onPressed: () {
              setState(() => _currentStep = AuthStep.phone);
            },
            child: const Text('Change Number'),
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
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Your Display Name',
              prefixIcon: const Icon(Icons.person_outline),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) => (value == null || value.isEmpty) ? 'Enter name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Email Address',
              prefixIcon: const Icon(Icons.email_outlined),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter email';
              if (!value.contains('@')) return 'Enter valid email';
              return null;
            },
          ),
          const SizedBox(height: 32),
          _buildSubmitButton(
            text: 'Get Started',
            onPressed: _completeProfile,
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({required String text, required VoidCallback onPressed}) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: auth.isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        );
      },
    );
  }
}
