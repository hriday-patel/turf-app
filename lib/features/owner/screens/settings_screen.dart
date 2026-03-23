import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/services/auth_service.dart';

// OtpDeliveryChannel enum removed - now using only phone OTP

/// Settings Screen
/// Change email, change password with validation
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isEmailLoading = false;
  bool _isPasswordLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _emailController.text = authProvider.ownerDisplayEmail;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      authProvider.ensureOwnerReadyForDashboard();
      if (_emailController.text.trim().isEmpty) {
        _emailController.text = authProvider.ownerDisplayEmail;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Min 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Needs uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'Needs lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Needs a number';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value))
      return 'Needs special character';
    return null;
  }

  Future<void> _updateEmail() async {
    final newEmail = _emailController.text.trim();
    final error = _validateEmail(newEmail);
    if (error != null) {
      _showSnackBar(error, isError: true);
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerPhone = authProvider.currentOwner?.phone.trim();
    if (ownerPhone == null ||
        ownerPhone.isEmpty ||
        ownerPhone.startsWith('pending_')) {
      _showSnackBar('No verified phone number found.', isError: true);
      return;
    }

    final otpVerified = await _runRealOtpFlow(
      phone: ownerPhone,
      purpose: 'email update',
    );
    if (!mounted || !otpVerified) return;

    setState(() => _isEmailLoading = true);
    final success = await authProvider.updateEmail(newEmail);

    if (!mounted) return;
    setState(() => _isEmailLoading = false);

    if (success) {
      final verificationConfirmed =
          await _showEmailVerificationDialog(authProvider, newEmail);
      if (!mounted || !verificationConfirmed) return;

      final shouldLogout = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Email Updated'),
              content: const Text(
                'Email verified and updated successfully. Please login again with your new email.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('OK'),
                ),
              ],
            ),
          ) ??
          false;

      if (!mounted) return;
      if (shouldLogout) {
        await authProvider.signOut();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login-selection',
          (route) => false,
        );
      }
    } else {
      _showSnackBar(authProvider.errorMessage ?? 'Failed to update email',
          isError: true);
    }
  }

  Future<bool> _showEmailVerificationDialog(
    AuthProvider authProvider,
    String newEmail,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            bool isChecking = false;
            String? infoMessage;

            return StatefulBuilder(
              builder: (dialogContext, setDialogState) {
                Future<void> verifyNow() async {
                  if (isChecking) return;
                  setDialogState(() {
                    isChecking = true;
                    infoMessage = null;
                  });

                  final confirmed =
                      await authProvider.confirmEmailUpdate(newEmail);

                  if (!mounted) return;

                  if (confirmed) {
                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext, true);
                    }
                    return;
                  }

                  setDialogState(() {
                    isChecking = false;
                    infoMessage = authProvider.errorMessage ??
                        'Verification pending. Please verify your new email and try again.';
                  });
                }

                return AlertDialog(
                  title: const Text('Verify New Email'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A verification link has been sent to $newEmail. Please verify it now, then tap Verify.',
                      ),
                      if (infoMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          infoMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        if (Navigator.canPop(dialogContext)) {
                          Navigator.pop(dialogContext, false);
                        }
                      },
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: isChecking ? null : verifyNow,
                      child: isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;
  }

  Future<void> _updatePassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final error = _validatePassword(newPassword);
    if (error != null) {
      _showSnackBar(error, isError: true);
      return;
    }
    if (newPassword != confirmPassword) {
      _showSnackBar('Passwords do not match', isError: true);
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final owner = authProvider.currentOwner;
    final phone = owner?.phone.trim();

    if (phone == null || phone.isEmpty || phone.startsWith('pending_')) {
      _showSnackBar('No verified phone number found.', isError: true);
      return;
    }

    // Run phone OTP verification flow
    final otpVerified = await _runRealOtpFlow(
      phone: phone,
      purpose: 'password update',
    );
    if (!mounted || !otpVerified) return;

    setState(() => _isPasswordLoading = true);
    final success = await authProvider.updatePassword(newPassword);

    if (!mounted) return;
    setState(() => _isPasswordLoading = false);

    if (success) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Password Updated'),
          content: const Text(
            'Password changed successfully. You can now use this password to login.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } else {
      _showSnackBar(authProvider.errorMessage ?? 'Failed to update password',
          isError: true);
    }
  }

  /// Real Supabase OTP flow for verifying phone before sensitive actions
  Future<bool> _runRealOtpFlow({
    required String phone,
    required String purpose,
  }) async {
    final authService = AuthService();
    final otpController = TextEditingController();
    bool isLoading = false;
    String? errorText;

    // Send OTP first
    try {
      await authService.sendPhoneChangeOtp(phone: phone);
    } catch (e) {
      _showSnackBar('Could not send OTP. Please try again.', isError: true);
      return false;
    }

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> handleVerify() async {
              final entered = otpController.text.trim();
              if (entered.length != 6) {
                setDialogState(() => errorText = 'Enter 6-digit OTP');
                return;
              }

              setDialogState(() {
                isLoading = true;
                errorText = null;
              });

              try {
                await authService.verifyPhoneChangeOtp(
                  phone: phone,
                  token: entered,
                );
                if (Navigator.canPop(dialogContext)) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                setDialogState(() {
                  isLoading = false;
                  errorText = 'Invalid OTP. Please try again.';
                });
              }
            }

            Future<void> handleResend() async {
              setDialogState(() {
                isLoading = true;
                errorText = null;
              });

              try {
                await authService.sendPhoneChangeOtp(phone: phone);
                setDialogState(() {
                  isLoading = false;
                  otpController.clear();
                });
                _showSnackBar('OTP resent to ${_maskPhone(phone)}');
              } catch (e) {
                setDialogState(() {
                  isLoading = false;
                  errorText = 'Could not resend OTP.';
                });
              }
            }

            return AlertDialog(
              title: Text('Verify OTP for ${_capitalize(purpose)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the 6-digit OTP sent to ${_maskPhone(phone)}.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: '6-digit OTP',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (Navigator.canPop(dialogContext)) {
                            Navigator.pop(dialogContext, false);
                          }
                        },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isLoading ? null : handleResend,
                  child: const Text('Resend OTP'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : handleVerify,
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    otpController.dispose();
    return verified == true;
  }

  String _maskPhone(String phone) {
    final compact = phone.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return compact;
    final last4 = compact.substring(compact.length - 4);
    return 'xxxxxx$last4';
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    showAppToast(context, message,
        type: isError ? ToastType.error : ToastType.success);
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
                  GlassAppBar(title: 'Profile Settings'),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Account Info
                          _buildSectionTitle('Account Information'),
                          _buildAccountInfo(),
                          const SizedBox(height: 32),

                          // Change Email
                          _buildSectionTitle('Change Email'),
                          _buildEmailSection(),
                          const SizedBox(height: 32),

                          // Change Password
                          _buildSectionTitle('Change Password'),
                          _buildPasswordSection(),
                          const SizedBox(height: 32),

                          // Danger Zone
                          _buildSectionTitle('Account'),
                          _buildDangerZone(),
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

  Widget _buildSectionTitle(String title) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: c.textPrimary,
        ),
      ),
    );
  }

  Widget _buildAccountInfo() {
    final c = AppColors.of(context);
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final ownerName = authProvider.ownerDisplayName.trim();
        final ownerEmail = authProvider.ownerDisplayEmail.trim();
        final ownerPhone = authProvider.ownerDisplayPhone.trim();

        final safeName = ownerName.isEmpty ? '-' : ownerName;
        final safeEmail = ownerEmail.isEmpty ? '-' : ownerEmail;
        final safePhone =
            ownerPhone.isEmpty || ownerPhone.startsWith('pending_')
                ? '-'
                : ownerPhone;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.glassBorder),
          ),
          child: Column(
            children: [
              _buildInfoRow(Icons.person, 'Name', safeName),
              const Divider(height: 24),
              _buildInfoRow(Icons.email, 'Email', safeEmail),
              const Divider(height: 24),
              _buildInfoRow(Icons.phone, 'Phone', safePhone),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Icon(icon, color: c.primary, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: c.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailSection() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'New Email Address',
              prefixIcon: const Icon(Icons.email_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isEmailLoading ? null : _updateEmail,
              child: _isEmailLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Update Email',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _newPasswordController,
            obscureText: _obscureNewPassword,
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureNewPassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              helperText: 'Min 8 chars, upper, lower, number, special',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isPasswordLoading ? null : _updatePassword,
              child: _isPasswordLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Update Password',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.logout, color: c.error),
            title: Text('Logout',
                style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
            onTap: () async {
              final didLogout = await _confirmAndSignOut();
              if (didLogout && mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login-selection', (route) => false);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAndSignOut() async {
    final c = AppColors.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

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
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
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
                                  return;
                                }

                                if (Navigator.canPop(dialogContext)) {
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                        child: isLoading
                            ? const _BouncingBallLoader()
                            : Text('Logout', style: TextStyle(color: c.error)),
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
}

class _BouncingBallLoader extends StatefulWidget {
  const _BouncingBallLoader();

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
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
