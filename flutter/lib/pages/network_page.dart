import 'package:flutter/material.dart';

import '../app.dart';
import '../data/database.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';
import 'reader_page.dart';
import 'thread_preview_page.dart';

/// 网络浏览：贴吧主题列表（下拉刷新、分页）+ 勾选抓取导入 + 登录 + 导入历史。
class NetworkSection extends StatefulWidget {
  const NetworkSection({super.key});

  @override
  State<NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<NetworkSection> {
  static const _forums = ['yy小说吧', '哀伤雪刃'];

  TiebaClient? _client;
  String _forum = _forums.first;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  final List<ThreadSummary> _threads = [];
  final Set<int> _selected = {};
  final Set<int> _imported = <int>{};
  bool _fetching = false;
  String _fetchStatus = '';

  /// 每个吧的已加载列表缓存：切回已浏览的吧即时显示，后台再刷新。
  final Map<String, List<ThreadSummary>> _cache = {};
  final Map<String, int> _pageByForum = {};
  final Map<String, bool> _hasMoreByForum = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_client == null) {
      _client = TiebaClient(
          bduss: AppScope.of(context).prefs.getString('tieba_bduss') ?? '');
      _restoreFromCacheOrReload();
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  TiebaClient get client => _client!;

  void _restoreFromCacheOrReload() {
    final cached = _cache[_forum];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _threads
          ..clear()
          ..addAll(cached);
        _page = _pageByForum[_forum] ?? 1;
        _hasMore = _hasMoreByForum[_forum] ?? true;
      });
      _refreshImported();
      return;
    }
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _page = 0;
      _hasMore = true;
      // 保留旧列表占位，加载完成后整体替换（stale-while-revalidate）。
    });
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await client.requestThreads(_forum, _page + 1);
      if (mounted) {
        setState(() {
          _page++;
          if (force) _threads.clear();
          _threads.addAll(page.threads.where((t) => !t.deleted && !t.masked));
          _hasMore = page.hasMore;
          _loading = false;
          _cache[_forum] = List.of(_threads);
          _pageByForum[_forum] = _page;
          _hasMoreByForum[_forum] = _hasMore;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
    await _refreshImported();
  }

  Future<void> _refreshImported() async {
    if (_threads.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final tids = _threads.map((t) => t.tid).toList();
    final placeholders = List.filled(tids.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT tid FROM network_threads WHERE tid IN ($placeholders)', tids);
    if (mounted) {
      setState(() {
        _imported
          ..clear()
          ..addAll(rows.map((r) => r['tid'] as int));
      });
    }
  }

  Future<void> _fetchSelected() async {
    if (_selected.isEmpty || _fetching) return;
    final targets = _threads.where((t) => _selected.contains(t.tid)).toList();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _fetching = true;
      _fetchStatus = '开始抓取 ${targets.length} 个主题…';
    });
    final importer = TiebaImporter(AppDatabase.instance);
    final collected = <CollectedThread>[];
    try {
      for (var i = 0; i < targets.length; i++) {
        final thread = await client.fetchThread(_forum, targets[i].tid,
            onStatus: (status) {
          if (mounted) {
            setState(
                () => _fetchStatus = '(${i + 1}/${targets.length}) $status');
          }
        });
        collected.add(thread);
      }
      final result = await importer.importThreads(collected);
      if (mounted) {
        setState(() {
          _fetching = false;
          _fetchStatus = '';
          _selected.clear();
        });
        await _refreshImported();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(
                  '抓取完成：新增 ${result.added} 条，跳过 ${result.skipped} 条（已存在或内容过短）')));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _fetching = false;
          _fetchStatus = '';
        });
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('抓取失败：$error')));
      }
    }
  }

  Future<void> _showLoginDialog() async {
    final prefs = AppScope.of(context).prefs;
    final controller =
        TextEditingController(text: prefs.getString('tieba_bduss') ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('贴吧登录（BDUSS）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration:
                  const InputDecoration(hintText: '粘贴 BDUSS Cookie，留空即退出登录'),
            ),
            const SizedBox(height: 8),
            Text('登录后请求配额更宽松，BDUSS 只保存在本机。',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved == true) {
      final bduss = controller.text.trim();
      await prefs.setString('tieba_bduss', bduss);
      controller.dispose();
      if (mounted) {
        _client?.close();
        setState(() => _client = TiebaClient(bduss: bduss));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
              SnackBar(content: Text(bduss.isEmpty ? '已退出登录' : '已登录')));
      }
      return;
    }
    controller.dispose();
  }

  Future<void> _showHistory() async {
    final db = await AppDatabase.instance.database;
    final rows = await db
        .rawQuery('SELECT n.tid, n.reply_count, n.view_count, n.collected_at, '
            'd.id doc_id, d.title FROM network_threads n '
            'JOIN documents d ON d.id=n.document_id '
            'ORDER BY n.collected_at DESC LIMIT 100');
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final outerContext = context;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('导入历史（${rows.length} 条）',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text('还没有导入过任何主题', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            ...rows.map((row) {
              final collected = row['collected_at'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: Text(row['title'] as String? ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '回复 ${row['reply_count']} · 浏览 ${row['view_count']}'
                        '${collected.isEmpty ? '' : ' · ${collected.substring(0, collected.length.clamp(0, 10))}'}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: scheme.onSurfaceVariant),
                      tooltip: '删除导入',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('删除导入'),
                            content: Text('将从本地库删除「${row['title']}」及其书目计数，确定？'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('取消')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('删除')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await deleteImportedThread(db, row['doc_id'] as int);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                          if (outerContext.mounted) {
                            _showHistory();
                            ScaffoldMessenger.of(outerContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                  const SnackBar(content: Text('导入已删除')));
                          }
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(outerContext).push(MaterialPageRoute(
                        builder: (_) =>
                            ReaderPage(documentId: row['doc_id'] as int),
                      ));
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = (scope.prefs.getString('tieba_bduss') ?? '').isNotEmpty;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final forum in _forums)
                        ChoiceChip(
                          label: Text(forum),
                          selected: _forum == forum,
                          onSelected: _fetching
                              ? null
                              : (_) {
                                  setState(() => _forum = forum);
                                  _restoreFromCacheOrReload();
                                },
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showLoginDialog,
                  icon: Icon(loggedIn ? Icons.logout : Icons.login,
                      size: 20, color: scheme.onSurfaceVariant),
                  tooltip: loggedIn ? '退出登录' : '贴吧登录',
                ),
                IconButton(
                  onPressed: _showHistory,
                  icon: Icon(Icons.history,
                      size: 20, color: scheme.onSurfaceVariant),
                  tooltip: '导入历史',
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: _selected.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: SizedBox(
                        height: 38,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: _fetchSelected,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text('抓取选中 (${_selected.length})'),
                        ),
                      ),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 140),
                  itemCount: _threads.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _threads.length) {
                      if (!_hasMore && _threads.isNotEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : _threads.isEmpty
                                  ? Text(_error == null ? '下拉即可刷新' : '',
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant))
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      child: const Text('加载更多')),
                        ),
                      );
                    }
                    final thread = _threads[index];
                    final done = _imported.contains(thread.tid);
                    final checked = _selected.contains(thread.tid);
                    final date = TiebaImporter.networkDate(thread.createTime);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: done
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ThreadPreviewPage(
                                        forum: _forum,
                                        thread: thread,
                                      ),
                                    ),
                                  );
                                  _refreshImported();
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: done ? true : checked,
                                  tristate: true,
                                  fillColor: WidgetStateProperty.resolveWith(
                                      (states) => done ? scheme.primary : null),
                                  onChanged: done
                                      ? null
                                      : (value) => setState(() {
                                            value == true
                                                ? _selected.add(thread.tid)
                                                : _selected.remove(thread.tid);
                                          }),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        thread.title.isEmpty
                                            ? '（无标题）'
                                            : thread.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: done
                                                ? scheme.onSurfaceVariant
                                                : scheme.onSurface),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${thread.author} · 回复 ${thread.replyCount} · 浏览 ${thread.viewCount}'
                                        '${date.isEmpty ? '' : ' · $date'}'
                                        '${thread.top ? ' · 置顶' : ''}'
                                        '${done ? ' · 已导入' : ''}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        if (_fetching)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_fetchStatus,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
