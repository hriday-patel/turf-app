import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';

enum OtpDeliveryChannel { mobile, email }

/// Settings Screen
/// Change email, change password with validation
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const int _maxOtpSends = 3;
  static const Duration _otpCooldownDuration = Duration(minutes: 30);

  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isEmailLoading = false;
  bool _isPasswordLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  DateTime? _emailOtpBlockedUntil;
  DateTime? _passwordOtpBlockedUntil;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _emailController.text = authProvider.currentEmail ?? '';
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
    final ownerPhone = authProvider.currentOwner?.phone?.trim();
    if (ownerPhone == null || ownerPhone.isEmpty) {
      _showSnackBar('Registered mobile number not found.', isError: true);
      return;
    }

    final otpVerified = await _runOtpFlow(
      purpose: 'email update',
      destinationLabel: 'registered mobile ${_maskPhone(ownerPhone)}',
      blockedUntil: _emailOtpBlockedUntil,
      onBlockedUntilChanged: (value) {
        setState(() => _emailOtpBlockedUntil = value);
      },
    );
    if (!otpVerified) return;

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
    final selectedChannel = await _selectOtpChannel();
    if (!mounted || selectedChannel == null) return;

    final owner = authProvider.currentOwner;
    String? destinationLabel;
    if (selectedChannel == OtpDeliveryChannel.mobile) {
      final phone = owner?.phone?.trim();
      if (phone == null || phone.isEmpty) {
        _showSnackBar('Registered mobile number not found.', isError: true);
        return;
      }
      destinationLabel = 'registered mobile ${_maskPhone(phone)}';
    } else {
      final email = owner?.email.trim();
      if (email == null || email.isEmpty) {
        _showSnackBar('Registered email not found.', isError: true);
        return;
      }
      destinationLabel = 'registered email ${_maskEmail(email)}';
    }

    final otpVerified = await _runOtpFlow(
      purpose: 'password update',
      destinationLabel: destinationLabel,
      blockedUntil: _passwordOtpBlockedUntil,
      onBlockedUntilChanged: (value) {
        setState(() => _passwordOtpBlockedUntil = value);
      },
    );
    if (!otpVerified) return;

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
            'Password changed successfully. Please use the updated password next time you login.',
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

  Future<OtpDeliveryChannel?> _selectOtpChannel() async {
    return showDialog<OtpDeliveryChannel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive OTP On'),
        content: const Text(
            'Choose where you want to receive the OTP for password update.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, OtpDeliveryChannel.mobile),
            child: const Text('Mobile'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, OtpDeliveryChannel.email),
            child: const Text('Email'),
          ),
        ],
      ),
    );
  }

  Future<bool> _runOtpFlow({
    required String purpose,
    required String destinationLabel,
    required DateTime? blockedUntil,
    required ValueChanged<DateTime?> onBlockedUntilChanged,
  }) async {
    final now = DateTime.now();
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      final remaining = blockedUntil.difference(now).inMinutes;
      _showSnackBar(
        'Too many OTP attempts. Try again later (${remaining + 1} min remaining).',
        isError: true,
      );
      return false;
    }

    final otpController = TextEditingController();
    String currentOtp = _generateOtp();
    int sendCount = 1;
    _showSnackBar('Simulation OTP for $destinationLabel: $currentOtp');

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? errorText;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canResend = sendCount < _maxOtpSends;

            Future<void> handleResend() async {
              if (!canResend) {
                final until = DateTime.now().add(_otpCooldownDuration);
                onBlockedUntilChanged(until);
                if (Navigator.canPop(dialogContext)) {
                  Navigator.pop(dialogContext, false);
                }
                _showSnackBar(
                    'Try again later. OTP limit reached for 30 minutes.',
                    isError: true);
                return;
              }

              setDialogState(() {
                sendCount++;
                currentOtp = _generateOtp();
                otpController.clear();
                errorText = null;
              });
              _showSnackBar(
                  'Simulation OTP for $destinationLabel: $currentOtp');
            }

            Future<void> handleVerify() async {
              final entered = otpController.text.trim();
              if (entered.length != 4) {
                setDialogState(() => errorText = 'Enter 4-digit OTP');
                return;
              }

              if (entered != currentOtp) {
                if (canResend) {
                  setDialogState(() {
                    errorText = 'Invalid OTP. Try again or regenerate OTP.';
                  });
                } else {
                  final until = DateTime.now().add(_otpCooldownDuration);
                  onBlockedUntilChanged(until);
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.pop(dialogContext, false);
                  }
                  _showSnackBar(
                      'Try again later. OTP limit reached for 30 minutes.',
                      isError: true);
                }
                return;
              }

              if (Navigator.canPop(dialogContext)) {
                Navigator.pop(dialogContext, true);
              }
            }

            return AlertDialog(
              title: Text('Verify OTP for ${_capitalize(purpose)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the 4-digit OTP sent to $destinationLabel.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: InputDecoration(
                      hintText: '4-digit OTP',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Simulation OTP: $currentOtp',
                    style:
                        Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                  ),
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
                TextButton(
                  onPressed: handleResend,
                  child: Text(canResend ? 'Regenerate OTP' : 'Limit Reached'),
                ),
                ElevatedButton(
                  onPressed: handleVerify,
                  child: const Text('Verify'),
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

  String _generateOtp() {
    final random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  String _maskPhone(String phone) {
    final compact = phone.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return compact;
    final last4 = compact.substring(compact.length - 4);
    return 'xxxxxx$last4';
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts[0];
    if (local.isEmpty) return '***@${parts[1]}';
    if (local.length <= 2) return '${local[0]}***@${parts[1]}';
    return '${local.substring(0, 2)}***@${parts[1]}';
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
        final owner = authProvider.currentOwner;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.glassBorder),
          ),
          child: Column(
            children: [
              _buildInfoRow(Icons.person, 'Name', owner?.name ?? '-'),
              const Divider(height: 24),
              _buildInfoRow(Icons.email, 'Email', owner?.email ?? '-'),
              const Divider(height: 24),
              _buildInfoRow(Icons.phone, 'Phone', owner?.phone ?? '-'),
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
