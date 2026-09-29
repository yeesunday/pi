/// Lifecycle and composition. No domain or concrete platform dependencies.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
export 'scoped_data.dart';
import 'scoped_data.dart';

typedef PiPluginFactory = PiPlugin Function();
typedef PiWidgetBuilder = Widget Function(BuildContext context, PiRuntime runtime);

enum PluginStatus { available, loading, active, failed, unloading, disabled, blocked }

abstract interface class PiPlugin {
  PluginManifest get manifest;
  Future<void> register(PluginContext context);
  Future<void> start(PluginContext context);
  Future<void> stop(PluginContext context);
}

class PluginDescriptor {
  const PluginDescriptor({required this.manifest, required this.create});
  final PluginManifest manifest;
  final PiPluginFactory create;
}

class PluginCatalog {
  PluginCatalog(Iterable<PluginDescriptor> descriptors) {
    for (final d in descriptors) {
      if (_entries.containsKey(d.manifest.id)) throw StateError('Duplicate plugin: ${d.manifest.id}');
      _entries[d.manifest.id] = d;
    }
  }
  final Map<String, PluginDescriptor> _entries = {};
  List<PluginDescriptor> get all => List.unmodifiable(_entries.values);
  PluginDescriptor? operator [](String id) => _entries[id];
  bool contains(String id) => _entries.containsKey(id);

  /// Validates the entire graph before any plugin side effects can run.
  List<String> resolve(Iterable<String> roots) {
    final result = <String>[], visited = <String>{}, visiting = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) throw StateError('循环依赖：${[...visiting, id].join(' → ')}');
      final d = this[id];
      if (d == null) throw StateError('当前安装包不包含 $id');
      for (final dependency in dependenciesOf(id)) { visit(dependency); }
      visiting.remove(id); visited.add(id); result.add(id);
    }
    for (final root in roots) { visit(root); }
    return result;
  }

  Set<String> dependenciesOf(String id) {
    final m = this[id]!.manifest;
    final dependencies = {...m.dependencies};
    for (final capability in m.requires) {
      final providers = all.where((d) => d.manifest.provides.contains(capability));
      if (providers.length != 1) throw StateError('$capability 必须有一个明确的 Provider');
      if (providers.single.manifest.id != id) dependencies.add(providers.single.manifest.id);
    }
    return dependencies;
  }
}

class UiContribution {
  const UiContribution({required this.id, required this.slot, required this.order, required this.builder});
  final String id, slot;
  final int order;
  final PiWidgetBuilder builder;
}

class RouteContribution {
  const RouteContribution({required this.id, required this.label, required this.icon, required this.builder, this.order = 0});
  final String id, label;
  final IconData icon;
  final int order;
  final PiWidgetBuilder builder;
}

class TabContribution {
  const TabContribution({required this.id, required this.label, required this.icon, required this.builder, this.order = 0, this.groupId});
  final String id, label; final IconData icon; final int order; final String? groupId;
  final PiWidgetBuilder builder;
}

class PiCommand {
  const PiCommand({required this.id, required this.description, required this.execute,
    this.parameters = const {'type': 'object', 'properties': <String, Object?>{}},
    this.mutates = false});
  final String id, description;
  final JsonMap parameters;
  final bool mutates;
  final Future<Object?> Function(JsonMap arguments) execute;
}

/// Uniqueness + ownership: cleanup cannot remove another plugin's registration.
class Registry<T> {
  final Map<String, T> _entries = {};
  List<T> get all => List.unmodifiable(_entries.values);
  T? operator [](String id) => _entries[id];
  Disposable register(String id, T value) {
    if (_entries.containsKey(id)) throw StateError('Duplicate contribution: $id');
    _entries[id] = value;
    return Cleanup(() { if (identical(_entries[id], value)) _entries.remove(id); });
  }
}

class UiSlotRegistry {
  final Registry<UiContribution> _items = Registry();
  List<UiContribution> contributions(String slot) => _items.all.where((e) => e.slot == slot).toList()
    ..sort((a,b) { final order = a.order.compareTo(b.order); return order == 0 ? a.id.compareTo(b.id) : order; });
  Disposable register(UiContribution item) => _items.register(item.id, item);
}

class ServiceRegistry {
  final Map<Type, Object> _services = {};
  Disposable register<T extends Object>(T service) {
    if (_services.containsKey(T)) throw StateError('Service $T already registered');
    _services[T] = service;
    return Cleanup(() { if (identical(_services[T], service)) _services.remove(T); });
  }
  T? get<T extends Object>() => _services[T] as T?;
  bool has<T extends Object>() => _services.containsKey(T);
}

class InMemoryEventBus implements PiEventBus {
  InMemoryEventBus({this.onError});
  final void Function(Object, StackTrace)? onError;
  final Map<Type, List<void Function(Object?)>> _listeners = {};
  int get listenerCount => _listeners.values.fold(0, (count, list) => count + list.length);
  @override
  EventSubscription on<T>(EventHandler<T> handler) {
    final listeners = _listeners.putIfAbsent(T, () => []);
    void listener(Object? event) => handler(event as T);
    listeners.add(listener);
    return _Subscription(() => listeners.remove(listener));
  }
  @override
  void emit<T>(T event) {
    for (final listener in [...?_listeners[T]]) {
      try { listener(event); } catch (e,s) { onError?.call(e,s); }
    }
  }
}

class InMemoryReminderService implements ReminderService {
  final Map<String, Reminder> _items = {};
  final Map<String, bool> _owners = {};
  @override
  Future<void> upsert(Reminder reminder) async => _items[reminder.id] = reminder;
  @override
  Future<void> remove(String id) async => _items.remove(id);
  @override
  Future<void> removePlugin(String pluginId) async => _items.removeWhere((_, r) => r.pluginId == pluginId);
  @override
  Future<List<Reminder>> list({String? pluginId}) async => (_items.values
    .where((r) => pluginId == null || r.pluginId == pluginId)
    .where((r) => _owners[r.pluginId] != false).toList())..sort((a,b) => a.when.compareTo(b.when));
  @override
  Future<void> setOwnerActive(String pluginId, bool active) async => _owners[pluginId] = active;
  @override
  Future<void> reconcile() async {}
  @override
  Future<void> snooze(String id, Duration duration) async { final r = _items[id]; if (r != null) _items[id] = r.copyWith(snoozedUntil: DateTime.now().add(duration)); }
  @override
  Future<void> complete(String id) async { final r = _items[id]; if (r != null) _items[id] = r.copyWith(completed: true); }
  @override
  Future<void> skip(String id) async => remove(id);
}

class PluginContext {
  PluginContext._(this.runtime, this.manifest) {
    data = ScopedDataStore(runtime.data, manifest.id, check, runtime.events);
    events = _ScopedEvents(runtime.events, check, own);
  }
  final PiRuntime runtime;
  final PluginManifest manifest;
  late final PiDataStore data;
  late final PiEventBus events;
  ReminderService get reminders { check(); return runtime.reminders; }
  // Existing APIs allow explicit own(registration); convenience methods below own automatically.
  UiSlotRegistry get ui => runtime.ui;
  ServiceRegistry get services => runtime.services;
  final List<Disposable> _owned = [];
  bool _alive = true;
  void check() { if (!_alive) throw StateError('插件 ${manifest.id} 已停用'); }
  void own(Disposable resource) { check(); _owned.add(resource); }
  void provide<T extends Object>(T service) { check(); own(services.register<T>(service)); }
  T require<T extends Object>() { check(); return services.get<T>() ?? (throw StateError('Missing service: $T')); }
  void contribute(UiContribution item) { check(); own(ui.register(item)); }
  void route(RouteContribution route) { check(); own(runtime.routes.register(route.id, route)); }
  void tab(TabContribution tab) { check(); own(runtime.tabs.register(tab.id, tab)); }
  void command(PiCommand command) {
    check();
    own(runtime.commands.register(command.id, PiCommand(id: command.id, description: command.description,
      parameters: command.parameters, mutates: command.mutates, execute: (args) { check(); return command.execute(args); })));
  }
  void periodic(Duration interval, void Function() callback) {
    check(); final timer = Timer.periodic(interval, (_) { if (_alive) callback(); }); own(Cleanup(timer.cancel));
  }
  void disposeOwned() {
    if (!_alive) return;
    _alive = false;
    for (final resource in _owned.reversed) {
      try { resource.dispose(); } catch (e) { runtime.diagnostics.add('清理 ${manifest.id}: $e'); }
    }
    _owned.clear();
  }
}

class _Record {
  _Record(this.plugin, this.context);
  final PiPlugin plugin;
  final PluginContext context;
  PluginStatus status = PluginStatus.loading;
  Object? error;
}

class PiRuntime extends ChangeNotifier {
  PiRuntime({required this.catalog, PiDataStore? data, PiEventBus? events, ReminderService? reminders})
    : data = data ?? InMemoryDataStore(), events = events ?? InMemoryEventBus(), reminders = reminders ?? InMemoryReminderService();
  final PluginCatalog catalog;
  final PiDataStore data;
  final PiEventBus events;
  final ReminderService reminders;
  final UiSlotRegistry ui = UiSlotRegistry();
  final ServiceRegistry services = ServiceRegistry();
  final Registry<RouteContribution> routes = Registry();
  final Registry<TabContribution> tabs = Registry();
  final Registry<PiCommand> commands = Registry();
  final List<String> diagnostics = [];
  final Map<String, _Record> _records = {};
  final Map<String, PluginStatus> _status = {};
  Future<void> _tail = Future.value();
  bool _disposed = false;
  String profileId = 'personal';

  List<TabContribution> get navigationTabs {
    final groups = <String, List<TabContribution>>{};
    for (final tab in tabs.all) { groups.putIfAbsent(tab.groupId ?? tab.id, () => []).add(tab); }
    return groups.values.map((items) {
      final first = items.first;
      if (items.length == 1) return first;
      return TabContribution(id: first.groupId ?? first.id, label: first.label, icon: first.icon, order: first.order,
        builder: (context, runtime) => ListView(padding: const EdgeInsets.all(20), children: items.map((item) => item.builder(context, runtime)).toList()));
    }).toList()..sort((a, b) => a.order.compareTo(b.order));
  }
  List<PluginDescriptor> get availablePlugins => catalog.all;
  List<PluginManifest> get activePlugins => _records.values.where((r) => r.status == PluginStatus.active).map((r) => r.plugin.manifest).toList();
  PluginStatus statusOf(String id) => _records[id]?.status ?? _status[id] ?? PluginStatus.available;
  bool isActive(String id) => statusOf(id) == PluginStatus.active;
  String? errorOf(String id) => _records[id]?.error?.toString();
  void _notify() { if (!_disposed) notifyListeners(); }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try { if (_disposed) throw StateError('Runtime disposed'); result.complete(await action()); }
      catch (e,s) { result.completeError(e,s); }
    });
    return result.future;
  }

  Future<void> install(String id) => _serialize(() async {
    final started = <String>[];
    try {
      for (final next in catalog.resolve([id])) {
        if (isActive(next)) continue;
        await _start(next); started.add(next);
      }
      await _persist();
    } catch (e) {
      for (final next in started.reversed) { await _stop(next); }
      _status[id] = PluginStatus.blocked; diagnostics.add('启用 $id: $e'); _notify(); rethrow;
    }
  });

  Future<void> _start(String id) async {
    final descriptor = catalog[id]!;
    final plugin = descriptor.create();
    if (plugin.manifest.id != id) throw StateError('Factory manifest mismatch: $id');
    final context = PluginContext._(this, descriptor.manifest);
    final record = _Record(plugin, context); _records[id] = record; _notify();
    try {
      await plugin.register(context); await plugin.start(context);
      await reminders.setOwnerActive(id, true); record.status = PluginStatus.active;
    } catch (e) {
      record.status = PluginStatus.failed; record.error = e;
      try { await plugin.stop(context); } catch (cleanup) { diagnostics.add('$cleanup'); }
      context.disposeOwned(); await reminders.setOwnerActive(id, false); rethrow;
    } finally { _notify(); }
  }

  Future<void> _stop(String id) async {
    final record = _records[id];
    if (record == null) return;
    record.status = PluginStatus.unloading; _notify();
    try { await record.plugin.stop(record.context); }
    catch (e) { diagnostics.add('停止 $id: $e'); }
    finally {
      record.context.disposeOwned(); await reminders.setOwnerActive(id, false);
      record.status = PluginStatus.disabled; _notify();
    }
  }

  Future<void> uninstall(String id, {bool deleteData = false}) => _serialize(() async {
    final dependents = activePlugins.where((m) => catalog.dependenciesOf(m.id).contains(id));
    if (dependents.isNotEmpty) throw StateError('${dependents.map((m) => m.name).join('、')} 仍依赖此插件');
    // Validate data deletion before changing activation; a failed delete leaves the plugin usable.
    if (deleteData) { await data.deletePlugin(id); await reminders.removePlugin(id); }
    await _stop(id); _status[id] = PluginStatus.disabled; await _persist(); _notify();
  });

  Future<void> installDefaults(Iterable<String> ids) => switchProfile(profileId, defaults: ids);

  Future<void> switchProfile(String profile, {Iterable<String> defaults = const []}) => _serialize(() async {
    final saved = await data.readSetting('runtime/profile/$profile');
    final requested = (saved?['plugins'] as List?)?.cast<String>() ?? defaults.toList();
    // Profiles survive app upgrades; quietly drop built-in plugins removed from this build.
    final selected = requested.where(catalog.contains).toList();
    final desired = catalog.resolve(selected);
    final old = activePlugins.map((m) => m.id).toList();
    try {
      for (final id in old.reversed) { if (!desired.contains(id)) await _stop(id); }
      for (final id in desired) { if (!isActive(id)) await _start(id); }
      profileId = profile; await _persist();
      await data.writeSetting('runtime/currentProfile', {'id': profile});
    } catch (_) {
      for (final id in activePlugins.map((m) => m.id).toList().reversed) { if (!old.contains(id)) await _stop(id); }
      for (final id in old) { if (!isActive(id)) await _start(id); }
      rethrow;
    } finally { _notify(); }
  });

  Future<void> _persist() => data.writeSetting('runtime/profile/$profileId', {'plugins': activePlugins.map((m) => m.id).toList()});
  Future<void> shutdown() async {
    if (_disposed) return;
    await _serialize(() async { for (final id in activePlugins.map((m) => m.id).toList().reversed) { await _stop(id); } });
    dispose();
  }
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final r in _records.values) { r.context.disposeOwned(); }
    super.dispose();
  }
}

class Cleanup implements Disposable {
  Cleanup(this._callback);
  final VoidCallback _callback;
  bool _disposed = false;
  @override
  void dispose() { if (_disposed) return; _disposed = true; _callback(); }
}
class _Subscription extends Cleanup implements EventSubscription { _Subscription(super.callback); }
class _ScopedEvents implements PiEventBus {
  _ScopedEvents(this.bus, this.check, this.own);
  final PiEventBus bus;
  final void Function() check;
  final void Function(Disposable) own;
  @override
  EventSubscription on<T>(EventHandler<T> handler) { check(); final sub = bus.on(handler); own(sub); return sub; }
  @override
  void emit<T>(T event) { check(); bus.emit(event); }
}

class PiRuntimeScope extends InheritedNotifier<PiRuntime> {
  const PiRuntimeScope({required PiRuntime runtime, required super.child, super.key}) : super(notifier: runtime);
  PiRuntime get runtime => notifier!;
  static PiRuntime of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PiRuntimeScope>()!.runtime;
}
