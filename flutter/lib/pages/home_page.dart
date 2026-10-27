import 'package:flutter/material.dart';

import '../app.dart';
import '../data/database.dart';
import '../services/system_bridge.dart';
import '../widgets/category_style.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 功能入口卡片：图标 + 标题 + 说明，点击进入对应页面。
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.desc,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String name;
  final int count;
  final VoidCallback onTap;
  const _CategoryTile(
      {required this.name, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = categoryStyleOf(name);
    return Material(
      color: style.container,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, size: 20, color: style.onContainer),
              const SizedBox(height: 4),
              Text(name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: style.onContainer)),
              Text('$count 条',
                  style: TextStyle(
                      fontSize: 10,
                      color: style.onContainer.withValues(alpha: 0.75))),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  final _db = AppDatabase.instance;
  bool _dbPreparing = false;
  String _prepareStatus = '';
  int _docs = 0;
  int _books = 0;
  int _sources = 0;
  List<Map<String, Object?>> _categories = const [];
  String _versionLabel = 'v4';

  late final void Function(String) _statusListener;

  @override
  void initState() {
    super.initState();
    _statusListener = (message) {
      if (mounted) setState(() => _prepareStatus = message);
    };
    _db.onStatus(_statusListener);
    _load();
    SystemBridge.appVersion().then((info) {
      if (mounted && info != null) {
        setState(() => _versionLabel = 'v${info['version']}');
      }
    });
  }

  @override
  void dispose() {
    _db.removeStatusListener(_statusListener);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _dbPreparing = true);
    try {
      final stats = await Future.wait(
          [_db.documentCount(), _db.bookCount(), _db.sourceCount()]);
      final docs = stats[0];
      final books = stats[1];
      final sources = stats[2];
      final categories = await _db.categoriesWithCounts();
      if (mounted) {
        setState(() {
          _docs = docs;
          _books = books;
          _sources = sources;
          _categories = categories;
          _dbPreparing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _dbPreparing = false;
          _prepareStatus = '数据库出错：$error';
        });
      }
    }
  }

  void _gotoTab(int index) {
    final scope = AppScope.of(context);
    scope.dockHidden.value = false;
    scope.tabIndex.value = index;
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchPage()));
  }

  /// 首页分类入口：跳转书库-分类浏览并选中该分类。
  void _jumpCategory(String name) {
    AppScope.of(context).browseJump.value = name;
    _gotoTab(1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_dbPreparing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_prepareStatus.isEmpty ? '正在准备数据…' : _prepareStatus,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('扫书新典',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(_versionLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '$_docs 条内容 · $_books 本书名 · $_sources 条来源',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Material(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: _openSearch,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: scheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('搜索书名、作者或正文',
                            style: TextStyle(
                                fontSize: 14, color: scheme.onSurface)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Text('搜索 ›',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('板块直达',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.32,
              children: [
                for (final entry in _categories)
                  _CategoryTile(
                      name: (entry['category'] ?? '') as String,
                      count: (entry['c'] as int? ?? 0),
                      onTap: () => _jumpCategory(
                          (entry['category'] ?? '') as String)),
              ],
            ),
            const SizedBox(height: 16),
            Text('功能入口',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                _ActionCard(
                  icon: Icons.public_rounded,
                  iconColor: const Color(0xFF4477E0),
                  title: '网络浏览',
                  desc: '贴吧抓取导入',
                  onTap: () => _gotoTab(2),
                ),
                _ActionCard(
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFF7E57C2),
                  title: '名词解释',
                  desc: '扫书黑话词典',
                  onTap: () {
                    AppScope.of(context).browseJump.value = '__glossary__';
                    _gotoTab(1);
                  },
                ),
                _ActionCard(
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFA66A2E),
                  title: '收藏与简记',
                  desc: '星标与笔记',
                  onTap: () => _gotoTab(3),
                ),
                _ActionCard(
                  icon: Icons.backup_rounded,
                  iconColor: const Color(0xFF009688),
                  title: '数据与设置',
                  desc: '备份 · 主题 · 更新',
                  onTap: () => _gotoTab(4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
