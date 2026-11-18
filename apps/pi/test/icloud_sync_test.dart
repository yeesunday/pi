import 'package:flutter_test/flutter_test.dart';
import 'package:pi_app/icloud_sync.dart';

void main() {
  test('daily sync becomes due once after 1 AM', () {
    final now = DateTime(2026, 9, 26, 9, 30);

    expect(dailySyncDue(now, null), isTrue);
    expect(dailySyncDue(now, DateTime(2026, 9, 25, 23, 59)), isTrue);
    expect(dailySyncDue(now, DateTime(2026, 9, 26, 1, 1)), isFalse);
  });

  test('daily sync does not run before 1 AM', () {
    expect(dailySyncDue(DateTime(2026, 9, 26, 0, 59), null), isFalse);
  });

  test('next automatic sync is the next 1 AM boundary', () {
    expect(
      nextDailySyncAt(DateTime(2026, 9, 26, 0, 30)),
      DateTime(2026, 9, 26, 1),
    );
    expect(nextDailySyncAt(DateTime(2026, 9, 26, 1)), DateTime(2026, 9, 27, 1));
    expect(
      nextDailySyncAt(DateTime(2026, 9, 26, 21)),
      DateTime(2026, 9, 27, 1),
    );
  });
}
