import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_plugin_sketch/sketch.dart';
import 'package:pi_runtime/pi_runtime.dart';

void main() {
  testWidgets('draw from home, save, and edit the same sketch', (tester) async {
    const portrait = Size(375, 812);
    await tester.binding.setSurfaceSize(portrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final runtime = PiRuntime(
      catalog: PluginCatalog([
        PluginDescriptor(manifest: sketchManifest, create: SketchPlugin.new),
      ]),
    );
    addTearDown(runtime.dispose);
    await runtime.install(sketchManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建画板'));
    await tester.pumpAndSettle();
    final paper = find.bySemanticsLabel('手绘画布');
    expect(tester.getSize(paper), portrait);
    await tester.tap(find.byTooltip('画笔颜色'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<Color>, '绿色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('笔触大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '粗'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起工具'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(20, 700), const Offset(60, 30));
    await tester.binding.setSurfaceSize(const Size(812, 375));
    await tester.pumpAndSettle();
    expect(tester.getSize(paper), const Size(812, 375));
    await tester.tap(find.byTooltip('展开工具'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '动线草图');
    await tester.tap(find.byTooltip('保存画板'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('画板').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('动线草图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    final share = find.widgetWithIcon(IconButton, Icons.ios_share_rounded);
    expect(tester.widget<IconButton>(share).onPressed, isNull);
    await tester.tap(find.byTooltip('重做'));
    await tester.tap(find.byTooltip('保存画板'));
    await tester.pumpAndSettle();
    final boards = await runtime.data.list(
      pluginId: sketchManifest.id,
      type: 'drawing',
    );
    final stroke = (boards.single.data['strokes'] as List).single as Map;
    expect((stroke['points'] as List).length, greaterThan(1));
    expect(stroke['width'], 12);
    expect(stroke['ink'], 0xff238451);
  });
}
