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
}
