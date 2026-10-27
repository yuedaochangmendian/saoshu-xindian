import 'package:flutter/material.dart';

import '../app.dart';
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

  /// 来源（贴吧/站点）过滤，来自「来源索引」面板。
  String? _forumFilter;

  /// 是否有生效中的筛选（筛选态下分页进度无跨会话意义，不持久化）。
  bool get _filtered =>
      _forumFilter != null || _monthFilter != null || _rangeDays > 0;
  final List<Document> _documents = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _loading = false;

  /// 请求进行中标记：与 _loading 分离，避免在「重置 → 加载」链路里自我阻塞。
  bool _fetching = false;

  AppScope? _scope;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadValues();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (_scope != scope) {
      _scope?.browseJump.removeListener(_applyBrowseJump);
      scope.browseJump.addListener(_applyBrowseJump);
      _scope = scope;
    }
  }

  /// 首页分类入口 → 直接选中对应分类。
  /// 若此时 _values 还没加载完，等 _loadValues 完成后补应用。
  void _applyBrowseJump() {
    final scope = _scope;
    if (scope == null) return;
    final target = scope.browseJump.value;
    if (target == null) return;
    scope.browseJump.value = null;
    if (!mounted) return;
    if (_values.isEmpty) {
      _pendingJump = target;
      return;
    }
    _selectValue(target);
  }

  void _selectValue(String target) {
    final hit = _values.where((e) => _labelOf(e) == target).toList();
    if (hit.isEmpty) return;
    _saveProgress();
    setState(() => _selected = target);
    _resetDocuments(restore: true);
  }

  String? _pendingJump;

  /// 持久化当前分类进度。offset 显式传入时（dispose 已在控制器销毁前
  /// 读取位置）用它，否则读实时位置；绝不跨 dispose 之后再碰控制器。
  /// px=0（用户回到了顶部）同样落盘——跳过 0 值会让陈旧深位置复活。
  Future<void> _saveProgress({double? offset}) async {
    final selected = _selected;
    if (selected == null || _restoring || _restoreLoading || _filtered) {
      return;
    }
    final px = offset ??
        (_scrollController.hasClients
            ? _scrollController.position.pixels
            : (_scrollMemory[selected] ?? 0));
    _scrollMemory[selected] = px;
    final prefs = await AppDatabase.instance.sharedPrefs;
    final pages = (_offset / _pageSize).ceil();
    await prefs.setInt('$_progressPrefix${selected}_pages', pages);
    await prefs.setDouble('$_progressPrefix${selected}_px', px);
  }

  @override
  void dispose() {
    _scope?.browseJump.removeListener(_applyBrowseJump);
    final px = _scrollController.hasClients
        ? _scrollController.position.pixels
        : null;
    _scrollController.dispose();
    if (px != null) {
      _saveProgress(offset: px);
    }
    super.dispose();
  }

  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

  void _onScroll() {
    final selected = _selected;
    final px = _scrollController.position.pixels;
    // 内存跟踪（含回顶的 0）+ 节流落盘：dispose 时 ListView 已先被框架
    // 卸载（hasClients 恒 false），"离开页面才写盘"实际永远拿不到最新
    // 位置——必须在滚动存活期以 ≥1.5s 间隔持久化。
    if (selected != null) _scrollMemory[selected] = px;
    final now = DateTime.now();
    if (now.difference(_lastPersist) >= const Duration(milliseconds: 1500)) {
      _lastPersist = now;
      _saveProgress();
    }
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
      final pending = _scope?.browseJump.value ?? _pendingJump;
      if (pending != null) {
        _pendingJump = null;
        // 消费即清值：ValueNotifier 同值不通知，残留会让下次点同一
        // 分类静默失效（首页快捷入口"点了没反应"）。
        _scope?.browseJump.value = null;
        final hit = _values
            .where((e) => _labelOf(e) == pending)
            .isNotEmpty;
        if (hit) _selected = pending;
      }
      await _resetDocuments(
          restore: _selected != null &&
              _scrollMemory.containsKey(_selected));
    }
  }

  int _resetSeq = 0;

  Future<void> _resetDocuments({bool restore = false}) async {
    // 序号防重入 + generation 失效在飞分页：旧分类的 _loadMore 响应
    // 不得再污染新分类的列表/进度（v4.2.3② 同款守卫补齐到 reset 链路）。
    final seq = ++_resetSeq;
    ++_generation;
    final savedPages = restore ? (await _loadSavedPages(_selected ?? '')) : 0;
    if (!mounted || seq != _resetSeq) return;
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
    if (!mounted || seq != _resetSeq) return;
    if (savedPages > 0 && _scrollController.hasClients) {
      _restoring = true;
      _scrollController.jumpTo(savedPx
          .clamp(0.0, _scrollController.position.maxScrollExtent));
      _restoring = false;
    }
    // 正常模式（无保存页数）必须显式载回首页：v4.5.1 把"补载循环"
    // 当成加载路径，savedPages=0 时循环一次都不跑，页面永远空。
    if (_offset == 0 && _hasMore && mounted && seq == _resetSeq) {
      await _loadMore();
    }
  }

  /// 读该分类已加载页数（prefs）。
  Future<int> _loadSavedPages(String category) async {
    final prefs = await AppDatabase.instance.sharedPrefs;
    final pages = prefs.getInt('$_progressPrefix${category}_pages') ?? 0;
    // 进程内最新位置优先：_onScroll 持续维护的内存值比 prefs 上次
    // 落盘值新，直接用 prefs 覆盖会把用户最后停留位置丢掉。
    final memPx = _scrollMemory[category] ?? 0;
    final prefsPx = prefs.getDouble('$_progressPrefix${category}_px') ?? 0;
    _pendingRestorePx = memPx > 0 ? memPx : prefsPx;
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
          offset: _offset,
          since: _sinceDate(),
          until: _untilDate(),
          forum: _forumFilter);
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
  /// 「来源索引」：当前分类下所有来源贴吧/站点（按条数排序，可搜索）。
  Future<void> _showForumIndex() async {
    final category = _selected;
    if (category == null) return;
    final rows = await _db.forumsForCategory(category);
    if (rows.isEmpty || !mounted) return;
    final forums = <String, int>{
      for (final r in rows) (r['forum'] ?? '') as String: (r['c'] as int? ?? 0)
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ForumIndexSheet(
          category: category, forums: forums, selected: _forumFilter),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _forumFilter = picked == _forumFilter ? null : picked;
    });
    _resetDocuments();
  }

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
                      setState(() {
                        _selected = _labelOf(entry);
                        _forumFilter = null;
                      });
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
            // 年月筛选并入日期图标：点击直接弹日历式年月选择。
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final picked = await _pickMonth();
                if (picked != null) _setMonth(picked);
              },
              icon: Icon(Icons.calendar_month_rounded,
                  size: 18,
                  color: _monthFilter != null
                      ? scheme.primary
                      : scheme.onSurfaceVariant),
              tooltip: _monthFilter == null ? '按年月筛选' : '当前 $_monthFilter（点击更换）',
            ),
            const SizedBox(width: 2),
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
            const SizedBox(width: 6),
            ActionChip(
              avatar: Icon(Icons.account_tree_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              label: const Text('来源', style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: _showForumIndex,
            ),
          ],
        ),
        // 筛选摘要：任何生效筛选都显式展示、可单独移除。
        if (_filtered) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (_forumFilter != null)
                      InputChip(
                        avatar: Icon(Icons.account_tree_rounded,
                            size: 14, color: scheme.primary),
                        label: Text(_forumFilter!),
                        labelStyle:
                            TextStyle(fontSize: 12, color: scheme.primary),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => setState(() {
                              _forumFilter = null;
                              _resetDocuments();
                            }),
                      ),
                    if (_monthFilter != null)
                      InputChip(
                        avatar: Icon(Icons.event_rounded,
                            size: 14, color: scheme.primary),
                        label: Text(_monthFilter!),
                        labelStyle:
                            TextStyle(fontSize: 12, color: scheme.primary),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => _setMonth(null),
                      ),
                    if (_rangeDays > 0)
                      InputChip(
                        avatar: Icon(Icons.schedule_rounded,
                            size: 14, color: scheme.primary),
                        label: Text('近 $_rangeDays 天'),
                        labelStyle:
                            TextStyle(fontSize: 12, color: scheme.primary),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => setState(() {
                              _rangeDays = 0;
                              _resetDocuments();
                            }),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _forumFilter = null;
                  _monthFilter = null;
                  _rangeDays = 0;
                  _resetDocuments();
                }),
                child: const Text('重置', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
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

/// 来源索引面板：分类下来源列表（条数降序），顶部搜索过滤，点击选定/再点取消。
class _ForumIndexSheet extends StatefulWidget {
  final String category;
  final Map<String, int> forums;
  final String? selected;
  const _ForumIndexSheet(
      {required this.category,
      required this.forums,
      required this.selected});

  @override
  State<_ForumIndexSheet> createState() => _ForumIndexSheetState();
}

class _ForumIndexSheetState extends State<_ForumIndexSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = widget.forums.entries.where((e) =>
            _query.isEmpty ||
            e.key.toLowerCase().contains(_query.toLowerCase())).toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: '在「${widget.category}」的 ${widget.forums.length} 个来源中搜索',
                  hintStyle: TextStyle(fontSize: 13),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final active = widget.selected == e.key;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                        active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: active ? scheme.primary : null),
                    title: Text(e.key,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('${e.value}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    onTap: () => Navigator.pop(context, e.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}