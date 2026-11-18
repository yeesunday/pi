import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pi_core/pi_core.dart';

enum ICloudSyncState { unavailable, idle, syncing, synced, failed }

class ICloudSyncStatus {
  const ICloudSyncStatus(this.state, this.message, {this.syncedAt});

  final ICloudSyncState state;
  final String message;
  final DateTime? syncedAt;
}

/// Local-first CloudKit exchange. Only domain entities are synchronized;
/// settings such as AI provider credentials intentionally stay on-device.
class ICloudSyncService extends ChangeNotifier {
  ICloudSyncService(
    this.store, {
    this.events,
    this.supportedSchemas = const {},
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  final PiDataStore store;
  final PiEventBus? events;
  final Map<String, int> supportedSchemas;
  final Clock _clock;
  static const _channel = MethodChannel('dev.buildpi.piApp/cloud_sync');
  static const _scheduleSetting = 'dev.pi.system/icloud_sync_schedule';
  ICloudSyncStatus _status = const ICloudSyncStatus(
    ICloudSyncState.idle,
    '等待同步',
  );
  ICloudSyncStatus get status => _status;
  Future<void>? _running;
  Timer? _dailyTimer;
  DateTime? _lastSyncedAt;
  DateTime? _lastDailyAttemptAt;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> startDailySchedule() async {
    final setting = await store.readSetting(_scheduleSetting);
    _lastSyncedAt = DateTime.tryParse(
      setting?['lastSyncedAt'] as String? ?? '',
    )?.toLocal();
    _lastDailyAttemptAt =
        DateTime.tryParse(
          setting?['lastDailyAttemptAt'] as String? ?? '',
        )?.toLocal() ??
        _lastSyncedAt;
    await checkDailySchedule();
  }

  Future<void> checkDailySchedule() async {
    if (!isSupported) return;
    _dailyTimer?.cancel();
    final now = _clock();
    if (dailySyncDue(now, _lastDailyAttemptAt)) await _runDailySync();
    _scheduleNextDailyRun();
  }

  void _scheduleNextDailyRun() {
    _dailyTimer?.cancel();
    final now = _clock();
    final next = nextDailySyncAt(now);
    _dailyTimer = Timer(next.difference(now), () async {
      await _runDailySync();
      _scheduleNextDailyRun();
    });
  }

  Future<void> _runDailySync() async {
    _lastDailyAttemptAt = _clock();
    await _persistSchedule();
    await synchronize();
  }

  Future<void> _persistSchedule() => store.writeSetting(_scheduleSetting, {
    'lastSyncedAt': _lastSyncedAt?.toUtc().toIso8601String(),
    'lastDailyAttemptAt': _lastDailyAttemptAt?.toUtc().toIso8601String(),
  });

  Future<void> synchronize() {
    final current = _running;
    if (current != null) return current;
    final completer = Completer<void>();
    _running = completer.future;
    _synchronize()
        .then(completer.complete, onError: completer.completeError)
        .whenComplete(() {
          _running = null;
        });
    return completer.future;
  }

  Future<void> _synchronize() async {
    if (!isSupported) {
      _set(
        const ICloudSyncStatus(ICloudSyncState.unavailable, '当前平台不支持 iCloud'),
      );
      return;
    }
    _set(
      ICloudSyncStatus(
        ICloudSyncState.syncing,
        '正在与 iCloud 同步…',
        syncedAt: _status.syncedAt,
      ),
    );
    try {
      if (!await isAvailable()) {
        _set(
          const ICloudSyncStatus(
            ICloudSyncState.unavailable,
            '请先在系统设置中登录 iCloud',
          ),
        );
        return;
      }
      final pending = await store.pendingChanges();
      final derived = pending
          .where((entity) => entity.pluginId.startsWith('dev.pi.system.'))
          .toList();
      if (derived.isNotEmpty) {
        await store.acknowledgeChanges({
          for (final entity in derived) entity.id: entity.revision,
        });
      }
      final local = pending
          .where((entity) => !entity.pluginId.startsWith('dev.pi.system.'))
          .toList();
      final response = await _channel.invokeMapMethod<String, Object?>(
        'synchronize',
        {
          'changes': local
              .map((entity) => jsonEncode(entity.toJson()))
              .toList(),
        },
      );
      final acknowledged = <String, int>{
        for (final entry in Map<String, Object?>.from(
          response?['acknowledged'] as Map? ?? const {},
        ).entries)
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      };
      await store.acknowledgeChanges(acknowledged);
      final remotePayload = response?['payload'] as String? ?? '[]';
      final remoteRecords = (jsonDecode(remotePayload) as List).map(
        (value) => PiEntity.fromJson(Map<String, Object?>.from(value as Map)),
      );
      var pulled = 0;
      final appliedRemoteIds = <String>[];
      for (final remote in remoteRecords) {
        final supported = supportedSchemas['${remote.pluginId}/${remote.type}'];
        if (supported == null || remote.schemaVersion > supported) continue;
        await store.applyRemote(remote);
        events?.emit(DataChanged(remote.pluginId, remote.type));
        appliedRemoteIds.add(remote.id);
        pulled++;
      }
      if (appliedRemoteIds.isNotEmpty) {
        await _channel.invokeMethod<void>('acknowledgeRemote', {
          'ids': appliedRemoteIds,
        });
      }
      final pushed = acknowledged.length;
      final conflicts = response?['conflicts'] as int? ?? 0;
      final now = _clock();
      _lastSyncedAt = now;
      final todayAtOne = DateTime(now.year, now.month, now.day, 1);
      if (!now.isBefore(todayAtOne)) _lastDailyAttemptAt = now;
      await _persistSchedule();
      _set(
        ICloudSyncStatus(
          ICloudSyncState.synced,
          '已同步 · 上传 $pushed 条，下载 $pulled 条'
          '${conflicts == 0 ? '' : '，解决 $conflicts 个冲突'}',
          syncedAt: now,
        ),
      );
    } on PlatformException catch (error) {
      _set(
        ICloudSyncStatus(
          ICloudSyncState.failed,
          error.message ?? 'iCloud 同步失败',
          syncedAt: _status.syncedAt,
        ),
      );
    } catch (error) {
      _set(
        ICloudSyncStatus(
          ICloudSyncState.failed,
          'iCloud 同步失败：$error',
          syncedAt: _status.syncedAt,
        ),
      );
    }
  }

  void _set(ICloudSyncStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    super.dispose();
  }
}

bool dailySyncDue(DateTime now, DateTime? lastRunAt) {
  final todayAtOne = DateTime(now.year, now.month, now.day, 1);
  if (now.isBefore(todayAtOne)) return false;
  return lastRunAt == null || lastRunAt.isBefore(todayAtOne);
}

DateTime nextDailySyncAt(DateTime now) {
  final todayAtOne = DateTime(now.year, now.month, now.day, 1);
  return todayAtOne.isAfter(now)
      ? todayAtOne
      : todayAtOne.add(const Duration(days: 1));
}
