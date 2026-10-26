import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 敏感凭据的加密存储（Android Keystore 支持）。
///
/// 贴吧 BDUSS 与 WebDAV 密码不再明文存入 SharedPreferences。
/// 启动时一次性把旧明文迁移过来并删除；读取走内存缓存以便 UI 同步使用。
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 需要从明文迁移的旧键。
  static const _legacyKeys = ['tieba_bduss', 'webdav_pass'];

  static final Map<String, String> _cache = {};

  /// 启动时调用：加载已加密的凭据，并迁移旧的明文值。
  static Future<void> init(SharedPreferences prefs) async {
    for (final key in _legacyKeys) {
      try {
        final value = await _storage.read(key: key);
        if (value != null) {
          _cache[key] = value;
          continue;
        }
        final legacy = prefs.getString(key);
        if (legacy != null && legacy.isNotEmpty) {
          await _storage.write(key: key, value: legacy);
          _cache[key] = legacy;
          await prefs.remove(key);
        }
      } catch (_) {
        // 密钥库不可用时退回明文读取，保证功能可用。
        final fallback = prefs.getString(key);
        if (fallback != null) _cache[key] = fallback;
      }
    }
  }

  /// 同步读取（init 之后可用）。
  static String get(String key) => _cache[key] ?? '';

  static Future<void> set(String key, String value) async {
    if (value.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    try {
      if (value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // 写失败时缓存仍保留，本次会话可用。
    }
  }
}
