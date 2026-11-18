import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

const habitsManifest = PluginManifest(
  id: 'dev.pi.habits',
  name: '习惯',
  description: '按自己的节奏打卡，看到长期积累。',
  icon: 'repeat',
  colorValue: 0xFF63D6A8,
);

enum HabitFrequency { daily, weekdays, weeklyGoal }

class HabitsPlugin implements PiPlugin {
  @override
  PluginManifest get manifest => habitsManifest;

  @override
  Future<void> register(PluginContext context) async {
    final repository = HabitRepository(context);
    Widget page(BuildContext context, PiRuntime runtime) =>
        HabitView(repository: repository);
    context.route(
      RouteContribution(
        id: manifest.id,
        label: manifest.name,
        icon: Icons.repeat_rounded,
        builder: page,
        order: 70,
      ),
    );
    context.contribute(
      UiContribution(
        id: '${manifest.id}.home',
        slot: 'home.secondary',
        order: 70,
        builder: (context, runtime) =>
            HabitView(repository: repository, compact: true),
      ),
    );
  }

  @override
  Future<void> start(PluginContext context) async {
    final repository = HabitRepository(context);
    for (final item in await repository.list()) {
      await repository.refreshReminders(item);
    }
  }

  @override
  Future<void> stop(PluginContext context) async {}
}

class HabitRepository extends EntryRepository {
  HabitRepository(PluginContext context) : super(context, 'habit');

  Future<PiEntity> saveHabit(JsonMap values, {PiEntity? previous}) async {
    final title = (values['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const FormatException('请填写习惯名称');
    final frequency = HabitFrequency.values.firstWhere(
      (item) => item.name == values['frequency'],
      orElse: () => HabitFrequency.daily,
    );
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
    if (frequency == HabitFrequency.weekdays && weekdays.isEmpty) {
      throw const FormatException('请至少选择一个打卡日');
    }
    final weeklyGoal = ((values['weeklyGoal'] as num?)?.toInt() ?? 3).clamp(
      1,
      7,
    );
    final startDate =
        DateTime.tryParse(values['startDate'] as String? ?? '') ??
        DateTime.now();
    final reminderTime = _parseTime(values['reminderTime'] as String? ?? '');
    final normalized = <String, Object?>{
      ...values,
      'title': title,
      'note': (values['note'] as String? ?? '').trim(),
      'frequency': frequency.name,
      'weekdays': weekdays,
      'weeklyGoal': weeklyGoal,
      'startDate': _dateKey(startDate),
      'paused': values['paused'] == true,
      'reminderEnabled': values['reminderEnabled'] == true,
      'reminderTime': _timeKey(
        reminderTime ?? const TimeOfDay(hour: 9, minute: 0),
      ),
      'completions':
          ((values['completions'] as List?) ?? const <Object?>[])
              .whereType<String>()
              .toSet()
              .toList()
            ..sort(),
    };
    final saved = await super.save(normalized, previous: previous);
    _refreshLater(saved);
    return saved;
  }

  Future<PiEntity> setCompleted(
    PiEntity item,
    bool completed, {
    DateTime? on,
  }) async {
    var current = await context.data.get(item.id) ?? item;
    for (var attempt = 0; attempt < 2; attempt++) {
      final completions = habitCompletions(current);
      final key = _dateKey(on ?? DateTime.now());
      completed ? completions.add(key) : completions.remove(key);
      try {
        return await saveHabit({
          ...current.data,
          'completions': completions.toList()..sort(),
        }, previous: current);
      } on DataConflict {
        if (attempt == 1) rethrow;
        current = await context.data.get(item.id) ?? current;
      }
    }
    throw const DataConflict('习惯打卡保存失败');
  }

  void _refreshLater(PiEntity item) {
    unawaited(
      refreshReminders(item).catchError((Object error, StackTrace stack) {
        context.reportDiagnostic('刷新习惯提醒失败：$error');
      }),
    );
  }

  Future<void> refreshReminders(PiEntity item) async {
    await context.reminders.replaceForEntity(
      habitsManifest.id,
      item.id,
      habitReminders(item),
    );
  }

  @override
  Future<void> remove(PiEntity item) async {
    await context.reminders.replaceForEntity(
      habitsManifest.id,
      item.id,
      const [],
    );
    await super.remove(item);
  }
}

HabitFrequency habitFrequency(PiEntity item) =>
    HabitFrequency.values.firstWhere(
      (value) => value.name == item.data['frequency'],
      orElse: () => HabitFrequency.daily,
    );

Set<String> habitCompletions(PiEntity item) =>
    ((item.data['completions'] as List?) ?? const <Object?>[])
        .whereType<String>()
        .toSet();

DateTime habitStart(PiEntity item) => DateUtils.dateOnly(
  DateTime.tryParse(item.data['startDate'] as String? ?? '') ??
      item.createdAt.toLocal(),
);

bool habitCompletedOn(PiEntity item, DateTime day) =>
    habitCompletions(item).contains(_dateKey(day));

bool habitScheduledOn(PiEntity item, DateTime day) {
  if (item.data['paused'] == true) return false;
  final date = DateUtils.dateOnly(day);
  if (date.isBefore(habitStart(item))) return false;
  switch (habitFrequency(item)) {
    case HabitFrequency.daily:
      return true;
    case HabitFrequency.weekdays:
      return ((item.data['weekdays'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((value) => value.toInt())
          .contains(date.weekday);
    case HabitFrequency.weeklyGoal:
      return habitCompletedOn(item, date) ||
          habitWeekCompleted(item, date) < habitWeeklyGoal(item);
  }
}

int habitWeeklyGoal(PiEntity item) =>
    ((item.data['weeklyGoal'] as num?)?.toInt() ?? 3).clamp(1, 7);

int habitWeekCompleted(PiEntity item, DateTime day) {
  final start = _weekStart(day);
  final end = start.add(const Duration(days: 7));
  return habitCompletions(item).where((key) {
    final date = DateTime.tryParse(key);
    return date != null && !date.isBefore(start) && date.isBefore(end);
  }).length;
}

int habitStreak(PiEntity item, {DateTime? from}) {
  final today = DateUtils.dateOnly(from ?? DateTime.now());
  final completions = habitCompletions(item);
  if (habitFrequency(item) == HabitFrequency.weeklyGoal) {
    var week = _weekStart(today);
    if (habitWeekCompleted(item, today) < habitWeeklyGoal(item)) {
      week = week.subtract(const Duration(days: 7));
    }
    var streak = 0;
    for (var index = 0; index < 104; index++) {
      if (habitWeekCompleted(item, week) < habitWeeklyGoal(item)) break;
      streak++;
      week = week.subtract(const Duration(days: 7));
    }
    return streak;
  }

  var cursor = today;
  if (!completions.contains(_dateKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  for (
    var index = 0;
    index < 730 && !cursor.isBefore(habitStart(item));
    index++
  ) {
    if (habitScheduledOn(item, cursor)) {
      if (!completions.contains(_dateKey(cursor))) break;
      streak++;
    }
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

double habitCompletionRate(PiEntity item, {DateTime? from, int days = 30}) {
  final today = DateUtils.dateOnly(from ?? DateTime.now());
  var scheduled = 0;
  var completed = 0;
  for (var offset = 0; offset < days; offset++) {
    final day = today.subtract(Duration(days: offset));
    if (day.isBefore(habitStart(item))) break;
    final shouldCount = habitFrequency(item) == HabitFrequency.weeklyGoal
        ? true
        : habitScheduledOn(item, day);
    if (!shouldCount) continue;
    scheduled++;
    if (habitCompletedOn(item, day)) completed++;
  }
  return scheduled == 0 ? 0 : completed / scheduled;
}

List<Reminder> habitReminders(PiEntity item, {DateTime? from}) {
  if (item.data['paused'] == true || item.data['reminderEnabled'] != true) {
    return const [];
  }
  final now = from ?? DateTime.now();
  final time =
      _parseTime(item.data['reminderTime'] as String? ?? '') ??
      const TimeOfDay(hour: 9, minute: 0);
  final title = item.data['title'] as String? ?? '习惯打卡';
  final start = habitStart(item);
  DateTime nextDaily() {
    var next = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (next.isBefore(start)) {
      next = DateTime(
        start.year,
        start.month,
        start.day,
        time.hour,
        time.minute,
      );
    }
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  switch (habitFrequency(item)) {
    case HabitFrequency.daily:
    case HabitFrequency.weeklyGoal:
      return [
        Reminder(
          id: 'habit-${item.id}-daily',
          pluginId: habitsManifest.id,
          sourceName: habitsManifest.name,
          entityId: item.id,
          title: '该打卡了：$title',
          when: nextDaily(),
          repeat: RepeatUnit.day,
        ),
      ];
    case HabitFrequency.weekdays:
      final weekdays =
          ((item.data['weekdays'] as List?) ?? const <Object?>[])
              .whereType<num>()
              .map((value) => value.toInt())
              .toSet()
              .toList()
            ..sort();
      return weekdays.map((weekday) {
        final anchor = DateTime(
          start.year,
          start.month,
          start.day,
          time.hour,
          time.minute,
        );
        return Reminder(
          id: 'habit-${item.id}-w$weekday',
          pluginId: habitsManifest.id,
          sourceName: habitsManifest.name,
          entityId: item.id,
          title: '该打卡了：$title',
          when: _nextWeekday(anchor, weekday, now),
          repeat: RepeatUnit.week,
        );
      }).toList();
  }
}

DateTime _nextWeekday(DateTime anchor, int weekday, DateTime from) {
  var candidate = DateTime(
    from.year,
    from.month,
    from.day,
    anchor.hour,
    anchor.minute,
  ).add(Duration(days: (weekday - from.weekday + 7) % 7));
  while (candidate.isBefore(anchor) || !candidate.isAfter(from)) {
    candidate = candidate.add(const Duration(days: 7));
  }
  return candidate;
}

class HabitView extends StatefulWidget {
  const HabitView({required this.repository, this.compact = false, super.key});

  final HabitRepository repository;
  final bool compact;

  @override
  State<HabitView> createState() => _HabitViewState();
}

class _HabitViewState extends State<HabitView> {
  late Future<List<PiEntity>> _items;
  EventSubscription? _subscription;
  final Map<String, bool> _completionOverrides = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
    _subscription = widget.repository.context.events.on<DataChanged>((event) {
      if (mounted && event.pluginId == habitsManifest.id) setState(_reload);
    });
  }

  void _reload() {
    final future = widget.repository.list();
    _items = future;
    unawaited(
      future.then((items) {
        if (!mounted || _completionOverrides.isEmpty) return;
        final now = DateTime.now();
        final actual = {
          for (final item in items) item.id: habitCompletedOn(item, now),
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
    const color = Color(0xFF63D6A8);
    final body = FutureBuilder<List<PiEntity>>(
      future: _items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <PiEntity>[];
        final today = DateTime.now();
        final visible = all.where((item) {
          if (widget.compact && !habitScheduledOn(item, today)) return false;
          return item.data.values
              .join(' ')
              .toLowerCase()
              .contains(_query.toLowerCase());
        }).toList();
        visible.sort((a, b) {
          final aDone =
              _completionOverrides[a.id] ?? habitCompletedOn(a, today);
          final bDone =
              _completionOverrides[b.id] ?? habitCompletedOn(b, today);
          if (aDone != bDone) return aDone ? 1 : -1;
          return (a.data['title'] as String? ?? '').compareTo(
            b.data['title'] as String? ?? '',
          );
        });
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
                    Icons.repeat_rounded,
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
                        '习惯',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.compact
                            ? '${visible.length} 个今日习惯'
                            : '${all.length} 个习惯 · 按日记录打卡',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '添加习惯',
                  onPressed: _edit,
                  icon: const Icon(Icons.add_rounded, color: color),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!widget.compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索习惯',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              Text('读取失败：${snapshot.error}')
            else if (visible.isEmpty)
              const PiEmptyState(
                icon: Icons.spa_outlined,
                message: '今天没有需要打卡的习惯。',
              )
            else
              ...visible.map((item) {
                final completed =
                    _completionOverrides[item.id] ??
                    habitCompletedOn(item, today);
                final canCheck = habitScheduledOn(item, today) || completed;
                return PiListRow(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    onTap: () => _edit(item),
                    leading: Checkbox(
                      value: completed,
                      activeColor: color,
                      onChanged: canCheck
                          ? (value) => _setCompleted(item, value == true, today)
                          : null,
                    ),
                    title: Text(
                      item.data['title'] as String? ?? '',
                      style: TextStyle(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: completed ? Colors.white38 : Colors.white,
                      ),
                    ),
                    subtitle: PiMetaLine(
                      items: _habitMetadata(item, today),
                      color: color,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white30,
                    ),
                  ),
                );
              }),
            if (widget.compact && all.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HabitView(repository: widget.repository),
                    ),
                  ),
                  child: const Text('习惯统计与管理 →'),
                ),
              ),
          ],
        );
      },
    );
    if (widget.compact) return PiCard(child: body);
    return Scaffold(
      appBar: AppBar(title: const Text('习惯')),
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

  Future<void> _edit([PiEntity? item]) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HabitEditor(repository: widget.repository, item: item),
    ),
  );

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

List<String> _habitMetadata(PiEntity item, DateTime today) {
  final parts = <String>[];
  switch (habitFrequency(item)) {
    case HabitFrequency.daily:
      parts.add('每天');
      parts.add('连续 ${habitStreak(item, from: today)} 天');
      parts.add(
        '近30天 ${(habitCompletionRate(item, from: today) * 100).round()}%',
      );
    case HabitFrequency.weekdays:
      final weekdays = ((item.data['weekdays'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((value) => _weekdayLabel(value.toInt()))
          .join('、');
      parts.add('每周$weekdays');
      parts.add('连续 ${habitStreak(item, from: today)} 次');
      parts.add(
        '近30天 ${(habitCompletionRate(item, from: today) * 100).round()}%',
      );
    case HabitFrequency.weeklyGoal:
      parts.add(
        '本周 ${habitWeekCompleted(item, today)}/${habitWeeklyGoal(item)} 次',
      );
      parts.add('连续 ${habitStreak(item, from: today)} 周达标');
  }
  if (item.data['paused'] == true) parts.add('已暂停');
  if (item.data['reminderEnabled'] == true) {
    parts.add('${item.data['reminderTime']} 提醒');
  }
  final note = (item.data['note'] as String? ?? '').trim();
  if (note.isNotEmpty) {
    parts.add(note.length > 18 ? '${note.substring(0, 18)}…' : note);
  }
  return parts;
}

class HabitEditor extends StatefulWidget {
  const HabitEditor({required this.repository, this.item, super.key});

  final HabitRepository repository;
  final PiEntity? item;

  @override
  State<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<HabitEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late HabitFrequency _frequency;
  late Set<int> _weekdays;
  late int _weeklyGoal;
  late DateTime _startDate;
  late Set<String> _completions;
  late bool _paused;
  late bool _reminderEnabled;
  late TimeOfDay _reminderTime;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = widget.item?.data ?? const <String, Object?>{};
    _title = TextEditingController(text: data['title'] as String? ?? '');
    _note = TextEditingController(text: data['note'] as String? ?? '');
    _frequency = HabitFrequency.values.firstWhere(
      (item) => item.name == data['frequency'],
      orElse: () => HabitFrequency.daily,
    );
    _weekdays = ((data['weekdays'] as List?) ?? const <Object?>[])
        .whereType<num>()
        .map((value) => value.toInt())
        .toSet();
    if (_weekdays.isEmpty) _weekdays.add(DateTime.now().weekday);
    _weeklyGoal = ((data['weeklyGoal'] as num?)?.toInt() ?? 3).clamp(1, 7);
    _startDate =
        DateTime.tryParse(data['startDate'] as String? ?? '') ?? DateTime.now();
    _completions = ((data['completions'] as List?) ?? const <Object?>[])
        .whereType<String>()
        .toSet();
    _paused = data['paused'] == true;
    _reminderEnabled = data['reminderEnabled'] == true;
    _reminderTime =
        _parseTime(data['reminderTime'] as String? ?? '') ??
        const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveHabit({
        ...?widget.item?.data,
        'title': _title.text,
        'note': _note.text,
        'frequency': _frequency.name,
        'weekdays': (_weekdays.toList()..sort()),
        'weeklyGoal': _weeklyGoal,
        'startDate': _dateKey(_startDate),
        'completions': _completions.toList()..sort(),
        'paused': _paused,
        'reminderEnabled': _reminderEnabled,
        'reminderTime': _timeKey(_reminderTime),
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
    icon: widget.item == null
        ? Icons.add_reaction_outlined
        : Icons.edit_rounded,
    title: '${widget.item == null ? '添加' : '编辑'}习惯',
    subtitle: widget.item == null ? '设定节奏、目标和本地提醒' : '调整频率、记录或暂停状态',
    color: const Color(0xFF5FD3A5),
    saving: _saving,
    onSave: _save,
    onDelete: widget.item == null ? null : _remove,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _title,
            autofocus: widget.item == null,
            decoration: const InputDecoration(
              labelText: '习惯名称',
              hintText: '例如：阅读、运动、早睡',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? '请填写习惯名称' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '备注（选填）'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HabitFrequency>(
            initialValue: _frequency,
            decoration: const InputDecoration(
              labelText: '打卡频率',
              prefixIcon: Icon(Icons.event_repeat_rounded),
            ),
            items: const [
              DropdownMenuItem(value: HabitFrequency.daily, child: Text('每天')),
              DropdownMenuItem(
                value: HabitFrequency.weekdays,
                child: Text('指定星期'),
              ),
              DropdownMenuItem(
                value: HabitFrequency.weeklyGoal,
                child: Text('每周完成若干次'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _frequency = value ?? HabitFrequency.daily),
          ),
          if (_frequency == HabitFrequency.weekdays) ...[
            const SizedBox(height: 12),
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
          ],
          if (_frequency == HabitFrequency.weeklyGoal) ...[
            const SizedBox(height: 12),
            Text('每周目标：$_weeklyGoal 次'),
            Slider(
              value: _weeklyGoal.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_weeklyGoal 次',
              onChanged: (value) => setState(() => _weeklyGoal = value.round()),
            ),
          ],
          PiListRow(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('开始日期'),
              subtitle: Text(
                '${_startDate.year}年${_startDate.month}月${_startDate.day}日',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2200),
                );
                if (selected != null && mounted) {
                  setState(() => _startDate = selected);
                }
              },
            ),
          ),
          if (widget.item != null) ...[
            const SizedBox(height: 4),
            const Text(
              '近 14 天打卡（可补签）',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(14, (index) {
                final day = DateUtils.dateOnly(
                  DateTime.now().subtract(Duration(days: 13 - index)),
                );
                final key = _dateKey(day);
                final enabled = !day.isBefore(DateUtils.dateOnly(_startDate));
                return FilterChip(
                  label: Text('${day.month}/${day.day}'),
                  selected: _completions.contains(key),
                  onSelected: enabled
                      ? (selected) => setState(() {
                          selected
                              ? _completions.add(key)
                              : _completions.remove(key);
                        })
                      : null,
                );
              }),
            ),
            const SizedBox(height: 8),
          ],
          PiListRow(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('本地提醒'),
              subtitle: Text(
                _reminderEnabled ? '每天 ${_reminderTime.format(context)}' : '关闭',
              ),
              value: _reminderEnabled,
              onChanged: (value) => setState(() => _reminderEnabled = value),
            ),
          ),
          if (_reminderEnabled)
            PiListRow(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('提醒时间'),
                subtitle: Text(_reminderTime.format(context)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: _reminderTime,
                  );
                  if (selected != null && mounted) {
                    setState(() => _reminderTime = selected);
                  }
                },
              ),
            ),
          PiListRow(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              secondary: const Icon(Icons.pause_circle_outline_rounded),
              title: const Text('暂停这个习惯'),
              subtitle: const Text('暂停后不在首页出现，也不会发送提醒'),
              value: _paused,
              onChanged: (value) => setState(() => _paused = value),
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
      builder: (context) => AlertDialog(
        title: const PiDialogTitle(
          icon: Icons.delete_outline_rounded,
          title: '删除这个习惯？',
          subtitle: '相关打卡记录和本地提醒也会移除',
          color: Color(0xFFFF8F91),
        ),
        content: const Text('相关打卡记录和本地提醒也会一起移除。'),
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
      try {
        await widget.repository.remove(widget.item!);
        if (mounted) Navigator.pop(context);
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
  }
}

DateTime _weekStart(DateTime date) {
  final day = DateUtils.dateOnly(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

TimeOfDay? _parseTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _timeKey(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _weekdayLabel(int weekday) =>
    const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
