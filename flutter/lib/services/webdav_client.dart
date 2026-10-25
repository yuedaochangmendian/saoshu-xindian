import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 极简 WebDAV 客户端（PUT / GET / PROPFIND / MKCOL），凭 Basic 认证。
class WebDavException implements Exception {
  final String message;
  WebDavException(this.message);
  @override
  String toString() => message;
}

class WebDavEntry {
  final String name;
  final bool isDirectory;
  final DateTime? modified;
  const WebDavEntry(this.name, this.isDirectory, this.modified);
}

class WebDavClient {
  final String server; // 例：https://dav.example.com/dav
  final String username;
  final String password;
  final String directory; // 远端目录（相对路径，可为空）

  WebDavClient(
      {required this.server,
      required this.username,
      required this.password,
      this.directory = ''});

  Uri _uri(String remotePath) {
    var base = server;
    if (!base.endsWith('/')) base += '/';
    final dirPart = directory.isEmpty
        ? ''
        : '${directory.replaceAll(RegExp(r'^/|/$'), '')}/';
    return Uri.parse('$base$dirPart$remotePath');
  }

  HttpClient _client() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'saoshu-xindian';
  }

  Future<HttpClientResponse> _send(String method, Uri uri,
      {Uint8List? body, int timeoutSeconds = 20}) async {
    final client = _client();
    try {
      final request = await client.openUrl(method, uri);
      if (username.isNotEmpty) {
        final token = base64Encode(utf8.encode('$username:$password'));
        request.headers.set('Authorization', 'Basic $token');
      }
      if (body != null) {
        request.headers.contentType =
            ContentType('application', 'octet-stream');
        request.contentLength = body.length;
        request.add(body);
      }
      final response =
          await request.close().timeout(Duration(seconds: timeoutSeconds));
      return response;
    } on SocketException {
      throw WebDavException('无法连接 WebDAV 服务器');
    } on TimeoutException {
      throw WebDavException('WebDAV 请求超时');
    } catch (error) {
      throw WebDavException('WebDAV 请求失败：$error');
    }
  }

  Future<void> _drain(HttpClientResponse response) async {
    await for (final _ in response) {}
  }

  /// 测试连接与目录可达性（PROPFIND depth 0），目录不存在时尝试 MKCOL。
  Future<void> testConnection() async {
    final response = await _send('PROPFIND', _uri(''), timeoutSeconds: 15);
    final headers = response.headers;
    await _drain(response);
    if (response.statusCode == 404 && directory.isNotEmpty) {
      // 目录不存在：逐级创建。
      final parts = directory.split('/').where((p) => p.isNotEmpty).toList();
      var created = '';
      for (final part in parts) {
        created += '/$part';
        final mk = await _send(
            'MKCOL',
            Uri.parse(server.endsWith('/')
                ? '${server.substring(0, server.length - 1)}$created'
                : '$server$created'));
        await _drain(mk);
      }
      final retry = await _send('PROPFIND', _uri(''));
      await _drain(retry);
      if (retry.statusCode == 207 || retry.statusCode == 200) return;
      throw WebDavException('目录创建后仍不可访问：${retry.statusCode}');
    }
    if (response.statusCode == 401) {
      throw WebDavException('用户名或密码错误（401）');
    }
    if (response.statusCode == 207 || response.statusCode == 200) {
      return;
    }
    throw WebDavException('服务器返回 ${response.statusCode} '
        '${headers.value('x-error') ?? ''}');
  }

  Future<void> upload(String name, String content) async {
    final body = utf8.encode(content);
    final response = await _send('PUT', _uri(name), body: body);
    await _drain(response);
    if (response.statusCode >= 300) {
      throw WebDavException('上传失败：${response.statusCode}');
    }
  }

  Future<List<WebDavEntry>> listBackups() async {
    final response = await _send('PROPFIND', _uri(''), timeoutSeconds: 20);
    final bodyText = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401) {
      throw WebDavException('用户名或密码错误（401）');
    }
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw WebDavException('列取失败：${response.statusCode}');
    }
    final entries = <WebDavEntry>[];
    final responses =
        RegExp(r'<[a-zA-Z0-9]*:?response>(.*?)</[a-zA-Z0-9]*:?response>')
            .allMatches(bodyText);
    for (final match in responses) {
      final chunk = match.group(1)!;
      final href = _tagValue(chunk, 'href');
      if (href == null) continue;
      final name = Uri.decodeComponent(
          href.split('/').lastWhere((p) => p.isNotEmpty, orElse: () => ''));
      if (name.isEmpty) continue;
      final isDir =
          _tagValue(chunk, 'collection') != null || href.endsWith('/');
      final modified = _tagValue(chunk, 'getlastmodified');
      entries.add(WebDavEntry(name, isDir,
          modified == null ? null : parseHttpDateCompat(modified)));
    }
    entries.removeWhere((e) => e.isDirectory || !e.name.endsWith('.json'));
    return entries;
  }

  String? _tagValue(String xml, String localName) {
    final match = RegExp(
            '<[a-zA-Z0-9]*:?$localName[^>]*>(.*?)</[a-zA-Z0-9]*:?$localName>',
            dotAll: true)
        .firstMatch(xml);
    return match?.group(1)?.trim();
  }

  Future<String> download(String name) async {
    final response = await _send('GET', _uri(name), timeoutSeconds: 30);
    final bodyText = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw WebDavException('下载失败：${response.statusCode}');
    }
    return bodyText;
  }
}

/// HttpDate.parse 只认固定格式；服务器变体不同，容错处理。
DateTime parseHttpDateCompat(String value) {
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return DateTime.now();
  }
}
