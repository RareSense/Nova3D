import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';

class AuthGuard extends ConsumerWidget {
  const AuthGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: kBgDark,
        body: Center(
          child: CircularProgressIndicator(color: kAccentBlue),
        ),
      );
    }

    if (auth.valueOrNull == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final location = GoRouter.of(context).state.uri.toString();
        context.go('/signin?redirect=${Uri.encodeComponent(location)}');
      });
      return const SizedBox.shrink();
    }

    return child;
  }
}
