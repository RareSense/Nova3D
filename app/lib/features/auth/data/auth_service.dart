import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/errors.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  AppError toAppError() =>
      AppError(message, kind: AppErrorKind.authentication, cause: this);

  @override
  String toString() => message;
}

class AuthService {
  late final Dio _dio;

  AuthService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kAuthBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
  }

  // ── Token helpers ──────────────────────────────────────────────────────────

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kTokenKey);
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kTokenKey, token);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTokenKey);
  }

  // ── Email / Password ───────────────────────────────────────────────────────

  Future<String> signIn(String email, String password) async {
    try {
      final response = await _dio.post(
        '/auth/jwt/login',
        data:
            'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final token = response.data['access_token'] as String;
      await _saveToken(token);
      return token;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      if (detail is String) throw AuthException(detail);
      throw AuthException('Invalid email or password');
    }
  }

  Future<UserModel> signUp(String email, String password) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {'email': email, 'password': password},
      );
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      if (detail is String) throw AuthException(detail);
      if (detail is List && detail.isNotEmpty) {
        throw AuthException(
          detail.first['msg'] as String? ?? 'Registration failed',
        );
      }
      throw AuthException('Registration failed');
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post('/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      throw AuthException(
        detail is String ? detail : 'Failed to send reset email',
      );
    }
  }

  Future<void> resetPassword(String token, String newPassword) async {
    try {
      await _dio.post(
        '/auth/reset-password',
        data: {'token': token, 'password': newPassword},
      );
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      throw AuthException(
        detail is String ? detail : 'Failed to reset password',
      );
    }
  }

  // ── Google OAuth ───────────────────────────────────────────────────────────

  // Passes this app's origin as redirect_to so the auth service sends the
  // token back here rather than to another registered frontend.
  Future<String> getGoogleAuthorizationUrl() async {
    // web.window.location.origin e.g. "http://localhost:5555"
    final origin = web.window.location.origin;

    final response = await _dio.get(
      '/auth/google/authorize',
      queryParameters: origin.isNotEmpty ? {'redirect_to': origin} : null,
    );
    return response.data['authorization_url'] as String;
  }

  // Called from the OAuth callback page after the server redirects back.
  Future<void> handleOAuthCallback(String token) async {
    await _saveToken(token);
  }

  // ── Current user ──────────────────────────────────────────────────────────

  Future<UserModel> getCurrentUser() async {
    final token = await getToken();
    if (token == null) throw AuthException('Not authenticated');

    try {
      return _userFromJwt(token);
    } on FormatException {
      await _clearToken();
      throw AuthException('Session expired');
    }
  }

  UserModel _userFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('Invalid token');

    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;

    final exp = payload['exp'];
    if (exp is num) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw const FormatException('Token expired');
      }
    }

    final id = payload['sub'] as String?;
    if (id == null || id.isEmpty) throw const FormatException('Missing sub claim');

    // email is not a required JWT claim in all FastAPI Users configurations.
    final email = payload['email'] as String? ?? '';

    return UserModel(
      id: id,
      email: email,
      isActive: true,
      isVerified: false,
      isSuperuser: false,
    );
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _clearToken();
  }
}
