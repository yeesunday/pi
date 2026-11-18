import 'package:pi_core/pi_core.dart';

class AiProviderConfig {
  const AiProviderConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });
  final String baseUrl, model, apiKey;
}

class AiKeyProfile {
  const AiKeyProfile({
    required this.id,
    required this.name,
    required this.config,
  });
  final String id, name;
  final AiProviderConfig config;
  JsonMap toMetadataJson() => {
    'id': id,
    'name': name,
    'baseUrl': config.baseUrl,
    'model': config.model,
  };
  factory AiKeyProfile.fromMetadata(JsonMap json, String apiKey) =>
      AiKeyProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        config: AiProviderConfig(
          baseUrl: json['baseUrl'] as String,
          model: json['model'] as String,
          apiKey: apiKey,
        ),
      );
}

abstract interface class AiSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class InMemoryAiSecretStore implements AiSecretStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Shared AI configuration. It is a capability consumed by plugins, never a plugin itself.
class PiAiKeyStore {
  PiAiKeyStore(this.data, this.secrets);
  final PiDataStore data;
  final AiSecretStore secrets;
  String _secretKey(String id) => 'pi.ai.provider.$id';

  Future<List<AiKeyProfile>> list() async {
    final value = await data.readSetting('ai/keys');
    final raw = (value?['items'] as List? ?? [])
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
    if (raw.any((item) => item.containsKey('apiKey'))) {
      await data.writeSetting('ai/keys', {
        'items': raw.map((item) => Map.of(item)..remove('apiKey')).toList(),
      });
    }
    final profiles = <AiKeyProfile>[];
    for (final metadata in raw) {
      final id = metadata['id'] as String;
      profiles.add(
        AiKeyProfile.fromMetadata(
          metadata,
          await secrets.read(_secretKey(id)) ?? '',
        ),
      );
    }
    return profiles;
  }

  Future<void> save(AiKeyProfile profile) async {
    final items = await list();
    final index = items.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      items.add(profile);
    } else {
      items[index] = profile;
    }
    await secrets.write(_secretKey(profile.id), profile.config.apiKey);
    await data.writeSetting('ai/keys', {
      'items': items.map((item) => item.toMetadataJson()).toList(),
    });
  }

  Future<Map<String, String>> selections() async {
    final value = await data.readSetting('ai/pluginSelection');
    return Map<String, String>.from(value?['items'] as Map? ?? {});
  }

  Future<void> selectForPlugin(String pluginId, String keyId) async {
    final selected = await selections();
    selected[pluginId] = keyId;
    await data.writeSetting('ai/pluginSelection', {'items': selected});
  }

  Future<AiKeyProfile?> forPlugin(String pluginId) async {
    final id = (await selections())[pluginId];
    if (id == null) return null;
    for (final profile in await list()) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}
