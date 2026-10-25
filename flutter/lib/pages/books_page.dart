import 'package:flutter/material.dart';

import 'browse_page.dart';
import 'glossary_page.dart';
import 'network_page.dart';

/// 书库：网络浏览（贴吧抓取）/ 分类浏览 / 名词解释 三个并列视图。
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
                    Tab(text: '网络浏览'),
                    Tab(text: '分类浏览'),
                    Tab(text: '名词解释'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    NetworkSection(),
                    SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: 140),
                        child: BrowseSection()),
                    SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: 140),
                        child: GlossarySection()),
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
