import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import 'book_detail_page.dart';
import 'browse_page.dart';
import 'glossary_page.dart';

/// 书库：书名聚合 / 分类浏览 / 名词解释 三个并列视图。
class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('书库',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: '书名聚合'),
                    Tab(text: '分类浏览'),
                    Tab(text: '名词解释'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _BookList(),
                    SingleChildScrollView(child: BrowseSection()),
                    SingleChildScrollView(child: GlossarySection()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 书名聚合列表（按评论数排序，无限加载）。
class _BookList extends StatefulWidget {
  const _BookList();

  @override
  State<_BookList> createState() => _BookListState();
}

class _BookListState extends State<_BookList> {
  final _db = AppDatabase.instance;
  final _scrollController = ScrollController();
  final List<Book> _books = [];
  String _query = '';
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = true;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _loadMore();
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading || !_hasMore && !reset) return;
    setState(() => _loading = true);
    final offset = reset ? 0 : _offset;
    final results = _query.isEmpty
        ? await _db.latestBooks(offset: offset)
        : await _db.searchBooks(_query, offset: offset);
    if (mounted) {
      setState(() {
        if (reset) _books.clear();
        _books.addAll(results);
        _offset = offset + results.length;
        _hasMore = results.length >= 60;
        _loading = false;
      });
    }
  }

  void _onQuery(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _query = query.trim();
      _hasMore = true;
      _loadMore(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        TextField(
          onChanged: (v) => _onQuery(v),
          decoration: InputDecoration(
            hintText: '搜索书名',
            prefixIcon: Icon(Icons.search, color: scheme.primary),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            itemCount: _books.length + 1,
            itemBuilder: (context, index) {
              if (index == _books.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : _books.isEmpty
                            ? Text('暂无书目',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant))
                            : const SizedBox.shrink(),
                  ),
                );
              }
              final book = _books[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: Text(book.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${book.reviewCount} 条评论${book.latestAt.isEmpty ? '' : ' · 最近 ${book.latestAt}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => BookDetailPage(book: book)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
