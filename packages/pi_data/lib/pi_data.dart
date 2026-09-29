/// SQLite-backed entity store. Domain plugins never see the database API.
library;

import 'dart:convert';
import 'package:pi_core/pi_core.dart';
import 'package:sqflite/sqflite.dart';
export 'backup.dart';

class SqliteDataStore implements PiDataStore {
  SqliteDataStore._(this._executor, this._database, this._inTransaction);
  final DatabaseExecutor _executor;
  final Database _database;
  final bool _inTransaction;

  static Future<SqliteDataStore> open(String path, {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(path,
      options: OpenDatabaseOptions(version: 1, onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      }, onCreate: (db, version) async {
        await db.execute('CREATE TABLE entities (id TEXT PRIMARY KEY, plugin_id TEXT NOT NULL, type TEXT NOT NULL, schema_version INTEGER NOT NULL, revision INTEGER NOT NULL, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, body TEXT NOT NULL)');
        await db.execute('CREATE INDEX entities_owner_type ON entities(plugin_id, type, deleted, updated_at)');
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, body TEXT NOT NULL)');
        await db.execute('CREATE TABLE plugin_migrations (plugin_id TEXT NOT NULL, type TEXT NOT NULL, version INTEGER NOT NULL, PRIMARY KEY(plugin_id, type))');
      }));
    return SqliteDataStore._(db, db, false);
  }

  PiEntity _decode(Map<String, Object?> row) => PiEntity.fromJson(Map<String, Object?>.from(jsonDecode(row['body'] as String) as Map));

  @override
  Future<List<PiEntity>> list({required String pluginId, required String type, bool includeDeleted = false}) async =>
    (await _executor.query('entities', where: 'plugin_id = ? AND type = ?${includeDeleted ? '' : ' AND deleted = 0'}',
      whereArgs: [pluginId, type], orderBy: 'updated_at DESC, id ASC')).map(_decode).toList();

  @override
  Future<PiEntity?> get(String id) async {
    final rows = await _executor.query('entities', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _decode(rows.first);
  }

  @override
  Future<PiEntity> upsert(PiEntity entity, {int? expectedRevision}) async {
    if (!_inTransaction) return transaction((tx) => tx.upsert(entity, expectedRevision: expectedRevision));
    final old = await get(entity.id);
    validateWrite(entity, old, expectedRevision);
    final next = entity.copyWith(revision: (old?.revision ?? 0) + 1, updatedAt: entity.updatedAt);
    await _writeEntity(next);
    return next;
  }

  Future<void> _writeEntity(PiEntity entity) async {
    await _executor.insert('entities', {'id': entity.id, 'plugin_id': entity.pluginId,
      'type': entity.type, 'schema_version': entity.schemaVersion, 'revision': entity.revision,
      'updated_at': entity.updatedAt.toUtc().toIso8601String(), 'deleted': entity.isDeleted ? 1 : 0,
      'body': jsonEncode(entity.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(PiDataStore) action) async {
    if (_inTransaction) return action(this);
    return _database.transaction((tx) => action(SqliteDataStore._(tx, _database, true)));
  }

  @override
  Future<void> deletePlugin(String pluginId) async {
    if (!_inTransaction) return transaction((tx) => tx.deletePlugin(pluginId));
    final entities = await exportEntities();
    if (entities.any((e) => e.pluginId != pluginId && !e.isDeleted && e.references.any((r) => r.pluginId == pluginId))) {
      throw const DataConflict('其他插件仍引用这些数据，请先移除相关记录');
    }
    await _executor.delete('entities', where: 'plugin_id = ?', whereArgs: [pluginId]);
    // Prefix comparison rather than LIKE: plugin IDs may contain wildcard characters.
    await _executor.delete('settings', where: 'substr(key, 1, ?) = ?', whereArgs: [pluginId.length + 1, '$pluginId/']);
  }

  @override
  Future<void> migrate(String pluginId, List<DataMigration> migrations) async {
    if (!_inTransaction) return transaction((tx) => tx.migrate(pluginId, migrations));
    for (final m in migrations) {
      final rows = await _executor.query('plugin_migrations', where: 'plugin_id = ? AND type = ?', whereArgs: [pluginId, m.type]);
      final current = rows.isEmpty ? 0 : rows.first['version'] as int;
      if (current > migrations.where((x) => x.type == m.type).map((x) => x.version).reduce((a,b) => a > b ? a : b)) {
        throw StateError('数据版本高于插件支持版本：$pluginId/${m.type}');
      }
      if (m.version <= current) continue;
      if (m.version != current + 1) throw StateError('Migration gap: $pluginId/${m.type}');
      for (final e in await list(pluginId: pluginId, type: m.type, includeDeleted: true)) {
        if (e.schemaVersion > m.version) continue;
        await _writeEntity(e.copyWith(data: m.upgrade(e.data), schemaVersion: m.version, updatedAt: e.updatedAt));
      }
      await _executor.insert('plugin_migrations', {'plugin_id': pluginId, 'type': m.type, 'version': m.version}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<List<PiEntity>> exportEntities({String? pluginId, String? type}) async {
    final clauses = <String>[], args = <Object>[];
    if (pluginId != null) { clauses.add('plugin_id = ?'); args.add(pluginId); }
    if (type != null) { clauses.add('type = ?'); args.add(type); }
    return (await _executor.query('entities', where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args, orderBy: 'plugin_id, type, id')).map(_decode).toList();
  }

  @override
  Future<JsonMap?> readSetting(String key) async {
    final rows = await _executor.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : Map<String, Object?>.from(jsonDecode(rows.first['body'] as String) as Map);
  }
  @override
  Future<void> writeSetting(String key, JsonMap value) async {
    await _executor.insert('settings', {'key': key, 'body': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  @override
  Future<void> close() => _database.close();
}
