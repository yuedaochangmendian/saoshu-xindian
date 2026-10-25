import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用偏好：包装 SharedPreferences，并提供原生版（Java）数据的一次性迁移。
///
/// 原生版收藏存在 saoshu_prefs.xml 的 favorite_ids 字符串集合里，
/// Flutter 的 SharedPreferences 使用另一个存储文件，需手动搬运。
class AppPrefs {
  static const _migratedKey = 'native_prefs_migrated';

  /// 全局引用（启动时注入，供无 context 的场景使用）。
  static SharedPreferences? instance;

  Future<SharedPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    instance = prefs;
    await _migrateNativePrefs(prefs);
    return prefs;
  }

  Future<void> _migrateNativePrefs(SharedPreferences prefs) async {
    if (prefs.getBool(_migratedKey) ?? false) return;
    try {
      final support = await getApplicationSupportDirectory();
      final native =
          File('${support.parent.path}/shared_prefs/saoshu_prefs.xml');
      if (native.existsSync()) {
        final xml = native.readAsStringSync();
        _migrateFavoriteIds(prefs, xml);
        _migrateString(prefs, xml, 'theme_id', 'theme_id');
        _migrateBool(prefs, xml, 'haptic_enabled', 'haptic_enabled');
        _migrateBool(prefs, xml, 'dock_frosted', 'dock_frosted');
      }
    } catch (_) {}
    await prefs.setBool(_migratedKey, true);
  }

  void _migrateFavoriteIds(SharedPreferences prefs, String xml) {
    final start = xml.indexOf('name="favorite_ids"');
    if (start < 0) return;
    final end = xml.indexOf('</string-set>', start);
    if (end < 0) return;
    final body = xml.substring(start, end);
    final ids = RegExp(r'<string>(\d+)</string>')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
    if (ids.isNotEmpty) {
      prefs.setStringList('favorite_ids', ids.toList());
    }
  }

  void _migrateString(
      SharedPreferences prefs, String xml, String nativeKey, String key) {
    final match =
        RegExp('<string name="$nativeKey">([^<]*)</string>').firstMatch(xml);
    if (match != null) {
      prefs.setString(key, match.group(1)!);
    }
  }

  void _migrateBool(
      SharedPreferences prefs, String xml, String nativeKey, String key) {
    final match = RegExp('<boolean name="$nativeKey" value="(true|false)" />')
        .firstMatch(xml);
    if (match != null) {
      prefs.setBool(key, match.group(1) == 'true');
    }
  }
}

/// 收藏状态的统一读写（与原生版同键名 favorite_ids）。
class Favorites extends ChangeNotifierX {
  final SharedPreferences prefs;
  final List<String> _ids;

  Favorites(this.prefs) : _ids = prefs.getStringList('favorite_ids') ?? [];

  List<String> get ids => List.unmodifiable(_ids);

  bool contains(int id) => _ids.contains(id.toString());

  void toggle(int id) {
    final key = id.toString();
    if (_ids.contains(key)) {
      _ids.remove(key);
    } else {
      _ids.insert(0, key);
    }
    prefs.setStringList('favorite_ids', _ids);
    notify();
  }
}

/// 极简可监听对象（避免引入额外状态管理依赖）。
class ChangeNotifierX {
  final List<void Function()> _listeners = [];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
