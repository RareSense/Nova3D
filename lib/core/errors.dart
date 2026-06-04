enum AppErrorKind {
  network,
  authentication,
  authorization,
  validation,
  persistence,
  unknown,
}

class AppError implements Exception {
  const AppError(
    this.message, {
    this.kind = AppErrorKind.unknown,
    this.cause,
  });

  final String message;
  final AppErrorKind kind;
  final Object? cause;

  bool get isAuth =>
      kind == AppErrorKind.authentication || kind == AppErrorKind.authorization;

  @override
  String toString() => 'AppError(${kind.name}): $message';
}
