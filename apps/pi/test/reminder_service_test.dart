import 'package:flutter_test/flutter_test.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_reminder/pi_reminder.dart';
import 'package:pi_runtime/pi_runtime.dart';

void main() {
  test('replaceForEntity replaces only that entity reminders', () async {
    final service = InMemoryReminderService();
    final first = Reminder(
      id: 'first',
      pluginId: 'plugin',
      entityId: 'one',
      title: 'first',
      when: DateTime(2026, 10, 1),
    );
    final other = Reminder(
      id: 'other',
      pluginId: 'plugin',
      entityId: 'two',
      title: 'other',
      when: DateTime(2026, 10, 2),
    );
    await service.upsert(first);
    await service.upsert(other);

    await service.replaceForEntity('plugin', 'one', const []);

    expect((await service.list()).map((item) => item.id), ['other']);
  });

  test(
    'next occurrence advances repeating reminders without device clocks',
    () {
      final reminder = Reminder(
        id: 'weekly',
        pluginId: 'plugin',
        entityId: 'one',
        title: 'weekly',
        when: DateTime(2026, 9, 1, 9),
        repeat: RepeatUnit.week,
      );

      expect(
        nextReminderOccurrence(reminder, DateTime(2026, 9, 28, 10)),
        DateTime(2026, 9, 29, 9),
      );
    },
  );

  test('notification window reserves four slots below the iOS limit', () {
    expect(PersistentReminderService.maxPendingNotifications, 60);
  });
}
