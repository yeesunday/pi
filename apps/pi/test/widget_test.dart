import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_runtime/pi_runtime.dart';

void main() {
  testWidgets('Pi renders its own dashboard shell', (tester) async {
    final runtime = PiRuntime(catalog: PluginCatalog(const []));
    await tester.pumpWidget(PiApp(runtime: runtime));
    expect(find.text('今天，也按自己的节奏来。'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    runtime.dispose();
  });
}
