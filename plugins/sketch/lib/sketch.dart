import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

import 'sketch_editor.dart';

const sketchManifest = PluginManifest(
  id: 'dev.pi.sketch',
  name: '画板',
  description: '随手画张示意图，分享给别人。',
  icon: 'draw',
  colorValue: 0xFF7CCCF2,
);

class SketchPlugin implements PiPlugin {
  @override
  PluginManifest get manifest => sketchManifest;

  @override
  Future<void> register(PluginContext context) async {
    final repo = _SketchRepository(context);
    context.route(
      RouteContribution(
        id: manifest.id,
        label: manifest.name,
        icon: Icons.draw_rounded,
        order: 40,
        builder: (_, _) => _SketchLibrary(repo),
      ),
    );
    context.contribute(
      UiContribution(
        id: '${manifest.id}.home',
        slot: 'home.secondary',
        order: 40,
        builder: (context, _) => PiCard(
          child: ListTile(
            leading: const Icon(Icons.draw_rounded),
            title: const Text('画板'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => _SketchLibrary(repo)),
            ),
            trailing: IconButton(
              tooltip: '新建画板',
              icon: const Icon(Icons.add),
              onPressed: () => openSketch(context, repo),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> start(PluginContext context) async {}
  @override
  Future<void> stop(PluginContext context) async {}
}

class _SketchRepository extends EntryRepository {
  _SketchRepository(PluginContext context) : super(context, 'drawing');
}

class _SketchLibrary extends StatefulWidget {
  const _SketchLibrary(this.repo);
  final EntryRepository repo;
  @override
  State<_SketchLibrary> createState() => _SketchLibraryState();
}

class _SketchLibraryState extends State<_SketchLibrary> {
  late Future<List<PiEntity>> _items = widget.repo.list();
  late final EventSubscription _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.repo.context.events.on<DataChanged>((event) {
      if (event.pluginId == sketchManifest.id) {
        setState(() => _items = widget.repo.list());
      }
    });
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('画板'),
      actions: [
        IconButton(
          tooltip: '新建画板',
          icon: const Icon(Icons.add),
          onPressed: () => openSketch(context, widget.repo),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<List<PiEntity>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('读取失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = [...snapshot.data!]
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          if (items.isEmpty) {
            return Center(
              child: FilledButton.icon(
                icon: const Icon(Icons.draw_rounded),
                label: const Text('画第一张图'),
                onPressed: () => openSketch(context, widget.repo),
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: const Icon(Icons.gesture),
                title: Text(item.data['title'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openSketch(context, widget.repo, item),
              );
            },
          );
        },
      ),
    ),
  );
}
