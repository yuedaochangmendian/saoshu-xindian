import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import 'tieba_client.dart';

/// 贴吧帖子导入本地库（移植自原生 ingestNetworkThread + 索引维护逻辑）。
class TiebaImportResult {
  final int added;
  final int skipped;
  const TiebaImportResult(this.added, this.skipped);
}

class TiebaImporter {
  static const sourceKind = 'tieba_network';
  final AppDatabase _app;

  TiebaImporter(this._app);

  Future<TiebaImportResult> importThreads(List<CollectedThread> threads) async {
    final db = await _app.database;
    var added = 0;
    var skipped = 0;
    for (final thread in threads) {
      final result = await _importOne(db, thread);
      if (result) {
        added++;
      } else {
        skipped++;
      }
    }
    return TiebaImportResult(added, skipped);
  }

  Future<bool> _importOne(Database db, CollectedThread thread) async {
    final combined = thread.combinedText();
    if (compact(combined).length < 20) return false;
    final sourceUrl = 'https://tieba.baidu.com/p/${thread.tid}';
    final sourceRef = thread.tid.toString();
    final existing = await db.rawQuery(
        'SELECT document_id FROM document_sources WHERE source_kind=? '
        'AND source_ref=? LIMIT 1',
        [sourceKind, sourceRef]);
    if (existing.isNotEmpty) return false;

    var title = cleanDisplayTitle(thread.title);
    final books = extractBooks('${thread.title}\n$combined');
    final category = classifyPost(thread.title, combined);
    if (books.isEmpty) {
      final candidate = titleBookCandidate(title);
      if (candidate.isNotEmpty) books.add(candidate);
    }
    title = books.isEmpty ? title : books.first;
    if (title.isEmpty) title = '贴吧主题 ${thread.tid}';

    var content = combined;
    if (thread.title.isNotEmpty && !content.startsWith(thread.title)) {
      content = '${thread.title}\n\n$content';
    }
    final mentionedJson = jsonEncode(books.toList());
    final date = networkDate(thread.createTime);
    final canonicalKey = 'tieba_network:${thread.tid}';
    final word = compact(content).length;

    return await db.transaction((txn) async {
      var documentId = await _idForKey(txn, canonicalKey);
      if (documentId == null) {
        final row = await txn.rawQuery(
            'SELECT id FROM documents '
            'WHERE source_url=? LIMIT 1',
            [sourceUrl]);
        documentId = row.isEmpty ? null : row.first['id'] as int;
      }
      if (documentId != null) return false;
      documentId = await txn.insert('documents', {
        'canonical_key': canonicalKey,
        'title': title,
        'title_norm': compact(title),
        'author': thread.author,
        'author_norm': compact(thread.author),
        'content': content,
        'category': category,
        'source_type': '百度贴吧',
        'forum': thread.forum,
        'mname': '',
        'zname': '',
        'published_at': date,
        'source_url': sourceUrl,
        'word': word,
        'hot_score': thread.maxAgree,
        'mentioned_books_json': mentionedJson,
      });
      await txn.execute(
          'INSERT OR IGNORE INTO document_sources('
          'document_id,source_kind,source_ref,source_url) VALUES(?,?,?,?)',
          [documentId, sourceKind, sourceRef, sourceUrl]);
      final searchable = StringBuffer('$title ${thread.author}');
      for (final book in books) {
        searchable.write(' ');
        searchable.write(book);
      }
      await txn.execute('DELETE FROM search_idx WHERE rowid=?', [documentId]);
      await txn.execute('INSERT INTO search_idx(rowid,tokens) VALUES(?,?)',
          [documentId, AppDatabase.buildFtsQuery(searchable.toString())]);
      await _adjustBookIndex(
          txn, title, mentionedJson, '百度贴吧', date, documentId);
      await txn.execute(
          'INSERT OR IGNORE INTO network_threads('
          'document_id,tid,forum,reply_count,view_count,agree_max,collected_at) '
          'VALUES(?,?,?,?,?,?,?)',
          [
            documentId,
            thread.tid,
            thread.forum,
            thread.replyNum,
            thread.viewNum,
            thread.maxAgree,
            DateTime.now().toIso8601String()
          ]);
      return true;
    });
  }

  Future<int?> _idForKey(DatabaseExecutor txn, String key) async {
    final rows = await txn.rawQuery(
        'SELECT id FROM documents WHERE canonical_key=? LIMIT 1', [key]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<void> _adjustBookIndex(
      DatabaseExecutor txn,
      String title,
      String mentionedJson,
      String sourceType,
      String date,
      int documentId) async {
    for (final entry in _candidateBookTitles(title, mentionedJson).entries) {
      final norm = entry.key;
      final display = entry.value;
      final exists = await txn
          .rawQuery('SELECT 1 FROM books WHERE title_norm=? LIMIT 1', [norm]);
      if (exists.isEmpty) {
        await txn.insert('books', {
          'title_norm': norm,
          'title': display,
          'review_count': 1,
          'best_document_id': documentId,
          'latest_at': date,
          'sources_json': jsonEncode([sourceType]),
        });
      } else {
        await txn.execute(
            'UPDATE books SET review_count=review_count+1,'
            'latest_at=CASE WHEN latest_at IS NULL OR latest_at<? '
            'THEN ? ELSE latest_at END WHERE title_norm=?',
            [date, date, norm]);
      }
    }
  }

  Map<String, String> _candidateBookTitles(String title, String mentionedJson) {
    final candidates = <String, String>{};
    final cleanTitle = title.replaceAll(RegExp(r'^《|》$'), '').trim();
    final looksLikePost =
        RegExp('(近期|记录|书单|推荐|求书|合集|杂谈|吐槽|楼中楼)').hasMatch(cleanTitle);
    if (cleanTitle.length >= 2 && cleanTitle.length <= 80 && !looksLikePost) {
      candidates[TiebaImporter.compact(cleanTitle)] = cleanTitle;
    }
    try {
      final books = jsonDecode(mentionedJson);
      if (books is List) {
        for (final raw in books) {
          final book = raw.toString().replaceAll(RegExp(r'^《|》$'), '').trim();
          if (book.length >= 2 && book.length <= 80) {
            final norm = compact(book);
            candidates.putIfAbsent(norm, () => book);
          }
        }
      }
    } catch (_) {}
    return candidates;
  }

  // ---------- 启发式（与原生一致） ----------

  static Set<String> extractBooks(String text) {
    final result = <String>{};
    for (final match in RegExp('《([^《》\\n]{1,80})》').allMatches(text)) {
      final book = match.group(1)!.trim();
      if (book.length >= 2) result.add(book);
    }
    for (final match
        in RegExp(r'^\s*书名\s*[:：]\s*([^\n]{2,80})', multiLine: true)
            .allMatches(text)) {
      final book = match.group(1)!.trim();
      if (book.length >= 2 && book.length <= 80) result.add(book);
    }
    return result;
  }

  static String titleBookCandidate(String title) {
    var value = title.trim();
    value = value
        .replaceFirst(RegExp(r'^(?:扫书|推书|排雷|避雷|推荐|吐槽|书评)\s*[:：\-]?\s*'), '')
        .trim();
    if (value.length < 2 || value.length > 50) return '';
    if (RegExp('(吧规|吧务|专用贴|怎么|为什么|有人|求书|求推|推荐|记录|书单|合集|作者|问题|吗|？|\\?)')
        .hasMatch(value)) {
      return '';
    }
    return value;
  }

  static String classifyPost(String title, String content) {
    final text = '$title\n$content';
    if (RegExp('(排雷|避雷|雷点|毒点|郁闷点|防御建议)').hasMatch(text)) return '排雷';
    if (RegExp('(求书|求扫|求推|书荒)').hasMatch(text)) return '求书';
    if (RegExp('(推书|推荐|安利|值得一看)').hasMatch(text)) return '推书';
    return '扫书';
  }

  static String networkDate(int epochSeconds) {
    if (epochSeconds <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true)
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
  }

  static String compact(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\p{P}\p{S}\s]+', unicode: true), '');

  static String cleanDisplayTitle(String value) {
    var title = value
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\u200b', '')
        .trim();
    title = title.replaceAll(RegExp(r'\s*[·•]\s*楼中楼\s*$'), '');
    title = title.replaceFirst(RegExp(r'^\s*(?:回复|楼中楼)\s*[:：]\s*'), '');
    title = title.replaceFirst(RegExp(r'^\s*[（(]?再补档[）)]?\s*'), '');
    title = title.replaceFirst(RegExp(r'^\s*【\s*Time\s*[:：].*?】\s*'), '');
    title = title.replaceAll(
        RegExp(r'\[(?:图片|image)\]|看高清大图[，,]?\s*打开贴吧App', caseSensitive: false),
        '');
    title = title.replaceAll(RegExp(r'_20\d{6}_\d{6}\s*$'), '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'\s+([,，。.!！？:：;；])'), r'$1');
    title = title.replaceAll(RegExp(r'^[\s·•\-—_]+|[\s·•\-—_]+$'), '');
    return title.isEmpty ? '未命名内容' : title;
  }
}

/// 导入记录删除：移除 document 及其全部关联行，并回退书目计数。
Future<bool> deleteImportedThread(Database db, int documentId) async {
  final rows = await db.rawQuery(
      'SELECT title, mentioned_books_json, word FROM documents WHERE id=? LIMIT 1',
      [documentId]);
  if (rows.isEmpty) return false;
  final title = rows.first['title'] as String? ?? '';
  final mentioned = rows.first['mentioned_books_json'] as String? ?? '';
  await db.transaction((txn) async {
    await txn.delete('document_sources',
        where: 'document_id=?', whereArgs: [documentId]);
    await txn.delete('network_threads',
        where: 'document_id=?', whereArgs: [documentId]);
    await txn.delete('search_idx', where: 'rowid=?', whereArgs: [documentId]);
    await txn.delete('documents', where: 'id=?', whereArgs: [documentId]);
    for (final entry in _candidateBookTitlesStatic(title, mentioned).entries) {
      await txn.execute(
          'UPDATE books SET review_count=review_count-1 WHERE title_norm=?',
          [entry.key]);
      await txn.execute(
          'DELETE FROM books WHERE title_norm=? AND review_count<=0',
          [entry.key]);
    }
  });
  return true;
}

Map<String, String> _candidateBookTitlesStatic(
    String title, String mentionedJson) {
  final candidates = <String, String>{};
  final cleanTitle = title.replaceAll(RegExp(r'^《|》$'), '').trim();
  final looksLikePost =
      RegExp('(近期|记录|书单|推荐|求书|合集|杂谈|吐槽|楼中楼)').hasMatch(cleanTitle);
  if (cleanTitle.length >= 2 && cleanTitle.length <= 80 && !looksLikePost) {
    candidates[TiebaImporter.compact(cleanTitle)] = cleanTitle;
  }
  try {
    final books = jsonDecode(mentionedJson);
    if (books is List) {
      for (final raw in books) {
        final book = raw.toString().replaceAll(RegExp(r'^《|》$'), '').trim();
        if (book.length >= 2 && book.length <= 80) {
          candidates.putIfAbsent(TiebaImporter.compact(book), () => book);
        }
      }
    }
  } catch (_) {}
  return candidates;
}

/// 备份恢复用：把一条已导入帖子的书目计数补进 books 索引。
Future<void> applyBookIndexForRestore(
    DatabaseExecutor txn,
    String title,
    String mentionedJson,
    String sourceType,
    String date,
    int documentId) async {
  for (final entry
      in _candidateBookTitlesStatic(title, mentionedJson).entries) {
    final exists = await txn.rawQuery(
        'SELECT 1 FROM books WHERE title_norm=? LIMIT 1', [entry.key]);
    if (exists.isEmpty) {
      await txn.insert('books', {
        'title_norm': entry.key,
        'title': entry.value,
        'review_count': 1,
        'best_document_id': documentId,
        'latest_at': date,
        'sources_json': jsonEncode([sourceType]),
      });
    } else {
      await txn.execute(
          'UPDATE books SET review_count=review_count+1,'
          'latest_at=CASE WHEN latest_at IS NULL OR latest_at<? '
          'THEN ? ELSE latest_at END WHERE title_norm=?',
          [date, date, entry.key]);
    }
  }
}

/// 备份恢复用：导出全部已导入的贴吧帖子（含来源与统计元数据）。
Future<List<Map<String, Object?>>> exportImportedPosts(Database db) async {
  final rows = await db.rawQuery(
      'SELECT d.canonical_key,d.title,d.title_norm,d.author,d.author_norm,'
      'd.content,d.category,d.source_type,d.forum,d.mname,d.zname,'
      'd.published_at,d.source_url,d.word,d.hot_score,d.mentioned_books_json,'
      'n.tid,n.forum AS thread_forum,n.reply_count,n.view_count,n.agree_max,'
      'n.collected_at '
      'FROM network_threads n JOIN documents d ON d.id=n.document_id '
      'WHERE d.id NOT IN (SELECT document_id FROM local_deleted) '
      'ORDER BY n.collected_at ASC');
  return rows;
}

/// 备份恢复用：按 canonical_key 去重写入帖子，返回新增条数。
Future<int> importPostsFromBackup(
    Database db, List<Map<String, Object?>> posts) async {
  var added = 0;
  for (final post in posts) {
    final key = post['canonical_key'] as String? ?? '';
    if (key.isEmpty) continue;
    final exists = await db.rawQuery(
        'SELECT id FROM documents WHERE canonical_key=? LIMIT 1', [key]);
    if (exists.isNotEmpty) continue;
    await db.transaction((txn) async {
      final id = await txn.insert('documents', {
        'canonical_key': key,
        'title': post['title'] ?? '',
        'title_norm': post['title_norm'] ?? '',
        'author': post['author'] ?? '',
        'author_norm': post['author_norm'] ?? '',
        'content': post['content'] ?? '',
        'category': post['category'] ?? '扫书',
        'source_type': post['source_type'] ?? '百度贴吧',
        'forum': post['forum'] ?? '',
        'mname': post['mname'] ?? '',
        'zname': post['zname'] ?? '',
        'published_at': post['published_at'] ?? '',
        'source_url': post['source_url'] ?? '',
        'word': post['word'] ?? 0,
        'hot_score': post['hot_score'] ?? 0,
        'mentioned_books_json': post['mentioned_books_json'] ?? '[]',
      });
      final title = post['title'] as String? ?? '';
      final mentioned = post['mentioned_books_json'] as String? ?? '[]';
      await txn.execute(
          'INSERT OR IGNORE INTO document_sources('
          'document_id,source_kind,source_ref,source_url) VALUES(?,?,?,?)',
          [
            id,
            TiebaImporter.sourceKind,
            (post['tid'] ?? '').toString(),
            post['source_url'] ?? ''
          ]);
      await txn.execute(
          'INSERT OR IGNORE INTO network_threads('
          'document_id,tid,forum,reply_count,view_count,agree_max,collected_at) '
          'VALUES(?,?,?,?,?,?,?)',
          [
            id,
            post['tid'] ?? 0,
            post['thread_forum'] ?? '',
            post['reply_count'] ?? 0,
            post['view_count'] ?? 0,
            post['agree_max'] ?? 0,
            post['collected_at'] ?? DateTime.now().toIso8601String(),
          ]);
      final searchable = StringBuffer('$title ${post['author'] ?? ''}');
      try {
        final books = jsonDecode(mentioned);
        if (books is List) {
          for (final book in books) {
            searchable.write(' ');
            searchable.write(book.toString());
          }
        }
      } catch (_) {}
      await txn.execute('DELETE FROM search_idx WHERE rowid=?', [id]);
      await txn.execute('INSERT INTO search_idx(rowid,tokens) VALUES(?,?)',
          [id, AppDatabase.buildFtsQuery(searchable.toString())]);
      await applyBookIndexForRestore(
          txn,
          title,
          mentioned,
          post['source_type'] as String? ?? '百度贴吧',
          post['published_at'] as String? ?? '',
          id);
    });
    added++;
  }
  return added;
}
