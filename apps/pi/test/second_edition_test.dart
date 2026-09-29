import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_runtime/pi_runtime.dart';
void main() {
  testWidgets('second edition shell remains usable on compact and wide layouts', (tester) async {
    final runtime = PiRuntime(catalog: PluginCatalog(const []));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(PiApp(runtime: runtime));
    expect(find.text('今日'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pump();
    expect(find.text('设置'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
    runtime.dispose();
  });
}
