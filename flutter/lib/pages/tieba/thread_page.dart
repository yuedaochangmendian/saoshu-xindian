import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../network/tieba_client.dart';
import '../../network/tieba_import.dart';
import '../../services/secure_store.dart';
import '../../services/system_bridge.dart';
import '../../widgets/tieba_rich_text.dart';
import 'photo_viewer.dart';
import 'user_page.dart';

/// 贴吧帖子页：TiebaLite 式楼层流——按页拉取（302001 分页）、楼中楼
/// 展开分页（302002）、图片大图、点击头像/作者查资料，并可一键导入
/// 本地库 / 跳转原帖。
class TiebaThreadPage extends StatefulWidget {
  final String fname;
  final int tid;
  final int fid;

  const TiebaThreadPage(
      {super.key, required this.fname, required this.tid, this.fid = 0});

  @override
  State<TiebaThreadPage> createState() => _TiebaThreadPageState();
}

/// 单个楼层的楼中楼展开状态。
class _SubState {
  List<SubPost> posts = [];
  int pn = 0;
  bool hasMore = false;
  bool loading = false;
  String? error;
}

class _TiebaThreadPageState extends State<TiebaThreadPage> {
  late final TiebaClient _client;

  PostsPage? _meta;
  final List<Floor> _floors = [];
  final Set<int> _seenPids = {};
  int _page = 0;
  bool _hasMore = true;
  bool _loadingPage = false;
  String? _error;

  final Map<int, _SubState> _subs = {};
  int _fid = 0;
  final _scrollController = ScrollController();

  bool _importing = false;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    _client = TiebaClient(
        bduss: SecureStore.get('tieba_bduss'),
        stoken: SecureStore.get('tieba_stoken'));
    _fid = widget.fid;
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _client.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 480) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingPage || !_hasMore) return;
    setState(() => _loadingPage = true);
    try {
      // fid 未知时先向列表接口解析一次（302002 楼中楼请求需要）。
      if (_fid == 0) {
        try {
          final page = await _client.requestThreads(widget.fname, 1);
          _fid = page.fid;
        } catch (_) {}
      }
      final result = await _client.requestPosts(widget.tid, _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        _meta ??= result;
        for (final floor in result.floors) {
          if (floor.pid != 0 && _seenPids.add(floor.pid)) {
            _floors.add(floor);
          }
        }
        _hasMore = result.hasMore;
        _loadingPage = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingPage = false;
          _error = error.toString();
        });
      }
    }
  }

  /// 展开/加载更多楼中楼（302002）。
  Future<void> _expandSubs(Floor floor) async {
    final state = _subs.putIfAbsent(floor.pid, () => _SubState());
    if (state.loading) return;
    setState(() => state.loading = true);
    try {
      final result = await _client.fetchSubPosts(
          widget.tid, floor.pid, state.pn + 1,
          fid: _fid);
      if (!mounted) return;
      final byPid = <int, SubPost>{
        for (final p in state.posts) p.pid: p,
        for (final p in result.posts) p.pid: p,
      };
      state.posts =
          byPid.values.toList()..sort((a, b) => a.pid.compareTo(b.pid));
      state.pn += 1;
      state.hasMore = result.hasMore;
      state.error = null;
      setState(() => state.loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          state.loading = false;
          state.error = error.toString();
        });
      }
    }
  }

  /// 导入本地库：整帖抓取（主楼楼层串）后走既有入库流程。
  Future<void> _import() async {
    if (_importing || _imported) return;
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final collected = await _client.fetchThread(widget.fname, widget.tid);
      final result =
          await TiebaImporter(AppDatabase.instance).importThreads([collected]);
      if (mounted) {
        setState(() {
          _importing = false;
          _imported = result.added > 0;
        });
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(result.added > 0
                  ? '已导入本地库'
                  : '未导入（内容过短或已存在）')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _importing = false);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    }
  }

  void _openUser(int uid, String portrait, String name) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          TiebaUserPage(uid: uid, portrait: portrait, name: name),
    ));
  }

  Widget _buildSubPosts(Floor floor) {
    final scheme = Theme.of(context).colorScheme;
    final state = _subs[floor.pid];
    final shown = state != null && state.posts.isNotEmpty
        ? state.posts
        : floor.subPosts;
    final loadedCount = state?.posts.length ?? floor.subPosts.length;
    final canExpand = floor.subNumber > shown.length;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sub in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TiebaAvatar(
                      radius: 8, portrait: sub.portrait, name: sub.author),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sub.author}'
                          '${sub.time > 0 ? ' · ${TiebaImporter.networkDate(sub.time)}' : ''}'
                          '${sub.agree > 0 ? ' · ${sub.agree}赞' : ''}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                        SelectableTiebaText(
                          content: sub.text,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: scheme.onSurface),
                        ),
                        for (final url in sub.images) ...[
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    fullscreenDialog: true,
                                    builder: (_) => PhotoViewerPage(
                                        urls: sub.images,
                                        initialIndex:
                                            sub.images.indexOf(url))),
                              ),
                              child: Image.network(url,
                                  cacheWidth: 360,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox.shrink()),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (state?.error != null)
            Text('楼中楼加载失败：${state!.error}',
                style: TextStyle(fontSize: 11, color: scheme.error)),
          if (state != null && state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (canExpand || (state?.hasMore ?? false))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _expandSubs(floor),
                child: Text(
                    state == null
                        ? '查看全部 ${floor.subNumber} 条楼中楼'
                        : '加载更多楼中楼（已载 $loadedCount/${floor.subNumber}）',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloor(Floor floor) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openUser(floor.authorId, floor.portrait,
                        floor.author),
                    child: TiebaAvatar(
                        radius: 11,
                        portrait: floor.portrait,
                        name: floor.author),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: floor.authorId > 0
                          ? () => _openUser(floor.authorId, floor.portrait,
                              floor.author)
                          : null,
                      child: Text(
                          floor.seq == 1
                              ? floor.author
                              : '${floor.seq}楼 · ${floor.author}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ),
                  if (floor.agree > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thumb_up_alt_rounded,
                            size: 13, color: scheme.primary),
                        const SizedBox(width: 3),
                        Text('${floor.agree}',
                            style: TextStyle(
                                fontSize: 11, color: scheme.primary)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableTiebaText(
                content: floor.text,
                style: TextStyle(
                    fontSize: 14, height: 1.55, color: scheme.onSurface),
              ),
              for (var i = 0; i < floor.images.length; i++) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => PhotoViewerPage(
                              urls: floor.images, initialIndex: i)),
                    ),
                    child: Image.network(floor.images[i],
                        fit: BoxFit.cover,
                        cacheWidth: 540,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 160,
                            color: scheme.surfaceContainerHigh,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2),
                          );
                        },
                        errorBuilder: (context, error, stack) =>
                            Container(
                                height: 60,
                                color: scheme.surfaceContainerHigh,
                                alignment: Alignment.center,
                                child: Text('图片加载失败',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant)))),
                  ),
                ),
              ],
              if (floor.subNumber > 0) _buildSubPosts(floor),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _meta;
    final date = meta == null || meta.createTime == 0
        ? ''
        : TiebaImporter.networkDate(meta.createTime);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.fname, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '打开原帖',
            onPressed: () => SystemBridge.openUrl(
                'https://tieba.baidu.com/p/${widget.tid}'),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _floors.isEmpty && _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _loadNextPage, child: const Text('重试')),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                    itemCount: _floors.length + (_hasMore ? 2 : 1),
                    itemBuilder: (context, index) {
                      // 首项是楼主信息卡（拿到第一页才有内容可填）。
                      if (index == 0) {
                        if (meta == null) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _openUser(
                                  0, meta.authorPortrait, meta.author),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        meta.title.isEmpty
                                            ? '（无标题）'
                                            : meta.title,
                                        style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                            color: scheme.onSurface)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        TiebaAvatar(
                                            radius: 11,
                                            portrait: meta.authorPortrait,
                                            name: meta.author),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${meta.author} · 回复 ${meta.replyNum}'
                                            ' · 浏览 ${meta.viewNum}'
                                            '${date.isEmpty ? '' : ' · $date'}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (index > _floors.length) {
                        // 尾部加载行：触底自动翻页；翻页出错给手动重试。
                        if (_error != null) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: OutlinedButton(
                                  onPressed: _loadNextPage,
                                  child: const Text('加载失败，点击重试')),
                            ),
                          );
                        }
                        if (!_loadingPage) {
                          // build 期间不能直接 setState：下一帧再翻页。
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _loadNextPage());
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        );
                      }
                      return _buildFloor(_floors[index - 1]);
                    },
                  ),
          ),
          if (meta != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _imported
                        ? scheme.surfaceContainerHigh
                        : scheme.primary,
                    foregroundColor: _imported
                        ? scheme.onSurfaceVariant
                        : scheme.onPrimary,
                  ),
                  onPressed: _importing || _imported ? null : _import,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_imported
                          ? Icons.check_circle_rounded
                          : Icons.download_rounded),
                  label: Text(_importing
                      ? '导入中…'
                      : _imported
                          ? '已导入本地库'
                          : '导入本地库'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
