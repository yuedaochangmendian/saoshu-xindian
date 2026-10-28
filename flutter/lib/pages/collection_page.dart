import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../prefs.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../services/system_bridge.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';

/// 收藏与简记：收藏列表 + 简记列表（新建/编辑/删除）。
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _db = AppDatabase.instance;
  List<Document> _favorites = const [];
  List<Map<String, Object?>> _notes = const [];
  bool _loading = true;

  Favorites? _favoritesNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_favoritesNotifier == null) {
      _favoritesNotifier = AppScope.of(context).favorites;
      _favoritesNotifier!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _favoritesNotifier?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final ids = AppScope.of(context)
        .favorites
        .ids
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    final favorites = await _db.favoritesDocuments(ids);
    final db = await _db.database;
    final notes = await db.query('user_notes',
        where: 'deleted_at IS NULL',
        orderBy: 'pinned DESC, updated_at DESC',
        limit: 100);
    if (mounted) {
      setState(() {
        _favorites = favorites;
        _notes = notes;
        _loading = false;
      });
    }
  }

  Future<void> _editNote([Map<String, Object?>? note]) async {
    // 历史版本把空标题强存成「未命名」——编辑时还原为空字段，
    // 否则用户删掉保存又变回来（"标题删不掉"）。
    final rawTitle = note?['title'] as String? ?? '';
    final titleController =
        TextEditingController(text: rawTitle == '未命名' ? '' : rawTitle);
    final contentController =
        TextEditingController(text: note?['content'] as String? ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: titleController,
                decoration: InputDecoration(
                    hintText: '标题（可留空）',
                    hintStyle: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.55),
                        fontSize: 14))),
            const SizedBox(height: 10),
            TextField(
                controller: contentController,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '内容')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    if (note == null) {
      await db.insert('user_notes', {
        'title': titleController.text.trim(),
        'content': contentController.text,
        'created_at': now,
        'updated_at': now,
        'pinned': 0,
      });
    } else {
      await db.update(
          'user_notes',
          {
            'title': titleController.text,
            'content': contentController.text,
            'updated_at': now,
          },
          where: 'id=?',
          whereArgs: [note['id']]);
    }
    _reload();
  }

  /// 单篇简记的纯文本形式。
  String _noteText(Map<String, Object?> note) {
    final title =
        (note['title'] as String? ?? '').trim();
    final content = (note['content'] as String? ?? '').trim();
    final updated = (note['updated_at'] as String? ?? '');
    final buffer = StringBuffer();
    buffer.writeln(title.isEmpty ? '（未命名简记）' : title);
    buffer.writeln();
    buffer.writeln(content.isEmpty ? '（空内容）' : content);
    buffer.writeln();
    buffer.writeln('—— 扫书新典${updated.isEmpty ? '' : ' · ${updated.replaceAll('T', ' ').substring(0, 16)}'}');
    return buffer.toString();
  }

  String _safeFileName(String raw, {String fallback = '未命名简记'}) {
    var name = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) name = fallback;
    if (name.length > 40) name = name.substring(0, 40);
    return '简记-$name.txt';
  }

  Future<void> _exportNote(Map<String, Object?> note) async {
    final name =
        _safeFileName((note['title'] as String? ?? '').trim());
    final result = await SystemBridge.saveToDownloads(
        name, Uint8List.fromList(utf8.encode(_noteText(note))));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(result.startsWith('error:')
              ? '导出失败：$result'
              : '已导出：$result')));
  }

  Future<void> _exportAllNotes() async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = 0;
    String? lastError;
    for (final note in _notes) {
      final name =
          _safeFileName((note['title'] as String? ?? '').trim());
      final result = await SystemBridge.saveToDownloads(
          name, Uint8List.fromList(utf8.encode(_noteText(note))));
      if (result.startsWith('error:')) {
        lastError = result;
      } else {
        ok++;
      }
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(lastError == null
              ? '已导出 $ok 篇简记（每篇一个 txt，位于 下载/扫书新典/）'
              : '导出 $ok 篇，$lastError')));
  }

  /// 从 .txt 文件导入简记：文件名作标题，全文作内容。
  Future<void> _importNotesFromFile() async {
    final picked = await SystemBridge.pickTextFile();
    if (!mounted || picked == null) return;
    final rawName = (picked['name'] ?? '').trim();
    var title = rawName.replaceAll(RegExp(r'\.(txt|md|json)$', caseSensitive: false), '').trim();
    final content = picked['content'] ?? '';
    if (content.trim().isEmpty) {
      _toast('所选文件为空');
      return;
    }
    if (title.isEmpty) {
      title = content
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '')
          .replaceAll('#', '')
          .trim();
      if (title.length > 30) title = title.substring(0, 30);
    }
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('user_notes', {
      'title': title,
      'content': content,
      'created_at': now,
      'updated_at': now,
    });
    _toast('已导入：${title.isEmpty ? '未命名简记' : title}');
    _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 滑动删除的确认框：返回 true 才允许滑走并删除。
  Future<bool> _confirmDeleteNote(Map<String, Object?> note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除简记'),
        content: Text('确定删除「${note['title']}」的简记？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteNote(note);
      return true;
    }
    return false;
  }

  Future<void> _deleteNote(Map<String, Object?> note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除简记'),
        content: Text((note['title'] as String? ?? '').isEmpty
            ? '确定删除这条简记？'
            : '确定删除「${note['title']}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await _db.database;
    await db.update(
        'user_notes', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id=?', whereArgs: [note['id']]);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Text('收藏与简记',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Text('${_favorites.length} 条收藏 · ${_notes.length} 条简记',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('收藏',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      TextButton.icon(
                        onPressed: () => _editNote(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建简记'),
                      ),
                    ],
                  ),
                  if (_favorites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('收藏的扫书会出现在这里',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    ..._favorites.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DocumentCard(
                            document: d,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => ReaderPage(documentId: d.id)),
                            ),
                          ),
                        )),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('简记',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: _importNotesFromFile,
                            icon: const Icon(Icons.file_open_outlined,
                                size: 18),
                            label: const Text('导入'),
                          ),
                          TextButton.icon(
                            onPressed: _notes.isEmpty ? null : _exportAllNotes,
                            icon: const Icon(Icons.ios_share_rounded,
                                size: 18),
                            label: const Text('导出全部'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('还没有简记',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    ..._notes.map((note) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: ValueKey('note-${note['id']}'),
                            direction: DismissDirection.endToStart,
                            // 先确认再滑走：onDismissed 是动画完成后
                            // 才触发，在那里弹"确定删除？"会出现
                            // "取消了但条目已经消失"的错觉。
                            confirmDismiss: (_) => _confirmDeleteNote(note),
                            onDismissed: (_) {},
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: scheme.errorContainer,
                              child: Icon(Icons.delete_outline,
                                  color: scheme.onErrorContainer),
                            ),
                            child: Material(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: Text(
                                    (note['title'] as String? ?? '')
                                            .isEmpty
                                        ? '（未命名）'
                                        : note['title'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (note['title'] as String? ?? '')
                                            .isEmpty
                                        ? TextStyle(
                                            color: scheme.onSurfaceVariant)
                                        : null),
                                subtitle: Text(note['content'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () => _editNote(note),
                                trailing: PopupMenuButton<String>(
                                  tooltip: '更多',
                                  onSelected: (action) {
                                    if (action == 'export') {
                                      _exportNote(note);
                                    } else if (action == 'delete') {
                                      _confirmDeleteNote(note).then((ok) {
                                        if (ok) _reload();
                                      });
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'export',
                                        child: Text('导出为 txt 文件')),
                                    PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除简记')),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )),
                ],
              ),
      ),
    );
  }
}
