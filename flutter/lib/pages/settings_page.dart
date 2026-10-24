import 'package:flutter/material.dart';

import '../app.dart';
import '../data/database.dart';
import '../theme.dart';

/// 数据页：主题选择、底栏磨砂、点击震动、统计与关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _db = AppDatabase.instance;
  int _docs = 0;
  int _books = 0;
  int _sources = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final docs = await _db.documentCount();
    final books = await _db.bookCount();
    final sources = await _db.sourceCount();
    if (mounted) {
      setState(() {
        _docs = docs;
        _books = books;
        _sources = sources;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final haptic = scope.prefs.getBool('haptic_enabled') ?? false;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('数据',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text('$_docs 条内容 · $_books 本书名 · $_sources 条来源',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('主题与外观',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in appThemes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ThemeChip(
                        option: option,
                        selected: option.id == scope.themeId,
                        onTap: () => scope.changeTheme(option.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SwitchCard(
              title: '底栏磨砂',
              hint: '开启后底栏呈半透明悬浮效果',
              value: scope.frosted,
              onChanged: (checked) => scope.toggleFrosted(),
            ),
            const SizedBox(height: 10),
            _SwitchCard(
              title: '点击震动',
              hint: '默认关闭；开启后仅提供轻微触感',
              value: haptic,
              onChanged: (checked) =>
                  scope.prefs.setBool('haptic_enabled', checked),
            ),
            const SizedBox(height: 20),
            Text('关于',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 10),
            Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('扫书新典 v4.0（Flutter 版）',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '由原生 Java 版迁移至 Flutter 的首个预览版。'
                      '数据与原生版共用同一私有数据库，收藏与主题设置自动迁移；'
                      '网络采集、WebDAV 备份等功能将在后续版本补齐。',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final AppThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChip(
      {required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color(option.seed),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 8),
              Text(option.label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? scheme.primary : scheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchCard(
      {required this.title,
      required this.hint,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3, bottom: 8),
                    child: Text(hint,
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
