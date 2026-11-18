import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_plugin_todo/todo.dart';
import 'package:pi_runtime/pi_runtime.dart';

void main() {
  PiEntity todo(Map<String, Object?> data, {DateTime? createdAt}) => PiEntity(
    id: 'cat-litter',
    pluginId: todoManifest.id,
    type: 'todo',
    data: {'title': '铲猫砂', ...data},
    createdAt: createdAt,
  );

  test('a future todo enters Today on its start date', () {
    final item = todo({'startAt': '2026-10-03T09:15:00', 'repeat': 'none'});

    expect(todoOccursOn(item, DateTime(2026, 10, 2)), isFalse);
    expect(todoOccursOn(item, DateTime(2026, 10, 3)), isTrue);
    expect(todoOccursOn(item, DateTime(2026, 10, 4)), isTrue);
  });

  test('weekly todos only occur on selected weekdays after start', () {
    final item = todo({
      'startAt': '2026-10-01T08:15:00',
      'repeat': 'weekly',
      'weekdays': [DateTime.tuesday, DateTime.saturday],
    });

    expect(todoOccursOn(item, DateTime(2026, 9, 29)), isFalse);
    expect(todoOccursOn(item, DateTime(2026, 10, 3)), isTrue);
    expect(todoOccursOn(item, DateTime(2026, 10, 6)), isTrue);
    expect(todoOccursOn(item, DateTime(2026, 10, 7)), isFalse);
  });

  test('weekly completion is tracked per occurrence', () {
    final item = todo({
      'startAt': '2026-09-01T08:15:00',
      'repeat': 'weekly',
      'weekdays': [DateTime.tuesday, DateTime.saturday],
      'completedDates': ['2026-10-03'],
    });

    expect(todoCompletedOn(item, DateTime(2026, 10, 3)), isTrue);
    expect(todoCompletedOn(item, DateTime(2026, 10, 6)), isFalse);
  });

  test('weekly start and end create durable system recurrences', () {
    final item = todo({
      'startAt': '2026-09-28T08:15:00',
      'endAt': '2026-09-28T08:45:00',
      'repeat': 'weekly',
      'weekdays': [DateTime.tuesday, DateTime.saturday],
    });

    final reminders = todoReminders(item, from: DateTime(2026, 9, 26, 10));
    expect(reminders, hasLength(4));
    expect(
      reminders.every((reminder) => reminder.repeat == RepeatUnit.week),
      isTrue,
    );
    expect(reminders.map((reminder) => reminder.when), {
      DateTime(2026, 9, 29, 8, 15),
      DateTime(2026, 9, 29, 8, 45),
      DateTime(2026, 10, 3, 8, 15),
      DateTime(2026, 10, 3, 8, 45),
    });
  });

  test('one-off reminders preserve minute precision', () {
    final item = todo({
      'startAt': '2026-10-03T09:17:00',
      'endAt': '2026-10-03T10:43:00',
      'repeat': 'none',
    });

    final reminders = todoReminders(item, from: DateTime(2026, 10, 1));
    expect(reminders.map((reminder) => reminder.when), {
      DateTime(2026, 10, 3, 9, 17),
      DateTime(2026, 10, 3, 10, 43),
    });
  });

  testWidgets('editor exposes minute scheduling and weekly multi-select', (
    tester,
  ) async {
    final runtime = PiRuntime(
      catalog: PluginCatalog([
        PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
      ]),
    );
    await runtime.install(todoManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加待办'));
    await tester.pumpAndSettle();
    expect(find.text('备注（选填）'), findsNothing);
    expect(find.byType(ChoiceChip), findsAtLeastNWidgets(1));
    expect(
      tester.getTopLeft(find.text('分类')).dy,
      lessThan(tester.getTopLeft(find.text('要做什么？')).dy),
    );
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.textContaining('现在开始'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(find.text('二'), findsOneWidget);
    expect(find.text('六'), findsOneWidget);
    expect(find.text('每个选中的星期都会创建系统级本地提醒。'), findsOneWidget);
    runtime.dispose();
  });

  testWidgets('checking a stale row merges onto the latest revision', (
    tester,
  ) async {
    final store = InMemoryDataStore();
    final original = await store.upsert(
      todo({
        'startAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'repeat': 'weekly',
        'weekdays': [DateTime.now().weekday],
        'completedDates': <String>[],
      }),
      expectedRevision: 0,
    );
    final runtime = PiRuntime(
      data: store,
      catalog: PluginCatalog([
        PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
      ]),
    );
    await runtime.install(todoManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();

    await store.upsert(
      original.copyWith(data: {...original.data, 'body': '来自同步的新备注'}),
      expectedRevision: original.revision,
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final saved = await store.get(original.id);
    expect(saved?.data['body'], '来自同步的新备注');
    expect(todoCompletedOn(saved!, DateTime.now()), isTrue);
    expect(find.textContaining('数据已发生变化'), findsNothing);
    runtime.dispose();
  });

  testWidgets('todo categories can be customized', (tester) async {
    final runtime = PiRuntime(
      catalog: PluginCatalog([
        PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
      ]),
    );
    await runtime.install(todoManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加待办'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('管理分类'));
    await tester.tap(find.byTooltip('管理分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '新分类'), '家务');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('家务'), findsOneWidget);
    expect(find.text('管理待办分类'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '家务'), findsOneWidget);
    runtime.dispose();
  });

  testWidgets('home shows every todo scheduled for today', (tester) async {
    final store = InMemoryDataStore();
    for (var index = 1; index <= 6; index++) {
      await store.upsert(
        PiEntity(
          id: 'today-$index',
          pluginId: todoManifest.id,
          type: 'todo',
          data: {
            'title': '今日事项 $index',
            'startAt': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            'repeat': 'none',
          },
        ),
        expectedRevision: 0,
      );
    }
    final runtime = PiRuntime(
      data: store,
      catalog: PluginCatalog([
        PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
      ]),
    );
    await runtime.install(todoManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();

    for (var index = 1; index <= 6; index++) {
      expect(find.text('今日事项 $index'), findsOneWidget);
    }
    expect(find.text('查看全部 →'), findsNothing);
    runtime.dispose();
  });
}
