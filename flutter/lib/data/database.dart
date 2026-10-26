import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/tieba_import.dart';
import 'models.dart';

/// 随包数据库接入层。
///
/// 数据连续性：原生版把私有库放在 files/saoshu.db（getApplicationSupportDirectory），
/// Flutter 版优先复用同一路径——覆盖安装后收藏、简记、采集数据与 FTS 索引全部保留；
/// 全新安装则从 assets 拷贝并重建本地表与 FTS。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const int dbAssetVersion = 16;

  Database? _db;
  final List<void Function(String)> _statusListeners = [];

  void onStatus(void Function(String message) listener) =>
      _statusListeners.add(listener);

  void removeStatusListener(void Function(String message) listener) =>
      _statusListeners.remove(listener);

  void _status(String message) {
    for (final listener in _statusListeners) {
      listener(message);
    }
  }

  Future<Database> get database async => _db ??= await _open();

  Future<String> _candidatePaths() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'saoshu.db');
  }

  Future<Database> _open() async {
    final path = await _candidatePaths();
    final file = File(path);
    final usable = file.existsSync() && file.lengthSync() > 65536;
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getInt('db_asset_version') ?? -1;

    // 全新安装：直接解压。
    if (!usable) {
      _status('正在准备随包数据库…');
      await _copyFromAssets(path);
    } else if (installed != dbAssetVersion) {
      // 库版本更新：重拷随包库，并迁移用户数据（简记/收藏/导入帖）。
      _status('正在更新随包数据库…');
      final oldDb = await openDatabase(path);
      final notes =
          await oldDb.query('user_notes', where: 'deleted_at IS NULL');
      final imported = await exportImportedPosts(oldDb);
      final favoriteIds = prefs.getStringList('favorite_ids') ?? [];
      await oldDb.close();
      await File(path).delete();
      await _copyFromAssets(path);
      final db = await openDatabase(path);
      await _initializeLocalSchema(db);
      _status('正在恢复用户数据…');
      await db.transaction((txn) async {
        for (final note in notes) {
          await txn.insert('user_notes', note,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      final idMap = await importPostsFromBackup(db,
          imported.map((e) => Map<String, Object?>.from(e as Map)).toList());
      final translated = favoriteIds.map((id) {
        final parsed = int.tryParse(id);
        return parsed != null && idMap.containsKey(parsed)
            ? idMap[parsed].toString()
            : id;
      }).toList();
      await prefs.setStringList('favorite_ids', translated);
      await prefs.setInt('db_asset_version', dbAssetVersion);
      _status('数据库已更新');
      return db;
    }
    await prefs.setInt('db_asset_version', dbAssetVersion);
    final db = await openDatabase(path);
    await _initializeLocalSchema(db);
    return db;
  }

  /// 资产以 gzip 存储（130MB，约为原始 33%），流式解压写盘，
  /// 避免一次性载入 332MB 原始字节（低内存设备友好）。
  Future<void> _copyFromAssets(String target) async {
    _status('正在解压随包数据库…');
    final data = await rootBundle.load('assets/saoshu.db.gz');
    final compressed =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final sink = File(target).openWrite();
    try {
      await ZLibDecoder()
          .bind(Stream<Uint8List>.fromIterable([compressed]))
          .pipe(sink);
    } catch (error) {
      await sink.close();
      final partial = File(target);
      if (partial.existsSync()) {
        await partial.delete();
      }
      rethrow;
    }
    _status('数据库就绪');
  }

  Future<void> _initializeLocalSchema(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS local_deleted ('
        'document_id INTEGER PRIMARY KEY, deleted_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS user_notes ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'title TEXT NOT NULL,'
        'content TEXT NOT NULL,'
        'created_at TEXT NOT NULL,'
        'updated_at TEXT NOT NULL,'
        'pinned INTEGER NOT NULL DEFAULT 0,'
        'deleted_at TEXT)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS user_notes_updated_idx ON user_notes(updated_at DESC)');
    await db.execute('CREATE TABLE IF NOT EXISTS collector_forums ('
        'fname TEXT PRIMARY KEY,'
        'fid INTEGER NOT NULL DEFAULT 0,'
        'enabled INTEGER NOT NULL DEFAULT 1,'
        'last_thread_time INTEGER NOT NULL DEFAULT 0,'
        'last_tid INTEGER NOT NULL DEFAULT 0,'
        'last_run_at TEXT,'
        'last_status TEXT NOT NULL DEFAULT \'never\','
        'last_error TEXT,'
        'consecutive_failures INTEGER NOT NULL DEFAULT 0,'
        'cooldown_until INTEGER NOT NULL DEFAULT 0,'
        'total_threads INTEGER NOT NULL DEFAULT 0,'
        'total_floors INTEGER NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS collector_logs ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'fname TEXT NOT NULL,'
        'run_at TEXT NOT NULL,'
        'status TEXT NOT NULL,'
        'threads_added INTEGER NOT NULL DEFAULT 0,'
        'floors_added INTEGER NOT NULL DEFAULT 0,'
        'skipped_dup INTEGER NOT NULL DEFAULT 0,'
        'detail TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS network_threads ('
        'document_id INTEGER PRIMARY KEY,'
        'tid INTEGER NOT NULL UNIQUE,'
        'forum TEXT NOT NULL,'
        'reply_count INTEGER NOT NULL DEFAULT 0,'
        'view_count INTEGER NOT NULL DEFAULT 0,'
        'agree_max INTEGER NOT NULL DEFAULT 0,'
        'collected_at TEXT NOT NULL)');
    await db.execute('CREATE INDEX IF NOT EXISTS network_threads_forum_idx '
        'ON network_threads(forum,collected_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS collector_logs_run_idx ON collector_logs(run_at DESC)');
    await db.execute(
        "INSERT OR IGNORE INTO collector_forums(fname,enabled) VALUES('yy小说吧',1)");
    await db.execute(
        "INSERT OR IGNORE INTO collector_forums(fname,enabled) VALUES('哀伤雪刃',1)");
    await db.execute('CREATE INDEX IF NOT EXISTS documents_forum_idx '
        'ON documents(forum)');
    await db.execute('CREATE INDEX IF NOT EXISTS documents_category_idx '
        'ON documents(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS documents_category_date_idx '
        'ON documents(category, published_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS books_review_id_idx '
        'ON books(review_count DESC,id DESC)');
    final hasIndex = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='search_idx' LIMIT 1");
    if (hasIndex.isEmpty) {
      await _buildSearchIndex(db);
    }
  }

  Future<void> _buildSearchIndex(Database db) async {
    _status('正在生成本地搜索索引…');
    final totalRow = await db.rawQuery('SELECT count(*) c FROM documents');
    final total = (totalRow.first['c'] as int? ?? 1).clamp(1, 1 << 40);
    await db.execute(
        'CREATE VIRTUAL TABLE search_idx USING fts4(tokens, tokenize=simple)');
    var done = 0;
    await db.transaction((txn) async {
      final rows = await txn.query('documents',
          columns: ['id', 'title', 'author', 'mentioned_books_json']);
      var batch = txn.batch();
      for (final row in rows) {
        final id = row['id'] as int;
        final searchable = StringBuffer()
          ..write(row['title'] ?? '')
          ..write(' ')
          ..write(row['author'] ?? '');
        try {
          final decoded =
              jsonDecode((row['mentioned_books_json'] ?? '') as String);
          if (decoded is List) {
            for (final book in decoded) {
              searchable.write(' ');
              searchable.write(book.toString());
            }
          }
        } catch (_) {}
        batch.execute('INSERT INTO search_idx(rowid,tokens) VALUES(?,?)',
            [id, buildFtsQuery(searchable.toString())]);
        done++;
        if (done % 2000 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
          _status('正在生成本地搜索索引 ${done * 100 ~/ total}%');
        }
      }
      await batch.commit(noResult: true);
    });
    _status('搜索索引完成');
  }

  /// 与原生版一致的 bigram 分词：中文按二元词组，其他按整块。
  static String buildFtsQuery(String input) {
    final tokens = <String>{};
    final chunkPattern = RegExp(r'[\u4e00-\u9fff]+|[a-z0-9]+');
    for (final match in chunkPattern.allMatches(input.toLowerCase())) {
      final chunk = match.group(0)!;
      final isCjk = RegExp(r'^[\u4e00-\u9fff]+$').hasMatch(chunk);
      if (isCjk) {
        if (chunk.length == 1) {
          tokens.add(chunk);
        } else {
          for (var i = 0; i < chunk.length - 1; i++) {
            tokens.add(chunk.substring(i, i + 2));
          }
        }
      } else {
        tokens.add(chunk);
      }
    }
    return tokens.join(' ');
  }

  // ---------- 查询 ----------

  Future<int> documentCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT count(*) c FROM documents WHERE id NOT IN '
            '(SELECT document_id FROM local_deleted)');
    return rows.first['c'] as int? ?? 0;
  }

  Future<int> bookCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT count(*) c FROM books');
    return rows.first['c'] as int? ?? 0;
  }

  Future<int> sourceCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT count(*) c FROM document_sources');
    return rows.first['c'] as int? ?? 0;
  }

  Future<List<Document>> randomHomeDocuments({int limit = 12}) async {
    final db = await database;
    final rows = await db.rawQuery(
        "SELECT * FROM documents WHERE category IN ('扫书','推书','排雷') "
        'AND length(content)>=20 '
        'AND id NOT IN (SELECT document_id FROM local_deleted) '
        'ORDER BY RANDOM() LIMIT ?',
        [limit]);
    return rows.map(Document.fromRow).toList();
  }

  Future<Document?> loadDocument(int id) async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT * FROM documents WHERE id=? LIMIT 1', [id]);
    return rows.isEmpty ? null : Document.fromRow(rows.first);
  }

  Future<int?> adjacentDocumentId(Document current, bool newer) async {
    final db = await database;
    final date = current.date;
    final sql = newer
        ? 'SELECT id FROM documents WHERE '
            '(published_at>? OR (published_at=? AND id<?)) '
            'AND id NOT IN (SELECT document_id FROM local_deleted) '
            'ORDER BY published_at ASC,id DESC LIMIT 1'
        : 'SELECT id FROM documents WHERE '
            '(published_at<? OR (published_at=? AND id>?)) '
            'AND id NOT IN (SELECT document_id FROM local_deleted) '
            'ORDER BY published_at DESC,id ASC LIMIT 1';
    final rows = await db.rawQuery(sql, [date, date, current.id]);
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<List<Document>> searchDocuments(String query,
      {bool fullText = false, int limit = 50, int offset = 0}) async {
    final db = await database;
    if (query.isEmpty) {
      final rows = await db.rawQuery(
          'SELECT * FROM documents WHERE id NOT IN '
          '(SELECT document_id FROM local_deleted) '
          'ORDER BY published_at DESC,id DESC LIMIT ? OFFSET ?',
          [limit, offset]);
      return rows.map(Document.fromRow).toList();
    }
    final like = '%$query%';
    final tokens = buildFtsQuery(query);
    var sql = 'SELECT d.* FROM documents d';
    final args = <Object>[];
    if (!fullText && tokens.isNotEmpty) {
      sql += ' JOIN search_idx s ON s.docid=d.id';
    }
    sql += ' WHERE d.id NOT IN (SELECT document_id FROM local_deleted)';
    if (fullText) {
      sql += ' AND (d.title LIKE ? OR d.author LIKE ? OR d.content LIKE ?)';
      args.addAll([like, like, like]);
    } else if (tokens.isNotEmpty) {
      sql += ' AND s.tokens MATCH ?';
      args.add(tokens);
    } else {
      sql +=
          ' AND (d.title LIKE ? OR d.author LIKE ? OR d.mentioned_books_json LIKE ?)';
      args.addAll([like, like, like]);
    }
    sql +=
        ' ORDER BY CASE WHEN d.title LIKE ? THEN 0 WHEN d.author LIKE ? THEN 1 ELSE 2 END,'
        ' d.published_at DESC,d.hot_score DESC,d.id DESC LIMIT ? OFFSET ?';
    args.addAll([like, like, limit, offset]);
    var rows = await db.rawQuery(sql, args);
    if (rows.isEmpty && !fullText) {
      // 与原生版一致：标题命中为空时回退正文 LIKE。
      rows = await db.rawQuery(
          'SELECT * FROM documents WHERE '
          '(title LIKE ? OR author LIKE ? OR content LIKE ?) '
          'AND id NOT IN (SELECT document_id FROM local_deleted) '
          'ORDER BY published_at DESC,hot_score DESC,id DESC LIMIT ? OFFSET ?',
          [like, like, like, limit, offset]);
    }
    return rows.map(Document.fromRow).toList();
  }

  // ---------- 分类浏览（来源 / 帖子类型） ----------

  Future<List<Map<String, Object?>>> forumsWithCounts() async {
    final db = await database;
    final rows = await db
        .rawQuery('SELECT forum, count(*) c FROM documents WHERE forum != '
            ' '
            'AND id NOT IN (SELECT document_id FROM local_deleted) '
            'GROUP BY forum ORDER BY c DESC');
    return rows;
  }

  Future<List<Map<String, Object?>>> categoriesWithCounts() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT category, count(*) c FROM documents '
        'WHERE id NOT IN (SELECT document_id FROM local_deleted) '
        'GROUP BY category ORDER BY c DESC');
    return rows;
  }

  Future<List<Document>> documentsByForum(String forum,
      {int limit = 40, int offset = 0}) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT * FROM documents WHERE forum=? '
        'AND id NOT IN (SELECT document_id FROM local_deleted) '
        'ORDER BY published_at DESC,id DESC LIMIT ? OFFSET ?',
        [forum, limit, offset]);
    return rows.map(Document.fromRow).toList();
  }

  /// since/until: 'yyyy-MM-dd' 日期上下限（published_at 同格式，字符串比较）。
  /// until 为开区间下界（次月 1 日），可完整覆盖所选月份。
  Future<List<Document>> documentsByCategory(String category,
      {int limit = 20, int offset = 0, String? since, String? until}) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT * FROM documents WHERE category=? '
        'AND id NOT IN (SELECT document_id FROM local_deleted) '
        "AND (? IS NULL OR published_at >= ?) "
        "AND (? IS NULL OR published_at < ?) "
        'ORDER BY published_at DESC,id DESC LIMIT ? OFFSET ?',
        [category, since, since, until, until, limit, offset]);
    return rows.map(Document.fromRow).toList();
  }

  Future<List<Document>> favoritesDocuments(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT * FROM documents WHERE id IN ($placeholders) '
        'AND id NOT IN (SELECT document_id FROM local_deleted) '
        'ORDER BY published_at DESC,id DESC',
        ids);
    return rows.map(Document.fromRow).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
