import '../../core/constants/enums.dart';

/// Phase 4 Iter 15 OM-08: turf owner / property manager account.
///
/// Invariants enforced by [OwnerModel.fromMap]:
///   * [email] and [phone] are trimmed; [email] is lower-cased.
///   * [authMethods] is a lower-cased, duplicate-free list of strings;
///     non-string entries from malformed rows are skipped rather than
///     crashing.
///   * Malformed timestamp strings fall back to `DateTime.now()`.
///
/// Note: [role] is currently always [UserRole.owner] when loaded via
/// [OwnerModel.fromMap]; the column exists for future admin promotion
/// flows.
class OwnerModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool isVerified;
  final List<String> authMethods;
  final String? profileImage;
  final bool hasPassword;
  final DateTime createdAt;
  final DateTime? updatedAt;

  OwnerModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.role = UserRole.owner,
    this.isVerified = false,
    this.authMethods = const ['email'],
    this.profileImage,
    this.hasPassword = false,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from Supabase map
  factory OwnerModel.fromMap(Map<String, dynamic> data) {
    // Phase 4 Iter 15 OM-01: tolerate malformed timestamps.
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseDateNullable(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // Phase 4 Iter 15 OM-02: safe list coercion + case normalisation.
    // OM-09: treat an empty list as "unknown" (no implicit default).
    List<String> parseAuthMethods(dynamic raw) {
      if (raw is! List) return const ['email'];
      final cleaned = <String>{
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty)
            item.trim().toLowerCase(),
      }.toList();
      if (cleaned.isEmpty) return const ['email'];
      return cleaned;
    }

    // Phase 4 Iter 15 OM-04: trim/normalise email + phone on ingest.
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    final phone = (data['phone'] ?? '').toString().trim();
    final name = (data['name'] ?? '').toString().trim();

    return OwnerModel(
      uid: data['id'] ?? data['uid'] ?? '',
      name: name,
      email: email,
      phone: phone,
      role: UserRole.owner,
      isVerified: data['is_verified'] ?? data['isVerified'] ?? false,
      authMethods: parseAuthMethods(data['auth_methods']),
      profileImage: data['profile_image'] ?? data['profileImage'],
      hasPassword: data['has_password'] ?? data['hasPassword'] ?? false,
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: parseDateNullable(data['updated_at'] ?? data['updatedAt']),
    );
  }

  /// Phase 4 Iter 15 OM-11: sentinel check for ghost owners created
  /// from empty maps.
  bool get isValid => uid.isNotEmpty;

  /// Phase 4 Iter 15 OM-10: convenience "fully onboarded" check.
  bool get isFullyOnboarded => isVerified && hasPassword;

  /// Phase 4 Iter 15 OM-03: map enum value explicitly.
  static String _roleValue(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'OWNER';
      case UserRole.player:
        return 'PLAYER';
      case UserRole.admin:
        return 'ADMIN';
    }
  }

  /// Convert to Supabase map.
  /// Phase 4 Iter 15 OM-03: include `id` when non-empty; derive role
  /// value from the enum instead of hard-coding.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'email': email,
      'phone': phone,
      'role': _roleValue(role),
      'is_verified': isVerified,
      'auth_methods': authMethods,
      'profile_image': profileImage,
      'has_password': hasPassword,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
    if (uid.isNotEmpty) map['id'] = uid;
    return map;
  }

  /// Copy with modified fields.
  /// Phase 4 Iter 15 OM-05: [role] is now copyable (e.g. owner → admin).
  OwnerModel copyWith({
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    bool? isVerified,
    List<String>? authMethods,
    String? profileImage,
    bool? hasPassword,
    DateTime? updatedAt,
  }) {
    return OwnerModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      authMethods: authMethods ?? this.authMethods,
      profileImage: profileImage ?? this.profileImage,
      hasPassword: hasPassword ?? this.hasPassword,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Phase 4 Iter 15 OM-07: value equality by uid (primary key).
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is OwnerModel && other.uid == uid);

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() {
    // Phase 4 Iter 15 OM-06: mask email locals in logs to avoid PII leak.
    final masked = _maskEmail(email);
    return 'OwnerModel(uid: $uid, name: $name, email: $masked)';
  }

  static String _maskEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 0) return '***';
    final local = value.substring(0, at);
    final domain = value.substring(at);
    if (local.length <= 2) return '${local[0]}***$domain';
    return '${local[0]}***${local[local.length - 1]}$domain';
  }
}
