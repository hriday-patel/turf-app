import 'package:cloud_functions/cloud_functions.dart';

/// Owner Auth Backend Service
/// Uses Cloud Functions for secure owner identity checks and phone linking.
class OwnerAuthBackendService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String _handleFunctionsError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service temporarily unavailable. Please try again.';
        case 'internal':
          return 'Service error. Please try again.';
        case 'invalid-argument':
          return error.message ?? 'Invalid request.';
        case 'not-found':
          return error.message ?? 'Account not found.';
        case 'unauthenticated':
          return 'Authentication required. Please try again.';
        case 'permission-denied':
          return 'Permission denied. Please try again.';
        default:
          return error.message ?? 'Request failed.';
      }
    }
    return 'Request failed. Please try again.';
  }

  /// Check if an owner exists for a phone number (pre-OTP).
  Future<bool> checkOwnerPhoneExists(String phone) async {
    try {
      final callable = _functions.httpsCallable('checkOwnerPhoneExists');
      final result = await callable.call({'phone': phone});
      final data = result.data as Map<String, dynamic>;
      return data['exists'] == true;
    } catch (e) {
      throw _handleFunctionsError(e);
    }
  }

  /// Resolve owner UID by phone number.
  Future<String?> getOwnerUidByPhone(String phone) async {
    try {
      final callable = _functions.httpsCallable('getOwnerUidByPhone');
      final result = await callable.call({'phone': phone});
      final data = result.data as Map<String, dynamic>;
      return data['ownerUid'] as String?;
    } catch (e) {
      throw _handleFunctionsError(e);
    }
  }

  /// Link verified phone auth to owner account and issue custom token.
  Future<String> linkPhoneToOwnerAndIssueToken({
    required String phone,
    required String phoneAuthUid,
  }) async {
    try {
      final callable = _functions.httpsCallable('linkPhoneToOwnerAndIssueToken');
      final result = await callable.call({
        'phone': phone,
        'phoneAuthUid': phoneAuthUid,
      });
      final data = result.data as Map<String, dynamic>;
      final token = data['customToken'] as String?;
      if (token == null || token.isEmpty) {
        throw 'Failed to link phone to owner account.';
      }
      return token;
    } catch (e) {
      throw _handleFunctionsError(e);
    }
  }
}
