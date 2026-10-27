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

  /// 导入本地库：弹层勾选楼层后，按所选楼层构建 CollectedThread 入库
  /// （导入语义 = 主楼楼层串，楼中楼不入库）。
  Future<void> _showFloorPicker() async {
    if (_importing || _imported) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_floors.isEmpty || _meta == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('楼层还在加载，请稍后再试')));
      return;
    }
    final meta = _meta!;
    final snapshot = List<Floor>.of(_floors);
    final snapshotHasMore = _hasMore;
    final picked = await showModalBottomSheet<List<Floor>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _FloorPickerSheet(floors: snapshot, hasMore: snapshotHasMore),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    final isFullPick = picked.length == snapshot.length;
    if (isFullPick && snapshotHasMore) {
      // 全选且帖子未加载完：自动整帖抓取入库，保证内容完整
      // （导入去重按 tid——入库一次后无法再补，宁可多抓几页）。
      await _importWholeThread();
      return;
    }
    if (!isFullPick) {
      // 部分楼层：tid 级去重使该帖一次性买断，必须明示不可追加。
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('仅导入选中楼层'),
          content: Text('将只导入选中的 ${picked.length} 层。贴吧帖子按主题'
              '一次性入库：导入后无法再追加其余楼层（如需重来，先在'
              '「导入历史」中删除该帖）。确定继续？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('仍要导入')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _importFloors(picked, meta);
  }

  /// 整帖抓取导入（fetchThread 自动翻页，含未加载楼层）。
  Future<void> _importWholeThread() async {
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
                  ? '已整帖导入本地库（${collected.floors.length} 层）'
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

  Future<void> _importFloors(List<Floor> floors, PostsPage meta) async {
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final collected = CollectedThread(
          widget.fname,
          widget.tid,
          meta.title,
          meta.author,
          meta.createTime,
          meta.replyNum,
          meta.viewNum,
          floors);
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
            tooltip: _imported
                ? '已导入本地库'
                : _importing
                    ? '导入中…'
                    : '导入本地库（选择楼层）',
            onPressed: _importing || _imported ? null : _showFloorPicker,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _imported
                        ? Icons.check_circle_rounded
                        : Icons.download_rounded,
                    size: 20,
                    color: _imported
                        ? Theme.of(context).colorScheme.primary
                        : null),
          ),
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
        ],
      ),
    );
  }
}


/// 导入楼层选择弹层：默认全选已加载楼层，可逐层勾选；
/// 帖子未加载完时给出提示（先滚动加载再选）。
class _FloorPickerSheet extends StatefulWidget {
  final List<Floor> floors;
  final bool hasMore;
  const _FloorPickerSheet({required this.floors, required this.hasMore});

  @override
  State<_FloorPickerSheet> createState() => _FloorPickerSheetState();
}

class _FloorPickerSheetState extends State<_FloorPickerSheet> {
  late final Set<int> _picked =
      widget.floors.map((f) => f.pid).toSet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('选择导入楼层（已加载 ${widget.floors.length} 层）',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    if (_picked.length == widget.floors.length) {
                      _picked.clear();
                    } else {
                      _picked
                        ..clear()
                        ..addAll(widget.floors.map((f) => f.pid));
                    }
                  }),
                  child: Text(
                      _picked.length == widget.floors.length
                          ? '全不选'
                          : '全选',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          if (widget.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('帖子还有未加载楼层：保持全选导入将自动抓取全部楼层',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.floors.length,
              itemBuilder: (context, i) {
                final floor = widget.floors[i];
                final summary = floor.text
                    .replaceAll('\n', ' ')
                    .replaceAll('#(', '[')
                    .trim();
                return CheckboxListTile(
                  dense: true,
                  value: _picked.contains(floor.pid),
                  onChanged: (v) => setState(() {
                    v == true
                        ? _picked.add(floor.pid)
                        : _picked.remove(floor.pid);
                  }),
                  title: Text(
                      floor.seq == 1
                          ? '楼主 · ${floor.author}'
                          : '${floor.seq}楼 · ${floor.author}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      summary.length > 42
                          ? '${summary.substring(0, 42)}…'
                          : (summary.isEmpty ? '（图片/表情楼层）' : summary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(widget.floors
                          .where((f) => _picked.contains(f.pid))
                          .toList()),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('导入选中 ${_picked.length} 层'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
