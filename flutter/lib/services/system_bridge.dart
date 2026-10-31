import 'package:flutter/services.dart';

/// 原生壳层桥：读取应用版本、用系统浏览器打开链接。
class SystemBridge {
  static const _channel = MethodChannel('app/system');

  /// 返回 {version: '4.0.0-pre17', build: 86}；失败返回 null。
  static Future<Map<String, Object?>?> appVersion() async {
    try {
      final result = await _channel.invokeMethod('appVersion');
      return result == null ? null : Map<String, Object?>.from(result);
    } catch (_) {
      return null;
    }
  }

  static Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (_) {}
  }

  /// 写入系统「下载」公共目录（子目录 扫书新典）。
  /// 返回落盘路径；失败返回错误文本（前缀 'error:'）。
  static Future<String> saveToDownloads(String name, Uint8List bytes) async {
    try {
      final path = await _channel.invokeMethod<String>(
          'saveToDownloads', {'name': name, 'bytes': bytes});
      return path ?? '(未知路径)';
    } catch (error) {
      return 'error: $error';
    }
  }

  /// 切换桌面图标：启用指定 alias、禁用其余。alias 如 'LauncherPhoto'。
  static Future<void> setLauncherIcon(String alias) async {
    try {
      await _channel.invokeMethod('setLauncherIcon', {'alias': alias});
    } catch (_) {}
  }

  /// 清空系统 WebView CookieManager 全部 cookie（退出登录时调用）。
  static Future<void> clearTiebaCookies() async {
    try {
      await _channel.invokeMethod('clearTiebaCookies');
    } catch (_) {}
  }

  /// 读取系统 WebView CookieManager 中指定 URL 的 cookie，
  /// 含 HttpOnly 的 BDUSS/STOKEN（document.cookie 拿不到的那些）。
  static Future<String?> getTiebaCookies(String url) async {
    try {
      return await _channel.invokeMethod<String>(
          'getTiebaCookies', {'url': url});
    } catch (_) {
      return null;
    }
  }

  /// 从系统文件选择器选一张图片，请求用户确认后以「桌面快捷方式」
  /// 形式钉到桌面（Android 不支持运行时用任意位图替换应用图标，
  /// 这是官方近似方案；与 app 图标并存，指向应用主页）。
  /// 返回 null=用户取消；'pinned'=已请求；其他=错误消息。
  static Future<String?> pinCustomShortcut() async {
    try {
      return await _channel.invokeMethod<String>('pickImageAndPinShortcut');
    } catch (error) {
      return error.toString();
    }
  }
}
