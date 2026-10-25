import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';

/// 分类浏览：按帖子类型过滤，列表无限下滑分页加载。
class BrowseSection extends StatefulWidget {
  const BrowseSection({super.key});

  @override
  State<BrowseSection> createState() => _BrowseSectionState();
}

class _BrowseSectionState extends State<BrowseSection> {
  static const _pageSize = 20;

  /// 日期筛选区间（天），0 = 不限。
  static const _rangeOptions = <int, String>{
    0: '不限',
    30: '近 30 天',
    90: '近 3 个月',
    365: '近 1 年',
  };

  final _db = AppDatabase.instance;
  final _scrollController = ScrollController();
  List<Map<String, Object?>> _values = const [];
  String? _selected;
  int _rangeDays = 0;
  final List<Document> _documents = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadValues();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadValues() async {
    setState(() => _loading = true);
    final values = await _db.categoriesWithCounts();
    if (mounted) {
      setState(() {
        _values = values;
        _selected = values.isEmpty ? null : _labelOf(values.first);
      });
      await _resetDocuments();
    }
  }

  Future<void> _resetDocuments() async {
    setState(() {
      _documents.clear();
      _offset = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final selected = _selected;
    if (selected == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    final documents = await _db.documentsByCategory(selected,
        offset: _offset, since: _sinceDate());
    if (mounted) {
      setState(() {
        _documents.addAll(documents);
        _offset += documents.length;
        _hasMore = documents.length >= _pageSize;
        _loading = false;
      });
    }
  }

  /// 日期下限（yyyy-MM-dd）；不限时返回 null。
  String? _sinceDate() {
    if (_rangeDays <= 0) return null;
    final date = DateTime.now().subtract(Duration(days: _rangeDays));
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _labelOf(Map<String, Object?> row) =>
      (row['forum'] ?? row['category'] ?? '') as String;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in _values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('${_labelOf(entry)} ${entry['c']}'),
                    selected: _selected == _labelOf(entry),
                    onSelected: (_) {
                      setState(() => _selected = _labelOf(entry));
                      _resetDocuments();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.calendar_month_rounded,
                size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('日期',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final entry in _rangeOptions.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          labelStyle: TextStyle(
                              fontSize: 12,
                              color: _rangeDays == entry.key
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                          selected: _rangeDays == entry.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _rangeDays = entry.key);
                            _resetDocuments();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _documents.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _documents.isEmpty
                  ? Center(
                      child: Text('该分类下暂无内容',
                          style: TextStyle(color: scheme.onSurfaceVariant)))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 140),
                      itemCount: _documents.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _documents.length) {
                          if (!_hasMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text('已加载全部 ${_documents.length} 条',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant)),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      child: const Text('加载更多')),
                            ),
                          );
                        }
                        final document = _documents[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DocumentCard(
                            document: document,
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  ReaderPage(documentId: document.id),
                            )),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
