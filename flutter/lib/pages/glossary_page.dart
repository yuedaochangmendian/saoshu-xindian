import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 名词解释：随包 glossary_terms.json（扫书宝典来源，42 条黑话词条）。
class GlossarySection extends StatefulWidget {
  const GlossarySection({super.key});

  @override
  State<GlossarySection> createState() => _GlossarySectionState();
}

class _GlossaryEntry {
  final String term;
  final String explanation;
  const _GlossaryEntry(this.term, this.explanation);
}

class _GlossarySectionState extends State<GlossarySection> {
  List<_GlossaryEntry> _all = const [];
  List<_GlossaryEntry> _filtered = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/glossary_terms.json');
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final terms = (decoded['terms'] as List? ?? const []);
      final entries = terms
          .map((e) => _GlossaryEntry(
                (e as Map)['term'] as String? ?? '',
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

  void _filter(String query) {
    final q = query.trim();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((e) =>
                  e.term.contains(q) || e.explanation.contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text(_error!,
          style: TextStyle(color: scheme.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: _filter,
          decoration: InputDecoration(
            hintText: '搜索名词或释义',
            prefixIcon: Icon(Icons.search, color: scheme.primary),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Text('${_filtered.length} 条 · 来自《扫书宝典》',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        ..._filtered.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    collapsedShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    title: Text(entry.term,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
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
              ),
            )),
      ],
    );
  }
}
