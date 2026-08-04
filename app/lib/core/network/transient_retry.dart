import 'package:dio/dio.dart';

const _defaultRetryDelays = <Duration>[
  Duration(milliseconds: 250),
  Duration(milliseconds: 750),
];

/// Retries an idempotent Dio operation after a bounded transient failure.
///
/// This is intentionally not a Dio interceptor: automatic retries on writes
/// can duplicate side effects. Callers must opt in only for safe GET-style
/// operations. Authentication and other permanent 4xx failures fail fast.
Future<T> retryIdempotentDio<T>(
  Future<T> Function() operation, {
  int maxAttempts = 3,
  List<Duration> delays = _defaultRetryDelays,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
  }

  for (var attempt = 1; ; attempt++) {
    try {
      return await operation();
    } on DioException catch (error) {
      if (attempt >= maxAttempts || !isTransientDioFailure(error)) rethrow;
      if (delays.isNotEmpty) {
        final delayIndex = (attempt - 1).clamp(0, delays.length - 1);
        await Future<void>.delayed(delays[delayIndex]);
      }
    }
  }
}

bool isTransientDioFailure(DioException error) {
  final status = error.response?.statusCode;
  if (status != null) {
    return status == 408 ||
        status == 425 ||
        status == 429 ||
        status == 500 ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }

  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.unknown;
}
