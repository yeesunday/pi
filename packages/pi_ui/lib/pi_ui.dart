import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';

const piLilac = Color(0xFFB6A0FF);

Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try { await action(); } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating));
  }
}

class PiCard extends StatelessWidget {
  const PiCard({required this.child, this.color = const Color(0xFF242331), super.key});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white.withValues(alpha: .07))), child: child);
}

class EntryField {
  const EntryField(this.key, this.label, {this.multiline = false, this.date = false, this.required = false});
  final String key, label;
  final bool multiline, date, required;
}

/// Shared presentation; domain validation and side effects remain in plugins.
abstract class EntryRepository {
  EntryRepository(this.context, this.type);
  final PluginContext context;
  final String type;
  Future<List<PiEntity>> list() => context.data.list(pluginId: context.manifest.id, type: type);
  Future<PiEntity> save(JsonMap values, {PiEntity? previous}) async {
    if ((values['title'] as String? ?? '').trim().isEmpty) throw const FormatException('请填写名称');
    final entity = previous?.copyWith(data: values) ?? PiEntity(id: newId(), pluginId: context.manifest.id, type: type, data: values);
    return context.data.upsert(entity, expectedRevision: previous?.revision ?? 0);
  }
  Future<void> remove(PiEntity item) async {
    await context.data.upsert(item.copyWith(deletedAt: DateTime.now()), expectedRevision: item.revision);
  }
}

void registerCollection(PluginContext context, EntryRepository repository, {
  required IconData icon, required List<EntryField> fields, required String empty,
  required int order, String slot = 'home.secondary',
  String Function(PiEntity)? subtitle, bool checkable = false,
}) {
  Widget page(BuildContext ctx, PiRuntime runtime) => CollectionView(repository: repository, fields: fields,
    icon: icon, empty: empty, subtitle: subtitle, checkable: checkable);
  context.route(RouteContribution(id: context.manifest.id, label: context.manifest.name, icon: icon, builder: page, order: order));
  context.contribute(UiContribution(id: '${context.manifest.id}.home', slot: slot, order: order,
    builder: (ctx, runtime) => CollectionView(repository: repository, fields: fields, icon: icon,
      empty: empty, subtitle: subtitle, compact: true, checkable: checkable)));
  context.command(PiCommand(id: '${context.manifest.id}.list', description: '读取${context.manifest.name}',
    execute: (_) async => (await repository.list()).map((e) => e.toJson()).toList()));
}

class CollectionView extends StatefulWidget {
  const CollectionView({required this.repository, required this.fields, required this.icon,
    required this.empty, this.subtitle, this.compact = false, this.checkable = false, super.key});
  final EntryRepository repository;
  final List<EntryField> fields;
  final IconData icon;
  final String empty;
  final String Function(PiEntity)? subtitle;
  final bool compact, checkable;
  @override
  State<CollectionView> createState() => _CollectionViewState();
}
class _CollectionViewState extends State<CollectionView> {
  late Future<List<PiEntity>> _items;
  EventSubscription? _subscription;
  String _query = '';
  @override
  void initState() { super.initState(); _reload(); _subscribe(); }
  void _subscribe() {
    _subscription = widget.repository.context.runtime.events.on<DataChanged>((event) {
      if (mounted && event.pluginId == widget.repository.context.manifest.id) setState(_reload);
    });
  }
  @override
  void didUpdateWidget(CollectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) { _subscription?.dispose(); _reload(); _subscribe(); }
  }
  void _reload() { _items = widget.repository.list(); }
  @override
  void dispose() { _subscription?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final manifest = widget.repository.context.manifest;
    final color = Color(manifest.colorValue);
    final body = FutureBuilder<List<PiEntity>>(future: _items, builder: (context, snapshot) {
      final all = snapshot.data ?? [];
      final filtered = all.where((e) => e.data.values.join(' ').toLowerCase().contains(_query.toLowerCase())).toList();
      final items = widget.compact ? filtered.take(3).toList() : filtered;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(
          color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(widget.icon, color: color, size: 21)),
          const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(manifest.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('${all.length} 条记录 · 只保存在你的设备', style: const TextStyle(color: Colors.white54, fontSize: 11))])),
          IconButton(tooltip: '添加${manifest.name}', onPressed: () => _edit(), icon: Icon(Icons.add_rounded, color: color))]),
        const SizedBox(height: 16),
        if (!widget.compact) Padding(padding: const EdgeInsets.only(bottom: 16), child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索记录'), onChanged: (v) => setState(() => _query = v))),
        if (snapshot.hasError) Text('读取失败：${snapshot.error}')
        else if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator()
        else if (items.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 22), child: Text(
          _query.isEmpty ? widget.empty : '没有找到匹配的记录', style: const TextStyle(color: Colors.white60, height: 1.7)))
        else ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Material(color: Colors.transparent,
          child: ListTile(contentPadding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => _edit(item),
            leading: widget.checkable ? Checkbox(value: item.data['completed'] == true,
              onChanged: (value) => guard(context, () async { await widget.repository.save({...item.data, 'completed': value}, previous: item); })) : null,
            title: Text(item.data['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, decoration: item.data['completed'] == true ? TextDecoration.lineThrough : null,
                color: item.data['completed'] == true ? Colors.white38 : Colors.white)),
            subtitle: Text(widget.subtitle?.call(item) ?? item.data['body'] as String? ?? '', maxLines: widget.compact ? 2 : 3,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.6)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 18))))),
        if (widget.compact && all.isNotEmpty) Align(alignment: Alignment.centerRight, child: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => CollectionView(
            repository: widget.repository, fields: widget.fields, icon: widget.icon, empty: widget.empty,
            subtitle: widget.subtitle, checkable: widget.checkable))), child: const Text('查看全部 →'))),
      ]);
    });
    if (widget.compact) return PiCard(child: body);
    return Scaffold(appBar: AppBar(title: Text(manifest.name)), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
      child: ListView(padding: const EdgeInsets.all(24), children: [PiCard(child: body)]))));
  }
  Future<void> _edit([PiEntity? item]) async {
    await showDialog<void>(context: context, builder: (ctx) => EntryEditor(repository: widget.repository, fields: widget.fields, item: item));
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({required this.repository, required this.fields, this.item, super.key});
  final EntryRepository repository;
  final List<EntryField> fields;
  final PiEntity? item;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}
class _EntryEditorState extends State<EntryEditor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); for (final f in widget.fields) { _controllers[f.key] = TextEditingController(text: widget.item?.data[f.key]?.toString() ?? ''); } }
  @override
  void dispose() { for (final c in _controllers.values) { c.dispose(); } super.dispose(); }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.save({...?widget.item?.data, for (final f in widget.fields) f.key: _controllers[f.key]!.text.trim()}, previous: widget.item);
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) setState(() { _saving = false; _error = '$e'; }); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.item == null ? '添加' : '编辑'}${widget.repository.context.manifest.name}'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      ...widget.fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
        controller: _controllers[f.key], minLines: f.multiline ? 4 : 1, maxLines: f.multiline ? 10 : 1,
        readOnly: f.date, decoration: InputDecoration(labelText: f.label, suffixIcon: f.date ? const Icon(Icons.calendar_today_outlined) : null),
        validator: (v) => f.required && (v ?? '').trim().isEmpty ? '请填写${f.label}' : null,
        onTap: f.date ? () async {
          final now = DateTime.now();
          final selected = await showDatePicker(context: context, initialDate: DateTime.tryParse(_controllers[f.key]!.text) ?? now,
            firstDate: DateTime(1900), lastDate: DateTime(2200));
          if (selected != null && mounted) _controllers[f.key]!.text = selected.toIso8601String().substring(0, 10);
        } : null))),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
    ])))),
    actions: [
      if (widget.item != null) TextButton(onPressed: _saving ? null : () async {
        final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('删除这条记录？'),
          content: const Text('记录将从列表移除，备份仍会保留删除标记。'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))]));
        if (confirmed == true && context.mounted) { await guard(context, () async { await widget.repository.remove(widget.item!); if (context.mounted) Navigator.pop(context); }); }
      }, child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '保存中…' : '保存')),
    ]);
}
