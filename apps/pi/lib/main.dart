import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pi_ai/pi_ai.dart';
import 'package:pi_data/pi_data.dart';
import 'package:pi_plugin_anniversary/anniversary.dart';
import 'package:pi_plugin_habits/habits.dart';
import 'package:pi_plugin_sketch/sketch.dart';
import 'package:pi_plugin_todo/todo.dart';
import 'package:pi_reminder/pi_reminder.dart';
import 'package:pi_runtime/pi_runtime.dart';

import 'app.dart';
import 'icloud_sync.dart';
import 'secure_ai_store.dart';

export 'app.dart' show PiApp;
export 'home_page.dart' show PiHomePage;
export 'settings_page.dart' show PiSettingsPage, PiSettingsSection;

const _supportedSchemas = <String, int>{
  'dev.pi.todo/todo': 1,
  'dev.pi.todo/todo_category': 1,
  'dev.pi.anniversary/anniversary': 1,
  'dev.pi.habits/habit': 1,
  'dev.pi.sketch/drawing': 1,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SqliteDataStore.openDefault();
  final reminders = PersistentReminderService(store);
  final aiKeys = PiAiKeyStore(store, const KeychainAiSecretStore());
  await aiKeys.list();

  final runtime = PiRuntime(
    data: store,
    reminders: reminders,
    catalog: PluginCatalog([
      PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
      PluginDescriptor(
        manifest: anniversaryManifest,
        create: AnniversaryPlugin.new,
      ),
      PluginDescriptor(manifest: habitsManifest, create: HabitsPlugin.new),
      PluginDescriptor(manifest: sketchManifest, create: SketchPlugin.new),
    ]),
  );
  for (final plugin in runtime.availablePlugins) {
    await reminders.setOwnerActive(plugin.manifest.id, false);
  }

  final cloudSync = ICloudSyncService(
    store,
    events: runtime.events,
    supportedSchemas: _supportedSchemas,
  );
  runtime.services.register<ICloudSyncService>(cloudSync);
  runtime.services.register<PiAiKeyStore>(aiKeys);
  cloudSync.addListener(() {
    if (cloudSync.status.state == ICloudSyncState.synced) {
      unawaited(reminders.reconcile());
    }
  });

  final defaults = const [
    'dev.pi.todo',
    'dev.pi.anniversary',
  ].where(runtime.catalog.contains);
  if (defaults.isNotEmpty) await runtime.installDefaults(defaults);
  await reminders.reconcile();

  runApp(PiApp(runtime: runtime, cloudSync: cloudSync));
  unawaited(cloudSync.startDailySchedule());
}
