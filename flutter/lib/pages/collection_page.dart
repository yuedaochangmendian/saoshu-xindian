import 'package:flutter/material.dart';

import '../app.dart';
import '../data/database.dart';
import '../data/models.dart';
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

  @override
  void initState() {
    super.initState();
    AppScope.of(context).favorites.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AppScope.of(context).favorites.removeListener(_reload);
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
    final titleController =
        TextEditingController(text: note?['title'] as String? ?? '');
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
                decoration: const InputDecoration(hintText: '简记标题')),
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
        'title': titleController.text.isEmpty ? '未命名' : titleController.text,
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

  Future<void> _deleteNote(Map<String, Object?> note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除简记'),
        content: Text('确定删除「${note['title']}」？'),
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
    await db.update('user_notes', {'deleted_at': DateTime.now().toIso8601String()},
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                          style:
                              TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    ..._favorites.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DocumentCard(
                            document: d,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ReaderPage(documentId: d.id)),
                            ),
                          ),
                        )),
                  const SizedBox(height: 8),
                  Text('简记',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                  if (_notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('还没有简记',
                          style:
                              TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    ..._notes.map((note) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: ValueKey('note-${note['id']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _deleteNote(note),
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
                                    borderRadius:
                                        BorderRadius.circular(20)),
                                title: Text(note['title'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    note['content'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () => _editNote(note),
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
