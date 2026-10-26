import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 名词解释：随包 glossary_terms.json（扫书宝典 2022 新版，按名词/雷点分类）。
class GlossarySection extends StatefulWidget {
  const GlossarySection({super.key});

  @override
  State<GlossarySection> createState() => _GlossarySectionState();
}

class _GlossaryEntry {
  final String term;
  final String category;
  final String explanation;
  const _GlossaryEntry(this.term, this.category, this.explanation);
}

class _GlossarySectionState extends State<GlossarySection> {
  List<_GlossaryEntry> _all = const [];
  List<_GlossaryEntry> _filtered = const [];
  String _categoryFilter = '全部';
  String _query = '';
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/glossary_terms.json');
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final terms = (decoded['terms'] as List? ?? const []);
      final entries = terms
          .map((e) => _GlossaryEntry(
                (e as Map)['term'] as String? ?? '',
                e['category'] as String? ?? '名词',
                e['explanation'] as String? ?? '',
              ))
          .toList();
      if (mounted) {
        setState(() {
          _all = entries;
          _filtered = entries;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '加载名词解释失败：$error';
          _loading = false;
        });
      }
    }
  }

  void _onQueryChanged(String query) {
    // 防抖：停止输入 200ms 后才重建列表，避免搜索时逐字符跳动错位。
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _query = query.trim();
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _query.toLowerCase();
    setState(() {
      _filtered = _all.where((e) {
        if (_categoryFilter != '全部' && e.category != _categoryFilter) {
          return false;
        }
        if (q.isEmpty) return true;
        return e.term.toLowerCase().contains(q) ||
            e.explanation.toLowerCase().contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: scheme.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            hintText: '搜索名词或释义',
            prefixIcon: Icon(Icons.search, color: scheme.primary),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final cat in const ['全部', '名词', '雷点'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  labelStyle: TextStyle(
                      fontSize: 12,
                      color: _categoryFilter == cat
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                  selected: _categoryFilter == cat,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _categoryFilter = cat);
                    _applyFilter();
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text('没有匹配的词条',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 140),
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child:
                        _GlossaryTile(entry: _filtered[index], scheme: scheme),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 单个词条：标题行（词 + 分类角标）+ 展开显示解释。
class _GlossaryTile extends StatelessWidget {
  final _GlossaryEntry entry;
  final ColorScheme scheme;

  const _GlossaryTile({required this.entry, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Flexible(
                child: Text(entry.term,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(entry.category,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(entry.explanation,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}
