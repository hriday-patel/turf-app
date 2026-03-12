import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/abstract_bg.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';

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
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

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
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Min 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Needs uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'Needs lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Needs a number';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) return 'Needs special character';
    return null;
  }

  Future<void> _updateEmail() async {
    final error = _validateEmail(_emailController.text.trim());
    if (error != null) {
      _showSnackBar(error, isError: true);
      return;
    }

    setState(() => _isEmailLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updateEmail(_emailController.text.trim());
    
    if (!mounted) return;
    setState(() => _isEmailLoading = false);

    if (success) {
      _showSnackBar('Email updated. Check your inbox for verification.');
    } else {
      _showSnackBar(authProvider.errorMessage ?? 'Failed to update email', isError: true);
    }
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

    setState(() => _isPasswordLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updatePassword(newPassword);
    
    if (!mounted) return;
    setState(() => _isPasswordLoading = false);

    if (success) {
      _showSnackBar('Password updated successfully');
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } else {
      _showSnackBar(authProvider.errorMessage ?? 'Failed to update password', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    showAppToast(context, message, type: isError ? ToastType.error : ToastType.success);
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
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textPrimary)),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isEmailLoading ? null : _updateEmail,
              child: _isEmailLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Update Email', style: TextStyle(fontWeight: FontWeight.w600)),
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
                icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isPasswordLoading ? null : _updatePassword,
              child: _isPasswordLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.w600)),
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
            title: Text('Logout', style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Logout', style: TextStyle(color: c.error)),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                await authProvider.signOut();
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login-selection', (route) => false);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
