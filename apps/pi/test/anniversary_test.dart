import 'package:flutter_test/flutter_test.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_plugin_anniversary/anniversary.dart';

void main() {
  test('solar anniversaries recur yearly and clamp leap day', () {
    final next = anniversaryNextOccurrence({
      'calendar': 'solar',
      'date': '2024-02-29',
      'time': '09:30',
    }, from: DateTime(2025, 1, 1));
    expect(next, DateTime(2025, 2, 28, 9, 30));
  });

  test('today stays today after the configured reminder time', () {
    final data = {
      'calendar': 'solar',
      'date': '2026-09-09',
      'time': '09:00',
    };
    expect(
      anniversaryNextOccurrence(data, from: DateTime(2026, 9, 9, 10)),
      DateTime(2027, 9, 9, 9),
    );
    expect(
      anniversaryDaysUntil(data, from: DateTime(2026, 9, 9, 10)),
      0,
    );
  });

  test('lunar anniversaries convert to the matching solar date', () {
    final next = anniversaryNextOccurrence({
      'calendar': 'lunar',
      'lunarMonth': 8,
      'lunarDay': 15,
      'lunarLeap': false,
      'time': '09:00',
    }, from: DateTime(2026, 9, 1));
    expect(next, DateTime(2026, 9, 25, 9));
    expect(
      anniversaryDateLabel({
        'calendar': 'lunar',
        'lunarMonth': 12,
        'lunarDay': 30,
      }),
      '农历 腊月三十',
    );
  });

  test('each advance day produces an independent reminder', () {
    final entity = PiEntity(
      id: 'wedding',
      pluginId: anniversaryManifest.id,
      type: 'anniversary',
      data: {
        'title': '结婚纪念日',
        'calendar': 'solar',
        'date': '2020-10-01',
        'time': '09:00',
        'reminderDays': [0, 7, 30],
      },
    );
    final reminders = anniversaryReminders(entity, from: DateTime(2026, 9, 1));
    expect(reminders.map((item) => item.id), {
      'anniversary-wedding-0',
      'anniversary-wedding-7',
      'anniversary-wedding-30',
    });
    expect(reminders.map((item) => item.when), {
      DateTime(2026, 10, 1, 9),
      DateTime(2026, 9, 24, 9),
      DateTime(2026, 9, 1, 9),
    });
  });
}
