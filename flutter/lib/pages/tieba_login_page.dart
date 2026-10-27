import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/system_bridge.dart';

/// 贴吧网页登录：内嵌 wappass 百度登录页（支持验证码/扫码/账密），
/// 登录成功后从 cookie 拦截 BDUSS 与 STOKEN 返回（参考 TiebaLite LoginPage）。
class TiebaLoginPage extends StatefulWidget {
  const TiebaLoginPage({super.key});

  @override
  State<TiebaLoginPage> createState() => _TiebaLoginPageState();
}

class _TiebaLoginPageState extends State<TiebaLoginPage> {
  late final WebViewController _controller;
  bool _checked = false;
  Timer? _poll;

  /// 登录地址：wappass 护照页，成功后跳转贴吧个人页。
  static const _loginUrl =
      'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _checkCookies(),
      ))
      ..loadRequest(Uri.parse(_loginUrl));
    // 登录跳转可能不触发 onPageFinished，轮询兜底。
    _poll = Timer.periodic(
        const Duration(seconds: 2), (_) => _checkCookies());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 从系统 CookieManager 读贴吧域 cookie；拿到 BDUSS 即视为登录成功。
  /// 注意：BDUSS/STOKEN 带 HttpOnly，JS 的 document.cookie 永远读不到，
  /// 必须走原生 MethodChannel。
  Future<void> _checkCookies() async {
    if (_checked) return;
    final cookie = await SystemBridge.getTiebaCookies(
        'https://tieba.baidu.com/');
    if (cookie == null || _checked) return;
    final bduss = cookieValueOf(cookie, 'BDUSS');
    if (bduss == null || bduss.isEmpty) return;
    final stoken = cookieValueOf(cookie, 'STOKEN') ?? '';
    _checked = true;
    _poll?.cancel();
    if (mounted) {
      Navigator.of(context).pop((bduss, stoken));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('贴吧登录', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text('在网页中使用验证码 / 扫码 / 账号密码登录，成功后自动返回应用。',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

/// 解析 cookie 字符串中指定名的值。
String? cookieValueOf(String cookie, String name) {
  for (final pair in cookie.split(';')) {
    final kv = pair.split('=');
    if (kv.length >= 2 && kv.first.trim() == name) {
      return kv.sublist(1).join('=').trim();
    }
  }
  return null;
}
