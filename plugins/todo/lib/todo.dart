import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

const todoManifest = PluginManifest(
  id: 'dev.pi.todo',
  name: '待办',
  description: '把今天真正重要的几件事放在手边。',
  icon: 'check_circle',
  colorValue: 0xFF6C63FF,
);

enum TodoRepeat { none, weekly }

class TodoPlugin implements PiPlugin {
  @override
  PluginManifest get manifest => todoManifest;

  @override
  Future<void> register(PluginContext context) async {
    final repository = TodoRepository(context);
    Widget page(BuildContext context, PiRuntime runtime) =>
        TodoView(repository: repository);
    context.route(
      RouteContribution(
        id: manifest.id,
        label: manifest.name,
        icon: Icons.check_circle_rounded,
        builder: page,
        order: 10,
      ),
    );
    context.contribute(
      UiContribution(
        id: '${manifest.id}.home',
        slot: 'home.secondary',
        order: 10,
        builder: (context, runtime) =>
            TodoView(repository: repository, compact: true),
      ),
    );
  }

  @override
  Future<void> start(PluginContext context) async {
    final repository = TodoRepository(context);
    for (final item in await repository.list()) {
      await repository.refreshReminders(item);
    }
  }

  @override
  Future<void> stop(PluginContext context) async {}
}

class TodoRepository extends EntryRepository {
  TodoRepository(PluginContext context) : super(context, 'todo');

  static const categoryType = 'todo_category';

  Future<List<PiEntity>> listCategories() async {
    final categories = await context.data.list(
      pluginId: todoManifest.id,
      type: categoryType,
    );
    categories.sort((a, b) {
      final aName = a.data['name'] as String? ?? '';
      final bName = b.data['name'] as String? ?? '';
      return aName.compareTo(bName);
    });
    return categories;
  }

  Future<PiEntity> addCategory(String value) async {
    final name = value.trim();
    if (name.isEmpty) throw const FormatException('请填写分类名称');
    final existing = await listCategories();
    if (existing.any(
      (item) =>
          (item.data['name'] as String? ?? '').toLowerCase() ==
          name.toLowerCase(),
    )) {
      throw const FormatException('这个分类已经存在');
    }
    return context.data.upsert(
      PiEntity(
        id: newId(),
        pluginId: todoManifest.id,
        type: categoryType,
        data: {'name': name},
      ),
      expectedRevision: 0,
    );
  }

  Future<void> removeCategory(PiEntity item) => context.data.upsert(
    item.copyWith(deletedAt: DateTime.now()),
    expectedRevision: item.revision,
  );

  Future<PiEntity> saveTodo(JsonMap values, {PiEntity? previous}) async {
    final title = (values['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const FormatException('请填写要做的事');
    final startImmediately = values['startImmediately'] != false;
    final start =
        DateTime.tryParse(values['startAt'] as String? ?? '') ?? DateTime.now();
    final end = DateTime.tryParse(values['endAt'] as String? ?? '');
    if (end != null && !end.isAfter(start)) {
      throw const FormatException('结束时间需要晚于开始时间');
    }
    final repeat = values['repeat'] == TodoRepeat.weekly.name
        ? TodoRepeat.weekly
        : TodoRepeat.none;
    final weekdays =
        ((values['weekdays'] as List?) ?? const <Object?>[])
            .whereType<num>()
            .map((value) => value.toInt())
            .where(
              (value) => value >= DateTime.monday && value <= DateTime.sunday,
            )
            .toSet()
            .toList()
          ..sort();
    if (repeat == TodoRepeat.weekly && weekdays.isEmpty) {
      throw const FormatException('请至少选择一个重复日期');
    }
    final normalized = <String, Object?>{
      ...values,
      'title': title,
      'category': (values['category'] as String? ?? '').trim(),
      'startAt': start.toIso8601String(),
      'startImmediately': startImmediately,
      'endAt': end?.toIso8601String(),
      'repeat': repeat.name,
      'weekdays': weekdays,
      'completed': values['completed'] == true,
      'completedDates': ((values['completedDates'] as List?) ?? const [])
          .whereType<String>()
          .toSet()
          .toList(),
    };
    final saved = await super.save(normalized, previous: previous);
    unawaited(
      refreshReminders(saved).catchError((Object error, StackTrace stack) {
        context.reportDiagnostic('刷新待办提醒失败：$error');
      }),
    );
    return saved;
  }

  Future<PiEntity> setCompleted(
    PiEntity item,
    bool completed, {
    DateTime? on,
  }) async {
    var current = await context.data.get(item.id) ?? item;
    for (var attempt = 0; attempt < 2; attempt++) {
      final date = DateUtils.dateOnly(on ?? DateTime.now());
      final values = <String, Object?>{...current.data};
      if (todoRepeat(current.data) == TodoRepeat.weekly) {
        final completedDates =
            ((current.data['completedDates'] as List?) ?? const <Object?>[])
                .whereType<String>()
                .toSet();
        final key = _dateKey(date);
        completed ? completedDates.add(key) : completedDates.remove(key);
        values['completedDates'] = completedDates.toList()..sort();
      } else {
        values['completed'] = completed;
        values['completedAt'] = completed
            ? DateTime.now().toIso8601String()
            : null;
      }
      try {
        return await saveTodo(values, previous: current);
      } on DataConflict {
        if (attempt == 1) rethrow;
        current = await context.data.get(item.id) ?? current;
      }
    }
    throw const DataConflict('待办状态保存失败');
  }

  Future<void> refreshReminders(PiEntity item) async {
    await context.reminders.replaceForEntity(
      todoManifest.id,
      item.id,
      todoReminders(item),
    );
  }

  @override
  Future<void> remove(PiEntity item) async {
    await context.reminders.replaceForEntity(
      todoManifest.id,
      item.id,
      const [],
    );
    await super.remove(item);
  }
}

TodoRepeat todoRepeat(JsonMap data) => data['repeat'] == TodoRepeat.weekly.name
    ? TodoRepeat.weekly
    : TodoRepeat.none;

DateTime todoStart(PiEntity item) =>
    DateTime.tryParse(item.data['startAt'] as String? ?? '')?.toLocal() ??
    item.createdAt.toLocal();

bool todoOccursOn(PiEntity item, DateTime day) {
  final date = DateUtils.dateOnly(day);
  if (date.isBefore(DateUtils.dateOnly(todoStart(item)))) return false;
  if (todoRepeat(item.data) == TodoRepeat.weekly) {
    final weekdays = ((item.data['weekdays'] as List?) ?? const <Object?>[])
        .whereType<num>()
        .map((value) => value.toInt());
    return weekdays.contains(date.weekday);
  }
  if (item.data['completed'] != true) return true;
  final completedAt = DateTime.tryParse(
    item.data['completedAt'] as String? ?? '',
  )?.toLocal();
  return completedAt != null && DateUtils.isSameDay(completedAt, date);
}

bool todoCompletedOn(PiEntity item, DateTime day) {
  if (todoRepeat(item.data) != TodoRepeat.weekly) {
    return item.data['completed'] == true;
  }
  final completedDates =
      ((item.data['completedDates'] as List?) ?? const <Object?>[])
          .whereType<String>();
  return completedDates.contains(_dateKey(day));
}

List<Reminder> todoReminders(PiEntity item, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final start = todoStart(item);
  final end = DateTime.tryParse(item.data['endAt'] as String? ?? '')?.toLocal();
  final title = item.data['title'] as String? ?? '待办';
  if (todoRepeat(item.data) == TodoRepeat.none) {
    if (item.data['completed'] == true) return const [];
    return [
      if (start.isAfter(now))
        Reminder(
          id: 'todo-${item.id}-start',
          pluginId: todoManifest.id,
          sourceName: todoManifest.name,
          entityId: item.id,
          title: '该开始了：$title',
          when: start,
        ),
      if (end != null && end.isAfter(now))
        Reminder(
          id: 'todo-${item.id}-end',
          pluginId: todoManifest.id,
          sourceName: todoManifest.name,
          entityId: item.id,
          title: '即将到时间：$title',
          when: end,
        ),
    ];
  }

  final weekdays =
      ((item.data['weekdays'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((value) => value.toInt())
          .toSet()
          .toList()
        ..sort();
  final duration = end?.difference(start);
  final reminders = <Reminder>[];
  for (final weekday in weekdays) {
    final firstStart = _nextWeekly(start, weekday, start);
    reminders.add(
      Reminder(
        id: 'todo-${item.id}-start-w$weekday',
        pluginId: todoManifest.id,
        sourceName: todoManifest.name,
        entityId: item.id,
        title: '该开始了：$title',
        when: _nextWeekly(firstStart, weekday, now),
        repeat: RepeatUnit.week,
      ),
    );
    if (duration != null) {
      final firstEnd = firstStart.add(duration);
      reminders.add(
        Reminder(
          id: 'todo-${item.id}-end-w$weekday',
          pluginId: todoManifest.id,
          sourceName: todoManifest.name,
          entityId: item.id,
          title: '即将到时间：$title',
          when: _nextWeekly(firstEnd, firstEnd.weekday, now),
          repeat: RepeatUnit.week,
        ),
      );
    }
  }
  return reminders;
}

DateTime _nextWeekly(DateTime anchor, int weekday, DateTime from) {
  final localFrom = from.toLocal();
  var candidate = DateTime(
    localFrom.year,
    localFrom.month,
    localFrom.day,
    anchor.hour,
    anchor.minute,
  ).add(Duration(days: (weekday - localFrom.weekday + 7) % 7));
  while (candidate.isBefore(anchor) || candidate.isBefore(localFrom)) {
    candidate = candidate.add(const Duration(days: 7));
  }
  return candidate;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class TodoView extends StatefulWidget {
  const TodoView({required this.repository, this.compact = false, super.key});

  final TodoRepository repository;
  final bool compact;

  @override
  State<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<TodoView> {
  late Future<List<PiEntity>> _items;
  EventSubscription? _subscription;
  String _query = '';
  final Map<String, bool> _completionOverrides = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _subscription = widget.repository.context.events.on<DataChanged>((event) {
      if (mounted && event.pluginId == todoManifest.id) setState(_reload);
    });
  }

  void _reload() {
    final future = widget.repository.list();
    _items = future;
    unawaited(
      future.then((items) {
        if (!mounted || _completionOverrides.isEmpty) return;
        final today = DateTime.now();
        final actual = {
          for (final item in items) item.id: todoCompletedOn(item, today),
        };
        final settled = _completionOverrides.entries
            .where((entry) => actual[entry.key] == entry.value)
            .map((entry) => entry.key)
            .toList();
        if (settled.isEmpty) return;
        setState(() {
          for (final id in settled) {
            _completionOverrides.remove(id);
          }
        });
      }),
    );
  }

  @override
  void dispose() {
    _subscription?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF6C63FF);
    final body = FutureBuilder<List<PiEntity>>(
      future: _items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <PiEntity>[];
        final today = DateTime.now();
        final searched = all.where((item) {
          if (widget.compact && !todoOccursOn(item, today)) return false;
          return item.data.values
              .join(' ')
              .toLowerCase()
              .contains(_query.toLowerCase());
        }).toList();
        searched.sort((a, b) {
          final aCompleted = todoCompletedOn(a, today);
          final bCompleted = todoCompletedOn(b, today);
          final completion = aCompleted == bCompleted
              ? 0
              : (aCompleted ? 1 : -1);
          if (completion != 0) return completion;
          return todoStart(a).compareTo(todoStart(b));
        });
        final items = searched;
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
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: color,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '待办',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.compact
                            ? '${searched.length} 件今日待办'
                            : '${all.length} 条记录 · 本地提醒已接入',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '添加待办',
                  onPressed: _edit,
                  icon: const Icon(Icons.add_rounded, color: color),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!widget.compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索待办',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              Text('读取失败：${snapshot.error}')
            else if (items.isEmpty)
              PiEmptyState(
                icon: Icons.task_alt_rounded,
                message: widget.compact
                    ? '今天没有待办，享受一点留白。'
                    : '还没有待办，点右上角添加第一件事。',
              )
            else
              ...items.map((item) {
                final completed =
                    _completionOverrides[item.id] ??
                    todoCompletedOn(item, today);
                final canCompleteToday = todoOccursOn(item, today);
                return PiListRow(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    onTap: () => _edit(item),
                    leading: Checkbox(
                      value: completed,
                      onChanged: canCompleteToday
                          ? (value) => _setCompleted(item, value == true, today)
                          : null,
                    ),
                    title: Text(
                      item.data['title'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: completed ? Colors.white38 : Colors.white,
                      ),
                    ),
                    subtitle: PiMetaLine(
                      items: _todoMetadata(item, today),
                      color: color,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white30,
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
    if (widget.compact) return PiCard(child: body);
    return Scaffold(
      appBar: AppBar(title: const Text('待办')),
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
        builder: (_) => TodoEditor(repository: widget.repository, item: item),
      ),
    );
  }

  Future<void> _setCompleted(
    PiEntity item,
    bool completed,
    DateTime today,
  ) async {
    setState(() => _completionOverrides[item.id] = completed);
    try {
      await widget.repository.setCompleted(item, completed, on: today);
    } catch (error) {
      if (!mounted) return;
      setState(() => _completionOverrides.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

List<String> _todoMetadata(PiEntity item, DateTime today) {
  final start = todoStart(item);
  final end = DateTime.tryParse(item.data['endAt'] as String? ?? '')?.toLocal();
  final repeat = todoRepeat(item.data);
  final parts = <String>[];
  final category = (item.data['category'] as String? ?? '').trim();
  if (category.isNotEmpty) parts.add(category);
  if (repeat == TodoRepeat.weekly) {
    final weekdays =
        ((item.data['weekdays'] as List?) ?? const <Object?>[])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList()
          ..sort();
    parts.add('每周${weekdays.map(_weekdayLabel).join('、')}');
    final duration = end?.difference(start);
    final todayStart = DateTime(
      today.year,
      today.month,
      today.day,
      start.hour,
      start.minute,
    );
    parts.add(
      duration == null
          ? _timeLabel(todayStart)
          : '${_timeLabel(todayStart)}–${_timeLabel(todayStart.add(duration))}',
    );
  } else {
    parts.add('${_dateTimeLabel(start)} 开始');
    if (end != null) parts.add('${_dateTimeLabel(end)} 结束');
  }
  return parts;
}

class TodoEditor extends StatefulWidget {
  const TodoEditor({required this.repository, this.item, super.key});

  final TodoRepository repository;
  final PiEntity? item;

  @override
  State<TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<TodoEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late Future<List<PiEntity>> _categories;
  String? _category;
  DateTime? _start;
  DateTime? _savedStart;
  DateTime? _end;
  late TodoRepeat _repeat;
  late Set<int> _weekdays;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = widget.item?.data ?? const <String, Object?>{};
    _title = TextEditingController(text: data['title'] as String? ?? '');
    _category = (data['category'] as String? ?? '').trim();
    if (_category!.isEmpty) _category = null;
    _categories = widget.repository.listCategories();
    _savedStart = DateTime.tryParse(
      data['startAt'] as String? ?? '',
    )?.toLocal();
    _start = data['startImmediately'] == true ? null : _savedStart;
    _end = DateTime.tryParse(data['endAt'] as String? ?? '')?.toLocal();
    _repeat = todoRepeat(data);
    _weekdays = ((data['weekdays'] as List?) ?? const <Object?>[])
        .whereType<num>()
        .map((value) => value.toInt())
        .toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final effectiveStart = _start ?? _savedStart ?? DateTime.now();
      await widget.repository.saveTodo({
        ...?widget.item?.data,
        'title': _title.text,
        'category': _category ?? '',
        'startAt': effectiveStart.toIso8601String(),
        'startImmediately': _start == null,
        'endAt': _end?.toIso8601String(),
        'repeat': _repeat.name,
        'weekdays': (_weekdays.toList()..sort()),
      }, previous: widget.item);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PiEditorScaffold(
    icon: widget.item == null ? Icons.add_task_rounded : Icons.edit_rounded,
    title: '${widget.item == null ? '添加' : '编辑'}待办',
    subtitle: widget.item == null ? '安排时间、重复规则和本地提醒' : '调整待办内容和提醒规则',
    color: const Color(0xFF8B7CFF),
    saving: _saving,
    onSave: _save,
    onDelete: widget.item == null ? null : _remove,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<List<PiEntity>>(
            future: _categories,
            builder: (context, snapshot) {
              final names = (snapshot.data ?? const <PiEntity>[])
                  .map((item) => item.data['name'] as String? ?? '')
                  .where((name) => name.isNotEmpty)
                  .toList();
              if (_category != null && !names.contains(_category)) {
                names.add(_category!);
              }
              names.sort();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '分类',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('未分类'),
                          selected: _category == null,
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                          onSelected: (_) => setState(() => _category = null),
                        ),
                        ...names.map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text(name),
                              selected: _category == name,
                              showCheckmark: false,
                              shape: const StadiumBorder(),
                              onSelected: (_) =>
                                  setState(() => _category = name),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Tooltip(
                            message: '管理分类',
                            child: ActionChip(
                              avatar: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('管理'),
                              shape: const StadiumBorder(),
                              onPressed: _manageCategories,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '要做什么？',
              hintText: '例如：铲猫砂',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? '请填写要做的事' : null,
          ),
          const SizedBox(height: 12),
          _DateTimeTile(
            title: '开始时间',
            value: _start == null ? '现在开始' : _dateTimeLabel(_start!),
            hint: '不填则保存后立即进入今日待办',
            icon: Icons.play_circle_outline_rounded,
            onTap: () async {
              final selected = await _pickDateTime(
                context,
                _start ?? DateTime.now(),
              );
              if (selected != null && mounted) {
                setState(() {
                  _start = selected;
                  if (_repeat == TodoRepeat.weekly && _weekdays.isEmpty) {
                    _weekdays.add(selected.weekday);
                  }
                });
              }
            },
            onClear: _start == null
                ? null
                : () => setState(() {
                    _start = null;
                    _savedStart = null;
                  }),
          ),
          _DateTimeTile(
            title: '结束时间',
            value: _end == null ? '不设置' : _dateTimeLabel(_end!),
            hint: '可精确到分钟，并在结束时再提醒一次',
            icon: Icons.stop_circle_outlined,
            onTap: () async {
              final selected = await _pickDateTime(
                context,
                _end ??
                    (_start ?? DateTime.now()).add(const Duration(hours: 1)),
              );
              if (selected != null && mounted) {
                setState(() => _end = selected);
              }
            },
            onClear: _end == null ? null : () => setState(() => _end = null),
          ),
          const SizedBox(height: 8),
          const Text('重复', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          SegmentedButton<TodoRepeat>(
            segments: const [
              ButtonSegment(value: TodoRepeat.none, label: Text('不重复')),
              ButtonSegment(
                value: TodoRepeat.weekly,
                label: Text('每周'),
                icon: Icon(Icons.repeat_rounded),
              ),
            ],
            selected: {_repeat},
            onSelectionChanged: (value) => setState(() {
              _repeat = value.single;
              if (_repeat == TodoRepeat.weekly && _weekdays.isEmpty) {
                _weekdays.add((_start ?? DateTime.now()).weekday);
              }
            }),
          ),
          if (_repeat == TodoRepeat.weekly) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: List.generate(7, (index) {
                final weekday = index + 1;
                return FilterChip(
                  label: Text(_weekdayLabel(weekday)),
                  selected: _weekdays.contains(weekday),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _weekdays.add(weekday)
                        : _weekdays.remove(weekday);
                  }),
                );
              }),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '每个选中的星期都会创建系统级本地提醒。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ],
      ),
    ),
  );

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PiDialogTitle(
          icon: Icons.delete_outline_rounded,
          title: '删除这个待办？',
          subtitle: '系统中对应的本地提醒也会取消',
          color: Color(0xFFFF8F91),
        ),
        content: const Text('对应的本地提醒也会一起取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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

  Future<void> _manageCategories() async {
    await showDialog<void>(
      context: context,
      builder: (_) => TodoCategoryManager(repository: widget.repository),
    );
    final categories = await widget.repository.listCategories();
    if (!mounted) return;
    final names = categories
        .map((item) => item.data['name'] as String? ?? '')
        .toSet();
    setState(() {
      if (_category != null && !names.contains(_category)) _category = null;
      _categories = Future.value(categories);
    });
  }
}

class TodoCategoryManager extends StatefulWidget {
  const TodoCategoryManager({required this.repository, super.key});

  final TodoRepository repository;

  @override
  State<TodoCategoryManager> createState() => _TodoCategoryManagerState();
}

class _TodoCategoryManagerState extends State<TodoCategoryManager> {
  late Future<List<PiEntity>> _categories;
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _categories = widget.repository.listCategories();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addCategory(_name.text);
      _name.clear();
      if (mounted) {
        setState(() {
          _saving = false;
          _reload();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _remove(PiEntity item) async {
    try {
      await widget.repository.removeCategory(item);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const PiDialogTitle(
      icon: Icons.folder_copy_outlined,
      title: '管理待办分类',
      subtitle: '创建几条常用分类，添加待办时直接选择',
      color: Color(0xFF8B7CFF),
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    labelText: '新分类',
                    hintText: '例如：家务、工作、购物',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _add,
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PiEntity>>(
            future: _categories,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) return Text('读取失败：${snapshot.error}');
              final categories = snapshot.data ?? const <PiEntity>[];
              if (categories.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '还没有分类，可以按自己的习惯添加几条。',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = categories[index];
                    return PiListRow(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                        ),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(item.data['name'] as String? ?? ''),
                        trailing: IconButton(
                          tooltip: '删除分类',
                          onPressed: () => _remove(item),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.title,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String title;
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => PiListRow(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('$value\n$hint'),
      isThreeLine: true,
      onTap: onTap,
      trailing: onClear == null
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton(
              tooltip: '清除$title',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
    ),
  );
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2200),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

String _weekdayLabel(int weekday) =>
    const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _dateTimeLabel(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日 ${_timeLabel(value)}';
