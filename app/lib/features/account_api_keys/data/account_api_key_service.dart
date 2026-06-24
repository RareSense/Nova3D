import 'package:dio/dio.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/account_api_keys/models/account_api_key_models.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';

class AccountApiKeyException implements Exception {
  AccountApiKeyException(this.message, {this.isAuthError = false});

  final String message;
  final bool isAuthError;

  @override
  String toString() => message;
}

class AccountApiKeyService {
  AccountApiKeyService(this._auth) {
    _dio = Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  final AuthService _auth;
  late final Dio _dio;

  Future<Options> _authOptions() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      throw AccountApiKeyException('Please sign in again.', isAuthError: true);
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<AccountMe> getMe() async {
    try {
      final response = await _dio.get('/me', options: await _authOptions());
      return AccountMe.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw AccountApiKeyException(e.message, isAuthError: true);
    }
  }

  Future<List<AccountApiKey>> listKeys() async {
    try {
      final response = await _dio.get(
        '/api-keys',
        options: await _authOptions(),
      );
      final parsed = AccountApiKeysResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      return parsed.keys.where((key) => key.isActive).toList();
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw AccountApiKeyException(e.message, isAuthError: true);
    }
  }

  Future<CreatedAccountApiKey> createKey(String name) async {
    try {
      final response = await _dio.post(
        '/api-keys',
        data: {'name': name.trim()},
        options: await _authOptions(),
      );
      return CreatedAccountApiKey.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw AccountApiKeyException(e.message, isAuthError: true);
    }
  }

  Future<void> revokeKey(String id) async {
    try {
      await _dio.delete('/api-keys/$id', options: await _authOptions());
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw AccountApiKeyException(e.message, isAuthError: true);
    }
  }

  AccountApiKeyException _exceptionFromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return AccountApiKeyException(
        'Your session expired. Please sign in again.',
        isAuthError: true,
      );
    }
    if (status == 404) {
      return AccountApiKeyException('That API key could not be found.');
    }
    if (status == 422) {
      final message = _safeDetailMessage(e.response?.data);
      return AccountApiKeyException(
        message ?? 'Invalid API key details. Check the name and try again.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return AccountApiKeyException(
        'Could not reach Nova3D. Check your connection and try again.',
      );
    }
    return AccountApiKeyException(
      _safeDetailMessage(e.response?.data) ??
          'API key request failed (${status ?? 'unknown'}).',
    );
  }

  String? _safeDetailMessage(Object? data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    if (detail is Map) {
      final message = detail['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }
}
