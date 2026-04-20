import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../providers/auth_provider.dart';
import '../utils/auth_form_utils.dart';

Future<bool> showPendingSignupVerificationDialog({
  required BuildContext context,
  required AuthProvider authProvider,
  required UserRole role,
  required String initialPhone,
}) async {
  final phoneController = TextEditingController(
    text: AuthFormUtils.stripIndiaDialCode(initialPhone),
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
            if (!AuthFormUtils.isValidIndianPhoneInput(phone)) {
              setDialogState(() {
                dialogError = 'Enter a valid 10-digit phone number.';
              });
              return;
            }

            final normalizedPhone = AuthFormUtils.normalizeIndianPhone(phone);
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
              role: role,
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
            if (!AuthFormUtils.isValidOtp(otp)) {
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
            if (!verified) {
              setDialogState(() {
                busy = false;
                dialogError = authProvider.errorMessage ??
                    'OTP verification failed. Please try again.';
              });
              return;
            }

            // Defensive compatibility path for older pending-owner flows.
            if (role == UserRole.owner && authProvider.isInDeferredSignupFlow) {
              final completed =
                  await authProvider.completeDeferredOwnerSignup();
              if (!completed) {
                setDialogState(() {
                  busy = false;
                  dialogError = authProvider.errorMessage ??
                      'Could not complete signup. Please try again.';
                });
                return;
              }
            }

            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
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
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(false);
                        }
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
