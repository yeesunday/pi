import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';

const piLilac = Color(0xFFB6A0FF);
const piSurface = Color(0xFF181A25);
const piSurfaceRaised = Color(0xFF202330);
const piMuted = Color(0xFFA9A5B4);

Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

class PiCard extends StatelessWidget {
  const PiCard({required this.child, this.color = piSurface, super.key});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .98), color.withValues(alpha: .86)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .065)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .16),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

class PiDialogTitle extends StatelessWidget {
  const PiDialogTitle({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = piLilac,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ],
  );
}

class PiListRow extends StatelessWidget {
  const PiListRow({required this.child, this.margin, super.key});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin ?? const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .032),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Colors.white.withValues(alpha: .045)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(color: Colors.transparent, child: child),
  );
}

class PiMetaLine extends StatelessWidget {
  const PiMetaLine({required this.items, this.color = piLilac, super.key});

  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      spacing: 6,
      runSpacing: 5,
      children: items
          .where((item) => item.trim().isNotEmpty)
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: .1)),
              ),
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: .88),
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class PiEmptyState extends StatelessWidget {
  const PiEmptyState({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: piMuted, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    ),
  );
}

class PiEditorScaffold extends StatelessWidget {
  const PiEditorScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onSave,
    this.color = piLilac,
    this.onDelete,
    this.saving = false,
    this.canSave = true,
    this.saveLabel = '保存',
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color color;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final bool saving;
  final bool canSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        if (onDelete != null)
          IconButton(
            tooltip: '删除',
            onPressed: saving ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        const SizedBox(width: 6),
      ],
    ),
    body: SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              PiDialogTitle(
                icon: icon,
                title: title,
                subtitle: subtitle,
                color: color,
              ),
              const SizedBox(height: 20),
              PiCard(child: child),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: Material(
      color: const Color(0xFF13151F),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving || !canSave ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? '保存中…' : saveLabel),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class EntryField {
  const EntryField(
    this.key,
    this.label, {
    this.multiline = false,
    this.date = false,
    this.required = false,
  });
  final String key, label;
  final bool multiline, date, required;
}

void registerCollection(
  PluginContext context,
  EntryRepository repository, {
  required IconData icon,
  required List<EntryField> fields,
  required String empty,
  required int order,
  String slot = 'home.secondary',
  String Function(PiEntity)? subtitle,
  bool checkable = false,
}) {
  Widget page(BuildContext ctx, PiRuntime runtime) => CollectionView(
    repository: repository,
    fields: fields,
    icon: icon,
    empty: empty,
    subtitle: subtitle,
    checkable: checkable,
  );
  context.route(
    RouteContribution(
      id: context.manifest.id,
      label: context.manifest.name,
      icon: icon,
      builder: page,
      order: order,
    ),
  );
  context.contribute(
    UiContribution(
      id: '${context.manifest.id}.home',
      slot: slot,
      order: order,
      builder: (ctx, runtime) => CollectionView(
        repository: repository,
        fields: fields,
        icon: icon,
        empty: empty,
        subtitle: subtitle,
        compact: true,
        checkable: checkable,
      ),
    ),
  );
}

class CollectionView extends StatefulWidget {
  const CollectionView({
    required this.repository,
    required this.fields,
    required this.icon,
    required this.empty,
    this.subtitle,
    this.compact = false,
    this.checkable = false,
    super.key,
  });
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
  void initState() {
    super.initState();
    _reload();
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.repository.context.events.on<DataChanged>((event) {
      if (mounted && event.pluginId == widget.repository.context.manifest.id) {
        setState(_reload);
      }
    });
  }

  @override
  void didUpdateWidget(CollectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _subscription?.dispose();
      _reload();
      _subscribe();
    }
  }

  void _reload() {
    _items = widget.repository.list();
  }

  @override
  void dispose() {
    _subscription?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.repository.context.manifest;
    final color = Color(manifest.colorValue);
    final body = FutureBuilder<List<PiEntity>>(
      future: _items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final filtered = all
            .where(
              (e) => e.data.values
                  .join(' ')
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
            )
            .toList();
        final items = widget.compact ? filtered.take(3).toList() : filtered;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${all.length} 条记录 · 本地保存',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '添加${manifest.name}',
                  onPressed: () => _edit(),
                  icon: Icon(Icons.add_rounded, color: color),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!widget.compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索记录',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            if (snapshot.hasError)
              Text('读取失败：${snapshot.error}')
            else if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (items.isEmpty)
              PiEmptyState(
                icon: _query.isEmpty
                    ? Icons.inbox_outlined
                    : Icons.search_off_rounded,
                message: _query.isEmpty ? widget.empty : '没有找到匹配的记录',
              )
            else
              ...items.map(
                (item) => PiListRow(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () => _edit(item),
                    leading: widget.checkable
                        ? Checkbox(
                            value: item.data['completed'] == true,
                            onChanged: (value) => guard(context, () async {
                              await widget.repository.save({
                                ...item.data,
                                'completed': value,
                              }, previous: item);
                            }),
                          )
                        : null,
                    title: Text(
                      item.data['title'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        decoration: item.data['completed'] == true
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.data['completed'] == true
                            ? Colors.white38
                            : Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      widget.subtitle?.call(item) ??
                          item.data['body'] as String? ??
                          '',
                      maxLines: widget.compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                        height: 1.6,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white30,
                      size: 18,
                    ),
                  ),
                ),
              ),
            if (widget.compact && all.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (ctx) => CollectionView(
                        repository: widget.repository,
                        fields: widget.fields,
                        icon: widget.icon,
                        empty: widget.empty,
                        subtitle: widget.subtitle,
                        checkable: widget.checkable,
                      ),
                    ),
                  ),
                  child: const Text('查看全部 →'),
                ),
              ),
          ],
        );
      },
    );
    if (widget.compact) return PiCard(child: body);
    return Scaffold(
      appBar: AppBar(title: Text(manifest.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [PiCard(child: body)],
          ),
        ),
      ),
    );
  }

  Future<void> _edit([PiEntity? item]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => EntryEditor(
          repository: widget.repository,
          fields: widget.fields,
          item: item,
        ),
      ),
    );
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    required this.repository,
    required this.fields,
    this.item,
    super.key,
  });
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
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _controllers[f.key] = TextEditingController(
        text: widget.item?.data[f.key]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save({
        ...?widget.item?.data,
        for (final f in widget.fields) f.key: _controllers[f.key]!.text.trim(),
      }, previous: widget.item);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PiEditorScaffold(
    icon: widget.item == null ? Icons.add_rounded : Icons.edit_rounded,
    title:
        '${widget.item == null ? '添加' : '编辑'}${widget.repository.context.manifest.name}',
    subtitle: widget.item == null ? '填写信息后保存到本机' : '修改这条记录的信息',
    saving: _saving,
    onSave: _save,
    onDelete: widget.item == null ? null : _remove,
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.fields.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _controllers[f.key],
                minLines: f.multiline ? 4 : 1,
                maxLines: f.multiline ? 10 : 1,
                readOnly: f.date,
                decoration: InputDecoration(
                  labelText: f.label,
                  suffixIcon: f.date
                      ? const Icon(Icons.calendar_today_outlined)
                      : null,
                ),
                validator: (v) => f.required && (v ?? '').trim().isEmpty
                    ? '请填写${f.label}'
                    : null,
                onTap: f.date
                    ? () async {
                        final now = DateTime.now();
                        final selected = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(_controllers[f.key]!.text) ??
                              now,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                        );
                        if (selected != null && mounted) {
                          _controllers[f.key]!.text = selected
                              .toIso8601String()
                              .substring(0, 10);
                        }
                      }
                    : null,
              ),
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
      ),
    ),
  );

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const PiDialogTitle(
          icon: Icons.delete_outline_rounded,
          title: '删除这条记录？',
          subtitle: '这个操作可以通过同步的删除标记传播',
          color: Color(0xFFFF8F91),
        ),
        content: const Text('记录将从列表移除，备份仍会保留删除标记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await guard(context, () async {
        await widget.repository.remove(widget.item!);
        if (mounted) Navigator.pop(context);
      });
    }
  }
}
