import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../providers/auth_provider.dart';
import '../utils/auth_form_utils.dart';

/// Modal phone-verification dialog used by both player and owner signup flows
/// to complete a deferred (pending) signup that still requires OTP verification.
///
/// Behavior (Phase 5 Iter 21 hardened):
///   * Two-step UI: collect/confirm phone number → send OTP → verify OTP.
///   * Phone field accepts only digits, capped to 10, with `+91` prefix.
///   * OTP field accepts only digits, capped to 6, hooked to `oneTimeCode`
///     autofill so platform-suggested OTPs flow in automatically.
///   * For legacy owner flows still in `isInDeferredSignupFlow`, calls
///     `completeDeferredOwnerSignup` after OTP verification.
///   * Returns `true` when verification (and any deferred completion) succeeds.
///   * Returns `false` when the user cancels (also cancels deferred signup).
///   * `barrierDismissible: false` — only Cancel/Verify can close the dialog.
///   * All `setDialogState` calls after awaits are guarded by
///     `dialogContext.mounted` so dismissed-mid-request dialogs do not leak
///     setState calls.
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
                dialogError = AppStrings.pendingSignupInvalidPhone;
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
            if (!dialogContext.mounted) return;
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
            if (!dialogContext.mounted) return;

            setDialogState(() {
              busy = false;
              otpSent = sent;
              dialogError = sent
                  ? null
                  : (authProvider.errorMessage ??
                      AppStrings.pendingSignupOtpSendFailed);
            });
          }

          Future<void> verifyOtpAndFinalize() async {
            final otp = otpController.text.trim();
            if (!AuthFormUtils.isValidOtp(otp)) {
              setDialogState(() {
                dialogError = AppStrings.pendingSignupInvalidOtp;
              });
              return;
            }

            setDialogState(() {
              busy = true;
              dialogError = null;
            });

            final verified = await authProvider.verifyOTP(otp);
            if (!dialogContext.mounted) return;
            if (!verified) {
              setDialogState(() {
                busy = false;
                dialogError = authProvider.errorMessage ??
                    AppStrings.pendingSignupOtpVerifyFailed;
              });
              return;
            }

            // Defensive compatibility path for older pending-owner flows.
            if (role == UserRole.owner && authProvider.isInDeferredSignupFlow) {
              final completed =
                  await authProvider.completeDeferredOwnerSignup();
              if (!dialogContext.mounted) return;
              if (!completed) {
                setDialogState(() {
                  busy = false;
                  dialogError = authProvider.errorMessage ??
                      AppStrings.pendingSignupCompleteFailed;
                });
                return;
              }
            }

            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          }

          final theme = Theme.of(dialogContext);

          return AlertDialog(
            title: const Text(AppStrings.pendingSignupTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  enabled: !otpSent && !busy,
                  maxLength: 10,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  textInputAction:
                      otpSent ? TextInputAction.next : TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onSubmitted: (_) {
                    if (!busy && !otpSent) {
                      sendOtp();
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: AppStrings.pendingSignupPhoneLabel,
                    prefixText: '+91 ',
                    counterText: '',
                  ),
                ),
                if (otpSent)
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    enabled: !busy,
                    maxLength: 6,
                    autofocus: true,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) {
                      if (!busy) {
                        verifyOtpAndFinalize();
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: AppStrings.pendingSignupOtpLabel,
                      counterText: '',
                    ),
                  ),
                if (dialogError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      dialogError!,
                      style: TextStyle(color: theme.colorScheme.error),
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
                child: const Text(AppStrings.pendingSignupCancel),
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
                      ? AppStrings.pendingSignupBusy
                      : (otpSent
                          ? AppStrings.pendingSignupVerifyOtp
                          : AppStrings.pendingSignupSendOtp),
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
