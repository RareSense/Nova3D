import 'package:dio/dio.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/subscription/models/billing_models.dart';

const String _billingBaseUrl = String.fromEnvironment(
  'BILLING_BASE_URL',
  defaultValue: 'https://nova3d.xyz',
);

const String _graphFlowApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://nova3d.xyz/api',
);

class BillingException implements Exception {
  BillingException(this.message, {this.isAuthError = false});

  final String message;
  final bool isAuthError;

  @override
  String toString() => message;
}

class BillingService {
  BillingService(this._auth) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _billingBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _apiDio = Dio(
      BaseOptions(
        baseUrl: _graphFlowApiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  final AuthService _auth;
  late final Dio _dio;
  late final Dio _apiDio;

  Future<List<BillingTier>> listTiers() async {
    try {
      final response = await _dio.get(
        '/billing/tiers',
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is! List) {
        throw BillingException('Billing returned an unexpected tier list.');
      }

      final tiers =
          data
              .whereType<Map>()
              .map(
                (item) => BillingTier.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((tier) => tier.tierId.isNotEmpty && tier.credits > 0)
              .toList()
            ..sort((a, b) => a.credits.compareTo(b.credits));

      return tiers;
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw BillingException(e.message, isAuthError: true);
    }
  }

  Future<String> createCheckout(
    String tierId, {
    BillingCheckoutSource source = BillingCheckoutSource.web,
  }) async {
    try {
      final response = await _dio.post(
        '/billing/checkout',
        data: {'tier_id': tierId, 'source': source.value},
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is Map && data['url'] is String) {
        final url = (data['url'] as String).trim();
        if (url.isNotEmpty) return url;
      }
      throw BillingException('Billing did not return a checkout URL.');
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw BillingException(e.message, isAuthError: true);
    }
  }

  Future<BillingWallet> getWallet() async {
    try {
      final response = await _apiDio.get(
        '/credits/balance/me',
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is Map) {
        return BillingWallet.fromJson(Map<String, dynamic>.from(data));
      }
      throw BillingException('Credits returned an unexpected wallet response.');
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw BillingException(e.message, isAuthError: true);
    }
  }

  Future<CheckoutVerification> verifyCheckout(String sessionId) async {
    try {
      final response = await _dio.get(
        '/billing/checkout/verify/$sessionId',
        options: await _authOptions(),
      );
      final data = response.data;
      if (data is Map) {
        return CheckoutVerification.fromJson(Map<String, dynamic>.from(data));
      }
      throw BillingException(
        'Billing returned an unexpected verification response.',
      );
    } on DioException catch (e) {
      throw _exceptionFromDio(e);
    } on AuthException catch (e) {
      throw BillingException(e.message, isAuthError: true);
    }
  }

  Future<Options> _authOptions() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      throw BillingException('Please sign in again.', isAuthError: true);
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  BillingException _exceptionFromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return BillingException(
        'Your session expired. Please sign in again.',
        isAuthError: true,
      );
    }
    if (status == 404) {
      return BillingException('That credit package is no longer available.');
    }
    if (status == 422) {
      return BillingException(
        _safeDetailMessage(e.response?.data) ??
            'Billing could not process that package.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return BillingException(
        'Could not reach billing. Check your connection and try again.',
      );
    }
    return BillingException(
      _safeDetailMessage(e.response?.data) ??
          'Billing request failed (${status ?? 'unknown'}).',
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

enum BillingCheckoutSource { web, mcp }

extension on BillingCheckoutSource {
  String get value => switch (this) {
    BillingCheckoutSource.web => 'web',
    BillingCheckoutSource.mcp => 'mcp',
  };
}
