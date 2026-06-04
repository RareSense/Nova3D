import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/errors.dart';
import 'package:nova3d_frontend/core/theme.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error, this.onDismiss});

  final AppError error;
  final VoidCallback? onDismiss;

  static void showSnackbar(BuildContext context, AppError error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: kBgSecondary,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kErrorRed),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: kErrorRed),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            error.message,
            style: const TextStyle(color: kTextPrimary, fontSize: 13),
          ),
        ),
        if (onDismiss != null)
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            color: kTextMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    ),
  );
}
