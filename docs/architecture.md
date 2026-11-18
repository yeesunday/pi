# Pi architecture

This document describes the code that is currently shipped. It is a contract,
not a roadmap.

## Platform and product boundaries

- Flutter application with an iOS 17 minimum deployment target.
- Local-first: user interactions commit to SQLite before any cloud operation.
- iCloud sync is explicit (the user taps Sync) plus one best-effort run after
  01:00 while the app is running or next returns to the foreground.
- Local notifications are derived from persistent reminder definitions.
- Domain features are runtime plugins, but they are not security sandboxes.

## Packages

| Package | Responsibility |
| --- | --- |
| `pi_core` | Pure Dart entities and stable storage/event/reminder contracts |
| `pi_data` | `sqflite` entity store, sync outbox, and JSON/ZIP backup |
| `pi_runtime` | Plugin catalog, lifecycle, scoped data/events, registries |
| `pi_reminder` | Persistent reminder definitions and the iOS notification window |
| `pi_ai` | Provider metadata, per-plugin selection, and secret-store abstraction |
| `pi_ui` | Shared Flutter presentation only |
| `apps/pi` | Composition root, iOS bridges, settings, sync policy |

The domain plugins are `dev.pi.todo`, `dev.pi.anniversary`, `dev.pi.habits`,
and `dev.pi.sketch`. Sketches store editable strokes in `drawing` entities.
The system share sheet receives a rendered PNG.

## Startup

`main()` performs host initialization before `runApp`:

1. Open the SQLite store.
2. Construct the reminder service and runtime.
3. Register host services (iCloud and AI key configuration).
4. Restore/install the selected default plugins.
5. Reconcile the native notification window.
6. Mount Flutter and start the daily sync timer.

Plugin installation does not depend on a widget frame or page lifecycle.

## Plugin lifecycle and boundaries

A plugin receives `PluginContext`, not `PiRuntime`. The context exposes:

- a `ScopedDataStore` restricted to the plugin ID;
- a scoped event bus whose subscriptions are owned by the plugin lifecycle;
- `ReminderService`;
- owned `provide`, `require`, `contribute`, and `route` registration helpers;
- a diagnostic reporting method.

When a plugin stops, registrations, subscriptions, and timers owned through the
context are disposed in reverse order. Direct access to the host data store,
raw registries, or the runtime is intentionally unavailable.

`EntryRepository` belongs to `pi_runtime`; `pi_ui` consumes it but does not own
data persistence.

## Entity persistence

All plugin entities share this envelope:

- globally unique `id`;
- `pluginId` and domain `type`;
- `schemaVersion` and optimistic `revision`;
- `createdAt`, `updatedAt`, and optional `deletedAt`;
- JSON `data`, metadata, and entity references.

SQLite contains `entities`, `settings`, and `sync_outbox`. Every local entity
write updates the outbox with the exact
revision. A remote apply writes the server entity without creating another
outbox entry. An acknowledgement removes an outbox row only if its revision
still matches, so an edit made during sync remains pending.

Deleting a plugin validates cross-plugin references, writes tombstones for its
live entities, and removes its namespaced settings. Entity rows are not
physically deleted. This lets deletion propagate and prevents a later sync from
restoring uninstalled data.

Backups contain entities only. The implemented formats are a versioned JSON
document and an optional ZIP containing `pi-backup.json`; settings and
credentials are excluded.

## iCloud sync

The iOS bridge uses `CKSyncEngine` against the private CloudKit database and a
custom record zone. `CKSyncEngine.State.Serialization` and last-known record
system fields are persisted so CloudKit can resume incrementally and detect
record conflicts.

One synchronization run is:

1. Read only entities in the SQLite outbox (excluding derived system reminder
   definitions).
2. Queue those record IDs in `CKSyncEngine` and send changes.
3. Fetch only CloudKit changes after the engine's stored token.
4. Apply supported remote payloads without adding them to the outbox.
5. Acknowledge exact local revisions and accepted remote payloads.

Cloud records are never deleted for ordinary domain deletion; the record
payload carries `deletedAt`. This ensures a new device also learns the deletion.

CloudKit `serverRecordChanged` is the conflict boundary. The current policy is
server-wins: the server record is returned to Dart and applied locally, without
comparing device clocks. Conflicts are counted in the sync result. Payloads
whose schema is newer than the composition root's supported-schema allowlist
remain in the native pending-remote cache and are not written into the old
local schema.

Sync is not expected to work fully in an iOS Simulator because CloudKit push
notifications require a real signed-in device. Manual sync still surfaces the
platform error rather than changing local data.

## Reminders and iOS notification limit

Every reminder definition is persisted under the host-owned
`dev.pi.system.reminders` namespace. Plugins update definitions through
`replaceForEntity(pluginId, entityId, reminders)`, which atomically removes
obsolete definitions and writes the replacement set without repeatedly listing
all reminders.

`PersistentReminderService` computes the next occurrence, sorts all active
definitions, and submits only the nearest 60 requests to iOS. Four slots remain
below iOS's 64 pending-notification limit. The complete definition set remains
in SQLite and the window is rebuilt after startup, foreground reconciliation,
plugin activation changes, and reminder edits.

The native bridge replaces the pending window in one operation. It asks for
notification permission only while authorization is `notDetermined`. Plugin
display names, timezone, sound, and recurrence are supplied by Dart; Swift does
not contain domain plugin IDs.

## AI credentials

SQLite stores only provider ID, display name, base URL, model, and per-plugin
selection. API keys are accessed through `AiSecretStore`; the iOS app provides
`flutter_secure_storage`, backed by Keychain. Plaintext `apiKey` members found
in the old `ai/keys` setting are stripped and are deliberately not migrated.
Neither backup nor iCloud sync includes settings or Keychain values.

## App composition

`main.dart` is the composition root only: it opens host services, builds the
catalog, restores plugin activation, and launches `PiApp`. Flutter shell and
screen widgets live in `home_page.dart`, `settings_overview.dart`, and
`settings_page.dart`; platform adapters remain in dedicated
files such as `icloud_sync.dart` and `secure_ai_store.dart`.
