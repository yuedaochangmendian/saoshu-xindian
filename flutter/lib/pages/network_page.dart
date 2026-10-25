import 'package:flutter/material.dart';

import '../data/database.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';

/// 网络浏览：贴吧主题列表 + 勾选抓取导入（参考 aiotieba / 原生采集器协议）。
class NetworkSection extends StatefulWidget {
  const NetworkSection({super.key});

  @override
  State<NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<NetworkSection> {
  static const _forums = ['yy小说吧', '哀伤雪刃'];

  final _client = TiebaClient();
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _threads.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadMore();
    await _refreshImported();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _client.requestThreads(_forum, _page + 1);
      if (mounted) {
        setState(() {
          _page++;
          _threads.addAll(page.threads.where((t) => !t.deleted && !t.masked));
          _hasMore = page.hasMore;
          _loading = false;
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
        final thread = await _client.fetchThread(_forum, targets[i].tid,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final forum in _forums)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(forum),
                      selected: _forum == forum,
                      onSelected: _fetching
                          ? null
                          : (_) {
                              setState(() => _forum = forum);
                              _reload();
                            },
                    ),
                  ),
                const Spacer(),
                if (_selected.isNotEmpty)
                  FilledButton(
                    onPressed: _fetchSelected,
                    child: Text('抓取选中 (${_selected.length})'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: _threads.length + 1,
                itemBuilder: (context, index) {
                  if (index == _threads.length) {
                    if (!_hasMore) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : OutlinedButton(
                                onPressed: _loadMore,
                                child: const Text('加载更多')),
                      ),
                    );
                  }
                  final thread = _threads[index];
                  final done = _imported.contains(thread.tid);
                  final checked = _selected.contains(thread.tid);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() {
                          if (!done) {
                            checked
                                ? _selected.remove(thread.tid)
                                : _selected.add(thread.tid);
                          }
                        }),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      '${thread.author} · 回复 ${thread.replyCount}'
                                      '${TiebaImporter.networkDate(thread.createTime).isEmpty ? '' : ' · ${TiebaImporter.networkDate(thread.createTime)}'}'
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
