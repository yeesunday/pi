import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pi_core/pi_core.dart';

/// Persists reminder definitions and mirrors their next trigger to the native
/// notification center. Definitions survive restarts and can be rebuilt after
/// a timezone change or a device restore.
class PersistentReminderService implements ReminderService {
  PersistentReminderService(this.store);

  final PiDataStore store;
  static const _owner = 'dev.pi.system.reminders';
  static const _type = 'definition';
  static const _channel = MethodChannel('dev.buildpi.piApp/notifications');
  static const maxPendingNotifications = 60;
  final Map<String, bool> _activeOwners = {};
  Map<String, Reminder>? _cache;
  Timer? _windowTimer;

  Future<List<PiEntity>> _entities() =>
      store.list(pluginId: _owner, type: _type);

  Future<Map<String, Reminder>> _reminders({bool reload = false}) async {
    if (!reload && _cache != null) return _cache!;
    _cache = {
      for (final entity in await _entities())
        entity.id: Reminder.fromJson(entity.data),
    };
    return _cache!;
  }

  Future<PiEntity?> _find(String reminderId) async {
    final entity = await store.get(_entityId(reminderId));
    return entity?.pluginId == _owner && entity?.type == _type ? entity : null;
  }

  String _entityId(String reminderId) => 'reminder-$reminderId';

  @override
  Future<void> upsert(Reminder reminder) async {
    await _write(reminder);
    (await _reminders())[_entityId(reminder.id)] = reminder;
    _queueWindowRefresh();
  }

  Future<void> _write(Reminder reminder, [PiDataStore? target]) async {
    final selectedStore = target ?? store;
    for (var attempt = 0; attempt < 2; attempt++) {
      final old = await selectedStore.get(_entityId(reminder.id));
      final entity =
          old?.copyWith(data: reminder.toJson(), restore: true) ??
          PiEntity(
            id: _entityId(reminder.id),
            pluginId: _owner,
            type: _type,
            data: reminder.toJson(),
          );
      try {
        await selectedStore.upsert(
          entity,
          expectedRevision: old?.revision ?? 0,
        );
        break;
      } on DataConflict {
        if (attempt == 1) rethrow;
      }
    }
  }

  @override
  Future<void> replaceForEntity(
    String pluginId,
    String entityId,
    Iterable<Reminder> reminders,
  ) async {
    final desired = reminders.toList();
    if (desired.any(
      (item) => item.pluginId != pluginId || item.entityId != entityId,
    )) {
      throw ArgumentError('提醒的插件或实体归属不一致');
    }
    final cache = await _reminders();
    final existing = cache.values
        .where((item) => item.pluginId == pluginId && item.entityId == entityId)
        .toList();
    final desiredIds = desired.map((item) => item.id).toSet();
    await store.transaction((transaction) async {
      for (final old in existing.where(
        (item) => !desiredIds.contains(item.id),
      )) {
        await _removeDefinition(old.id, transaction);
      }
      for (final reminder in desired) {
        await _write(reminder, transaction);
      }
    });
    for (final old in existing) {
      cache.remove(_entityId(old.id));
    }
    for (final reminder in desired) {
      cache[_entityId(reminder.id)] = reminder;
    }
    _queueWindowRefresh();
  }

  void _queueWindowRefresh() {
    _windowTimer?.cancel();
    _windowTimer = Timer(
      const Duration(milliseconds: 80),
      () => unawaited(_refreshNativeWindow()),
    );
  }

  Future<void> _refreshNativeWindow() async {
    final now = DateTime.now();
    final candidates = <({Reminder reminder, DateTime next})>[];
    for (final reminder in (await _reminders()).values) {
      if (!reminder.enabled ||
          reminder.completed ||
          _activeOwners[reminder.pluginId] == false) {
        continue;
      }
      final next = nextReminderOccurrence(reminder, now);
      if (next != null) candidates.add((reminder: reminder, next: next));
    }
    candidates.sort((a, b) => a.next.compareTo(b.next));
    final requests = candidates.take(maxPendingNotifications).map((item) {
      final reminder = item.reminder;
      final canRepeatNatively =
          reminder.snoozedUntil == null && reminder.interval == 1;
      return <String, Object?>{
        'id': reminder.id,
        'title': reminder.title,
        'sourceName': reminder.sourceName,
        'timestamp': item.next.millisecondsSinceEpoch,
        'sound': reminder.sound,
        'timezone': reminder.timezone,
        'locale': reminder.locale,
        'repeat': canRepeatNatively ? reminder.repeat.name : 'none',
      };
    }).toList();
    await _native('replaceWindow', {'requests': requests});
  }

  Future<T?> _native<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<Reminder>> list({String? pluginId}) async {
    final reminders =
        (await _reminders()).values
            .where(
              (reminder) => pluginId == null || reminder.pluginId == pluginId,
            )
            .toList()
          ..sort((a, b) => a.when.compareTo(b.when));
    return reminders;
  }

  @override
  Future<void> remove(String id) async {
    await _removeDefinition(id, store);
    (await _reminders()).remove(_entityId(id));
    _queueWindowRefresh();
  }

  Future<void> _removeDefinition(String id, PiDataStore target) async {
    final old = await target.get(_entityId(id));
    if (old == null || old.isDeleted) return;
    await target.upsert(
      old.copyWith(deletedAt: DateTime.now()),
      expectedRevision: old.revision,
    );
  }

  @override
  Future<void> removePlugin(String pluginId) async {
    final cache = await _reminders();
    final removed = cache.values
        .where((item) => item.pluginId == pluginId)
        .toList();
    await store.transaction((transaction) async {
      for (final reminder in removed) {
        await _removeDefinition(reminder.id, transaction);
      }
    });
    for (final reminder in removed) {
      cache.remove(_entityId(reminder.id));
    }
    _queueWindowRefresh();
  }

  @override
  Future<void> setOwnerActive(String pluginId, bool active) async {
    _activeOwners[pluginId] = active;
    _queueWindowRefresh();
  }

  @override
  Future<void> reconcile() async {
    _windowTimer?.cancel();
    await _reminders(reload: true);
    await _refreshNativeWindow();
  }

  @override
  Future<void> snooze(String id, Duration duration) async {
    final entity = await _find(id);
    if (entity == null) return;
    await upsert(
      Reminder.fromJson(
        entity.data,
      ).copyWith(snoozedUntil: DateTime.now().add(duration)),
    );
  }

  @override
  Future<void> complete(String id) async {
    final entity = await _find(id);
    if (entity == null) return;
    await upsert(Reminder.fromJson(entity.data).copyWith(completed: true));
  }

  @override
  Future<void> skip(String id) async {
    final entity = await _find(id);
    if (entity == null) return;
    final reminder = Reminder.fromJson(entity.data);
    if (reminder.repeat == RepeatUnit.year) {
      await upsert(
        reminder.copyWith(
          when: DateTime(
            reminder.when.year + reminder.interval,
            reminder.when.month,
            reminder.when.day,
            reminder.when.hour,
            reminder.when.minute,
          ),
          clearSnooze: true,
        ),
      );
    } else {
      await remove(id);
    }
  }
}

DateTime? nextReminderOccurrence(Reminder reminder, DateTime now) {
  final snoozed = reminder.snoozedUntil;
  if (snoozed != null) return snoozed.isAfter(now) ? snoozed : null;
  var candidate = reminder.when.subtract(
    Duration(minutes: reminder.offsetMinutes),
  );
  if (candidate.isAfter(now)) return candidate;
  if (reminder.repeat == RepeatUnit.none) return null;
  final interval = reminder.interval < 1 ? 1 : reminder.interval;
  for (var attempts = 0; attempts < 10000; attempts++) {
    candidate = switch (reminder.repeat) {
      RepeatUnit.day => candidate.add(Duration(days: interval)),
      RepeatUnit.week => candidate.add(Duration(days: 7 * interval)),
      RepeatUnit.month => DateTime(
        candidate.year,
        candidate.month + interval,
        candidate.day,
        candidate.hour,
        candidate.minute,
      ),
      RepeatUnit.year => DateTime(
        candidate.year + interval,
        candidate.month,
        candidate.day,
        candidate.hour,
        candidate.minute,
      ),
      RepeatUnit.none => candidate,
    };
    if (candidate.isAfter(now)) return candidate;
  }
  return null;
}
