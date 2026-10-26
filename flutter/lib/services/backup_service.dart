import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 用户数据备份（JSON）：收藏、简记、设置。
/// 内容型数据（documents）随包分发，不入备份；导入的帖子可通过重新抓取恢复。
class BackupService {
  static const formatVersion = 1;
  static const fileNamePattern = 'saoshu_backup_';

  /// 本地备份目录（应用专属外部存储，无需权限）。
  static Future<Directory> backupDirectory() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory(
        '${base?.path ?? (await getApplicationSupportDirectory()).path}/backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<Map<String, Object?>> buildSnapshot(
      SharedPreferences prefs, Database db) async {
    final notes = await db.query('user_notes',
        where: 'deleted_at IS NULL', orderBy: 'id ASC');
    return {
      'format': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'favorites': prefs.getStringList('favorite_ids') ?? [],
      'notes': notes,
      'prefs': {
        'theme_id': prefs.getString('theme_id') ?? 'teal',
        'haptic_enabled': prefs.getBool('haptic_enabled') ?? false,
        'dock_frosted': prefs.getBool('dock_frosted') ?? false,
        'download_mirror': prefs.getString('download_mirror') ?? 'direct',
      },
    };
  }

  static Future<String> createLocalBackup(
      SharedPreferences prefs, Database db) async {
    final snapshot = await buildSnapshot(prefs, db);
    final dir = await backupDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-]'), '')
        .substring(0, 15);
    final file = File('${dir.path}/$fileNamePattern$stamp.json');
    await file.writeAsString(jsonEncode(snapshot), flush: true);
    return file.path;
  }

  static Future<List<File>> listLocalBackups() async {
    try {
      final dir = await backupDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.contains(fileNamePattern) && f.path.endsWith('.json'))
          .toList();
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// 从备份 JSON 恢复。返回摘要 {favorites: n, notesAdded: n}。
  static Future<Map<String, int>> restoreFromContent(
      String content, SharedPreferences prefs, Database db) async {
    final data = jsonDecode(content) as Map<String, Object?>;
    final favorites = ((data['favorites'] ?? const []) as List)
        .map((e) => e.toString())
        .toList();
    final notes = (data['notes'] ?? const []) as List;
    final savedPrefs = (data['prefs'] ?? {}) as Map<String, Object?>;

    await db.transaction((txn) async {
      for (final raw in notes) {
        final note = raw as Map<String, Object?>;
        await txn.insert(
            'user_notes',
            {
              'id': note['id'],
              'title': note['title'] ?? '',
              'content': note['content'] ?? '',
              'created_at': note['created_at'] ?? '',
              'updated_at': note['updated_at'] ?? '',
              'pinned': note['pinned'] ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await prefs.setStringList('favorite_ids', favorites);
    // 调用方需随后调用 Favorites.reload() 刷新内存缓存。
    savedPrefs.forEach((key, value) {
      if (value is String) {
        prefs.setString(key, value);
      } else if (value is bool) {
        prefs.setBool(key, value);
      }
    });
    return {'favorites': favorites.length, 'notesAdded': notes.length};
  }

  static String summaryLabel(File file) {
    final stat = file.statSync();
    final stamp =
        stat.modified.toIso8601String().substring(0, 16).replaceAll('T', ' ');
    return '$stamp · ${(stat.size / 1024).toStringAsFixed(1)} KB';
  }
}
