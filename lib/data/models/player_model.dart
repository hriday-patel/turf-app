import '../../core/constants/enums.dart';

/// Phase 4 Iter 16 PM-10: customer / end-user account.
///
/// Invariants enforced by [PlayerModel.fromMap]:
///   * [email] and [phone] are trimmed; [email] is lower-cased.
///   * [authMethods] and [favoriteTurfs] are lower-cased (methods only),
///     trimmed, deduped lists of strings; malformed or non-string
///     entries are skipped rather than crashing.
///   * Malformed timestamp strings fall back to `DateTime.now()`.
class PlayerModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final List<String> authMethods;
  final bool hasPassword;
  final String? profileImage;
  final List<String> favoriteTurfs;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PlayerModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.role = UserRole.player,
    this.authMethods = const ['email'],
    this.hasPassword = false,
    this.profileImage,
    this.favoriteTurfs = const [],
    required this.createdAt,
    this.updatedAt,
  });

  factory PlayerModel.fromMap(Map<String, dynamic> data) {
    // Phase 4 Iter 16 PM-01: tolerate malformed timestamps.
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

    // Phase 4 Iter 16 PM-03: safe list coercion + case normalisation.
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

    // Phase 4 Iter 16 PM-02 + PM-07: safe favorites coercion; dedupe;
    // drop empty strings.
    List<String> parseFavorites(dynamic raw) {
      if (raw is! List) return const [];
      return <String>{
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      }.toList();
    }

    // Phase 4 Iter 16 PM-05: trim/normalise name/email/phone.
    final name = (data['name'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    final phone = (data['phone'] ?? '').toString().trim();

    return PlayerModel(
      uid: data['id'] ?? data['uid'] ?? '',
      name: name,
      email: email,
      phone: phone,
      role: UserRole.player,
      authMethods: parseAuthMethods(data['auth_methods']),
      hasPassword: data['has_password'] ?? data['hasPassword'] ?? false,
      profileImage: data['profile_image'] ?? data['profileImage'],
      favoriteTurfs:
          parseFavorites(data['favorite_turfs'] ?? data['favoriteTurfs']),
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: parseDateNullable(data['updated_at'] ?? data['updatedAt']),
    );
  }

  /// Phase 4 Iter 16 PM-11: sentinel for ghost players from empty maps.
  bool get isValid => uid.isNotEmpty;

  /// Phase 4 Iter 16 PM-04: map enum value explicitly.
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

  /// Phase 4 Iter 16 PM-04: include `id` on upsert; derive role from enum.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'email': email,
      'phone': phone,
      'role': _roleValue(role),
      'auth_methods': authMethods,
      'has_password': hasPassword,
      'profile_image': profileImage,
      'favorite_turfs': favoriteTurfs,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
    if (uid.isNotEmpty) map['id'] = uid;
    return map;
  }

  /// Phase 4 Iter 16 PM-06: [email], [role], and [updatedAt] are now
  /// copyable. [updatedAt] defaults to the existing value (not
  /// `DateTime.now()`) so callers who only want to tweak a single
  /// field don't accidentally overwrite server-provided timestamps.
  PlayerModel copyWith({
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    List<String>? authMethods,
    bool? hasPassword,
    String? profileImage,
    List<String>? favoriteTurfs,
    DateTime? updatedAt,
  }) {
    return PlayerModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      authMethods: authMethods ?? this.authMethods,
      hasPassword: hasPassword ?? this.hasPassword,
      profileImage: profileImage ?? this.profileImage,
      favoriteTurfs: favoriteTurfs ?? this.favoriteTurfs,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Phase 4 Iter 16 PM-09: value equality by uid (primary key).
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PlayerModel && other.uid == uid);

  @override
  int get hashCode => uid.hashCode;

  /// Phase 4 Iter 16 PM-08: useful debug output; email is masked to
  /// avoid PII leaks in logs.
  @override
  String toString() {
    return 'PlayerModel(uid: $uid, name: $name, email: ${_maskEmail(email)}, '
        'favs: ${favoriteTurfs.length})';
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
