import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

const anniversaryManifest = PluginManifest(
  id: 'dev.pi.anniversary',
  name: '纪念日',
  description: '生日、节日和每一个值得记住的日子。',
  icon: 'celebration',
  colorValue: 0xFFFF8B7B,
);

enum AnniversaryCalendar { solar, lunar }

class AnniversaryPlugin implements PiPlugin {
  @override
  PluginManifest get manifest => anniversaryManifest;

  @override
  Future<void> register(PluginContext context) async {
    final repository = AnniversaryRepository(context);
    Widget page(BuildContext context, PiRuntime runtime) =>
        AnniversaryView(repository: repository);
    context.route(
      RouteContribution(
        id: manifest.id,
        label: manifest.name,
        icon: Icons.celebration_rounded,
        builder: page,
        order: 20,
      ),
    );
    context.contribute(
      UiContribution(
        id: '${manifest.id}.home',
        slot: 'home.secondary',
        order: 20,
        builder: (context, runtime) =>
            AnniversaryView(repository: repository, compact: true),
      ),
    );
  }

  @override
  Future<void> start(PluginContext context) async {
    final repository = AnniversaryRepository(context);
    for (final item in await repository.list()) {
      await repository.refreshReminders(item);
    }
  }

  @override
  Future<void> stop(PluginContext context) async {}
}

class AnniversaryRepository extends EntryRepository {
  AnniversaryRepository(PluginContext context) : super(context, 'anniversary');

  Future<PiEntity> saveAnniversary(JsonMap values, {PiEntity? previous}) async {
    final title = (values['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const FormatException('请填写名称');
    final reminderDays =
        ((values['reminderDays'] as List?) ?? const [0])
            .map((value) => value as int)
            .where((value) => value >= 0 && value <= 365)
            .toSet()
            .toList()
          ..sort();
    if (reminderDays.isEmpty) throw const FormatException('请至少选择一个提醒时间');
    final normalized = <String, Object?>{
      ...values,
      'title': title,
      'reminderDays': reminderDays,
    };
    anniversaryNextOccurrence(normalized);
    final saved = await super.save(normalized, previous: previous);
    await refreshReminders(saved);
    return saved;
  }

  Future<void> refreshReminders(PiEntity item) async {
    await context.reminders.replaceForEntity(
      anniversaryManifest.id,
      item.id,
      anniversaryReminders(item),
    );
  }

  @override
  Future<void> remove(PiEntity item) async {
    await context.reminders.replaceForEntity(
      anniversaryManifest.id,
      item.id,
      const [],
    );
    await super.remove(item);
  }
}

List<Reminder> anniversaryReminders(PiEntity item, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final days = ((item.data['reminderDays'] as List?) ?? const [0]).cast<int>();
  return days.map((daysBefore) {
    final occurrence = anniversaryNextOccurrence(
      item.data,
      from: now.add(Duration(days: daysBefore)),
    );
    return Reminder(
      id: 'anniversary-${item.id}-$daysBefore',
      pluginId: anniversaryManifest.id,
      sourceName: anniversaryManifest.name,
      entityId: item.id,
      title: daysBefore == 0
          ? '今天是${item.data['title']}'
          : '还有 $daysBefore 天是${item.data['title']}',
      when: occurrence.subtract(Duration(days: daysBefore)),
      repeat: RepeatUnit.year,
    );
  }).toList();
}

DateTime anniversaryNextOccurrence(JsonMap data, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final time = (data['time'] as String? ?? '09:00').split(':');
  final hour = int.tryParse(time.first) ?? 9;
  final minute = time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0;
  if (data['calendar'] != AnniversaryCalendar.lunar.name) {
    final source = DateTime.tryParse(data['date'] as String? ?? '');
    if (source == null) throw const FormatException('请选择公历日期');
    for (var year = now.year; year <= now.year + 8; year++) {
      final maxDay = DateTime(year, source.month + 1, 0).day;
      final candidate = DateTime(
        year,
        source.month,
        math.min(source.day, maxDay),
        hour,
        minute,
      );
      if (!candidate.isBefore(now)) return candidate;
    }
  } else {
    final month = data['lunarMonth'] as int?;
    final day = data['lunarDay'] as int?;
    if (month == null || day == null) throw const FormatException('请选择农历日期');
    final leap = data['lunarLeap'] == true;
    final currentLunarYear = Lunar.fromDate(now).getYear();
    for (var year = currentLunarYear; year <= currentLunarYear + 20; year++) {
      final candidateDays = day == 30 ? const [30, 29] : [day];
      for (final candidateDay in candidateDays) {
        try {
          final solar = Lunar.fromYmd(
            year,
            leap ? -month : month,
            candidateDay,
          ).getSolar();
          final candidate = DateTime(
            solar.getYear(),
            solar.getMonth(),
            solar.getDay(),
            hour,
            minute,
          );
          if (!candidate.isBefore(now)) return candidate;
          break;
        } catch (_) {
          // Lunar month 30 may become month 29; leap months do not occur every year.
        }
      }
    }
  }
  throw const FormatException('无法计算下一次纪念日');
}

/// Calendar-day distance for display. Notification time must not make an
/// anniversary that is today appear as next year's event after its alert time.
int anniversaryDaysUntil(JsonMap data, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final today = DateUtils.dateOnly(now);
  final next = anniversaryNextOccurrence(data, from: today);
  return DateUtils.dateOnly(next).difference(today).inDays;
}

String anniversaryDateLabel(JsonMap data) {
  if (data['calendar'] == AnniversaryCalendar.lunar.name) {
    final month = data['lunarMonth'] as int? ?? 1;
    final day = data['lunarDay'] as int? ?? 1;
    final leap = data['lunarLeap'] == true ? '闰' : '';
    return '农历 $leap${LunarUtil.MONTH[month]}月${LunarUtil.DAY[day]}';
  }
  final date = DateTime.tryParse(data['date'] as String? ?? '');
  return date == null ? '未选择日期' : '公历 ${date.month}月${date.day}日';
}

class AnniversaryView extends StatefulWidget {
  const AnniversaryView({
    required this.repository,
    this.compact = false,
    super.key,
  });
  final AnniversaryRepository repository;
  final bool compact;

  @override
  State<AnniversaryView> createState() => _AnniversaryViewState();
}

class _AnniversaryViewState extends State<AnniversaryView> {
  late Future<List<PiEntity>> _items;
  EventSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _reload();
    _subscription = widget.repository.context.events.on<DataChanged>((event) {
      if (mounted && event.pluginId == anniversaryManifest.id) {
        setState(_reload);
      }
    });
  }

  void _reload() => _items = widget.repository.list();

  @override
  void dispose() {
    _subscription?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<PiEntity>>(
      future: _items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <PiEntity>[];
        final sorted = [...all]
          ..sort(
            (a, b) => anniversaryDaysUntil(
              a.data,
            ).compareTo(anniversaryDaysUntil(b.data)),
          );
        final items = widget.compact ? sorted.take(3) : sorted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8B7B).withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.celebration_rounded,
                    color: Color(0xFFFF8B7B),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '纪念日',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${all.length} 个重要日子',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '添加纪念日',
                  onPressed: _edit,
                  icon: const Icon(Icons.add_rounded, color: Color(0xFFFF8B7B)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              Text('读取失败：${snapshot.error}')
            else if (items.isEmpty)
              const PiEmptyState(
                icon: Icons.favorite_border_rounded,
                message: '把生日、相识日和重要节日放在这里。',
              )
            else
              ...items.map((item) {
                final days = anniversaryDaysUntil(item.data);
                return PiListRow(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    onTap: () => _edit(item),
                    title: Text(item.data['title'] as String? ?? ''),
                    subtitle: PiMetaLine(
                      items: [
                        anniversaryDateLabel(item.data),
                        days == 0 ? '就是今天' : '$days 天后',
                      ],
                      color: const Color(0xFFFF8B7B),
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
                      builder: (_) =>
                          AnniversaryView(repository: widget.repository),
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
      appBar: AppBar(title: const Text('纪念日')),
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
        builder: (_) =>
            AnniversaryEditor(repository: widget.repository, item: item),
      ),
    );
  }
}

class AnniversaryEditor extends StatefulWidget {
  const AnniversaryEditor({required this.repository, this.item, super.key});
  final AnniversaryRepository repository;
  final PiEntity? item;

  @override
  State<AnniversaryEditor> createState() => _AnniversaryEditorState();
}

class _AnniversaryEditorState extends State<AnniversaryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _customReminder;
  late final TextEditingController _lunarYear;
  late AnniversaryCalendar _calendar;
  late DateTime _solarDate;
  late int _lunarMonth;
  late int _lunarDay;
  late bool _lunarLeap;
  late TimeOfDay _time;
  late Set<int> _reminderDays;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = widget.item?.data ?? const <String, Object?>{};
    _title = TextEditingController(text: data['title'] as String? ?? '');
    _note = TextEditingController(text: data['note'] as String? ?? '');
    _customReminder = TextEditingController();
    _lunarYear = TextEditingController(
      text: data['lunarYear']?.toString() ?? '',
    );
    _calendar = data['calendar'] == AnniversaryCalendar.lunar.name
        ? AnniversaryCalendar.lunar
        : AnniversaryCalendar.solar;
    _solarDate =
        DateTime.tryParse(data['date'] as String? ?? '') ?? DateTime.now();
    final currentLunar = Lunar.fromDate(DateTime.now());
    _lunarMonth = data['lunarMonth'] as int? ?? currentLunar.getMonth().abs();
    _lunarDay = data['lunarDay'] as int? ?? currentLunar.getDay();
    _lunarLeap = data['lunarLeap'] == true;
    final timeParts = (data['time'] as String? ?? '09:00').split(':');
    _time = TimeOfDay(
      hour: int.tryParse(timeParts.first) ?? 9,
      minute: timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0,
    );
    _reminderDays =
        (((data['reminderDays'] as List?) ?? const [0, 1, 7]).cast<int>())
            .toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _customReminder.dispose();
    _lunarYear.dispose();
    super.dispose();
  }

  JsonMap _values() => {
    'title': _title.text.trim(),
    'note': _note.text.trim(),
    'calendar': _calendar.name,
    'date': _solarDate.toIso8601String().substring(0, 10),
    'lunarYear': int.tryParse(_lunarYear.text),
    'lunarMonth': _lunarMonth,
    'lunarDay': _lunarDay,
    'lunarLeap': _lunarLeap,
    'time':
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
    'reminderDays': (_reminderDays.toList()..sort()),
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveAnniversary(_values(), previous: widget.item);
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

  void _addCustomReminder() {
    final value = int.tryParse(_customReminder.text);
    if (value == null || value < 0 || value > 365) {
      setState(() => _error = '提前天数需为 0–365');
      return;
    }
    setState(() {
      _reminderDays.add(value);
      _customReminder.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const commonDays = [0, 1, 3, 7, 14, 30];
    return PiEditorScaffold(
      icon: widget.item == null
          ? Icons.favorite_border_rounded
          : Icons.edit_calendar_outlined,
      title: '${widget.item == null ? '添加' : '编辑'}纪念日',
      subtitle: widget.item == null ? '支持公历、农历和多个提前提醒' : '修改日期和本地提醒时间',
      color: const Color(0xFFFF8B7B),
      saving: _saving,
      canSave: _reminderDays.isNotEmpty,
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
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：结婚纪念日、妈妈生日',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请填写名称' : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<AnniversaryCalendar>(
              segments: const [
                ButtonSegment(
                  value: AnniversaryCalendar.solar,
                  label: Text('公历'),
                  icon: Icon(Icons.calendar_today_outlined),
                ),
                ButtonSegment(
                  value: AnniversaryCalendar.lunar,
                  label: Text('农历'),
                  icon: Icon(Icons.brightness_3_outlined),
                ),
              ],
              selected: {_calendar},
              onSelectionChanged: (value) =>
                  setState(() => _calendar = value.single),
            ),
            const SizedBox(height: 16),
            if (_calendar == AnniversaryCalendar.solar)
              PiListRow(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('日期'),
                  subtitle: Text(
                    '${_solarDate.year}年${_solarDate.month}月${_solarDate.day}日',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _solarDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                    );
                    if (selected != null && mounted) {
                      setState(() => _solarDate = selected);
                    }
                  },
                ),
              )
            else ...[
              TextFormField(
                controller: _lunarYear,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '年份（选填）',
                  hintText: '只用于记录年份，不影响每年提醒',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _lunarMonth,
                      decoration: const InputDecoration(labelText: '农历月份'),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('${index + 1} 月'),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _lunarMonth = value ?? 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _lunarDay,
                      decoration: const InputDecoration(labelText: '农历日期'),
                      items: List.generate(
                        30,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('${index + 1} 日'),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _lunarDay = value ?? 1),
                    ),
                  ),
                ],
              ),
              PiListRow(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  secondary: const Icon(Icons.brightness_3_outlined),
                  title: const Text('闰月'),
                  subtitle: const Text('仅在对应年份存在该闰月时发生'),
                  value: _lunarLeap,
                  onChanged: (value) => setState(() => _lunarLeap = value),
                ),
              ),
            ],
            PiListRow(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('提醒时间'),
                subtitle: Text(_time.format(context)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (selected != null && mounted) {
                    setState(() => _time = selected);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text('提前提醒', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...commonDays.map(
                  (days) => FilterChip(
                    label: Text(days == 0 ? '当天' : '$days 天前'),
                    selected: _reminderDays.contains(days),
                    onSelected: (selected) => setState(
                      () => selected
                          ? _reminderDays.add(days)
                          : _reminderDays.remove(days),
                    ),
                  ),
                ),
                ..._reminderDays
                    .where((days) => !commonDays.contains(days))
                    .map(
                      (days) => InputChip(
                        label: Text('$days 天前'),
                        onDeleted: () =>
                            setState(() => _reminderDays.remove(days)),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customReminder,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自定义提前天数',
                      hintText: '0–365',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _addCustomReminder,
                  tooltip: '添加提醒',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '备注（选填）'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PiDialogTitle(
          icon: Icons.delete_outline_rounded,
          title: '删除这个纪念日？',
          subtitle: '对应的多个本地提醒也会一起取消',
          color: Color(0xFFFF8F91),
        ),
        content: const Text('删除后，这个纪念日将不再出现在首页。'),
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
}
