import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_plugin_anniversary/anniversary.dart';
import 'package:pi_runtime/pi_runtime.dart';

class _CountingReminderService extends InMemoryReminderService {
  int reconciliations = 0;

  @override
  Future<void> reconcile() async {
    reconciliations++;
  }
}

void main() {
  testWidgets('Pi renders its own dashboard shell', (tester) async {
    final runtime = PiRuntime(
      catalog: PluginCatalog([
        PluginDescriptor(
          manifest: anniversaryManifest,
          create: AnniversaryPlugin.new,
        ),
      ]),
    );
    await runtime.install(anniversaryManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.text('今天，也按自己的节奏来。'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.byTooltip('设置与数据'), findsNothing);

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义首页'), findsOneWidget);
    expect(find.text('已显示在首页'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('未显示'), findsOneWidget);
    runtime.dispose();
  });

  testWidgets('returning to foreground rebuilds the notification window', (
    tester,
  ) async {
    final reminders = _CountingReminderService();
    final runtime = PiRuntime(
      catalog: PluginCatalog(const []),
      reminders: reminders,
    );
    await tester.pumpWidget(PiApp(runtime: runtime));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(reminders.reconciliations, 1);
    runtime.dispose();
  });
}
