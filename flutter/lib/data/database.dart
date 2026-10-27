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

  static const int dbAssetVersion = 18;

  Database? _db;
  final List<void Function(String)> _statusListeners = [];

  /// SharedPreferences 便捷访问（供浏览进度等模块）。
  Future<SharedPreferences> get sharedPrefs =>
      SharedPreferences.getInstance();

  void onStatus(void Function(String message) listener) =>
      _statusListeners.add(listener);

  void removeStatusListener(void Function(String message) listener) =>
      _statusListeners.remove(listener);

  void _status(String message) {
    for (final listener in _statusListeners) {
      listener(message);
    }
  }

  /// 打开中的单飞 future：冷启动首页 Future.wait 三连查会并发进入
  /// getter，无锁时三个 _open() 同时对同一文件解压/建表（首装库损坏、
  /// FTS 二次 CREATE 抛错、句柄泄漏）。
  Future<Database>? _opening;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<String> _candidatePaths() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'saoshu.db');
  }

  Future<Database> _open() async {
    final path = await _candidatePaths();
    final file = File(path);
    final migrating = File('$path.migrating');
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getInt('db_asset_version') ?? -1;

    // 半截库自愈：解压/迁移中断留下的文件能过 size 检查但打不开
    // （SQLite 头损坏或 user_notes 缺失），一律视为不可用重拷。
    var usable = file.existsSync() && file.lengthSync() > 65536;
    if (usable && installed != dbAssetVersion) {
      usable = await _probeUsable(path);
    }

    if (!usable) {
      if (migrating.existsSync()) {
        // 上次迁移在「重拷/回填」窗口被杀：旧库快照还在 .migrating，
        // 用它重走迁移，用户数据（简记/导入帖/收藏）不丢。
        _status('检测到未完成的数据库迁移，正在恢复…');
        if (file.existsSync()) file.deleteSync();
        migrating.renameSync(path);
        return _migrate(path, prefs, installed);
      }
      // 全新安装（或半截库）：直接解压。
      _status('正在准备随包数据库…');
      if (file.existsSync()) file.deleteSync();
      await _copyFromAssets(path);
    } else if (installed != dbAssetVersion) {
      return _migrate(path, prefs, installed);
    }
    await prefs.setInt('db_asset_version', dbAssetVersion);
    final db = await openDatabase(path);
    await _initializeLocalSchema(db);
    return db;
  }

  /// 旧库能否安全打开并读出用户数据（半截库/损坏库探测）。
  Future<bool> _probeUsable(String path) async {
    Database? probe;
    try {
      probe = await openDatabase(path, readOnly: true);
      await probe.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='documents' LIMIT 1");
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await probe?.close();
      } catch (_) {}
    }
  }

  /// 版本迁移：导出用户数据 → 旧库改名 .migrating 保底 → 重拷资产 →
  /// 回填 → 收藏 id 翻译 → 全部成功才删快照。中途被杀由下次启动的
  /// .migrating 检测接管（见 _open）。
  Future<Database> _migrate(
      String path, SharedPreferences prefs, int installed) async {
    {
      // 库版本更新：重拷随包库，并迁移用户数据（简记/收藏/导入帖）。
      _status('正在更新随包数据库…');
      final oldDb = await openDatabase(path);
      List<Map<String, Object?>> notes = const [];
      List<Object?> imported = const [];
      try {
        notes = await oldDb.query('user_notes', where: 'deleted_at IS NULL');
        imported = await exportImportedPosts(oldDb);
      } catch (_) {
        // 旧库无用户表（理论不可达，_probeUsable 已挡）：按空迁移。
      }
      final favoriteIds = prefs.getStringList('favorite_ids') ?? [];
      await oldDb.close();
      // 重命名而非删除：迁移中途被杀时下次启动从 .migrating 恢复。
      final migrating = File('$path.migrating');
      if (migrating.existsSync()) migrating.deleteSync();
      File(path).renameSync(migrating.path);
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
      final (idMap, _) = await importPostsFromBackup(db,
          imported.map((e) => Map<String, Object?>.from(e as Map)).toList());
      final translated = favoriteIds.map((id) {
        final parsed = int.tryParse(id);
        return parsed != null && idMap.containsKey(parsed)
            ? idMap[parsed].toString()
            : id;
      }).toList();
      await prefs.setStringList('favorite_ids', translated);
      await prefs.setInt('db_asset_version', dbAssetVersion);
      // 迁移全部成功后才清理旧库快照。
      if (migrating.existsSync()) migrating.deleteSync();
      _status('数据库已更新');
      return db;
    }
  }

  /// 资产以 gzip 存储（约 130MB，原始库的 38%），分块流式解压写盘，
  /// 避免一次性载入 346MB 原始字节（低内存设备友好）。
  ///
  /// 兼容两种历史容器：标准 gzip（1f 8b 头，现行打包格式）与裸
  /// zlib（78 xx 头，早期版本）。dart:io 的 ZLibDecoder 默认只认
  /// zlib——gzip 必须剥掉定长头+可选字段后用 raw inflate。
  /// 切片全部用 Uint8List.view 共享原始缓冲，不解压不复制。
  Future<void> _copyFromAssets(String target) async {
    _status('正在解压随包数据库…');
    final data = await rootBundle.load('assets/saoshu.db.gz');
    final compressed = Uint8List.view(
        data.buffer, data.offsetInBytes, data.lengthInBytes);
    final ZLibDecoder decoder;
    var bodyOffset = 0;
    if (compressed.length > 2 &&
        compressed[0] == 0x1f &&
        compressed[1] == 0x8b) {
      bodyOffset = _gzipBodyOffset(compressed);
      decoder = ZLibDecoder(raw: true);
    } else {
      decoder = ZLibDecoder();
    }
    const chunkSize = 4 << 20;
    final chunks = <Uint8List>[];
    for (var off = bodyOffset; off < compressed.length;) {
      final end = (off + chunkSize).clamp(0, compressed.length);
      // 切片继续基于原始 ByteData.buffer，避免任何复制。
      chunks.add(Uint8List.view(data.buffer,
          data.offsetInBytes + off, end - off));
      off = end;
    }
    final sink = File(target).openWrite();
    try {
      await decoder
          .bind(Stream<Uint8List>.fromIterable(chunks))
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

  /// gzip：定长头 10 字节之后按 FLG 跳过 FEXTRA/FNAME/FCOMMENT/FHCRC，
  /// 返回 deflate 体偏移；**头部**截断即抛（宁失败勿写出坏库）。
  /// 注意：body 级截断 raw inflate 不报错（Z_BUF_ERROR 静默收尾）、
  /// gzip 尾 CRC 不校验——资产完整性由发布侧 roundtrip sha1 验证保证
  /// （见 AGENTS.md DB SOP），这里不做二次校验。
  int _gzipBodyOffset(Uint8List b) {
    if (b.length < 10) throw StateError('gzip header truncated');
    final flg = b[3];
    var i = 10;
    if ((flg & 0x04) != 0) {
      if (i + 2 > b.length) throw StateError('gzip FEXTRA truncated');
      i += 2 + (b[i] | (b[i + 1] << 8));
    }
    if ((flg & 0x08) != 0) {
      while (i < b.length && b[i] != 0) {
        i++;
      }
      i++;
    }
    if ((flg & 0x10) != 0) {
      while (i < b.length && b[i] != 0) {
        i++;
      }
      i++;
    }
    if ((flg & 0x02) != 0) i += 2;
    if (i >= b.length) throw StateError('gzip body missing');
    return i;
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
    await db.execute('CREATE INDEX IF NOT EXISTS '
        'documents_category_forum_idx '
        'ON documents(category, forum)');
    final hasIndex = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='search_idx' LIMIT 1");
    if (hasIndex.isEmpty) {
      await _buildSearchIndex(db);
      return;
    }
    // 空壳检测：上次建索引中途被杀会留下 0 行的 search_idx（DDL 在事务外
    // 已提交），存在性检查会永远跳过重建、搜索静默降级为全文 LIKE。
    final ftsRows = await db
        .rawQuery('SELECT count(*) c FROM search_idx')
        .then((r) => r.first['c'] as int? ?? 0)
        .catchError((_) => -1);
    if (ftsRows == 0) {
      final docRows = await db.rawQuery('SELECT count(*) c FROM documents');
      if ((docRows.first['c'] as int? ?? 0) > 0) {
        await db.execute('DROP TABLE IF EXISTS search_idx');
        await _buildSearchIndex(db);
      }
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
        .rawQuery("SELECT forum, count(*) c FROM documents WHERE forum != '' "
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
  /// forum 非空时限定来源贴吧/站点（分类浏览「来源索引」）。
  Future<List<Document>> documentsByCategory(String category,
      {int limit = 20,
      int offset = 0,
      String? since,
      String? until,
      String? forum}) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT * FROM documents WHERE category=? '
        'AND id NOT IN (SELECT document_id FROM local_deleted) '
        "AND (? IS NULL OR forum = ?) "
        "AND (? IS NULL OR published_at >= ?) "
        "AND (? IS NULL OR published_at < ?) "
        'ORDER BY published_at DESC,id DESC LIMIT ? OFFSET ?',
        [
          category, forum, forum, since, since, until, until, limit, offset
        ]);
    return rows.map(Document.fromRow).toList();
  }

  /// 当前分类下的来源列表（名称+条数），供「来源索引」面板。
  Future<List<Map<String, Object?>>> forumsForCategory(String category) async {
    final db = await database;
    return db.rawQuery(
        "SELECT forum, count(*) c FROM documents WHERE category=? "
        "AND forum IS NOT NULL AND forum != '' "
        'GROUP BY forum ORDER BY c DESC', [category]);
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
