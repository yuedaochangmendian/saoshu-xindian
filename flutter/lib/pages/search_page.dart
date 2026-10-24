import 'package:flutter/material.dart';

import '../data/database.dart';
import '../prefs.dart';
import '../data/models.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';

/// 搜索页：进入自动弹出输入法，标题/全文双模式，最近 10 条记录。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _db = AppDatabase.instance;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _fullText = false;
  bool _searching = false;
  bool _searched = false;
  List<Document> _results = const [];
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _history = AppHistory.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final results =
        await _db.searchDocuments(query.trim(), fullText: _fullText);
    AppHistory.push(query.trim());
    if (mounted) {
      setState(() {
        _results = results;
        _searched = true;
        _searching = false;
        _history = AppHistory.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('搜索', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _runSearch,
                      decoration: InputDecoration(
                        hintText: '例如：世子很凶 / 作者名 / 西幻',
                        prefixIcon: Icon(Icons.search, color: scheme.primary),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        _runSearch(_controller.text),
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('标题/书名'),
                    selected: !_fullText,
                    onSelected: (_) => setState(() => _fullText = false),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('全文'),
                    selected: _fullText,
                    onSelected: (_) => setState(() => _fullText = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : !_searched
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_history.isNotEmpty) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('最近搜索',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: scheme.onSurface)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      AppHistory.clear();
                                      setState(() => _history = []);
                                    },
                                    child: const Text('清空'),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _history
                                    .map((q) => InputChip(
                                          label: Text(q),
                                          onPressed: () {
                                            _controller.text = q;
                                            _runSearch(q);
                                          },
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        )
                      : _results.isEmpty
                          ? Center(
                              child: Text('没有找到相关内容',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _results.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DocumentCard(
                                  document: _results[index],
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ReaderPage(
                                          documentId: _results[index].id),
                                    ),
                                  ),
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索历史（最近 10 条，存 SharedPreferences）。
class AppHistory {
  static const _key = 'search_history_flutter';
  static List<String> load() =>
      AppPrefs.instance?.getStringList(_key)?.take(10).toList() ?? [];

  static void push(String query) {
    final prefs = AppPrefs.instance;
    if (prefs == null) return;
    final list = prefs.getStringList(_key) ?? [];
    list.remove(query);
    list.insert(0, query);
    prefs.setStringList(_key, list.take(10).toList());
  }

  static void clear() {
    AppPrefs.instance?.remove(_key);
  }
}
