import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'system_bridge.dart';

import '../network/tieba_import.dart';

/// 用户数据备份（JSON）：收藏、简记、设置，以及导入的贴吧帖子。
/// 随包内容库不纳入（体积 332 MiB，随 APK 分发）；凭据永不进备份。
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
    final posts = await exportImportedPosts(db);
    return {
      'format': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'favorites': prefs.getStringList('favorite_ids') ?? [],
      'notes': notes,
      'networkPosts': posts,
      'prefs': {
        'theme_id': prefs.getString('theme_id') ?? 'teal',
        'haptic_enabled': prefs.getBool('haptic_enabled') ?? false,
        'dock_frosted': prefs.getBool('dock_frosted') ?? false,
        'download_mirror': prefs.getString('download_mirror') ?? 'direct',
      },
    };
  }

  /// 创建本地备份。除应用私有目录（恢复列表读取）外，
  /// 同时镜像写入系统「下载/扫书新典」公共目录——卸载/清数据不丢，
  /// 文件管理器可直接拷走。返回 (私有路径, 公共路径或 null)。
  static Future<(String, String?)> createLocalBackup(
      SharedPreferences prefs, Database db) async {
    final snapshot = await buildSnapshot(prefs, db);
    final dir = await backupDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-]'), '')
        .substring(0, 15);
    final name = '$fileNamePattern$stamp.json';
    final file = File('${dir.path}/$name');
    final encoded = jsonEncode(snapshot);
    await file.writeAsString(encoded, flush: true);
    String? publicPath;
    try {
      final r = await SystemBridge.saveToDownloads(
          name, Uint8List.fromList(utf8.encode(encoded)));
      if (!r.startsWith('error:')) publicPath = r;
    } catch (_) {}
    return (file.path, publicPath);
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

  /// 从备份 JSON 恢复。返回摘要 {favorites, notesAdded, postsAdded}。
  static Future<Map<String, int>> restoreFromContent(
      String content, SharedPreferences prefs, Database db) async {
    final data = jsonDecode(content) as Map<String, Object?>;
    final favorites = ((data['favorites'] ?? const []) as List)
        .map((e) => e.toString())
        .toList();
    final notes = (data['notes'] ?? const []) as List;
    final posts = (data['networkPosts'] ?? const []) as List;
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
    final idMap = await importPostsFromBackup(
        db, posts.map((e) => Map<String, Object?>.from(e as Map)).toList());
    // 收藏 id 翻译：导入帖恢复后是新 id，按映射改写；未命中的保留
    // （对应随包库内容的收藏，其 id 与备份时相同）。
    final translated = favorites.map((id) {
      final parsed = int.tryParse(id);
      return parsed != null && idMap.containsKey(parsed)
          ? idMap[parsed].toString()
          : id;
    }).toList();
    await prefs.setStringList('favorite_ids', translated);
    // 调用方需随后调用 Favorites.reload() 刷新内存缓存。
    savedPrefs.forEach((key, value) {
      if (value is String) {
        prefs.setString(key, value);
      } else if (value is bool) {
        prefs.setBool(key, value);
      }
    });
    return {
      'favorites': translated.length,
      'notesAdded': notes.length,
      'postsAdded': idMap.values.where((newId) => newId > 0).length,
    };
  }

  static String summaryLabel(File file) {
    final stat = file.statSync();
    final stamp =
        stat.modified.toIso8601String().substring(0, 16).replaceAll('T', ' ');
    return '$stamp · ${(stat.size / 1024).toStringAsFixed(1)} KB';
  }
}
