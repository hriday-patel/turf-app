import '../../core/constants/enums.dart';

/// Owner model representing a turf owner/property manager
class OwnerModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool isVerified;
  final List<String> authMethods;
  final String? profileImage;
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
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from Supabase map
  factory OwnerModel.fromMap(Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return OwnerModel(
      uid: data['id'] ?? data['uid'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: UserRole.owner,
      isVerified: data['is_verified'] ?? data['isVerified'] ?? false,
      authMethods: data['auth_methods'] != null
          ? List<String>.from(data['auth_methods'] as List)
          : const ['email'],
      profileImage: data['profile_image'] ?? data['profileImage'],
      createdAt: parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: data['updated_at'] != null || data['updatedAt'] != null
          ? parseDate(data['updated_at'] ?? data['updatedAt'])
          : null,
    );
  }

  /// Convert to Supabase map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': 'OWNER',
      'is_verified': isVerified,
      'auth_methods': authMethods,
      'profile_image': profileImage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Copy with modified fields
  OwnerModel copyWith({
    String? name,
    String? email,
    String? phone,
    bool? isVerified,
    List<String>? authMethods,
    String? profileImage,
    DateTime? updatedAt,
  }) {
    return OwnerModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role,
      isVerified: isVerified ?? this.isVerified,
      authMethods: authMethods ?? this.authMethods,
      profileImage: profileImage ?? this.profileImage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'OwnerModel(uid: $uid, name: $name, email: $email)';
  }
}
