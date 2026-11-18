import 'package:pi_core/pi_core.dart';

/// Cooperating plugins only receive access to their data namespace.
/// Native code is trusted build-time code; this is not a process sandbox.
class ScopedDataStore implements PiDataStore {
  ScopedDataStore(
    this._store,
    this.owner,
    this.check,
    this.events, [
    this._pending,
  ]);
  final PiDataStore _store;
  final String owner;
  final void Function() check;
  final PiEventBus events;
  final List<DataChanged>? _pending;
  void _owner(String id) {
    check();
    if (owner != id) throw StateError('插件不能直接访问其他插件的数据');
  }

  void _changed(String type) {
    final change = DataChanged(owner, type);
    if (_pending != null) {
      _pending.add(change);
    } else {
      events.emit(change);
    }
  }

  @override
  Future<List<PiEntity>> list({
    required String pluginId,
    required String type,
    bool includeDeleted = false,
  }) {
    _owner(pluginId);
    return _store.list(
      pluginId: owner,
      type: type,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<PiEntity?> get(String id) async {
    check();
    final e = await _store.get(id);
    if (e != null) _owner(e.pluginId);
    return e;
  }

  @override
  Future<PiEntity> upsert(PiEntity entity, {int? expectedRevision}) async {
    _owner(entity.pluginId);
    final result = await _store.upsert(
      entity,
      expectedRevision: expectedRevision,
    );
    _changed(entity.type);
    return result;
  }

  @override
  Future<List<PiEntity>> pendingChanges() async {
    check();
    return (await _store.pendingChanges())
        .where((entity) => entity.pluginId == owner)
        .toList();
  }

  @override
  Future<void> acknowledgeChanges(Map<String, int> revisions) async {
    throw StateError('只有宿主可以确认同步变更');
  }

  @override
  Future<void> applyRemote(PiEntity entity) async {
    throw StateError('只有宿主可以写入远端变更');
  }

  @override
  Future<void> deletePlugin(String pluginId) async {
    _owner(pluginId);
    await _store.deletePlugin(owner);
    _changed('*');
  }

  @override
  Future<T> transaction<T>(Future<T> Function(PiDataStore) action) async {
    check();
    final pending = <DataChanged>[];
    final result = await _store.transaction(
      (tx) => action(ScopedDataStore(tx, owner, check, events, pending)),
    );
    for (final change in pending) {
      if (_pending != null) {
        _pending.add(change);
      } else {
        events.emit(change);
      }
    }
    return result;
  }

  @override
  Future<List<PiEntity>> exportEntities({String? pluginId, String? type}) {
    _owner(pluginId ?? owner);
    return _store.exportEntities(pluginId: owner, type: type);
  }

  @override
  Future<JsonMap?> readSetting(String key) {
    check();
    return _store.readSetting('$owner/$key');
  }

  @override
  Future<void> writeSetting(String key, JsonMap value) {
    check();
    return _store.writeSetting('$owner/$key', value);
  }

  @override
  Future<void> close() async {
    throw StateError('Only the host may close the data store');
  }
}
