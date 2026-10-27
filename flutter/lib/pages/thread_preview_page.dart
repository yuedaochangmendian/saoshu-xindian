import 'package:flutter/material.dart';

import '../data/database.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';
import '../services/secure_store.dart';
import '../widgets/category_style.dart';
import '../widgets/tieba_rich_text.dart';

/// 帖子预览：楼层流式浏览（对齐 TiebaLite ThreadPage 的核心体验）——
/// 楼层头像、楼中楼（内嵌预览 + 302002 分页展开）、图片大图浏览、
/// 登录态复用（凭据走 SecureStore，登录用户的预览也过带 BDUSS 通道），
/// 并可一键导入本地库。
class ThreadPreviewPage extends StatefulWidget {
  final String forum;

  /// 吧 fid；跨吧搜索入口可缺省（预览页自行向列表接口解析一次）。
  final int fid;
  final ThreadSummary thread;
  final VoidCallback? onImported;

  const ThreadPreviewPage(
      {super.key,
      required this.forum,
      this.fid = 0,
      required this.thread,
      this.onImported});

  @override
  State<ThreadPreviewPage> createState() => _ThreadPreviewPageState();
}

/// 单个楼层的楼中楼展开状态。
class _SubState {
  List<SubPost> posts = [];
  int pn = 0;
  bool hasMore = false;
  bool loading = false;
  String? error;
}

class _ThreadPreviewPageState extends State<ThreadPreviewPage> {
  late final TiebaClient _client;

  CollectedThread? _collected;
  String? _error;
  bool _importing = false;
  bool _imported = false;
  int _fid = 0;

  /// pid → 楼中楼展开状态（仅展开过的楼层持有）。
  final Map<int, _SubState> _subs = {};

  @override
  void initState() {
    super.initState();
    _client = TiebaClient(
        bduss: SecureStore.get('tieba_bduss'),
        stoken: SecureStore.get('tieba_stoken'));
    _fid = widget.fid;
    _fetch();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      // fid 未知（跨吧搜索入口）：先向列表接口要一次。
      if (_fid == 0) {
        try {
          final page = await _client.requestThreads(widget.forum, 1);
          _fid = page.fid;
        } catch (_) {}
      }
      final collected = await _client
          .fetchThread(widget.forum, widget.thread.tid, onStatus: (status) {
        if (mounted) setState(() => _error = null);
      });
      if (mounted) setState(() => _collected = collected);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  /// 展开/加载更多楼中楼（302002）。
  Future<void> _expandSubs(Floor floor) async {
    final state = _subs.putIfAbsent(floor.pid, () => _SubState());
    if (state.loading) return;
    setState(() => state.loading = true);
    try {
      final result = await _client.fetchSubPosts(widget.thread.tid, floor.pid,
          state.pn + 1,
          fid: _fid);
      if (!mounted) return;
      final byPid = <int, SubPost>{
        for (final p in state.posts) p.pid: p,
        for (final p in result.posts) p.pid: p,
      };
      state.posts = byPid.values.toList()..sort((a, b) => a.pid.compareTo(b.pid));
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

  Future<void> _import() async {
    final collected = _collected;
    if (collected == null || _importing || _imported) return;
    setState(() => _importing = true);
    try {
      final result =
          await TiebaImporter(AppDatabase.instance).importThreads([collected]);
      if (mounted) {
        setState(() {
          _importing = false;
          _imported = result.added > 0;
        });
        if (result.added > 0) {
          widget.onImported?.call();
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(result.added > 0 ? '已导入本地库' : '未导入（内容过短或已存在）')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    }
  }

  /// 图片大图浏览：黑底 PageView + InteractiveViewer 缩放，点击关闭。
  void _openPhoto(List<String> urls, int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => PhotoViewerPage(urls: urls, initialIndex: index),
    );
  }

  Widget _buildSubPosts(BuildContext context, Floor floor) {
    final scheme = Theme.of(context).colorScheme;
    final state = _subs[floor.pid];
    // 未展开：展示 302001 内嵌的楼中楼预览；展开后：用抓取到的完整列表。
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = categoryHeaderOf(
        context,
        TiebaImporter.classifyPost(
            widget.thread.title, _collected?.combinedText() ?? ''));
    final date = TiebaImporter.networkDate(widget.thread.createTime);
    return Scaffold(
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, innerScrolled) => [
              SliverAppBar(
                leading: const BackButton(),
                expandedHeight: 0,
                floating: true,
                snap: true,
                title: Text(widget.forum, style: const TextStyle(fontSize: 16)),
              ),
            ],
            body: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _fetch, child: const Text('重试')),
                      ],
                    ),
                  )
                : _collected == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 120),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(17),
                            decoration: BoxDecoration(
                              color: header.background,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.thread.title.isEmpty
                                      ? '（无标题）'
                                      : widget.thread.title,
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                      color: header.text),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TiebaAvatar(
                                        radius: 11,
                                        portrait: widget.thread.authorPortrait,
                                        name: widget.thread.author),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${widget.thread.author} · 回复 ${widget.thread.replyCount}'
                                        ' · 浏览 ${widget.thread.viewCount}'
                                        '${date.isEmpty ? '' : ' · $date'}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: header.subText),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final floor in _collected!.floors)
                            if (floor.text.trim().isNotEmpty ||
                                floor.images.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            TiebaAvatar(
                                                radius: 11,
                                                portrait: floor.portrait,
                                                name: floor.author),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                  floor.seq == 1
                                                      ? floor.author
                                                      : '${floor.seq}楼 · ${floor.author}',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme
                                                          .onSurfaceVariant)),
                                            ),
                                            if (floor.agree > 0)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .thumb_up_alt_rounded,
                                                      size: 13,
                                                      color: scheme.primary),
                                                  const SizedBox(width: 3),
                                                  Text('${floor.agree}',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              scheme.primary)),
                                                ],
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        SelectableTiebaText(
                                          content: floor.text,
                                          style: TextStyle(
                                              fontSize: 14,
                                              height: 1.55,
                                              color: scheme.onSurface)),
                                        for (var i = 0;
                                            i < floor.images.length;
                                            i++) ...[
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            child: InkWell(
                                              onTap: () =>
                                                  _openPhoto(floor.images, i),
                                              child: Image.network(
                                                  floor.images[i],
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 540,
                                                  loadingBuilder: (context,
                                                      child, progress) {
                                                    if (progress == null) {
                                                      return child;
                                                    }
                                                    return Container(
                                                      height: 160,
                                                      color: scheme
                                                          .surfaceContainerHigh,
                                                      alignment:
                                                          Alignment.center,
                                                      child: const CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                    );
                                                  },
                                                  errorBuilder: (context,
                                                          error, stack) =>
                                                      Container(
                                                          height: 60,
                                                          color: scheme
                                                              .surfaceContainerHigh,
                                                          alignment:
                                                              Alignment.center,
                                                          child: Text(
                                                              '图片加载失败',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      12,
                                                                  color: scheme
                                                                      .onSurfaceVariant))),
                                                ),
                                            ),
                                          ),
                                        ],
                                        if (floor.subNumber > 0)
                                          _buildSubPosts(context, floor),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
          ),
          if (_collected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
            ),
        ],
      ),
    );
  }
}

/// 全屏大图浏览：左右滑动 + 双指缩放，点击任意处关闭。
class PhotoViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const PhotoViewerPage(
      {super.key, required this.urls, required this.initialIndex});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(widget.urls[i],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => Text(
                            '图片加载失败',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13))),
                  ),
                ),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text('${_index + 1}/${widget.urls.length}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 8,
            child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
