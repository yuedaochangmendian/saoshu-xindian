import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';

/// 分类浏览：按「来源」或「帖子类型」两个维度过滤内容。
class BrowseSection extends StatefulWidget {
  const BrowseSection({super.key});

  @override
  State<BrowseSection> createState() => _BrowseSectionState();
}

enum _Dimension { source, category }

class _BrowseSectionState extends State<BrowseSection> {
  final _db = AppDatabase.instance;
  _Dimension _dimension = _Dimension.source;
  List<Map<String, Object?>> _values = const [];
  String? _selected;
  List<Document> _documents = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  Future<void> _loadValues() async {
    setState(() => _loading = true);
    final values = _dimension == _Dimension.source
        ? await _db.forumsWithCounts()
        : await _db.categoriesWithCounts();
    if (mounted) {
      setState(() {
        _values = values;
        _selected =
            values.isEmpty ? null : _labelOf(values.first);
        _loading = false;
      });
      _loadDocuments();
    }
  }

  Future<void> _loadDocuments() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _loading = true);
    final documents = _dimension == _Dimension.source
        ? await _db.documentsByForum(selected)
        : await _db.documentsByCategory(selected);
    if (mounted) {
      setState(() {
        _documents = documents;
        _loading = false;
      });
    }
  }

  static String _labelOf(Map<String, Object?> row) =>
      (row['forum'] ?? row['category'] ?? '') as String;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_Dimension>(
          segments: const [
            ButtonSegment(
                value: _Dimension.source, label: Text('按来源')),
            ButtonSegment(
                value: _Dimension.category, label: Text('按类型')),
          ],
          selected: {_dimension},
          onSelectionChanged: (selection) {
            setState(() => _dimension = selection.first);
            _loadValues();
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in _values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                        '${_labelOf(entry)} ${entry['c']}'),
                    selected: _selected == _labelOf(entry),
                    onSelected: (_) {
                      setState(() => _selected = _labelOf(entry));
                      _loadDocuments();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('该分类下暂无内容',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          ..._documents.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DocumentCard(
                  document: d,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReaderPage(documentId: d.id),
                  )),
                ),
              )),
      ],
    );
  }
}
