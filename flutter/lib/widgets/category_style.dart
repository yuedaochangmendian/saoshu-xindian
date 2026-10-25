import 'package:flutter/material.dart';

/// 分类「贴纸」样式的唯一来源：每种帖子类型一个配色对 + 图标，
/// 卡片徽章与详情页头卡染色都从这里取，保证全应用色调统一。
class CategoryStyle {
  final Color container;
  final Color onContainer;
  final IconData icon;
  const CategoryStyle(this.container, this.onContainer, this.icon);
}

const _fallback = CategoryStyle(
    Color(0xFFECEFF1), Color(0xFF37474F), Icons.bookmark_rounded);

const categoryStyles = <String, CategoryStyle>{
  '扫书': CategoryStyle(Color(0xFFFFECB3), Color(0xFF7A5C00),
      Icons.auto_stories_rounded),
  '推书': CategoryStyle(Color(0xFFC8E6C9), Color(0xFF1C5E20),
      Icons.recommend_rounded),
  '排雷': CategoryStyle(Color(0xFFFFCDD2), Color(0xFF8C1D18),
      Icons.warning_amber_rounded),
  '书评': CategoryStyle(Color(0xFFC5CAE9), Color(0xFF1A2B8C),
      Icons.rate_review_rounded),
  '讨论': CategoryStyle(Color(0xFFE1BEE7), Color(0xFF541B6D),
      Icons.forum_rounded),
  '求书': CategoryStyle(Color(0xFFFFE0B2), Color(0xFF8A5000),
      Icons.help_rounded),
  '卷首': CategoryStyle(Color(0xFFD7E3E8), Color(0xFF26343B),
      Icons.bookmark_rounded),
};

CategoryStyle categoryStyleOf(String category) =>
    categoryStyles[category] ?? _fallback;
