import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';
import 'package:share_plus/share_plus.dart';

// Older drawings used a 1024-square paper and a single 6-unit brush.
const _side = 1024.0;
const _inks = {
  '黑色': Colors.black,
  '蓝色': Color(0xff1559ae),
  '红色': Color(0xffb52e38),
  '橙色': Color(0xffc35c13),
  '黄色': Color(0xffdea900),
  '绿色': Color(0xff238451),
  '紫色': Color(0xff7846af),
};
const _widths = {'细': 3.0, '标准': 6.0, '粗': 12.0, '特粗': 24.0};

class _Stroke {
  _Stroke(this.ink, this.width, this.points) {
    final first = points.first;
    path.moveTo(first.dx, first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
  }
  final Color ink;
  final double width;
  final List<Offset> points;
  final path = Path();
  void extend(Offset point) {
    if (point == points.last) return;
    points.add(point);
    path.lineTo(point.dx, point.dy);
  }

  JsonMap encode() => {
    'ink': ink.toARGB32(),
    'width': width,
    'points': [
      for (final p in points) [p.dx.toInt(), p.dy.toInt()],
    ],
  };

  factory _Stroke.decode(Map data) {
    final points = <Offset>[];
    for (final pair in data['points'] as List) {
      points.add(
        Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
      );
    }
    return _Stroke(
      Color(data['ink'] as int),
      (data['width'] as num?)?.toDouble() ?? 6,
      points,
    );
  }
}

Future<void> openSketch(
  BuildContext context,
  EntryRepository repo, [
  PiEntity? item,
]) => guard(context, () async {
  final strokes = [
    for (final data in item?.data['strokes'] as List? ?? const [])
      _Stroke.decode(data as Map),
  ];
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _Editor(repo: repo, item: item, strokes: strokes),
    ),
  );
});

class _Paper extends CustomPainter {
  _Paper(this.strokes, this.view, {super.repaint});
  final List<_Stroke> strokes;
  final Rect view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.save();
    canvas.scale(size.width / view.width);
    canvas.translate(-view.left, -view.top);
    final pen = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      pen.color = stroke.ink;
      pen.strokeWidth = stroke.width;
      if (stroke.points.length == 1) {
        pen.style = PaintingStyle.fill;
        canvas.drawCircle(stroke.points.first, stroke.width / 2, pen);
      } else {
        pen.style = PaintingStyle.stroke;
        canvas.drawPath(stroke.path, pen);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Paper oldDelegate) => true;
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.repo,
    required this.item,
    required this.strokes,
  });
  final EntryRepository repo;
  final PiEntity? item;
  final List<_Stroke> strokes;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _title = TextEditingController(
    text: widget.item?.data['title'] as String?,
  );
  Color _ink = Colors.black;
  double _width = 6;
  bool _toolsVisible = true;
  Size? _lastSize;
  late Rect _view = _savedView();
  Rect _savedView() {
    final paper = widget.item?.data['paper'];
    if (paper is List &&
        paper.length == 4 &&
        paper.every((v) => v is num && v.isFinite)) {
      final values = paper.cast<num>();
      final rect = Rect.fromLTWH(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      );
      if (!rect.isEmpty) return rect;
    }
    return const Rect.fromLTWH(0, 0, _side, _side);
  }

  Rect _viewport(Size size) {
    if (_lastSize == size) return _view;
    // Fit all existing ink on rotation. Empty margins also accept new strokes.
    var content = _savedView();
    for (final stroke in widget.strokes) {
      content = content.expandToInclude(
        stroke.path.getBounds().inflate(stroke.width / 2),
      );
      final first = stroke.points.first;
      content = content.expandToInclude(
        Rect.fromCircle(center: first, radius: stroke.width / 2),
      );
    }
    final units = math.max(
      content.width / size.width,
      content.height / size.height,
    );
    _lastSize = size;
    return _view = Rect.fromCenter(
      center: content.center,
      width: size.width * units,
      height: size.height * units,
    );
  }

  int? _pointer;
  bool _dirty = false;
  bool _saving = false;
  final _redo = <_Stroke>[];
  final _inkRevision = ValueNotifier(0);

  @override
  void dispose() {
    _inkRevision.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await guard(context, () async {
      final name = _title.text.trim();
      final time = DateTime.now().toString().substring(0, 16);
      await widget.repo.save({
        'title': name.isEmpty ? '示意图 $time' : name,
        'strokes': widget.strokes.map((s) => s.encode()).toList(),
        'paper': [_view.left, _view.top, _view.width, _view.height],
      }, previous: widget.item);
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _share(BuildContext anchor) => guard(context, () async {
    final box = anchor.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final recorder = ui.PictureRecorder();
    final scale = 2048 / math.max(_view.width, _view.height);
    final size = Size(
      math.max(1, (_view.width * scale).round()).toDouble(),
      math.max(1, (_view.height * scale).round()).toDouble(),
    );
    _Paper(widget.strokes, _view).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('生成图片失败');
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: ['sketch.png'],
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      image.dispose();
    }
  });

  Future<void> _leave(bool didPop, void result) async {
    if (didPop || _saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续画'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) Navigator.pop(context);
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isEmpty) return const SizedBox.shrink();
      final view = _viewport(size);
      Offset point(Offset local) {
        final scale = view.width / size.width;
        return Offset(
          (view.left + local.dx.clamp(0, size.width) * scale).roundToDouble(),
          (view.top + local.dy.clamp(0, size.height) * scale).roundToDouble(),
        );
      }

      return Semantics(
        label: '手绘画布',
        child: ClipRect(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (_pointer != null) return;
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                _pointer = event.pointer;
                widget.strokes.add(
                  _Stroke(_ink, _width, [point(event.localPosition)]),
                );
                _redo.clear();
                _dirty = true;
              });
            },
            onPointerMove: (event) {
              if (_pointer == event.pointer) {
                widget.strokes.last.extend(point(event.localPosition));
                _inkRevision.value++;
              }
            },
            onPointerUp: (event) {
              if (_pointer == event.pointer) {
                setState(() => _pointer = null);
              }
            },
            onPointerCancel: (event) {
              if (_pointer == event.pointer) {
                setState(() => _pointer = null);
              }
            },
            child: CustomPaint(
              painter: _Paper(widget.strokes, view, repaint: _inkRevision),
            ),
          ),
        ),
      );
    },
  );

  Widget _toolbar() => Wrap(
    alignment: WrapAlignment.center,
    children: [
      PopupMenuButton<Color>(
        tooltip: '画笔颜色',
        initialValue: _ink,
        icon: Icon(
          Icons.circle,
          color: _ink,
          shadows: const [Shadow(color: Colors.white70, blurRadius: 3)],
        ),
        onSelected: (color) => setState(() => _ink = color),
        itemBuilder: (_) => [
          for (final entry in _inks.entries)
            CheckedPopupMenuItem(
              value: entry.value,
              checked: entry.value == _ink,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: entry.value),
                  const SizedBox(width: 12),
                  Text(entry.key),
                ],
              ),
            ),
        ],
      ),
      PopupMenuButton<double>(
        tooltip: '笔触大小',
        icon: const Icon(Icons.line_weight),
        initialValue: _width,
        onSelected: (width) => setState(() => _width = width),
        itemBuilder: (_) => [
          for (final entry in _widths.entries)
            CheckedPopupMenuItem(
              value: entry.value,
              checked: _width == entry.value,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    child: Divider(thickness: entry.value / 2),
                  ),
                  const SizedBox(width: 12),
                  Text(entry.key),
                ],
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: '撤销',
        icon: const Icon(Icons.undo),
        onPressed: widget.strokes.isEmpty || _pointer != null
            ? null
            : () => setState(() {
                _redo.add(widget.strokes.removeLast());
                _dirty = true;
              }),
      ),
      IconButton(
        tooltip: '重做',
        icon: const Icon(Icons.redo),
        onPressed: _redo.isEmpty || _pointer != null
            ? null
            : () => setState(() {
                widget.strokes.add(_redo.removeLast());
                _dirty = true;
              }),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: _leave,
    child: AbsorbPointer(
      absorbing: _saving,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _canvas(),
            SafeArea(
              minimum: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Material(
                    borderRadius: BorderRadius.circular(24),
                    elevation: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_toolsVisible) ...[
                          const BackButton(),
                          Expanded(
                            child: TextField(
                              controller: _title,
                              decoration: const InputDecoration(
                                hintText: '画板名称',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() => _dirty = true),
                            ),
                          ),
                          Builder(
                            builder: (anchor) => IconButton(
                              tooltip: '分享图片',
                              icon: const Icon(Icons.ios_share_rounded),
                              onPressed: widget.strokes.isEmpty
                                  ? null
                                  : () => _share(anchor),
                            ),
                          ),
                          IconButton(
                            tooltip: '保存画板',
                            icon: const Icon(Icons.check),
                            onPressed: _dirty ? _save : null,
                          ),
                        ],
                        IconButton(
                          tooltip: _toolsVisible ? '收起工具' : '展开工具',
                          icon: Icon(
                            _toolsVisible
                                ? Icons.fullscreen
                                : Icons.fullscreen_exit,
                          ),
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _toolsVisible = !_toolsVisible);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_toolsVisible)
                    Center(
                      child: Material(
                        borderRadius: BorderRadius.circular(24),
                        elevation: 2,
                        child: _toolbar(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
