import 'package:flutter/material.dart';

import '../app.dart';
import 'dart:convert';
import 'dart:io';
import '../services/backup_service.dart';
import '../services/system_bridge.dart';
import '../services/update_service.dart';
import '../services/webdav_client.dart';
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
    final haptic = scope.prefs.getBool('haptic_enabled') ?? false;
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
            Text('备份与恢复',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 10),
            _BackupSection(),
            const SizedBox(height: 20),
            Text('检查更新',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 10),
            _UpdateSection(),
            const SizedBox(height: 20),
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
        final path = await BackupService.createLocalBackup(scope.prefs, db);
        return '已备份到 $path';
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
          selected.readAsStringSync(), scope.prefs, db);
      return '恢复完成：收藏 ${summary['favorites']} 条，简记 ${summary['notesAdded']} 条';
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
        TextEditingController(text: prefs.getString('webdav_pass') ?? '');
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
    await prefs.setString('webdav_pass', pass);
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
        return '恢复完成：收藏 ${summary['favorites']} 条，简记 ${summary['notesAdded']} 条';
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
