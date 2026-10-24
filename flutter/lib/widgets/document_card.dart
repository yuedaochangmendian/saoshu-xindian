import 'package:flutter/material.dart';

import '../data/models.dart';

/// 内容卡片：分类徽章 + 标题 + 预览 + 元信息（20dp 超椭圆风格圆角）。
class DocumentCard extends StatelessWidget {
  final Document document;
  final VoidCallback onTap;

  const DocumentCard({super.key, required this.document, required this.onTap});

  static const _categoryColors = {
    '扫书': Color(0xFFFFD54F),
    '推书': Color(0xFFA5D6A7),
    '排雷': Color(0xFFEF9A9A),
    '书评': Color(0xFF90CAF9),
    '讨论': Color(0xFFCE93D8),
    '求书': Color(0xFFFFCC80),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _categoryColors[document.category] ??
        scheme.secondaryContainer;
    final preview = document.content.length > 220
        ? document.content.substring(0, 220)
        : document.content;
    final meta = [
      if (document.forum.isNotEmpty) document.forum,
      if (document.date.isNotEmpty) document.date,
      if (document.author.isNotEmpty) document.author,
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badge.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(document.category,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                document.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: scheme.onSurface),
              ),
              const SizedBox(height: 7),
              Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
