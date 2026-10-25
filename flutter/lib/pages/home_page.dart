import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = AppDatabase.instance;
  bool _loading = true;
  bool _dbPreparing = false;
  String _prepareStatus = '';
  int _docs = 0;
  int _books = 0;
  int _sources = 0;
  List<Document> _random = const [];

  @override
  void initState() {
    super.initState();
    _db.onStatus((message) {
      if (mounted) setState(() => _prepareStatus = message);
    });
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() => _loading = true);
    } else {
      setState(() => _dbPreparing = true);
    }
    try {
      final docs = await _db.documentCount();
      final books = await _db.bookCount();
      final sources = await _db.sourceCount();
      final random = await _db.randomHomeDocuments(limit: 12);
      if (mounted) {
        setState(() {
          _docs = docs;
          _books = books;
          _sources = sources;
          _random = random;
          _loading = false;
          _dbPreparing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _dbPreparing = false;
          _prepareStatus = '数据库出错：$error';
        });
      }
    }
  }

  void _openReader(Document document) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(documentId: document.id),
    ));
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()));
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
                  child: Text('v4.0',
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 11),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('随机扫书 · 推书 · 避雷',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                ),
                TextButton(
                  onPressed: _loading ? null : () => _load(refresh: true),
                  child: const Text('换一批'),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_random.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('暂无内容',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else
              ..._random.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child:
                        DocumentCard(document: d, onTap: () => _openReader(d)),
                  )),
          ],
        ),
      ),
    );
  }
}
