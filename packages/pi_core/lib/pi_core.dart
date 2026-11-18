/// Stable, domain-neutral protocols. No Flutter or platform dependencies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

typedef JsonMap = Map<String, Object?>;
typedef Clock = DateTime Function();

String newId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

abstract interface class Disposable {
  void dispose();
}

class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    this.version = '0.1.0',
    required this.description,
    required this.icon,
    required this.colorValue,
    this.dependencies = const {},
  });
  final String id, name, version, description, icon;
  final int colorValue;
  final Set<String> dependencies;
}

class PiEntity {
  PiEntity({
    required this.id,
    required this.pluginId,
    required this.type,
    required JsonMap data,
    JsonMap metadata = const {},
    this.schemaVersion = 1,
    this.revision = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.references = const [],
  }) : data = Map.unmodifiable(
         jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
       ),
       metadata = Map.unmodifiable(metadata),
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();
  final String id, pluginId, type;
  final int schemaVersion, revision;
  final JsonMap data, metadata;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final List<EntityReference> references;
  bool get isDeleted => deletedAt != null;

  PiEntity copyWith({
    JsonMap? data,
    DateTime? updatedAt,
    int? schemaVersion,
    int? revision,
    DateTime? deletedAt,
    bool restore = false,
    List<EntityReference>? references,
  }) => PiEntity(
    id: id,
    pluginId: pluginId,
    type: type,
    data: data ?? this.data,
    metadata: metadata,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    deletedAt: restore ? null : deletedAt ?? this.deletedAt,
    references: references ?? this.references,
  );

  JsonMap toJson() => {
    'id': id,
    'pluginId': pluginId,
    'type': type,
    'schemaVersion': schemaVersion,
    'revision': revision,
    'data': data,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'references': references.map((r) => r.toJson()).toList(),
  };

  factory PiEntity.fromJson(JsonMap json) {
    final id = json['id'] as String, owner = json['pluginId'] as String;
    final type = json['type'] as String;
    if (id.isEmpty || owner.isEmpty || type.isEmpty) {
      throw const FormatException('实体缺少标识');
    }
    final version = json['schemaVersion'] as int;
    if (version < 1) throw const FormatException('无效的数据版本');
    return PiEntity(
      id: id,
      pluginId: owner,
      type: type,
      schemaVersion: version,
      revision: json['revision'] as int? ?? 0,
      data: Map<String, Object?>.from(json['data'] as Map),
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      references: (json['references'] as List? ?? [])
          .map(
            (r) =>
                EntityReference.fromJson(Map<String, Object?>.from(r as Map)),
          )
          .toList(),
    );
  }
}

class EntityReference {
  const EntityReference({
    required this.pluginId,
    required this.type,
    required this.id,
  });
  final String pluginId, type, id;
  JsonMap toJson() => {'pluginId': pluginId, 'type': type, 'id': id};
  factory EntityReference.fromJson(JsonMap j) => EntityReference(
    pluginId: j['pluginId'] as String,
    type: j['type'] as String,
    id: j['id'] as String,
  );
}

class DataConflict implements Exception {
  const DataConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class DataChanged {
  const DataChanged(this.pluginId, this.type);
  final String pluginId, type;
}

abstract interface class PiDataStore {
  Future<List<PiEntity>> list({
    required String pluginId,
    required String type,
    bool includeDeleted = false,
  });
  Future<PiEntity?> get(String id);
  Future<PiEntity> upsert(PiEntity entity, {int? expectedRevision});
  Future<List<PiEntity>> pendingChanges();
  Future<void> acknowledgeChanges(Map<String, int> revisions);
  Future<void> applyRemote(PiEntity entity);
  Future<void> deletePlugin(String pluginId);
  Future<T> transaction<T>(Future<T> Function(PiDataStore transaction) action);
  Future<List<PiEntity>> exportEntities({String? pluginId, String? type});
  Future<JsonMap?> readSetting(String key);
  Future<void> writeSetting(String key, JsonMap value);
  Future<void> close();
}

/// Contract test store: atomic snapshots and serialized top-level transactions.
class InMemoryDataStore implements PiDataStore {
  Map<String, PiEntity> _entities = {};
  Map<String, JsonMap> _settings = {};
  Map<String, int> _pending = {};
  bool _closed = false;
  Future<void> _tail = Future.value();
  void _check() {
    if (_closed) throw StateError('Data store is closed');
  }

  @override
  Future<List<PiEntity>> list({
    required String pluginId,
    required String type,
    bool includeDeleted = false,
  }) async {
    _check();
    return _entities.values
        .where(
          (e) =>
              e.pluginId == pluginId &&
              e.type == type &&
              (includeDeleted || !e.isDeleted),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<PiEntity?> get(String id) async {
    _check();
    return _entities[id];
  }

  @override
  Future<PiEntity> upsert(PiEntity entity, {int? expectedRevision}) async {
    _check();
    final old = _entities[entity.id];
    validateWrite(entity, old, expectedRevision);
    final next = entity.copyWith(
      revision: (old?.revision ?? 0) + 1,
      updatedAt: entity.updatedAt,
    );
    _entities[next.id] = next;
    _pending[next.id] = next.revision;
    return next;
  }

  @override
  Future<List<PiEntity>> pendingChanges() async {
    _check();
    return _pending.keys
        .map((id) => _entities[id])
        .whereType<PiEntity>()
        .toList();
  }

  @override
  Future<void> acknowledgeChanges(Map<String, int> revisions) async {
    _check();
    for (final entry in revisions.entries) {
      if (_pending[entry.key] == entry.value) _pending.remove(entry.key);
    }
  }

  @override
  Future<void> applyRemote(PiEntity entity) async {
    _check();
    final old = _entities[entity.id];
    validateWrite(entity, old, null);
    _entities[entity.id] = entity;
    _pending.remove(entity.id);
  }

  @override
  Future<void> deletePlugin(String pluginId) async {
    _check();
    final references = _entities.values
        .where((e) => e.pluginId != pluginId && !e.isDeleted)
        .expand((e) => e.references)
        .where((r) => r.pluginId == pluginId);
    if (references.isNotEmpty) throw const DataConflict('其他插件仍引用这些数据，请先移除相关记录');
    final deletedAt = DateTime.now().toUtc();
    for (final entry
        in _entities.entries
            .where(
              (entry) =>
                  entry.value.pluginId == pluginId && !entry.value.isDeleted,
            )
            .toList()) {
      final entity = entry.value;
      final deleted = entity.copyWith(
        deletedAt: deletedAt,
        updatedAt: deletedAt,
        revision: entity.revision + 1,
      );
      _entities[entry.key] = deleted;
      _pending[entry.key] = deleted.revision;
    }
    _settings.removeWhere((key, _) => key.startsWith('$pluginId/'));
  }

  @override
  Future<T> transaction<T>(Future<T> Function(PiDataStore) action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      _check();
      final tx = InMemoryDataStore()
        .._entities = Map.of(_entities)
        .._settings = Map.of(_settings)
        .._pending = Map.of(_pending);
      try {
        final value = await action(tx);
        _entities = tx._entities;
        _settings = tx._settings;
        _pending = tx._pending;
        result.complete(value);
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  @override
  Future<List<PiEntity>> exportEntities({
    String? pluginId,
    String? type,
  }) async {
    _check();
    return _entities.values
        .where(
          (e) =>
              (pluginId == null || pluginId == e.pluginId) &&
              (type == null || type == e.type),
        )
        .toList();
  }

  @override
  Future<JsonMap?> readSetting(String key) async {
    _check();
    return _settings[key];
  }

  @override
  Future<void> writeSetting(String key, JsonMap value) async {
    _check();
    _settings[key] = Map.unmodifiable(value);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

void validateWrite(PiEntity entity, PiEntity? old, int? expectedRevision) {
  if (old != null &&
      (old.pluginId != entity.pluginId || old.type != entity.type)) {
    throw const DataConflict('实体标识已经属于另一个类型或插件');
  }
  if (expectedRevision != null && expectedRevision != (old?.revision ?? 0)) {
    throw const DataConflict('数据已发生变化，请重新打开再编辑');
  }
}

typedef EventHandler<T> = void Function(T event);

abstract interface class EventSubscription implements Disposable {}

abstract interface class PiEventBus {
  EventSubscription on<T>(EventHandler<T> handler);
  void emit<T>(T event);
}

enum RepeatUnit { none, day, week, month, year }

class Reminder {
  const Reminder({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.when,
    this.entityId,
    this.sourceName = 'Pi',
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh_CN',
    this.repeat = RepeatUnit.none,
    this.interval = 1,
    this.offsetMinutes = 0,
    this.enabled = true,
    this.completed = false,
    this.sound = true,
    this.channel = 'pi.reminders',
    this.snoozedUntil,
  });
  final String id, pluginId, title, sourceName, timezone, locale, channel;
  final String? entityId;
  final DateTime when;
  final RepeatUnit repeat;
  final int interval, offsetMinutes;
  final bool enabled, completed, sound;
  final DateTime? snoozedUntil;
  JsonMap toJson() => {
    'id': id,
    'pluginId': pluginId,
    'title': title,
    'sourceName': sourceName,
    'entityId': entityId,
    'when': when.toIso8601String(),
    'timezone': timezone,
    'locale': locale,
    'repeat': repeat.name,
    'interval': interval,
    'offsetMinutes': offsetMinutes,
    'enabled': enabled,
    'completed': completed,
    'sound': sound,
    'channel': channel,
    'snoozedUntil': snoozedUntil?.toIso8601String(),
  };
  factory Reminder.fromJson(JsonMap j) => Reminder(
    id: j['id'] as String,
    pluginId: j['pluginId'] as String,
    title: j['title'] as String,
    sourceName: j['sourceName'] as String? ?? 'Pi',
    when: DateTime.parse(j['when'] as String),
    entityId: j['entityId'] as String?,
    timezone: j['timezone'] as String? ?? 'Asia/Shanghai',
    locale: j['locale'] as String? ?? 'zh_CN',
    repeat: RepeatUnit.values.byName(j['repeat'] as String? ?? 'none'),
    interval: j['interval'] as int? ?? 1,
    offsetMinutes: j['offsetMinutes'] as int? ?? 0,
    enabled: j['enabled'] as bool? ?? true,
    completed: j['completed'] as bool? ?? false,
    sound: j['sound'] as bool? ?? true,
    channel: j['channel'] as String? ?? 'pi.reminders',
    snoozedUntil: j['snoozedUntil'] == null
        ? null
        : DateTime.parse(j['snoozedUntil'] as String),
  );
  Reminder copyWith({
    DateTime? when,
    bool? enabled,
    bool? completed,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) => Reminder.fromJson({
    ...toJson(),
    if (when != null) 'when': when.toIso8601String(),
    'enabled': ?enabled,
    'completed': ?completed,
    if (clearSnooze)
      'snoozedUntil': null
    else if (snoozedUntil != null)
      'snoozedUntil': snoozedUntil.toIso8601String(),
  });
}

abstract interface class ReminderService {
  Future<void> upsert(Reminder reminder);
  Future<void> replaceForEntity(
    String pluginId,
    String entityId,
    Iterable<Reminder> reminders,
  );
  Future<void> remove(String id);
  Future<void> removePlugin(String pluginId);
  Future<List<Reminder>> list({String? pluginId});
  Future<void> setOwnerActive(String pluginId, bool active);
  Future<void> reconcile();
  Future<void> snooze(String id, Duration duration);
  Future<void> complete(String id);
  Future<void> skip(String id);
}
