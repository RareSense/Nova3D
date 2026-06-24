class UserModel {
  final String id;
  final String email;
  final bool isActive;
  final bool isVerified;
  final bool isSuperuser;

  const UserModel({
    required this.id,
    required this.email,
    required this.isActive,
    required this.isVerified,
    required this.isSuperuser,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        isActive: json['is_active'] as bool? ?? true,
        isVerified: json['is_verified'] as bool? ?? false,
        isSuperuser: json['is_superuser'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'is_active': isActive,
        'is_verified': isVerified,
        'is_superuser': isSuperuser,
      };
}
