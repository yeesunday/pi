import 'package:flutter/material.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';

import 'plugin_icon.dart';
import 'settings_page.dart';

class PiSettingsOverview extends StatelessWidget {
  const PiSettingsOverview({required this.runtime, super.key});

  final PiRuntime runtime;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 4),
        sliver: SliverToBoxAdapter(
          child: Text(
            '设置',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
        sliver: SliverToBoxAdapter(
          child: Text(
            '让 Pi 更贴合你的生活方式。',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(
          child: _SettingsSection(
            title: '插件与入口',
            icon: Icons.extension_rounded,
            color: piLilac,
            children: [
              const Text(
                '插件可以贡献首页卡片和独立页面。你可以随时启用或停用。',
                style: TextStyle(color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 14),
              ...runtime.availablePlugins.map(
                (descriptor) =>
                    _PluginTile(runtime: runtime, descriptor: descriptor),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        sliver: SliverToBoxAdapter(
          child: _SettingsSection(
            title: '数据与 AI',
            icon: Icons.tune_rounded,
            color: const Color(0xFF65B7E8),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.import_export_rounded),
                title: const Text('数据与备份'),
                subtitle: const Text('导入、导出本地数据'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PiSettingsPage(
                      runtime: runtime,
                      section: PiSettingsSection.data,
                    ),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('AI Provider'),
                subtitle: const Text('配置兼容 OpenAI 的模型服务'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PiSettingsPage(
                      runtime: runtime,
                      section: PiSettingsSection.ai,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        sliver: SliverToBoxAdapter(
          child: _SettingsSection(
            title: '偏好',
            icon: Icons.palette_outlined,
            color: const Color(0xFFFFB45B),
            children: [
              const SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: true,
                onChanged: null,
                title: Text('深色外观'),
                subtitle: Text('当前版本固定使用深色外观'),
                secondary: Icon(Icons.dark_mode_outlined),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('个人资料'),
                subtitle: const Text('个人空间 · 本机设备'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const PiDialogTitle(
                      icon: Icons.person_outline_rounded,
                      title: '个人资料',
                      subtitle: 'Pi 当前使用一个本机个人空间',
                    ),
                    content: const Text('当前版本只有一个本机个人空间。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PiCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children.map(
          (child) => Material(color: Colors.transparent, child: child),
        ),
      ],
    ),
  );
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.runtime, required this.descriptor});

  final PiRuntime runtime;
  final PluginDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final manifest = descriptor.manifest;
    final active = runtime.isActive(manifest.id);
    final color = Color(manifest.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active && runtime.routes[manifest.id] != null
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      runtime.routes[manifest.id]!.builder(context, runtime),
                ),
              )
            : null,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(pluginIcon(manifest.icon), color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manifest.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    manifest.description,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: active,
              onChanged: (value) => guard(context, () async {
                if (value) {
                  await runtime.install(manifest.id);
                } else {
                  await runtime.uninstall(manifest.id);
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}
