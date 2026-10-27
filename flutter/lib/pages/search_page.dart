import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../network/tieba_client.dart';
import '../network/tieba_import.dart';
import '../prefs.dart';
import '../widgets/document_card.dart';
import 'reader_page.dart';
import 'tieba/thread_page.dart';

/// 搜索页：进入自动弹出输入法，本地标题/全文 + 网络三模式，最近 10 条记录。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

enum _SearchMode { localTitle, localFullText, network }

class _SearchPageState extends State<SearchPage> {
  final _db = AppDatabase.instance;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _SearchMode _mode = _SearchMode.localTitle;
  bool _searching = false;
  bool _searched = false;
  bool _hasMore = false;
  int _offset = 0;
  List<Document> _results = const [];
  List<ThreadSummary> _networkResults = const [];
  List<String> _history = [];
  String _lastQuery = '';
  final TiebaClient _client = TiebaClient();
  String _networkError = '';

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
    _client.close();
    super.dispose();
  }

  Future<void> _runSearch(String query, {bool append = false}) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    if (_mode == _SearchMode.network) {
      await _runNetworkSearch(query.trim(), append: append);
      return;
    }
    final offset = append ? _offset : 0;
    final results = await _db.searchDocuments(query.trim(),
        fullText: _mode == _SearchMode.localFullText, offset: offset);
    if (!append) {
      AppHistory.push(query.trim());
    }
    if (mounted) {
      setState(() {
        if (append) {
          _results = [..._results, ...results];
        } else {
          _results = results;
          _lastQuery = query.trim();
          _searched = true;
        }
        _offset = offset + results.length;
        _hasMore = results.length >= 50;
        _searching = false;
        _history = AppHistory.load();
      });
    }
  }

  /// 网络搜索：与网络浏览同一接口——抓两吧前 3 页列表，按标题过滤。
  Future<void> _runNetworkSearch(String query, {bool append = false}) async {
    const forums = ['yy小说吧', '哀伤雪刃'];
    var matches = <ThreadSummary>[];
    try {
      for (final forum in forums) {
        for (var page = 1; page <= 3; page++) {
          final result = await _client.requestThreads(forum, page);
          matches.addAll(result.threads.where(
              (t) => !t.deleted && !t.masked && t.title.contains(query)));
          if (!result.hasMore) break;
        }
      }
      if (mounted) {
        setState(() {
          _networkResults = matches;
          _networkError = '';
          _searched = true;
          _lastQuery = query;
          _hasMore = false;
          _searching = false;
          if (!append) {
            AppHistory.push(query);
            _history = AppHistory.load();
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _networkError = '网络搜索失败：$error';
          _searching = false;
          _searched = true;
          _hasMore = false;
        });
      }
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
                        hintText: _mode == _SearchMode.network
                            ? '搜索贴吧帖子标题'
                            : '例如：世子很凶 / 作者名 / 西幻',
                        prefixIcon: Icon(Icons.search, color: scheme.primary),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _runSearch(_controller.text),
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
                    selected: _mode == _SearchMode.localTitle,
                    onSelected: (_) =>
                        setState(() => _mode = _SearchMode.localTitle),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('全文'),
                    selected: _mode == _SearchMode.localFullText,
                    onSelected: (_) =>
                        setState(() => _mode = _SearchMode.localFullText),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('网络'),
                    selected: _mode == _SearchMode.network,
                    onSelected: (_) =>
                        setState(() => _mode = _SearchMode.network),
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
                      : _mode == _SearchMode.network
                          ? _buildNetworkResults(scheme)
                          : _buildLocalResults(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkResults(ColorScheme scheme) {
    if (_networkError.isNotEmpty) {
      return Center(
          child: Text(_networkError,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    if (_networkResults.isEmpty) {
      return Center(
          child: Text('贴吧前 3 页未找到含该关键词的帖子',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _networkResults.length,
      itemBuilder: (context, index) {
        final thread = _networkResults[index];
        final date = TiebaImporter.networkDate(thread.createTime);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(thread.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${thread.author} · 回复 ${thread.replyCount}'
                  '${date.isEmpty ? '' : ' · $date'}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    TiebaThreadPage(fname: thread.forum, tid: thread.tid),
              )),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalResults(ColorScheme scheme) {
    if (_results.isEmpty) {
      return Center(
          child: Text('没有找到相关内容',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == _results.length) {
          if (!_hasMore) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: OutlinedButton(
                onPressed: _searching
                    ? null
                    : () => _runSearch(_lastQuery, append: true),
                child: Text(
                    _searching ? '加载中…' : '加载更多（已显示 ${_results.length} 条）'),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DocumentCard(
            document: _results[index],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderPage(documentId: _results[index].id),
              ),
            ),
          ),
        );
      },
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
