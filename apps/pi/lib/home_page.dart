import 'package:flutter/material.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

import 'plugin_icon.dart';
import 'settings_overview.dart';

class PiHomePage extends StatefulWidget {
  const PiHomePage({super.key});

  @override
  State<PiHomePage> createState() => _PiHomePageState();
}

class _PiHomePageState extends State<PiHomePage> {
  int _tab = 0;
  int _dashboardRevision = 0;

  @override
  Widget build(BuildContext context) {
    final runtime = PiRuntimeScope.of(context);
    final pages = <Widget>[
      _dashboard(context, runtime),
      PiSettingsOverview(runtime: runtime),
    ];
    const destinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: '今日',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings_rounded),
        label: '设置',
      ),
    ];
    if (_tab >= pages.length) _tab = 0;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: destinations,
      ),
    );
  }

  Widget _dashboard(BuildContext context, PiRuntime runtime) {
    final contributions = [
      ...runtime.ui.contributions('home.primary'),
      ...runtime.ui.contributions('home.secondary'),
    ];
    return RefreshIndicator(
      onRefresh: () async => setState(() => _dashboardRevision++),
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
            sliver: SliverToBoxAdapter(child: _todayPill(context, runtime)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: contributions.length,
              itemBuilder: (context, index) {
                final contribution = contributions[index];
                return KeyedSubtree(
                  key: ValueKey('${contribution.id}:$_dashboardRevision'),
                  child: contribution.builder(context, runtime),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _greeting(PiRuntime runtime) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? '早上好'
        : now.hour < 18
        ? '下午好'
        : '晚上好';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .48),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '今天，也按自己的节奏来。',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${runtime.activePlugins.length} 个能力正在陪伴你',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .38),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB6A6FF), Color(0xFF6C63FF)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B7CFF).withValues(alpha: .3),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Widget _todayPill(BuildContext context, PiRuntime runtime) {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF8B7CFF).withValues(alpha: .14),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}',
            style: const TextStyle(
              color: Color(0xFFB7ADFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _showHomeCustomization(context, runtime),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: const Text('自定义'),
        ),
      ],
    );
  }

  Future<void> _showHomeCustomization(
    BuildContext context,
    PiRuntime runtime,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: runtime,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              const Text(
                '自定义首页',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '启用的能力会以卡片形式出现在首页；关闭不会删除已有数据。',
                style: TextStyle(color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 18),
              if (runtime.availablePlugins.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '暂无可自定义的能力',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: runtime.availablePlugins.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final descriptor = runtime.availablePlugins[index];
                      final manifest = descriptor.manifest;
                      final active = runtime.isActive(manifest.id);
                      return Material(
                        color: Colors.white.withValues(alpha: .055),
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          secondary: Icon(
                            pluginIcon(manifest.icon),
                            color: Color(manifest.colorValue),
                          ),
                          title: Text(
                            manifest.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            active ? '已显示在首页' : '未显示',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: active,
                          onChanged: (enabled) => guard(sheetContext, () async {
                            if (enabled) {
                              await runtime.install(manifest.id);
                            } else {
                              await runtime.uninstall(manifest.id);
                            }
                          }),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
