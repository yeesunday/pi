import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_data/pi_data.dart';
import 'package:pi_ui/pi_ui.dart';
import 'package:pi_plugin_birthday/birthday.dart';
import 'package:pi_plugin_reminder/reminder.dart';
import 'package:pi_plugin_todo/todo.dart';
import 'package:pi_plugin_habits/habits.dart';

import 'package:pi_runtime/pi_runtime.dart';

void main() {
  final runtime = PiRuntime(catalog: PluginCatalog([
    PluginDescriptor(manifest: todoManifest, create: TodoPlugin.new),
    PluginDescriptor(manifest: birthdayManifest, create: BirthdayPlugin.new),
    PluginDescriptor(manifest: reminderManifest, create: ReminderPlugin.new),
    PluginDescriptor(manifest: habitsManifest, create: HabitsPlugin.new),
  ]));
  runApp(PiApp(runtime: runtime));
}

class PiApp extends StatelessWidget {
  const PiApp({required this.runtime, super.key});
  final PiRuntime runtime;

  @override
  Widget build(BuildContext context) => PiRuntimeScope(
        runtime: runtime,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Pi',
          theme: _theme,
          home: const PiHomePage(),
        ),
      );
}

final _theme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF11131E),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B7CFF), brightness: Brightness.dark),
  fontFamily: 'SF Pro Display',
  useMaterial3: true,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white.withValues(alpha: .06),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  ),
);

class PiHomePage extends StatefulWidget {
  const PiHomePage({super.key});
  @override
  State<PiHomePage> createState() => _PiHomePageState();
}

class _PiHomePageState extends State<PiHomePage> {
  int _tab = 0;
  bool _showAllPlugins = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final runtime = PiRuntimeScope.of(context);
      final defaults = const ['dev.pi.todo', 'dev.pi.birthday'].where(runtime.catalog.contains);
      if (defaults.isNotEmpty) await runtime.installDefaults(defaults);
    });
  }

  @override
  Widget build(BuildContext context) {
    final runtime = PiRuntimeScope.of(context);
    final customTabs = runtime.navigationTabs;
    final pages = <Widget>[_dashboard(context, runtime), ...customTabs.map((tab) => tab.builder(context, runtime)), _settings(context, runtime)];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '今日'),
      ...customTabs.map((tab) => NavigationDestination(icon: Icon(tab.icon), selectedIcon: Icon(tab.icon), label: tab.label)),
      const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
    ];
    if (_tab >= pages.length) _tab = 0;
    return Scaffold(body: SafeArea(child: IndexedStack(index: _tab, children: pages)), bottomNavigationBar: NavigationBar(
      selectedIndex: _tab, onDestinationSelected: (index) => setState(() => _tab = index), backgroundColor: const Color(0xFF151724),
      indicatorColor: const Color(0xFF8B7CFF).withValues(alpha: .2), destinations: destinations));
  }

  Widget _dashboard(BuildContext context, PiRuntime runtime) => RefreshIndicator(
        onRefresh: () async => setState(() {}),
        color: const Color(0xFF9C90FF),
        backgroundColor: const Color(0xFF26243A),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverToBoxAdapter(child: _greeting(runtime)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(child: _todayPill(runtime)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: runtime.ui.contributions('home.primary').length + runtime.ui.contributions('home.secondary').length,
                itemBuilder: (context, index) {
                  final items = [...runtime.ui.contributions('home.primary'), ...runtime.ui.contributions('home.secondary')];
                  return items[index].builder(context, runtime);
                },
              ),
            ),
          ],
        ),
      );

  Widget _greeting(PiRuntime runtime) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? '早上好' : now.hour < 18 ? '下午好' : '晚上好';
    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: TextStyle(color: Colors.white.withValues(alpha: .48), fontSize: 15)),
            const SizedBox(height: 5),
            const Text('今天，也按自己的节奏来。', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -.5)),
            const SizedBox(height: 8),
            Text('${runtime.activePlugins.length} 个能力正在陪伴你', style: TextStyle(color: Colors.white.withValues(alpha: .38), fontSize: 12)),
          ]),
        ),
        IconButton(tooltip: '设置与数据', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PiSettingsPage(runtime: runtime))), icon: const Icon(Icons.settings_outlined, color: Colors.white54)),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFB6A6FF), Color(0xFF6C63FF)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFF8B7CFF).withValues(alpha: .3), blurRadius: 18)],
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Widget _todayPill(PiRuntime runtime) {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF8B7CFF).withValues(alpha: .14), borderRadius: BorderRadius.circular(30)),
        child: Text('${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}', style: const TextStyle(color: Color(0xFFB7ADFF), fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      const Spacer(),
      TextButton.icon(onPressed: () => setState(() => _showAllPlugins = !_showAllPlugins), icon: const Icon(Icons.tune_rounded, size: 16), label: const Text('自定义')),
    ]);
  }

  Widget _settings(BuildContext context, PiRuntime runtime) => CustomScrollView(slivers: [
    const SliverPadding(padding: EdgeInsets.fromLTRB(20, 28, 20, 4), sliver: SliverToBoxAdapter(child: Text('设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)))),
    const SliverPadding(padding: EdgeInsets.fromLTRB(20, 0, 20, 18), sliver: SliverToBoxAdapter(child: Text('让 Pi 更贴合你的生活方式。', style: TextStyle(color: Colors.white54)))),
    SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverToBoxAdapter(child: _SettingsSection(title: '插件与入口', icon: Icons.extension_rounded, color: piLilac, children: [
      const Text('插件可以贡献首页卡片、独立页面和快捷操作。你可以选择它们出现在哪里。', style: TextStyle(color: Colors.white60, height: 1.5)),
      const SizedBox(height: 14),
      ...runtime.availablePlugins.map((d) => _PluginTile(runtime: runtime, descriptor: d)),
    ]))),
    SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), sliver: SliverToBoxAdapter(child: _SettingsSection(title: '数据与 AI', icon: Icons.tune_rounded, color: const Color(0xFF65B7E8), children: [
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.import_export_rounded), title: const Text('数据与备份'), subtitle: const Text('导入、导出本地数据'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PiSettingsPage(runtime: runtime)))),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.auto_awesome_rounded), title: const Text('AI Provider'), subtitle: const Text('配置兼容 OpenAI 的模型服务'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PiSettingsPage(runtime: runtime)))),
    ]))),
    SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), sliver: SliverToBoxAdapter(child: _SettingsSection(title: '偏好', icon: Icons.palette_outlined, color: const Color(0xFFFFB45B), children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, value: true, onChanged: (_) {}, title: const Text('深色外观'), subtitle: const Text('跟随 Pi 的安静配色'), secondary: const Icon(Icons.dark_mode_outlined)),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline_rounded), title: const Text('个人资料'), subtitle: const Text('个人空间 · 本机设备'), trailing: const Icon(Icons.chevron_right_rounded)),
    ]))),
  ]);

}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.icon, required this.color, required this.children});
  final String title; final IconData icon; final Color color; final List<Widget> children;
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .055), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: .07))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]), const SizedBox(height: 14), ...children.map((child) => Material(color: Colors.transparent, child: child))]));
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.runtime, required this.descriptor});
  final PiRuntime runtime;
  final PluginDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final m = descriptor.manifest;
    final active = runtime.isActive(m.id);
    final color = Color(m.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .08))),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: active && runtime.routes[m.id] != null ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => runtime.routes[m.id]!.builder(context, runtime))) : null, child: Row(children: [
        Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Icon(_iconFor(m.icon), color: color)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 4), Text(m.description, style: const TextStyle(color: Colors.white54, fontSize: 12))])),
        Switch(value: active, onChanged: (value) async { if (value) { await runtime.install(m.id); } else { await runtime.uninstall(m.id); } }),
      ])),
    );
  }

  IconData _iconFor(String name) => switch (name) { 'check_circle' => Icons.check_circle_rounded, 'cake' => Icons.cake_rounded, 'edit_note' => Icons.edit_note_rounded, _ => Icons.extension_rounded };
}


class PiSettingsPage extends StatefulWidget {
  const PiSettingsPage({required this.runtime, super.key});
  final PiRuntime runtime;
  @override State<PiSettingsPage> createState() => _PiSettingsPageState();
}
class _PiSettingsPageState extends State<PiSettingsPage> {
  final _name = TextEditingController(), _base = TextEditingController(), _model = TextEditingController(), _key = TextEditingController();
  final List<Map<String, String>> _keys = [];
  final Map<String, String> _selectedKeys = {};
  String? _editingKeyId;
  String _status = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final keys = await widget.runtime.data.readSetting('ai/keys');
    final selected = await widget.runtime.data.readSetting('ai/pluginSelection');
    if (!mounted) return;
    if (keys != null) {
      _keys.addAll((keys['items'] as List? ?? []).map((item) => Map<String, String>.from(item as Map)));
    }
    if (_keys.isEmpty) {
      final legacy = await widget.runtime.data.readSetting('ai/provider');
      if (legacy != null) _keys.add({'id': 'default', 'name': '默认 Provider', 'baseUrl': legacy['baseUrl'] as String? ?? '', 'model': legacy['model'] as String? ?? '', 'apiKey': legacy['apiKey'] as String? ?? ''});
    }
    _selectedKeys.addAll(Map<String, String>.from(selected?['items'] as Map? ?? {}));
    setState(() {});
  }
  @override void dispose() { for (final c in [_name, _base, _model, _key]) c.dispose(); super.dispose(); }
  void _editKey(Map<String, String> value) { _editingKeyId=value['id']; _name.text=value['name']??''; _base.text=value['baseUrl']??''; _model.text=value['model']??''; _key.text=value['apiKey']??''; setState(() {}); }
  Future<void> _saveKey() async {
    if (_name.text.trim().isEmpty || _base.text.trim().isEmpty || _model.text.trim().isEmpty) { setState(() => _status='请填写名称、Base URL 和模型'); return; }
    final id=_editingKeyId ?? 'key-${DateTime.now().microsecondsSinceEpoch}'; final value={'id':id,'name':_name.text.trim(),'baseUrl':_base.text.trim(),'model':_model.text.trim(),'apiKey':_key.text};
    final index=_keys.indexWhere((item)=>item['id']==id); if(index<0) _keys.add(value); else _keys[index]=value;
    await widget.runtime.data.writeSetting('ai/keys', {'items':_keys});
    _editingKeyId=null; _name.clear(); _base.clear(); _model.clear(); _key.clear(); if(mounted)setState(()=>_status='Provider Key 已保存在本机');
  }
  Future<void> _selectKey(String pluginId, String? keyId) async { if(keyId==null)return; _selectedKeys[pluginId]=keyId; await widget.runtime.data.writeSetting('ai/pluginSelection', {'items':_selectedKeys}); setState(() {}); }
  Future<void> _export() async { final json=await PiBackup(widget.runtime.data).exportJson(); await Clipboard.setData(ClipboardData(text:json)); if (mounted) setState(() => _status='已导出到剪贴板（${json.length} 字符）'); }
  Future<void> _import() async { final c=TextEditingController(); final json=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('导入 JSON 备份'),content:SizedBox(width:520,child:TextField(controller:c,maxLines:10,decoration:const InputDecoration(hintText:'粘贴由 Pi 导出的 JSON')),),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text),child:const Text('导入'))])); c.dispose(); if(json==null||json.trim().isEmpty)return; try { final report=await PiBackup(widget.runtime.data).importJson(json,knownOwners:widget.runtime.catalog.all.map((d)=>d.manifest.id).toSet()); if(mounted)setState(()=>_status='已导入 ${report.imported} 条，跳过 ${report.skipped} 条'); } catch(e){if(mounted)setState(()=>_status='导入失败：$e');} }
  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('设置与数据')),body:ListView(padding:const EdgeInsets.all(20),children:[
    const Text('数据主权',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('你的数据只保存在当前设备。导出前不会上传任何内容。',style:TextStyle(color:Colors.white60)),const SizedBox(height:16),
    Row(children: [Expanded(child: FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share_rounded), label: const Text('导出 JSON'))), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.file_download_outlined), label: const Text('导入 JSON')))]),
    const SizedBox(height:32),const Text('Provider Keys',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('AI Key 是共享基础配置，不是插件。每个需要 AI 的插件可以单独选择一个 Provider Key。',style:TextStyle(color:Colors.white60)),const SizedBox(height:16),
    if(_keys.isNotEmpty) ..._keys.map((item)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.key_rounded),title:Text(item['name']??''),subtitle:Text('${item['model']} · ${item['baseUrl']}'),trailing:IconButton(icon:const Icon(Icons.edit_outlined),onPressed:()=>_editKey(item)))),
    TextField(controller:_name,decoration:const InputDecoration(labelText:'配置名称',hintText:'个人 OpenAI')),const SizedBox(height:12),TextField(controller:_base,decoration:const InputDecoration(labelText:'Base URL',hintText:'https://api.openai.com/v1')),const SizedBox(height:12),TextField(controller:_model,decoration:const InputDecoration(labelText:'模型',hintText:'gpt-4o-mini')),const SizedBox(height:12),TextField(controller:_key,obscureText:true,decoration:const InputDecoration(labelText:'API Key')),const SizedBox(height:16),FilledButton(onPressed:_saveKey,child:Text(_editingKeyId==null?'添加 Provider Key':'更新 Provider Key')),
    const SizedBox(height:24),const Text('插件使用的 Key',style:TextStyle(fontSize:16,fontWeight:FontWeight.w700)),const SizedBox(height:8),
    ...widget.runtime.availablePlugins.map((plugin)=>DropdownButtonFormField<String>(value:_selectedKeys[plugin.manifest.id],decoration:InputDecoration(labelText:plugin.manifest.name),items:_keys.map((item)=>DropdownMenuItem(value:item['id'],child:Text(item['name']??''))).toList(),onChanged:(value)=>_selectKey(plugin.manifest.id,value))),
    if(_status.isNotEmpty)Padding(padding:const EdgeInsets.only(top:16),child:Text(_status,style:const TextStyle(color:piLilac))),
  ]));
}
