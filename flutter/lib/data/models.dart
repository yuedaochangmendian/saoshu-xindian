import 'dart:convert';

class Document {
  final int id;
  final String title;
  final String author;
  final String category;
  final String forum;
  final String date;
  final String sourceUrl;
  final String content;
  final int hotScore;
  final String mentionedJson;

  const Document({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.forum,
    required this.date,
    required this.sourceUrl,
    required this.content,
    required this.hotScore,
    this.mentionedJson = '',
  });

  static Document fromRow(Map<String, Object?> row) => Document(
        id: (row['id'] ?? 0) as int,
        title: (row['title'] ?? '') as String,
        author: (row['author'] ?? '') as String,
        category: (row['category'] ?? '') as String,
        forum: (row['forum'] ?? '') as String,
        date: (row['published_at'] ?? '') as String,
        sourceUrl: (row['source_url'] ?? '') as String,
        content: (row['content'] ?? '') as String,
        hotScore: (row['hot_score'] ?? 0) as int,
        mentionedJson: (row['mentioned_books_json'] ?? '') as String,
      );

  List<String> get mentionedBooks {
    try {
      final decoded = jsonDecode(mentionedJson);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  String get displayTitle => title.isEmpty ? '（无标题）' : title;
}

class Book {
  final int id;
  final String title;
  final String titleNorm;
  final int reviewCount;
  final int bestDocumentId;
  final String latestAt;

  const Book({
    required this.id,
    required this.title,
    required this.titleNorm,
    required this.reviewCount,
    required this.bestDocumentId,
    required this.latestAt,
  });

  static Book fromRow(Map<String, Object?> row) => Book(
        id: (row['id'] ?? 0) as int,
        title: (row['title'] ?? '') as String,
        titleNorm: (row['title_norm'] ?? '') as String,
        reviewCount: (row['review_count'] ?? 0) as int,
        bestDocumentId: (row['best_document_id'] ?? 0) as int,
        latestAt: (row['latest_at'] is String)
            ? row['latest_at'] as String
            : (row['published_at'] ?? '') as String,
      );
}
