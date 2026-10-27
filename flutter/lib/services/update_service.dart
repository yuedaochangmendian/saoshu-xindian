import 'dart:convert';
import 'dart:io';

/// 更新检查与下载镜像源。
class UpdateInfo {
  final String tag;
  final String name;
  final String notes;
  final String apkUrl;
  final DateTime? publishedAt;

  /// 该 Release 是否 GitHub 预发布（prerelease）标记。
  final bool prerelease;
  const UpdateInfo(this.tag, this.name, this.notes, this.apkUrl,
      {this.publishedAt, this.prerelease = false});
}

/// 下载镜像源定义（作用于 GitHub release 资产的下载地址前缀）。
class DownloadMirror {
  final String id;
  final String label;
  final String prefix; // 空串 = GitHub 直连

  const DownloadMirror(this.id, this.label, this.prefix);
}

const downloadMirrors = <DownloadMirror>[
  DownloadMirror('direct', 'GitHub 直连', ''),
  DownloadMirror('ghfast', 'ghfast 镜像', 'https://ghfast.top/'),
  DownloadMirror('ghproxy', 'gh-proxy 镜像', 'https://gh-proxy.com/'),
];

DownloadMirror mirrorById(String id) => downloadMirrors
    .firstWhere((m) => m.id == id, orElse: () => downloadMirrors.first);

class UpdateService {
  static const _apiBase =
      'https://api.github.com/repos/yuedaochangmendian/saoshu-xindian';

  /// 查询最新 Release。GitHub API 直连（镜像源只作用于下载地址）。
  ///
  /// [includePrerelease] 为 true 时走「预览版更新频道」：取 Release 列表
  /// （created_at 降序）里第一个带 APK 资产的非草稿发布——本项目的预览版
  /// （prerelease）因此也能被检查到；为 false 时维持 /releases/latest
  /// 语义（仅正式版）。db-latest / ci-log-* 等无 APK 资产的发布天然跳过。
  static Future<UpdateInfo> checkLatest(
      {bool includePrerelease = false}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      if (includePrerelease) {
        final releases = await _getJson(
            client, '$_apiBase/releases?per_page=20');
        // /releases 列表端点返回数组（/releases/latest 才是对象）
        for (final item in
            (releases as List).whereType<Map<String, Object?>>()) {
          if (item['draft'] == true) continue;
          final info = _toUpdateInfo(item);
          if (info.apkUrl.isNotEmpty) return info;
        }
        throw Exception('未找到带 APK 的发布');
      }
      final json = await _getJson(client, '$_apiBase/releases/latest');
      return _toUpdateInfo(json as Map<String, Object?>);
    } finally {
      // force：超时被放弃的请求仍挂在 client 上，非 force close 会
      // 等它到永远——「检查更新」按钮就永久转圈。
      client.close(force: true);
    }
  }

  static Future<Object?> _getJson(HttpClient client, String url) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Accept', 'application/vnd.github+json');
    final response =
        await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('GitHub API ${response.statusCode}');
    }
    return jsonDecode(body);
  }

  static UpdateInfo _toUpdateInfo(Map<String, Object?> json) {
    final tag = (json['tag_name'] ?? '') as String;
    final assets = (json['assets'] as List? ?? const []);
    String apkUrl = '';
    for (final asset in assets) {
      final a = asset as Map<String, Object?>;
      final name = (a['name'] ?? '') as String;
      if (name.endsWith('.apk')) {
        apkUrl = (a['browser_download_url'] ?? '') as String;
        break;
      }
    }
    return UpdateInfo(
      tag,
      (json['name'] ?? tag) as String,
      (json['body'] ?? '') as String,
      apkUrl,
      publishedAt: DateTime.tryParse((json['published_at'] ?? '') as String),
      prerelease: json['prerelease'] == true,
    );
  }

  /// 按镜像源生成实际下载地址。
  static String applyMirror(String githubUrl, String mirrorPrefix) {
    if (mirrorPrefix.isEmpty || !githubUrl.startsWith('https://github.com/')) {
      return githubUrl;
    }
    return mirrorPrefix + githubUrl.substring('https://github.com/'.length);
  }

  /// 版本比较：'4.1.0' > '4.0.0-pre17'。返回 >0 表示 remote 更新。
  static int compareVersions(String remote, String current) {
    final r = _parts(remote);
    final c = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (r[i] != c[i]) return r[i].compareTo(c[i]);
    }
    final rPre = r.preNumber;
    final cPre = c.preNumber;
    // 无预发布后缀视为比有后缀的新；pre 按整数比较（pre6 < pre10）。
    if (rPre == null && cPre == null) return 0;
    if (rPre == null) return 1;
    if (cPre == null) return -1;
    return rPre.compareTo(cPre);
  }

  static _VersionParts _parts(String version) {
    var v = version.trim().replaceFirst(RegExp(r'^v'), '');
    int? preNumber;
    final preMatch = RegExp(r'-(?:pre)?(\d+)$').firstMatch(v);
    if (preMatch != null) {
      preNumber = int.tryParse(preMatch.group(1)!);
      v = v.substring(0, v.length - preMatch.group(0)!.length);
    }
    final nums = <int>[];
    for (final part in v.split('.')) {
      nums.add(int.tryParse(part) ?? 0);
    }
    while (nums.length < 3) {
      nums.add(0);
    }
    return _VersionParts(nums.sublist(0, 3), preNumber);
  }
}

class _VersionParts {
  final List<int> numbers;
  final int? preNumber;
  const _VersionParts(this.numbers, this.preNumber);
  int operator [](int index) => numbers[index];
}
