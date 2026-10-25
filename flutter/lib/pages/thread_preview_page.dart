import 'package:flutter/material.dart';

import '../data/database.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';
import '../widgets/category_style.dart';

/// 帖子预览：进入即抓取楼层内容，可一键导入本地库。
class ThreadPreviewPage extends StatefulWidget {
  final String forum;
  final ThreadSummary thread;
  final VoidCallback? onImported;

  const ThreadPreviewPage(
      {super.key, required this.forum, required this.thread, this.onImported});

  @override
  State<ThreadPreviewPage> createState() => _ThreadPreviewPageState();
}

class _ThreadPreviewPageState extends State<ThreadPreviewPage> {
  final _client =
      TiebaClient(bduss: ''); // BDUSS 由调用方壳层注入成本高，预览走游客通道即可；导入后正文入库。

  CollectedThread? _collected;
  String? _error;
  bool _importing = false;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final collected = await _client
          .fetchThread(widget.forum, widget.thread.tid, onStatus: (status) {
        if (mounted) setState(() => _error = null);
      });
      if (mounted) setState(() => _collected = collected);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = categoryStyleOf(TiebaImporter.classifyPost(
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
                              color: style.container.withValues(alpha: 0.42),
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
                                      color: style.onContainer),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${widget.thread.author} · 回复 ${widget.thread.replyCount}'
                                  ' · 浏览 ${widget.thread.viewCount}'
                                  '${date.isEmpty ? '' : ' · $date'}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: style.onContainer
                                          .withValues(alpha: 0.85)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final floor in _collected!.floors)
                            if (floor.text.trim().isNotEmpty)
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
                                        SelectableText(floor.text,
                                            style: TextStyle(
                                                fontSize: 14,
                                                height: 1.55,
                                                color: scheme.onSurface)),
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
