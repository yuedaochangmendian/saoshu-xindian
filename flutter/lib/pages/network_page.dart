import 'package:flutter/material.dart';

import '../data/database.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';
import '../services/secure_store.dart';
import '../app.dart';
import 'reader_page.dart';
import 'thread_preview_page.dart';
import 'tieba_login_page.dart';
import '../services/system_bridge.dart';
import '../widgets/tieba_rich_text.dart';

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

  /// 每个吧的已加载列表缓存：切回已浏览的吧即时显示（静态持有，
  /// 页面被 AnimatedSwitcher 重建时缓存不丢，避免自动重载）。
  static final Map<String, List<ThreadSummary>> _cache = {};
  static final Map<String, int> _pageByForum = {};
  static final Map<String, bool> _hasMoreByForum = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_client == null) {
      _client = TiebaClient(
          bduss: SecureStore.get('tieba_bduss'),
          stoken: SecureStore.get('tieba_stoken'));
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
          // tid 去重：刷新失败重试 / 翻页回退时防止重复条目。
          final seen = _threads.map((t) => t.tid).toSet();
          for (final thread in page.threads) {
            if (!thread.deleted && !thread.masked && seen.add(thread.tid)) {
              _threads.add(thread);
            }
          }
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
    final imported = <int>{};
    // SQLite 单语句默认最多 999 个绑定参数，分批查询。
    const chunkSize = 500;
    for (var start = 0; start < tids.length; start += chunkSize) {
      final chunk =
          tids.sublist(start, (start + chunkSize).clamp(0, tids.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
          'SELECT tid FROM network_threads WHERE tid IN ($placeholders)',
          chunk);
      imported.addAll(rows.map((r) => r['tid'] as int));
    }
    if (mounted) {
      setState(() {
        _imported
          ..clear()
          ..addAll(imported);
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

  /// 打开 WebView 网页登录页（验证码/扫码/账密均可），拿到 BDUSS 后验证。
  Future<void> _showLoginDialog() async {
    final prefs = AppScope.of(context).prefs;
    final messenger = ScaffoldMessenger.of(context);
    final credentials = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TiebaLoginPage()),
    );
    if (credentials == null || !mounted) return;
    final (bduss, stoken, uid, cookieName) = credentials;
    setState(() => _loading = true);
    await SecureStore.set('tieba_bduss', bduss);
    await SecureStore.set('tieba_stoken', stoken);
    await prefs.setString('tieba_uid', uid);
    _client?.close();
    _client = TiebaClient(bduss: bduss, stoken: stoken);
    String message;
    try {
      final profile = await client.fetchProfile(selfUid: uid);
      if (profile != null) {
        await prefs.setString('tieba_username', profile.name);
        message = '已登录：${profile.name}';
      } else if (cookieName.isNotEmpty) {
        // 服务端资料接口没返回，但 BDUSS 已到手 + web 侧 NAME cookie
        // 能解析出账号名——按登录成功处理，不让验证失败误伤登录。
        await prefs.setString('tieba_username', cookieName);
        message = '已登录：$cookieName';
      } else {
        message = '登录失败：未能获取到有效账号信息';
        await prefs.setString('tieba_username', '');
      }
    } catch (error) {
      // 凭据已写入（CookieManager 也确认拿到 BDUSS）：网络原因验证
      // 失败不代表登录失败，用 web 侧账号名兜底。
      if (cookieName.isNotEmpty) {
        await prefs.setString('tieba_username', cookieName);
        message = '已登录：$cookieName（资料验证暂不可用）';
      } else {
        message = '登录验证失败（凭据已保存）：$error';
      }
    }
    if (mounted) {
      setState(() => _loading = false);
      await _reload();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _logout() async {
    final prefs = AppScope.of(context).prefs;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出贴吧登录'),
        content: const Text('将清除本机保存的 BDUSS / STOKEN 凭据，'
            '退出后网络浏览以游客身份访问。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出登录')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SecureStore.set('tieba_bduss', '');
    await SecureStore.set('tieba_stoken', '');
    await prefs.setString('tieba_username', '');
    await prefs.setString('tieba_uid', '');
    // 关键：同时清 WebView CookieManager——否则重进登录页会被
    // 残留的 BDUSS cookie 立刻自动"登录回来"（表现为退出失败）。
    await SystemBridge.clearTiebaCookies();
    setState(() {
      _client?.close();
      _client = TiebaClient();
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已退出贴吧登录')));
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
    final scheme = Theme.of(context).colorScheme;
    final prefs = AppScope.of(context).prefs;
    final account = prefs.getString('tieba_username') ?? '';
    final loggedIn = SecureStore.get('tieba_bduss').isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            // 与其他 dock 页一致：纵向滑动隐藏 dock，横滑（贴吧选择）不触发。
            if (notification.metrics.axis != Axis.vertical) return false;
            if (notification.scrollDelta == null) return false;
            final hidden = AppScope.of(context).dockHidden;
            final delta = notification.scrollDelta!;
            if (delta > 6 &&
                notification.metrics.pixels > 60 &&
                !hidden.value) {
              hidden.value = true;
            } else if (delta < -6 && hidden.value) {
              hidden.value = false;
            }
            return false;
          },
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('网络浏览',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
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
                                              _restoreFromCacheOrReload();
                                            },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: loggedIn ? _logout : _showLoginDialog,
                          icon: Icon(loggedIn ? Icons.logout : Icons.login,
                              size: 20, color: scheme.onSurfaceVariant),
                          tooltip: loggedIn
                              ? (account.isEmpty
                                  ? '退出登录'
                                  : '已登录：$account（点击退出）')
                              : '贴吧登录',
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                  ),
                                  onPressed: _fetchSelected,
                                  icon: const Icon(Icons.download_rounded,
                                      size: 18),
                                  label: Text('抓取选中 (${_selected.length})'),
                                ),
                              ),
                            ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!,
                            style:
                                TextStyle(color: scheme.error, fontSize: 12)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: _loading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : _threads.isEmpty
                                          ? Text(_error == null ? '下拉即可刷新' : '',
                                              style: TextStyle(
                                                  color:
                                                      scheme.onSurfaceVariant))
                                          : OutlinedButton(
                                              onPressed: _loadMore,
                                              child: const Text('加载更多')),
                                ),
                              );
                            }
                            final thread = _threads[index];
                            final done = _imported.contains(thread.tid);
                            final checked = _selected.contains(thread.tid);
                            final date =
                                TiebaImporter.networkDate(thread.createTime);
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
                                          fillColor:
                                              WidgetStateProperty.resolveWith(
                                                  (states) => done
                                                      ? scheme.primary
                                                      : null),
                                          onChanged: done
                                              ? null
                                              : (value) => setState(() {
                                                    value == true
                                                        ? _selected
                                                            .add(thread.tid)
                                                        : _selected
                                                            .remove(thread.tid);
                                                  }),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  if (thread.authorPortrait
                                                      .isNotEmpty) ...[
                                                    TiebaAvatar(
                                                      radius: 10,
                                                      portrait:
                                                          thread.authorPortrait,
                                                      name: thread.author,
                                                    ),
                                                    const SizedBox(width: 6),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      thread.title.isEmpty
                                                          ? '（无标题）'
                                                          : thread.title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: done
                                                              ? scheme
                                                                  .onSurfaceVariant
                                                              : scheme
                                                                  .onSurface),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${thread.author} · 回复 ${thread.replyCount} · 浏览 ${thread.viewCount}'
                                                '${date.isEmpty ? '' : ' · $date'}'
                                                '${thread.top ? ' · 置顶' : ''}'
                                                '${done ? ' · 已导入' : ''}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: scheme
                                                        .onSurfaceVariant),
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
              ),
              if (_fetching)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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
                                  fontSize: 12,
                                  color: scheme.onPrimaryContainer)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
