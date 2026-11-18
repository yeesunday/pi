import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_ai/pi_ai.dart';
import 'package:pi_data/pi_data.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

import 'icloud_sync.dart';

enum PiSettingsSection { data, ai }

class PiSettingsPage extends StatefulWidget {
  const PiSettingsPage({
    required this.runtime,
    required this.section,
    super.key,
  });

  final PiRuntime runtime;
  final PiSettingsSection section;

  @override
  State<PiSettingsPage> createState() => _PiSettingsPageState();
}

class _PiSettingsPageState extends State<PiSettingsPage> {
  final _name = TextEditingController();
  final _base = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final List<AiKeyProfile> _keys = [];
  final Map<String, String> _selectedKeys = {};
  String? _editingKeyId;
  String _status = '';

  ICloudSyncService? get _cloud =>
      widget.runtime.services.get<ICloudSyncService>();
  PiAiKeyStore get _keyStore => widget.runtime.services.get<PiAiKeyStore>()!;

  @override
  void initState() {
    super.initState();
    _cloud?.addListener(_cloudChanged);
    _load();
  }

  void _cloudChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final keys = await _keyStore.list();
    final selected = await _keyStore.selections();
    if (!mounted) return;
    _keys.addAll(keys);
    _selectedKeys.addAll(selected);
    setState(() {});
  }

  @override
  void dispose() {
    _cloud?.removeListener(_cloudChanged);
    for (final controller in [_name, _base, _model, _key]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _editKey(AiKeyProfile value) {
    _editingKeyId = value.id;
    _name.text = value.name;
    _base.text = value.config.baseUrl;
    _model.text = value.config.model;
    _key.text = value.config.apiKey;
    setState(() {});
  }

  Future<void> _saveKey() async {
    if (_name.text.trim().isEmpty ||
        _base.text.trim().isEmpty ||
        _model.text.trim().isEmpty) {
      setState(() => _status = '请填写名称、Base URL 和模型');
      return;
    }
    final id = _editingKeyId ?? 'key-${DateTime.now().microsecondsSinceEpoch}';
    final value = AiKeyProfile(
      id: id,
      name: _name.text.trim(),
      config: AiProviderConfig(
        baseUrl: _base.text.trim(),
        model: _model.text.trim(),
        apiKey: _key.text,
      ),
    );
    await _keyStore.save(value);
    final index = _keys.indexWhere((item) => item.id == id);
    if (index < 0) {
      _keys.add(value);
    } else {
      _keys[index] = value;
    }
    _editingKeyId = null;
    _name.clear();
    _base.clear();
    _model.clear();
    _key.clear();
    if (mounted) setState(() => _status = 'Provider Key 已保存在本机');
  }

  Future<void> _selectKey(String pluginId, String? keyId) async {
    if (keyId == null) return;
    _selectedKeys[pluginId] = keyId;
    await _keyStore.selectForPlugin(pluginId, keyId);
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final json = await PiBackup(widget.runtime.data).exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) setState(() => _status = '已导出到剪贴板（${json.length} 字符）');
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PiDialogTitle(
          icon: Icons.file_download_outlined,
          title: '导入 JSON 备份',
          subtitle: '粘贴之前由 Pi 导出的完整备份内容',
          color: Color(0xFF7CCCF2),
        ),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(hintText: '粘贴由 Pi 导出的 JSON'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (json == null || json.trim().isEmpty) return;
    try {
      final report = await PiBackup(widget.runtime.data).importJson(
        json,
        knownOwners: widget.runtime.catalog.all
            .map((descriptor) => descriptor.manifest.id)
            .toSet(),
      );
      if (mounted) {
        setState(
          () => _status = '已导入 ${report.imported} 条，跳过 ${report.skipped} 条',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _status = '导入失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.section == PiSettingsSection.data ? '数据与同步' : 'AI Provider',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            PiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.section == PiSettingsSection.data
                    ? _dataSection()
                    : _aiSection(),
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 16),
                child: Text(_status, style: const TextStyle(color: piLilac)),
              ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _dataSection() => [
    const Text(
      '数据与同步',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    const Text(
      '数据先保存在本机。你可以手动同步，App 运行时会在每日凌晨 1 点自动同步；错过后会在下次打开时补一次。AI Key 不会上传。',
      style: TextStyle(color: Colors.white60),
    ),
    const SizedBox(height: 16),
    if (_cloud != null)
      ListenableBuilder(
        listenable: _cloud!,
        builder: (context, _) => PiListRow(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            leading: Icon(
              _cloud!.status.state == ICloudSyncState.synced
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_sync_rounded,
            ),
            title: const Text('iCloud 同步'),
            subtitle: Text(_cloud!.status.message),
            trailing: IconButton(
              tooltip: '立即同步',
              onPressed: _cloud!.status.state == ICloudSyncState.syncing
                  ? null
                  : () => _cloud!.synchronize(),
              icon: const Icon(Icons.sync_rounded),
            ),
          ),
        ),
      ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('导出 JSON'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('导入 JSON'),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _aiSection() => [
    const Text(
      'Provider Keys',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    const Text(
      'AI Key 是共享基础配置，不是插件。每个需要 AI 的插件可以单独选择一个 Provider Key。',
      style: TextStyle(color: Colors.white60),
    ),
    const SizedBox(height: 16),
    if (_keys.isNotEmpty)
      ..._keys.map(
        (item) => PiListRow(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            leading: const Icon(Icons.key_rounded),
            title: Text(item.name),
            subtitle: Text('${item.config.model} · ${item.config.baseUrl}'),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editKey(item),
            ),
          ),
        ),
      ),
    TextField(
      controller: _name,
      decoration: const InputDecoration(
        labelText: '配置名称',
        hintText: '个人 OpenAI',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _base,
      decoration: const InputDecoration(
        labelText: 'Base URL',
        hintText: 'https://api.openai.com/v1',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _model,
      decoration: const InputDecoration(
        labelText: '模型',
        hintText: 'gpt-4o-mini',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _key,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'API Key'),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _saveKey,
      child: Text(
        _editingKeyId == null ? '添加 Provider Key' : '更新 Provider Key',
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      '插件使用的 Key',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    ...widget.runtime.availablePlugins.map(
      (plugin) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _selectedKeys[plugin.manifest.id],
          decoration: InputDecoration(labelText: plugin.manifest.name),
          items: _keys
              .map(
                (item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
              )
              .toList(),
          onChanged: (value) => _selectKey(plugin.manifest.id, value),
        ),
      ),
    ),
  ];
}
