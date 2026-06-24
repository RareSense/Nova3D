import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/main.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Nova3DApp()));
    await tester.pump();
  });
}
