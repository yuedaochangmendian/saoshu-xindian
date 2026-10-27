import 'package:flutter/material.dart';

import '../app.dart';
import 'dart:convert';
import 'dart:io';
import '../services/backup_service.dart';
import '../services/secure_store.dart';
import '../services/system_bridge.dart';
import '../services/update_service.dart';
import '../services/webdav_client.dart';
import '../data/database.dart';
import '../theme.dart';

/// 数据页：主题选择、底栏磨砂、点击震动、统计与关于。
/// 设置页统一折叠组外壳：Material 圆角卡 + 无边 ExpansionTile。
Widget _settingsGroup(BuildContext context,
    {required String title,
    required String subtitle,
    required List<Widget> children}) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        children: children,
      ),
    ),
  );
}

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
  String _appVersionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await SystemBridge.appVersion();
    if (mounted) {
      setState(() {
        final version = info?['version'] as String? ?? '';
        _appVersionLabel = version.isEmpty ? 'v4.1' : 'v$version';
      });
    }
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text('数据',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text('$_docs 条内容 · $_books 本书名 · $_sources 条来源',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            // 低频设置全部折叠成两组，页面只剩 数据/备份 + 个性化 + 关于。
            _settingsGroup(context,
                title: '数据与备份',
                subtitle: '本地备份 / WebDAV',
                children: [
                  _BackupSection(),
                ]),
            const SizedBox(height: 16),
            _settingsGroup(context,
                title: '主题与个性化',
                subtitle: '主题 / 点击震动 / 桌面图标',
                children: [
                    const SizedBox(height: 2),
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
                    ValueListenableBuilder<bool>(
                      valueListenable: scope.haptic,
                      builder: (context, hapticEnabled, _) => _SwitchCard(
                        title: '点击震动',
                        hint: '默认关闭；开启后仅提供轻微触感',
                        value: hapticEnabled,
                        onChanged: scope.setHaptic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('桌面图标',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                    ),
                    const SizedBox(height: 10),
                    _IconSection(),
                  ]),
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
                    Text('扫书新典 $_appVersionLabel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '离线扫书资料阅读器（Flutter 版）。数据与原生版共用同一'
                      '私有数据库；支持本地与 WebDAV 备份、贴吧网络浏览抓取、'
                      '应用内检查更新。',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 10),
                    Text('检查更新',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const SizedBox(height: 8),
                    _UpdateSection(),
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
                            fontSize: 11, color: scheme.onSurfaceVariant)),
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

/// 备份与恢复区块：本地备份 / WebDAV 备份与恢复。
class _BackupSection extends StatefulWidget {
  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _busy = false;
  String _status = '';

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 恢复备份后把 prefs 里的全局设置同步到内存状态（收藏、主题、震动）。
  void _syncAfterRestore(AppScope scope) {
    scope.favorites.reload();
    scope.setHaptic(scope.prefs.getBool('haptic_enabled') ?? false);
    scope.changeTheme(scope.prefs.getString('theme_id') ?? 'teal');
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) {
        setState(() {
          _busy = false;
          _status = message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('失败：$error');
      }
    }
  }

  Future<void> _localBackup() => _run(() async {
        final scope = AppScope.of(context);
        final db = await AppDatabase.instance.database;
        final (path, publicPath) =
            await BackupService.createLocalBackup(scope.prefs, db);
        return publicPath == null
            ? '已备份到 $path'
            : '已备份：$path\n公共目录：$publicPath';
      });

  Future<void> _localRestore() async {
    final scope = AppScope.of(context);
    final files = await BackupService.listLocalBackups();
    if (!mounted) return;
    if (files.isEmpty) {
      _toast('暂无本地备份文件');
      return;
    }
    final selected = await showModalBottomSheet<File>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('选择要恢复的备份',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final file in files)
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: Text(file.uri.pathSegments.last,
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(BackupService.summaryLabel(file),
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(sheetContext, file),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final db = await AppDatabase.instance.database;
    await _run(() async {
      final summary = await BackupService.restoreFromContent(
          await selected.readAsString(), scope.prefs, db);
      _syncAfterRestore(scope);
      return '恢复完成：收藏 ${summary['favorites']} 条，简记 ${summary['notesAdded']} 条，'
          '网络帖子 ${summary['postsAdded'] ?? 0} 条';
    });
  }

  /// WebDAV 流程：保存配置 → 执行备份（或列出云端备份选择恢复）。
  Future<void> _webdavFlow({required bool restore}) async {
    final scope = AppScope.of(context);
    final prefs = scope.prefs;
    final serverCtrl =
        TextEditingController(text: prefs.getString('webdav_server') ?? '');
    final userCtrl =
        TextEditingController(text: prefs.getString('webdav_user') ?? '');
    final passCtrl =
        TextEditingController(text: SecureStore.get('webdav_pass'));
    final dirCtrl =
        TextEditingController(text: prefs.getString('webdav_dir') ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(restore ? 'WebDAV 恢复' : 'WebDAV 备份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: serverCtrl,
                  keyboardType: TextInputType.url,
                  decoration:
                      const InputDecoration(hintText: '服务器地址 https://…')),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(hintText: '用户名')),
              TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '密码')),
              TextField(
                  controller: dirCtrl,
                  decoration:
                      const InputDecoration(hintText: '目录（可选，如 saoshu）')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(restore ? '列出云端备份' : '开始备份')),
        ],
      ),
    );
    final server = serverCtrl.text.trim();
    final user = userCtrl.text.trim();
    final pass = passCtrl.text;
    final dir = dirCtrl.text.trim().replaceAll(RegExp(r'^/|/$'), '');
    serverCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    dirCtrl.dispose();
    if (confirmed != true || !mounted) return;
    await prefs.setString('webdav_server', server);
    await prefs.setString('webdav_user', user);
    await SecureStore.set('webdav_pass', pass);
    await prefs.setString('webdav_dir', dir);
    if (server.isEmpty) {
      _toast('请填写服务器地址');
      return;
    }
    final client = WebDavClient(
        server: server, username: user, password: pass, directory: dir);
    if (restore) {
      await _run(() async {
        final entries = await client.listBackups();
        if (entries.isEmpty) return '云端没有备份文件';
        if (!mounted) return '已取消';
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                const Text('选择云端备份',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final entry in entries)
                  ListTile(
                    leading: const Icon(Icons.cloud_rounded),
                    title:
                        Text(entry.name, style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.pop(sheetContext, entry.name),
                  ),
              ],
            ),
          ),
        );
        if (picked == null) return '已取消';
        final db = await AppDatabase.instance.database;
        final content = await client.download(picked);
        final summary =
            await BackupService.restoreFromContent(content, scope.prefs, db);
        _syncAfterRestore(scope);
        return '恢复完成：收藏 ${summary['favorites']} 条，简记 ${summary['notesAdded']} 条，'
            '网络帖子 ${summary['postsAdded'] ?? 0} 条';
      });
    } else {
      await _run(() async {
        final db = await AppDatabase.instance.database;
        final snapshot = await BackupService.buildSnapshot(scope.prefs, db);
        final stamp = DateTime.now().toIso8601String().substring(0, 19);
        final name =
            'saoshu_backup_${stamp.replaceAll(RegExp(r'[:\-]'), '')}.json';
        await client.upload(name, jsonEncode(snapshot));
        return '已上传到 WebDAV：$name';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = AppScope.of(context).prefs;
    final hasWebDav = (prefs.getString('webdav_server') ?? '').isNotEmpty;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本地备份',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniAction(
                    icon: Icons.save_rounded,
                    label: '备份到本机',
                    onTap: _busy ? null : _localBackup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.restore_rounded,
                    label: '从本机恢复',
                    onTap: _busy ? null : _localRestore,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('WebDAV 云备份',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniAction(
                    icon: Icons.cloud_upload_rounded,
                    label: '上传备份',
                    onTap: _busy ? null : () => _webdavFlow(restore: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.cloud_download_rounded,
                    label: '恢复云端备份',
                    onTap: _busy ? null : () => _webdavFlow(restore: true),
                  ),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_status,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (_busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (!hasWebDav) ...[
              const SizedBox(height: 10),
              Text('提示：WebDAV 需要服务器地址、账号与密码；目录不存在会自动创建。',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 检查更新区块：版本对比 + 镜像源选择 + 跳转下载。
class _UpdateSection extends StatefulWidget {
  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  bool _checking = false;
  String _status = '';
  String _currentVersion = '';
  UpdateInfo? _latest;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await SystemBridge.appVersion();
    if (mounted) {
      setState(() => _currentVersion = info?['version'] as String? ?? '');
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = '';
      _latest = null;
    });
    try {
      final latest = await UpdateService.checkLatest();
      final current = _currentVersion;
      final isNewer = current.isEmpty
          ? false
          : UpdateService.compareVersions(latest.tag, current) > 0;
      if (mounted) {
        setState(() {
          _checking = false;
          _latest = latest;
          _status = isNewer ? '发现新版本 ${latest.tag}' : '已是最新版本（${latest.tag}）';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _checking = false;
          _status = '检查失败：$error';
        });
      }
    }
  }

  Future<void> _chooseMirror() async {
    final prefs = AppScope.of(context).prefs;
    final current = prefs.getString('download_mirror') ?? 'direct';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => RadioGroup<String>(
        groupValue: current,
        onChanged: (value) => Navigator.pop(dialogContext, value),
        child: SimpleDialog(
          title: const Text('下载镜像源'),
          children: [
            for (final mirror in downloadMirrors)
              RadioListTile<String>(
                value: mirror.id,
                title: Text(mirror.label),
                subtitle: mirror.prefix.isEmpty
                    ? null
                    : Text(mirror.prefix, style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      await prefs.setString('download_mirror', selected);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final mirror =
        mirrorById(scope.prefs.getString('download_mirror') ?? 'direct');
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '当前版本 ${_currentVersion.isEmpty ? '…' : _currentVersion}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      if (_status.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(_status,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_rounded, size: 18),
                  label: const Text('检查更新'),
                ),
              ],
            ),
            if (_latest != null && _status.startsWith('发现新版本')) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: _latest!.apkUrl.isEmpty
                    ? null
                    : () {
                        final url = UpdateService.applyMirror(
                            _latest!.apkUrl, mirror.prefix);
                        SystemBridge.openUrl(url);
                      },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('下载新版本 APK'),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text('下载镜像源',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: _chooseMirror,
                  icon: const Icon(Icons.dns_rounded, size: 16),
                  label: Text(mirror.label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 备份区块内的小按钮。
class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _MiniAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面图标选择区块：四款预置图标（activity-alias 切换）。
class _IconSection extends StatefulWidget {
  @override
  State<_IconSection> createState() => _IconSectionState();
}

class _IconChoice {
  final String id;
  final String alias;
  final String asset;
  final String label;
  const _IconChoice(this.id, this.alias, this.asset, this.label);
}

const _iconChoices = <_IconChoice>[
  _IconChoice(
      'default', 'LauncherDefault', 'assets/icons/preview_default.png', '经典'),
  _IconChoice('photo', 'LauncherPhoto', 'assets/icons/preview_photo.png', '绿书'),
  _IconChoice('book', 'LauncherBook', 'assets/icons/preview_book.png', '蓝脊'),
  _IconChoice(
      'reading', 'LauncherReading', 'assets/icons/preview_reading.png', '灰页'),
];

class _IconSectionState extends State<_IconSection> {
  String _selected = 'default';
  bool _applying = false;
  bool _busy = false;
  String _importStatus = '';

  /// 从本地选图：Android 无运行时替换应用图标的 API，采用官方近似——
  /// 选图后请求用户确认，把带自定义图标的快捷方式钉到桌面（与
  /// 应用图标并存，指向主页）。
  Future<void> _importFromLocal() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _importStatus = '';
    });
    final messenger = ScaffoldMessenger.of(context);
    final result = await SystemBridge.pinCustomShortcut();
    if (mounted) {
      setState(() {
        _busy = false;
        _importStatus = result == null
            ? '已取消'
            : result == 'pinned'
                ? '已创建桌面快捷方式（用所选图片作为图标）'
                : '导入失败：$result';
      });
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(result == null
              ? '已取消'
              : result == 'pinned'
                  ? '桌面快捷方式已创建'
                  : '导入失败：$result')));
  }

  @override
  void initState() {
    super.initState();
    _selected =
        AppScope.of(context).prefs.getString('launcher_icon') ?? 'default';
  }

  Future<void> _apply(_IconChoice choice) async {
    if (_applying || choice.id == _selected) return;
    setState(() {
      _applying = true;
      _selected = choice.id;
    });
    await AppScope.of(context).prefs.setString('launcher_icon', choice.id);
    await SystemBridge.setLauncherIcon(choice.alias);
    if (mounted) {
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('桌面图标已切换，启动器将在几秒内刷新'),
            duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < _iconChoices.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: _applying ? null : () => _apply(_iconChoices[i]),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      width: 2,
                                      color: _selected == _iconChoices[i].id
                                          ? scheme.primary
                                          : Colors.transparent),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.asset(_iconChoices[i].asset,
                                      width: 64, height: 64),
                                ),
                              ),
                              if (_selected == _iconChoices[i].id)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                        color: scheme.primary,
                                        shape: BoxShape.circle),
                                    child: Icon(Icons.check_rounded,
                                        size: 12, color: scheme.onPrimary),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_iconChoices[i].label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _selected == _iconChoices[i].id
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: _selected == _iconChoices[i].id
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniAction(
                    icon: Icons.add_photo_alternate_rounded,
                    label: '从本地导入',
                    onTap: _busy ? null : _importFromLocal,
                  ),
                ),
              ],
            ),
            if (_importStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_importStatus,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 10),
            Text(
                '切换后桌面图标会在几秒内刷新；部分启动器可能需要重新进入桌面。'
                '「从本地导入」会以所选图片创建桌面快捷方式（与原图标并存）。',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
