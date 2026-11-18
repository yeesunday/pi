import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ai/pi_ai.dart';
import 'package:pi_core/pi_core.dart';

void main() {
  test(
    'plugins can select a shared provider key without being an AI plugin',
    () async {
      final data = InMemoryDataStore();
      final secrets = InMemoryAiSecretStore();
      final store = PiAiKeyStore(data, secrets);
      await store.save(
        const AiKeyProfile(
          id: 'local',
          name: '本地模型',
          config: AiProviderConfig(
            baseUrl: 'http://localhost:11434/v1',
            model: 'llama3',
            apiKey: 'secret',
          ),
        ),
      );
      await store.selectForPlugin('dev.pi.todo', 'local');
      final selected = await store.forPlugin('dev.pi.todo');
      expect(selected?.config.model, 'llama3');
      expect(selected?.config.apiKey, 'secret');
      expect(
        (await data.readSetting('ai/keys')).toString(),
        isNot(contains('secret')),
      );
    },
  );
}
