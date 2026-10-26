import 'dart:convert';
import 'dart:io';

/// 更新检查与下载镜像源。
class UpdateInfo {
  final String tag;
  final String name;
  final String notes;
  final String apkUrl;
  final DateTime? publishedAt;
  const UpdateInfo(this.tag, this.name, this.notes, this.apkUrl,
      {this.publishedAt});
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
  /// 查询最新 Release。GitHub API 直连（镜像源只作用于下载地址）。
  static Future<UpdateInfo> checkLatest() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/yuedaochangmendian/saoshu-xindian/releases/latest'));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('GitHub API ${response.statusCode}');
      }
      final json = jsonDecode(body) as Map<String, Object?>;
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
      );
    } finally {
      client.close();
    }
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
