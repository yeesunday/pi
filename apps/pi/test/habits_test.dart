import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/main.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_plugin_habits/habits.dart';
import 'package:pi_runtime/pi_runtime.dart';

void main() {
  PiEntity habit(Map<String, Object?> data) => PiEntity(
    id: 'reading',
    pluginId: habitsManifest.id,
    type: 'habit',
    data: {'title': '阅读', 'startDate': '2026-09-01', ...data},
  );

  test('daily and selected-weekday habits appear on the right days', () {
    final daily = habit({'frequency': 'daily'});
    final selected = habit({
      'frequency': 'weekdays',
      'weekdays': [DateTime.tuesday, DateTime.saturday],
    });

    expect(habitScheduledOn(daily, DateTime(2026, 9, 26)), isTrue);
    expect(habitScheduledOn(selected, DateTime(2026, 9, 26)), isTrue);
    expect(habitScheduledOn(selected, DateTime(2026, 9, 27)), isFalse);
  });

  test('weekly-goal habits leave Today after the target is reached', () {
    final item = habit({
      'frequency': 'weeklyGoal',
      'weeklyGoal': 3,
      'completions': ['2026-09-21', '2026-09-23', '2026-09-25'],
    });

    expect(habitWeekCompleted(item, DateTime(2026, 9, 26)), 3);
    expect(habitScheduledOn(item, DateTime(2026, 9, 26)), isFalse);
  });

  test('habit streak and completion rate use daily check-ins', () {
    final item = habit({
      'frequency': 'daily',
      'completions': ['2026-09-24', '2026-09-25', '2026-09-26'],
    });

    expect(habitStreak(item, from: DateTime(2026, 9, 26)), 3);
    expect(habitCompletionRate(item, from: DateTime(2026, 9, 26), days: 3), 1);
  });

  test('selected weekdays create durable weekly reminders', () {
    final item = habit({
      'frequency': 'weekdays',
      'weekdays': [DateTime.tuesday, DateTime.saturday],
      'reminderEnabled': true,
      'reminderTime': '08:15',
    });

    final reminders = habitReminders(item, from: DateTime(2026, 9, 26, 10));
    expect(reminders, hasLength(2));
    expect(reminders.every((item) => item.repeat == RepeatUnit.week), isTrue);
    expect(reminders.map((item) => item.when), {
      DateTime(2026, 9, 29, 8, 15),
      DateTime(2026, 10, 3, 8, 15),
    });
  });

  testWidgets('new habit editor exposes frequency, reminder and pause', (
    tester,
  ) async {
    final runtime = PiRuntime(
      catalog: PluginCatalog([
        PluginDescriptor(manifest: habitsManifest, create: HabitsPlugin.new),
      ]),
    );
    await runtime.install(habitsManifest.id);
    await tester.pumpWidget(PiApp(runtime: runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加习惯'));
    await tester.pumpAndSettle();
    expect(find.text('打卡频率'), findsOneWidget);
    expect(find.text('本地提醒'), findsOneWidget);
    expect(find.text('暂停这个习惯'), findsOneWidget);
    runtime.dispose();
  });
}
