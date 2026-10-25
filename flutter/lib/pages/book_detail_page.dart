import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';

/// 书名详情：头卡 + 相关内容列表。
class BookDetailPage extends StatefulWidget {
  final Book book;
  const BookDetailPage({super.key, required this.book});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final _db = AppDatabase.instance;
  List<Document> _documents = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final documents = await _db.documentsForBook(widget.book);
    if (mounted) {
      setState(() {
        _documents = documents;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final book = widget.book;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('书名详情', style: TextStyle(fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 6),
                      Text(
                        '评论聚合 ${book.reviewCount} 条 · '
                        '${book.latestAt.isEmpty ? '日期未知' : '最近 ${book.latestAt}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('相关内容 ${_documents.length} 条',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 10),
                if (_documents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('暂无相关内容',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                else
                  ..._documents.map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DocumentCard(
                          document: d,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => ReaderPage(documentId: d.id)),
                          ),
                        ),
                      )),
              ],
            ),
    );
  }
}
