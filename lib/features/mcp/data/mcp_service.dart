import 'package:dio/dio.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';

class McpException implements Exception {
  McpException(this.message, {this.isAuthError = false});

  final String message;
  final bool isAuthError;

  @override
  String toString() => message;
}

class McpService {
  McpService(this._auth) {
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

  Future<McpStatus> getStatus() async {
    try {
      final response = await _dio.get(
        '/mcp/status',
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return McpStatus.fromJson(data);
      if (data is Map) {
        return McpStatus.fromJson(Map<String, dynamic>.from(data));
      }
      throw McpException('Nova3D returned an unexpected MCP status response.');
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw McpException(e.message, isAuthError: true);
    }
  }

  Future<String> createSessionCode() async {
    try {
      final response = await _dio.post(
        '/mcp/session/create',
        data: const <String, dynamic>{},
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is Map) {
        final sessionCode = (data['session_code'] ?? '').toString().trim();
        if (sessionCode.isNotEmpty) return sessionCode;
      }
      throw McpException('Nova3D did not return an MCP session code.');
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw McpException(e.message, isAuthError: true);
    }
  }

  Future<Options> _authOptions() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      throw McpException('Please sign in again.', isAuthError: true);
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  McpException _exceptionFromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return McpException(
        'Your session expired. Please sign in again.',
        isAuthError: true,
      );
    }
    if (status == 422) {
      return McpException(
        _safeDetailMessage(e.response?.data) ??
            'Nova3D could not complete MCP setup yet.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.unknown) {
      return McpException(
        'Could not reach Nova3D setup services. Check your connection and try again.',
      );
    }
    return McpException(
      _safeDetailMessage(e.response?.data) ??
          'Nova3D MCP setup failed (${status ?? 'unknown'}).',
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
