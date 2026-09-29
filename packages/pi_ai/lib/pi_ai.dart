import 'dart:convert';
import 'package:pi_core/pi_core.dart';
import 'package:http/http.dart' as http;
class AiProviderConfig { const AiProviderConfig({required this.baseUrl, required this.model, required this.apiKey}); final String baseUrl, model, apiKey; }

class AiKeyProfile {
  const AiKeyProfile({required this.id, required this.name, required this.config});
  final String id, name;
  final AiProviderConfig config;
  JsonMap toJson() => {'id': id, 'name': name, 'baseUrl': config.baseUrl, 'model': config.model, 'apiKey': config.apiKey};
  factory AiKeyProfile.fromJson(JsonMap json) => AiKeyProfile(id: json['id'] as String, name: json['name'] as String,
    config: AiProviderConfig(baseUrl: json['baseUrl'] as String, model: json['model'] as String, apiKey: json['apiKey'] as String? ?? ''));
}

/// Shared AI configuration. It is a capability consumed by plugins, never a plugin itself.
class PiAiKeyStore {
  PiAiKeyStore(this.data);
  final PiDataStore data;
  Future<List<AiKeyProfile>> list() async {
    final value = await data.readSetting('ai/keys');
    return (value?['items'] as List? ?? []).map((item) => AiKeyProfile.fromJson(Map<String, Object?>.from(item as Map))).toList();
  }
  Future<void> save(AiKeyProfile profile) async {
    final items = await list();
    final index = items.indexWhere((item) => item.id == profile.id);
    if (index < 0) items.add(profile); else items[index] = profile;
    await data.writeSetting('ai/keys', {'items': items.map((item) => item.toJson()).toList()});
  }
  Future<void> selectForPlugin(String pluginId, String keyId) async {
    final value = await data.readSetting('ai/pluginSelection');
    final selected = Map<String, Object?>.from(value?['items'] as Map? ?? {});
    selected[pluginId] = keyId;
    await data.writeSetting('ai/pluginSelection', {'items': selected});
  }
  Future<AiKeyProfile?> forPlugin(String pluginId) async {
    final value = await data.readSetting('ai/pluginSelection');
    final id = (value?['items'] as Map?)?[pluginId] as String?;
    if (id == null) return null;
    for (final profile in await list()) { if (profile.id == id) return profile; }
    return null;
  }
}
class PiAiClient {
  PiAiClient(this.config, {http.Client? client}):_client=client??http.Client();
  final AiProviderConfig config; final http.Client _client;
  Future<String> generate(String prompt) async {
    final response=await _client.post(Uri.parse('${config.baseUrl.replaceFirst(RegExp(r'/$'),'')}/chat/completions'),headers:{'content-type':'application/json','authorization':'Bearer ${config.apiKey}'},body:jsonEncode({'model':config.model,'messages':[{'role':'user','content':prompt}]}));
    if(response.statusCode<200||response.statusCode>=300) throw StateError('AI 请求失败（${response.statusCode}）');
    final body=jsonDecode(response.body) as Map; return (((body['choices'] as List).first as Map)['message'] as Map)['content'] as String;
  }
  void close()=>_client.close();
}
