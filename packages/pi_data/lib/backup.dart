import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pi_core/pi_core.dart';

enum ImportConflict { keepLocal, replaceLocal }

class ImportReport {
  const ImportReport({
    required this.imported,
    required this.skipped,
    required this.unknownOwners,
  });
  final int imported, skipped;
  final Set<String> unknownOwners;
}

/// Portable entity backup. Credentials and host settings are never included.
class PiBackup {
  PiBackup(this.store);
  final PiDataStore store;
  static const maxBytes = 32 * 1024 * 1024;

  Future<String> exportJson({String? pluginId, String? type}) async {
    final entities = await store.exportEntities(pluginId: pluginId, type: type);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'pi.backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'entities': entities.map((e) => e.toJson()).toList(),
    });
  }

  Future<Uint8List> exportZip({String? pluginId, String? type}) async {
    final bytes = utf8.encode(await exportJson(pluginId: pluginId, type: type));
    final archive = Archive()
      ..addFile(ArchiveFile('pi-backup.json', bytes.length, bytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  List<PiEntity> preview(String json) {
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('备份超过 32 MB 限制');
    }
    final document = jsonDecode(json) as Map;
    if (document['format'] != 'pi.backup' || document['version'] != 1) {
      throw const FormatException('不支持的 Pi 备份格式');
    }
    final records = document['entities'] as List;
    if (records.length > 50000) throw const FormatException('备份条目过多');
    final entities = records
        .map((e) => PiEntity.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
    if (entities.map((e) => e.id).toSet().length != entities.length) {
      throw const FormatException('备份包含重复的实体标识');
    }
    return entities;
  }

  String decodeZip(List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException('备份过大');
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final file = archive.findFile('pi-backup.json');
    if (file == null || file.size > maxBytes) {
      throw const FormatException('缺少有效的 pi-backup.json');
    }
    // Never extract archive paths onto the filesystem.
    final content = file.content;
    if (content.length > maxBytes) throw const FormatException('解压数据过大');
    return utf8.decode(content);
  }

  Future<ImportReport> importJson(
    String json, {
    ImportConflict conflict = ImportConflict.keepLocal,
    Set<String> knownOwners = const {},
  }) async {
    final entities = preview(json);
    return store.transaction((tx) async {
      var imported = 0, skipped = 0;
      for (final entity in entities) {
        final existing = await tx.get(entity.id);
        if (existing != null) {
          validateWrite(entity, existing, null);
          if (conflict == ImportConflict.keepLocal) {
            skipped++;
            continue;
          }
        }
        await tx.upsert(entity);
        imported++;
      }
      return ImportReport(
        imported: imported,
        skipped: skipped,
        unknownOwners: entities
            .map((e) => e.pluginId)
            .where((id) => !knownOwners.contains(id))
            .toSet(),
      );
    });
  }
}
