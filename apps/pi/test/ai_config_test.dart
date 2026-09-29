import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ai/pi_ai.dart';
import 'package:pi_core/pi_core.dart';

void main() {
  test('plugins can select a shared provider key without being an AI plugin', () async {
    final store = PiAiKeyStore(InMemoryDataStore());
    await store.save(const AiKeyProfile(id: 'local', name: '本地模型', config: AiProviderConfig(baseUrl: 'http://localhost:11434/v1', model: 'llama3', apiKey: '')));
    await store.selectForPlugin('dev.pi.todo', 'local');
    expect((await store.forPlugin('dev.pi.todo'))?.config.model, 'llama3');
  });
}
