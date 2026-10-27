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

  /// 各分类的浏览进度（静态：切换页面/重建后仍保留）。
  /// scrollMemory = 进程内滚动位置；prefs 持久化每分类已加载页数，
  /// 恢复时补载这些页后跳回滚动位置。
  static final Map<String, double> _scrollMemory = {};
  static const _progressPrefix = 'browse_pages_';
  double _pendingRestorePx = 0;
  bool _restoring = false;

  /// 恢复补载中：_saveProgress 必须跳过，否则 position.pixels==0 会覆盖已存 px。
  bool _restoreLoading = false;

  /// 按月筛选（'yyyy-MM'）；非空时区间筛选失效（两者互斥）。
  String? _monthFilter;
  final List<Document> _documents = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _loading = false;

  /// 请求进行中标记：与 _loading 分离，避免在「重置 → 加载」链路里自我阻塞。
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadValues();
  }

  /// 持久化当前分类进度。offset 显式传入时（dispose 已在控制器销毁前
  /// 读取位置）用它，否则读实时位置；绝不跨 dispose 之后再碰控制器。
  Future<void> _saveProgress({double? offset}) async {
    final selected = _selected;
    if (selected == null || _restoring || _restoreLoading) return;
    final px = offset ??
        (_scrollController.hasClients
            ? _scrollController.position.pixels
            : (_scrollMemory[selected] ?? 0));
    if (px <= 0) return;
    _scrollMemory[selected] = px;
    final prefs = await AppDatabase.instance.sharedPrefs;
    final pages = (_offset / _pageSize).ceil();
    await prefs.setInt('$_progressPrefix${selected}_pages', pages);
    await prefs.setDouble('$_progressPrefix${selected}_px', px);
  }

  @override
  void dispose() {
    final px = _scrollController.hasClients
        ? _scrollController.position.pixels
        : null;
    _scrollController.dispose();
    if (px != null && px > 0) {
      _saveProgress(offset: px);
    }
    super.dispose();
  }

  void _onScroll() {
    final selected = _selected;
    final px = _scrollController.position.pixels;
    // 仅内存跟踪；写 prefs 发生在离开页面 / 切换分类时，不再每帧落盘。
    if (selected != null && px > 0) _scrollMemory[selected] = px;
    if (px > _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadValues() async {
    // 首次进入先显示加载态，避免首帧闪「暂无内容」。
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

  Future<void> _resetDocuments({bool restore = false}) async {
    final savedPages = restore ? (await _loadSavedPages(_selected ?? '')) : 0;
    setState(() {
      _documents.clear();
      _offset = 0;
      _hasMore = true;
      _loading = false;
      _fetching = false;
    });
    // 恢复模式：先把保存的页数补载回来（期间屏蔽 _saveProgress，
    // 否则实时 pixels=0 会覆盖已保存的 px），再跳回滚动位置。
    final savedPx = savedPages > 0 ? _pendingRestorePx : 0.0;
    _restoreLoading = true;
    try {
      for (var i = 0; i < savedPages; i++) {
        await _loadMore();
      }
    } finally {
      _restoreLoading = false;
    }
    if (savedPages > 0 && _scrollController.hasClients) {
      _restoring = true;
      _scrollController.jumpTo(savedPx
          .clamp(0.0, _scrollController.position.maxScrollExtent));
      _restoring = false;
    }
  }

  /// 读该分类已加载页数（prefs）。
  Future<int> _loadSavedPages(String category) async {
    final prefs = await AppDatabase.instance.sharedPrefs;
    final pages = prefs.getInt('$_progressPrefix${category}_pages') ?? 0;
    _pendingRestorePx = prefs.getDouble('$_progressPrefix${category}_px') ?? 0;
    _scrollMemory[category] = _pendingRestorePx;
    return pages;
  }

  Future<void> _loadMore() async {
    final selected = _selected;
    if (selected == null || _fetching || _restoring || !_hasMore) return;
    _fetching = true;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final documents = await _db.documentsByCategory(selected,
          offset: _offset, since: _sinceDate(), until: _untilDate());
      if (mounted && generation == _generation) {
        setState(() {
          _documents.addAll(documents);
          _offset += documents.length;
          _hasMore = documents.length >= _pageSize;
          _loading = false;
        });
        _saveProgress();
      }
    } finally {
      // 仅当本次请求仍是最新代号时才释放锁，避免过期响应清掉在飞请求的锁。
      if (generation == _generation) _fetching = false;
    }
  }

  /// 请求代号：筛选切换时递增，丢弃过期响应。
  int _generation = 0;

  /// 日历式月份选择面板：切换年份 + 12 宫格，返回 'yyyy-MM'。
  Future<String?> _pickMonth() async {
    final scheme = Theme.of(context).colorScheme;
    var year = _monthFilter != null
        ? int.parse(_monthFilter!.split('-').first)
        : DateTime.now().year;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: () => setSheetState(() => year--),
                      icon: const Icon(Icons.chevron_left_rounded)),
                  Text('$year',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(
                      onPressed: () => setSheetState(() => year++),
                      icon: const Icon(Icons.chevron_right_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
                children: [
                  for (var month = 1; month <= 12; month++)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      onPressed: () => Navigator.pop(sheetContext,
                          '$year-${month.toString().padLeft(2, '0')}'),
                      child: Text('$month 月'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  /// 日期下限（yyyy-MM-dd）；按月筛选或不限时返回 null。
  String? _sinceDate() {
    if (_monthFilter != null) return '$_monthFilter-01';
    if (_rangeDays <= 0) return null;
    final date = DateTime.now().subtract(Duration(days: _rangeDays));
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// 日期上限开区间（次月 1 日）；仅按月筛选时非空。
  String? _untilDate() {
    if (_monthFilter == null) return null;
    final parts = _monthFilter!.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final nextYear = month == 12 ? year + 1 : year;
    final nextMonth = month == 12 ? 1 : month + 1;
    return '$nextYear-${nextMonth.toString().padLeft(2, '0')}-01';
  }

  void _setMonth(String? month) {
    setState(() {
      _monthFilter = month;
      if (month != null) _rangeDays = 0;
    });
    _resetDocuments();
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
                      _saveProgress();
                      setState(() => _selected = _labelOf(entry));
                      _resetDocuments(restore: true);
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
                    if (_monthFilter != null) ...[
                      InputChip(
                        avatar: Icon(Icons.event_rounded,
                            size: 14, color: scheme.primary),
                        label: Text(_monthFilter!),
                        labelStyle:
                            TextStyle(fontSize: 12, color: scheme.primary),
                        onDeleted: () => _setMonth(null),
                      ),
                      const SizedBox(width: 6),
                    ],
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
                            setState(() {
                              _rangeDays = entry.key;
                              _monthFilter = null;
                            });
                            _resetDocuments();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ActionChip(
              avatar: Icon(Icons.calendar_today_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              label: const Text('按月', style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final picked = await _pickMonth();
                if (picked != null) _setMonth(picked);
              },
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
