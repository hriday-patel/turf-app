import '../../core/constants/enums.dart';

/// Player model representing a customer/user
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
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return PlayerModel(
      uid: data['id'] ?? data['uid'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: UserRole.player,
      authMethods: data['auth_methods'] != null
          ? List<String>.from(data['auth_methods'] as List)
          : const ['email'],
      hasPassword: data['has_password'] ?? data['hasPassword'] ?? false,
      profileImage: data['profile_image'] ?? data['profileImage'],
      favoriteTurfs: List<String>.from(
          data['favorite_turfs'] ?? data['favoriteTurfs'] ?? []),
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: data['updated_at'] != null || data['updatedAt'] != null
          ? parseDate(data['updated_at'] ?? data['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': 'PLAYER',
      'auth_methods': authMethods,
      'has_password': hasPassword,
      'profile_image': profileImage,
      'favorite_turfs': favoriteTurfs,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PlayerModel copyWith({
    String? name,
    String? phone,
    List<String>? authMethods,
    bool? hasPassword,
    String? profileImage,
    List<String>? favoriteTurfs,
  }) {
    return PlayerModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      authMethods: authMethods ?? this.authMethods,
      hasPassword: hasPassword ?? this.hasPassword,
      profileImage: profileImage ?? this.profileImage,
      favoriteTurfs: favoriteTurfs ?? this.favoriteTurfs,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
