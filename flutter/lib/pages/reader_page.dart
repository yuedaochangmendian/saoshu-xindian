import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../data/database.dart';
import '../data/models.dart';

/// 正文详情：主色容器头卡 + 操作行 + 正文 + 上一篇/下一篇。
class ReaderPage extends StatefulWidget {
  final int documentId;
  const ReaderPage({super.key, required this.documentId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _db = AppDatabase.instance;
  Document? _document;
  int? _newerId;
  int? _olderId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(widget.documentId);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    final document = await _db.loadDocument(id);
    if (document == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('没有找到这条内容')));
      }
      return;
    }
    final newer = await _db.adjacentDocumentId(document, true);
    final older = await _db.adjacentDocumentId(document, false);
    if (mounted) {
      setState(() {
        _document = document;
        _newerId = newer;
        _olderId = older;
        _loading = false;
      });
    }
  }

  void _toggleFavorite() {
    final document = _document;
    if (document == null) return;
    AppScope.of(context).favorites.toggle(document.id);
    setState(() {});
  }

  void _copyContent() {
    final document = _document;
    if (document == null) return;
    Clipboard.setData(ClipboardData(text: document.content));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('扫书内容已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('正文详情', style: TextStyle(fontSize: 16)),
        actions: [
          if (document != null)
            IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                AppScope.of(context).favorites.contains(document.id)
                    ? Icons.star
                    : Icons.star_border,
                color: scheme.primary,
              ),
              tooltip: '收藏',
            ),
          if (document != null)
            IconButton(
              onPressed: _copyContent,
              icon: const Icon(Icons.copy_rounded),
              tooltip: '复制正文',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : document == null
              ? Center(
                  child: Text('内容不存在',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(document.category,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            scheme.onSecondaryContainer)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  document.date.isEmpty
                                      ? '日期未知'
                                      : document.date,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.8)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Text(
                            document.displayTitle,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: scheme.onPrimaryContainer),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            document.author.isEmpty
                                ? '作者/发帖人未知'
                                : '作者/发帖人  ${document.author}',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: AppScope.of(context)
                                    .favorites
                                    .contains(document.id)
                                ? Icons.star
                                : Icons.star_border,
                            label: AppScope.of(context)
                                    .favorites
                                    .contains(document.id)
                                ? '已收藏'
                                : '收藏',
                            onTap: _toggleFavorite,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.copy_rounded,
                            label: '复制正文',
                            onTap: _copyContent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SelectableText(
                        document.content,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.65,
                            color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _NavButton(
                            label: '上一篇',
                            enabled: _olderId != null,
                            onTap: _olderId == null
                                ? null
                                : () => _load(_olderId!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NavButton(
                            label: '下一篇',
                            enabled: _newerId != null,
                            onTap: _newerId == null
                                ? null
                                : () => _load(_newerId!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton(
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

class _NavButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  const _NavButton(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: enabled
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerLow.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5))),
          ),
        ),
      ),
    );
  }
}
