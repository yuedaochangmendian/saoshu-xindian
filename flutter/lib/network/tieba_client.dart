import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tieba_proto.dart';

/// 贴吧客户端（协议移植自原生 TiebaCollector.java，UA 沿用 aiotieba）。
class TiebaException implements Exception {
  final String message;
  TiebaException(this.message);
  @override
  String toString() => message;
}

class TiebaUserProfile {
  final int id;
  final String name;
  final String portrait;
  const TiebaUserProfile(
      {required this.id, required this.name, required this.portrait});
}

class ThreadSummary {
  final int tid;
  final String forum;
  final String title;
  final String author;
  final int createTime;
  final int lastTime;
  final int replyCount;
  final int viewCount;
  final bool top;
  final bool deleted;
  final bool masked;

  /// 作者头像（portrait token，渲染侧用 tiebaAvatarUrl 拼 himg portrait 路径）
  final String authorPortrait;

  const ThreadSummary(
      this.tid,
      this.forum,
      this.title,
      this.author,
      this.authorPortrait,
      this.createTime,
      this.lastTime,
      this.replyCount,
      this.viewCount,
      this.top,
      this.deleted,
      this.masked);
}

class Floor {
  final int pid;
  final int seq;
  final int agree;
  final String author;
  final String text;

  /// 楼内图片 URL（720px 流量与清晰度平衡，取自 type=3 分片 field 8）。
  final List<String> images;

  /// 楼层作者头像 portrait token（来自 post 关联的 user 映射）。
  final String portrait;

  /// 楼层作者百度 uid（Post.author_id），资料页 friend_uid 用。
  final int authorId;

  /// 楼中楼总数（Post.sub_post_number）。
  final int subNumber;

  /// 302001 响应内嵌的楼中楼预览（通常前 2 条，Post.sub_post_list=15）；
  /// 全部展开走 fetchSubPosts(302002)。
  final List<SubPost> subPosts;
  const Floor(this.pid, this.seq, this.agree, this.author, this.text,
      {this.images = const [],
      this.portrait = '',
      this.authorId = 0,
      this.subNumber = 0,
      this.subPosts = const []});
}

/// 楼中楼（小回复）。字段对齐 TiebaLite SubPostList.proto。
class SubPost {
  final int pid;
  final String author;
  final String portrait;
  final int time;
  final int agree;
  final String text;
  final List<String> images;
  const SubPost(
      {required this.pid,
      required this.author,
      required this.portrait,
      required this.time,
      required this.agree,
      required this.text,
      this.images = const []});
}

/// fetchSubPosts 返回：一页楼中楼 + 是否还有下一页。
class SubPostPage {
  final bool hasMore;
  final List<SubPost> posts;
  const SubPostPage(this.hasMore, this.posts);
}

class CollectedThread {
  final String forum;
  final int tid;
  final String title;
  final String author;
  final int createTime;
  final int replyNum;
  final int viewNum;
  final List<Floor> floors;

  const CollectedThread(this.forum, this.tid, this.title, this.author,
      this.createTime, this.replyNum, this.viewNum, this.floors);

  int get maxAgree => floors.fold(
      0, (value, floor) => value > floor.agree ? value : floor.agree);

  String combinedText() {
    final builder = StringBuffer();
    for (final floor in floors) {
      final text = floor.text.trim();
      if (text.isEmpty) continue;
      if (builder.isNotEmpty) builder.write('\n\n');
      if (floor.seq > 1) {
        builder.write('第${floor.seq}楼');
        if (floor.author.isNotEmpty) builder.write(' · ${floor.author}');
        builder.write('\n');
      }
      builder.write(text);
    }
    return builder.toString().trim();
  }
}

class ThreadsPage {
  final int fid;
  final bool hasMore;
  final List<ThreadSummary> threads;
  const ThreadsPage(this.fid, this.hasMore, this.threads);
}

class PostsPage {
  final bool hasMore;
  final String title;
  final String author;
  final int createTime;
  final int replyNum;
  final int viewNum;
  final List<Floor> floors;

  /// 楼主头像 portrait（thread.author field 18 text 5），帖子页头部用。
  final String authorPortrait;
  const PostsPage(this.hasMore, this.title, this.author, this.createTime,
      this.replyNum, this.viewNum, this.floors,
      {this.authorPortrait = ''});
}

/// 设备参数（参考 TiebaLite CommonRequest v11 字段集）。
/// 值随机生成一次后持久化（经 `TiebaClient.ensureDevice`），cuid/client_id
/// 的一致性影响服务端对登录态的校验。
class TiebaDeviceParams {
  final String cuid;
  final String clientId;
  final String imei;
  final String c3Aid;
  final String model;
  const TiebaDeviceParams({
    required this.cuid,
    required this.clientId,
    required this.imei,
    required this.c3Aid,
    this.model = 'M2012K11AC',
  });
}

class TiebaClient {
  /// 设备参数的进程级共享缓存：所有实例共用同一设备指纹。
  static TiebaDeviceParams? _sharedDevice;

  /// 从持久化恢复设备参数；无则生成。load/persist 由调用方提供（读写 prefs）。
  static Future<TiebaDeviceParams> ensureDevice(
      String? Function(String key) load,
      Future<void> Function(String key, String value) persist) async {
    if (_sharedDevice != null) return _sharedDevice!;
    final saved = load('tieba_device_cuid');
    final device = (saved != null && saved.startsWith('baidutiebaapp'))
        ? TiebaDeviceParams(
            cuid: saved,
            clientId: load('tieba_device_client') ?? _randHex(32),
            imei: load('tieba_device_imei') ?? _randHex(15),
            c3Aid: load('tieba_device_c3') ?? '${_randHex(26)}${_randHex(4)}',
          )
        : TiebaDeviceParams(
            cuid: 'baidutiebaapp${_randHex(26)}00',
            clientId: _randHex(32),
            imei: _randHex(15),
            c3Aid: '${_randHex(26)}${_randHex(4)}',
          );
    await persist('tieba_device_cuid', device.cuid);
    await persist('tieba_device_client', device.clientId);
    await persist('tieba_device_imei', device.imei);
    await persist('tieba_device_c3', device.c3Aid);
    _sharedDevice = device;
    return device;
  }

  static String _randHex(int len) {
    final rnd = Random();
    return List.generate(len, (i) => '0123456789abcdef'[rnd.nextInt(16)])
        .join();
  }

  TiebaClient(
      {String bduss = '', String stoken = '', TiebaDeviceParams? device})
      : _bduss = bduss,
        _stoken = stoken,
        _device = device ?? _sharedDevice ?? _randomDevice();
  final String _bduss;
  final String _stoken;
  final TiebaDeviceParams _device;
  static const _host = 'https://tiebac.baidu.com';
  static const _userAgent = 'aiotieba/22.12.1.0';
  static const _clientVersion = '12.64.1.1';
  static const _boundary = '-*_r1999';
  static const _frsCmd = 301001;

  static TiebaDeviceParams _randomDevice() {
    final rnd = Random();
    String hex(int len) =>
        List.generate(len, (i) => '0123456789abcdef'[rnd.nextInt(16)]).join();
    return TiebaDeviceParams(
      cuid: 'baidutiebaapp${hex(26)}00',
      clientId: hex(32),
      imei: hex(15),
      c3Aid: '${hex(26)}${hex(4)}',
    );
  }

  static const _pbCmd = 302001;
  static const _listPageSize = 50;
  static const _postPageSize = 30;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _throttle() async {
    final minimum = const Duration(milliseconds: 1600);
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < minimum) {
      await Future.delayed(minimum - elapsed);
    }
  }

  Future<ThreadsPage> requestThreads(String fname, int page) async {
    final apiPage = page <= 1 ? 0 : page;
    final data = PbWriter()
      ..messageField(39, _commonRequest())
      ..textField(1, fname)
      ..varintField(2, _listPageSize)
      ..varintField(3, _listPageSize + 5)
      ..varintField(4, 0)
      ..varintField(15, apiPage)
      ..varintField(47, 1);
    final request = (PbWriter()..messageField(1, data)).toBytes();
    final response = await _postProto('/c/f/frs/page?cmd=$_frsCmd', request);
    return _parseThreads(response, fname);
  }

  /// 解析 SubPostList 数组（楼中楼元素）。
  /// SubPostList: id=1 content=2(repeated PbContent) time=3 author_id=4
  /// floor=6 author=7(User) agree=9。
  List<SubPost> _parseSubPostLists(List<PbMessage> list) {
    final result = <SubPost>[];
    for (final sp in list) {
      final fragments = sp.messages(2);
      final images = <String>[];
      for (final fragment in fragments) {
        if (fragment.varint(1) == 3) {
          final url = fragment.text(8);
          if (url.startsWith('http')) images.add(url);
        }
      }
      final user = sp.message(7);
      var name = _userDisplay(user);
      if (name.isEmpty) name = '匿名用户${sp.varint(4)}';
      result.add(SubPost(
          pid: sp.varint(1),
          author: name,
          portrait: user?.text(5) ?? '',
          time: sp.varint(3).toInt(),
          agree: sp.message(9)?.varint(1) ?? 0,
          text: _assembleContent(fragments),
          images: images));
    }
    return result;
  }

  /// 楼中楼分页（/c/f/pb/floor cmd=302002，对齐 TiebaLite PbFloorRequestData：
  /// kz=1 tid、pid=2 主楼 pid、pn=4 页码、common=9、forum_id=11）。
  Future<SubPostPage> fetchSubPosts(int tid, int pid, int pn,
      {int fid = 0}) async {
    final data = PbWriter()
      ..varintField(1, tid)
      ..varintField(2, pid)
      ..varintField(4, pn)
      ..messageField(9, _commonRequest())
      ..varintField(11, fid);
    final request = (PbWriter()..messageField(1, data)).toBytes();
    final response =
        await _postProto('/c/f/pb/floor?cmd=302002', request);
    final root = PbMessage.parse(response);
    _checkError(root.message(1));
    final dataMsg = root.message(2);
    if (dataMsg == null) throw TiebaException('楼中楼响应缺少 data');
    var hasMore = false;
    final page = dataMsg.message(1);
    if (page != null) hasMore = page.varint(6) != 0;
    return SubPostPage(hasMore, _parseSubPostLists(dataMsg.messages(4)));
  }

  Future<CollectedThread> fetchThread(String fname, int tid,
      {int maxFloors = 100, void Function(String status)? onStatus}) async {
    var title = '';
    var author = '';
    var createTime = 0;
    var replyNum = 0;
    var viewNum = 0;
    final floors = <Floor>[];
    final seen = <int>{};
    for (var page = 1; page <= 8; page++) {
      onStatus?.call('抓取 $tid 第 $page 页…');
      final result = await requestPosts(tid, page);
      if (page == 1) {
        title = result.title;
        author = result.author;
        createTime = result.createTime;
      }
      if (result.replyNum > replyNum) replyNum = result.replyNum;
      if (result.viewNum > viewNum) viewNum = result.viewNum;
      for (final floor in result.floors) {
        if (floor.pid != 0 && seen.add(floor.pid)) {
          floors.add(floor);
        }
      }
      if (floors.length >= maxFloors || !result.hasMore) break;
    }
    if (floors.length > maxFloors) {
      floors.removeRange(maxFloors, floors.length);
    }
    floors.sort((a, b) => a.seq.compareTo(b.seq));
    return CollectedThread(
        fname, tid, title, author, createTime, replyNum, viewNum, floors);
  }

  /// 帖子单页楼层（浏览器按页拉取；fetchThread 的整帖抓取复用此接口）。
  Future<PostsPage> requestPosts(int tid, int page) async {
    final data = PbWriter()
      ..messageField(25, _commonRequest())
      ..varintField(4, tid)
      ..varintField(5, 0)
      ..varintField(6, 0)
      ..varintField(13, _postPageSize)
      ..varintField(18, page);
    final request = (PbWriter()..messageField(1, data)).toBytes();
    final response = await _postProto('/c/f/pb/page?cmd=$_pbCmd', request);
    return _parsePosts(response);
  }

  /// 完整 CommonRequest（参考 TiebaLite CommonRequest.proto v11 字段集）。
  /// BDUSS 在 field 10；字段一致性影响服务端对登录态的校验。
  PbWriter _commonRequest() {
    final writer = PbWriter()
      ..varintField(1, 2) // _client_type
      ..textField(2, _clientVersion)
      ..textField(3, _device.clientId)
      ..textField(5, _device.imei)
      ..textField(6, '1024324o') // from
      ..textField(7, _device.cuid)
      ..varintField(8, DateTime.now().millisecondsSinceEpoch)
      ..textField(9, _device.model)
      ..varintField(12, 1) // net_type wifi
      ..textField(24, '1.0.3') // pversion
      ..textField(25, '13') // _os_version
      ..textField(26, 'Xiaomi') // brand
      ..textField(28, '3.0.0') // lego_lib_version
      ..textField(32, _device.cuid) // cuid_galaxy2
      ..textField(35, _device.c3Aid)
      ..varintField(41, 0); // is_teenager
    if (_bduss.isNotEmpty) {
      writer.textField(10, _bduss);
    }
    if (_stoken.isNotEmpty) {
      writer.textField(30, _stoken);
    }
    return writer;
  }

  /// 请求个人资料（严格对齐 TiebaLite UserApiImpl.userProfileFlow 的
  /// ProfileRequestData 字段组合，/c/u/user/profile?cmd=303012）。
  /// - 自查（登录验证）：selfUid 来自登录 cookie UID，is_guest=0；
  ///   返回 null = BDUSS 无效/未登录。
  /// - 查看他人（浏览器资料页）：friendUid=目标楼层 author_id，
  ///   friend_uid=3 + is_guest=1，同 TiebaLite isSelf 分支。
  Future<TiebaUserProfile?> fetchProfile(
      {String? selfUid, int? friendUid}) async {
    final data = PbWriter()
      ..messageField(9, _commonRequest())
      ..varintField(2, 1) // need_post_count
      ..varintField(4, friendUid != null ? 1 : 0) // is_guest
      ..varintField(6, 1) // pn
      ..varintField(7, 20) // rn
      ..varintField(8, 1) // has_plist
      ..varintField(12, 0) // q_type
      ..varintField(14, 1) // is_from_usercenter
      ..varintField(15, 1); // page
    if (selfUid != null && selfUid.isNotEmpty) {
      final uidNum = int.tryParse(selfUid);
      if (uidNum != null) data.varintField(1, uidNum); // uid
    }
    if (friendUid != null && friendUid > 0) {
      data.varintField(3, friendUid); // friend_uid
    }
    final request = (PbWriter()..messageField(1, data)).toBytes();
    final response = await _postProto('/c/u/user/profile?cmd=303012', request);
    final root = PbMessage.parse(response);
    final error = root.message(1);
    if (error != null && error.varint(1) != 0) {
      throw TiebaException('贴吧错误 ${error.varint(1)} ${error.text(2)}');
    }
    final dataMsg = root.message(2);
    final user = dataMsg?.message(1);
    if (dataMsg == null || user == null) return null;
    final name = user.text(4).isNotEmpty ? user.text(4) : user.text(3);
    if (name.isEmpty) return null;
    return TiebaUserProfile(
      id: user.varint(2),
      name: name,
      portrait: user.text(5),
    );
  }

  Future<Uint8List> _postProto(String path, Uint8List protobuf) async {
    await _throttle();
    _lastRequest = DateTime.now();
    var versionPart = utf8
        .encode('--$_boundary\r\n'
            'Content-Disposition: form-data; name="_client_version"\r\n'
            '\r\n'
            '$_clientVersion\r\n')
        .toList();
    if (_stoken.isNotEmpty) {
      versionPart.addAll(utf8.encode('--$_boundary\r\n'
          'Content-Disposition: form-data; name="stoken"\r\n'
          '\r\n'
          '$_stoken\r\n'));
    }
    final head = utf8.encode('--$_boundary\r\n'
        'Content-Disposition: form-data; name="data"; filename="file"\r\n'
        '\r\n');
    final tail = utf8.encode('\r\n--$_boundary--\r\n');
    final body = (BytesBuilder(copy: false)
          ..add(versionPart)
          ..add(head)
          ..add(protobuf)
          ..add(tail))
        .toBytes();
    try {
      final request = await _http.postUrl(Uri.parse(_host + path));
      request.headers.set('User-Agent', _userAgent);
      request.headers.set('x_bd_data_type', 'protobuf');
      request.headers.set('Accept-Encoding', 'identity');
      request.headers.set('Connection', 'keep-alive');
      request.headers
          .set('Content-Type', 'multipart/form-data; boundary=$_boundary');
      request.contentLength = body.length;
      request.add(body);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      if (response.statusCode != 200) {
        throw TiebaException('贴吧 HTTP ${response.statusCode}');
      }
      return Uint8List.fromList(bytes);
    } on SocketException {
      throw TiebaException('网络连接失败');
    } on TimeoutException {
      throw TiebaException('请求超时');
    }
  }

  ThreadsPage _parseThreads(Uint8List response, String fname) {
    final root = PbMessage.parse(response);
    _checkError(root.message(1));
    final data = root.message(2);
    if (data == null) {
      throw TiebaException('贴吧列表响应缺少 data');
    }
    var fid = 0;
    final forum = data.message(2);
    if (forum != null) fid = forum.varint(1);
    var hasMore = false;
    final page = data.message(4);
    if (page != null) hasMore = page.varint(6) != 0;
    final users = _parseUsersWithPortrait(data.messages(17));
    final threads = <ThreadSummary>[];
    for (final item in data.messages(7)) {
      final tid = item.varint(1);
      if (tid <= 0) continue;
      final authorId = item.varint(56);
      var author = users[authorId]?[0] ?? '';
      if (author.isEmpty) author = _userDisplay(item.message(18));
      final authorPortrait = users[authorId]?[1] ?? '';
      threads.add(ThreadSummary(
          tid,
          fname,
          item.text(3),
          author,
          authorPortrait,
          item.varint(45),
          item.varint(7),
          item.varint(4),
          item.varint(5),
          item.varint(9) != 0,
          item.varint(181) != 0,
          item.varint(198) != 0));
    }
    return ThreadsPage(fid, hasMore, threads);
  }

  PostsPage _parsePosts(Uint8List response) {
    final root = PbMessage.parse(response);
    _checkError(root.message(1));
    final data = root.message(2);
    if (data == null) {
      throw TiebaException('楼层响应缺少 data');
    }
    var hasMore = false;
    final page = data.message(3);
    if (page != null) hasMore = page.varint(6) != 0;
    final thread = data.message(8);
    final title = thread?.text(3) ?? '';
    final author = thread == null ? '' : _userDisplay(thread.message(18));
    final createTime = thread?.varint(45) ?? 0;
    final replyNum = thread?.varint(4) ?? 0;
    final viewNum = thread?.varint(5) ?? 0;
    final users = _parseUsersWithPortrait(data.messages(13));
    final floors = <Floor>[];
    for (final post in data.messages(6)) {
      final pid = post.varint(1);
      final authorId = post.varint(19);
      var floorAuthor = users[authorId]?[0] ?? '';
      if (floorAuthor.isEmpty) floorAuthor = _userDisplay(post.message(23));
      final agreeNode = post.message(37);
      final agree = agreeNode?.varint(1) ?? 0;
      final fragments = post.messages(5);
      final images = <String>[];
      for (final fragment in fragments) {
        if (fragment.varint(1) == 3) {
          final url = fragment.text(8);
          if (url.startsWith('http')) images.add(url);
        }
      }
      floors.add(Floor(
          pid, post.varint(3), agree, floorAuthor, _assembleContent(fragments),
          images: images,
          portrait: users[authorId]?[1] ??
              post.message(23)?.text(5) ??
              '',
          authorId: authorId,
          subNumber: post.varint(13),
          subPosts: _parseSubPostLists(post.messages(15))));
    }
    return PostsPage(hasMore, title, author, createTime, replyNum, viewNum,
        floors,
        authorPortrait: thread?.message(18)?.text(5) ?? '');
  }

  /// {user_id: [显示名, 头像 portrait 参数]}
  Map<int, List<String>> _parseUsersWithPortrait(List<PbMessage> list) {
    final result = <int, List<String>>{};
    for (final user in list) {
      final id = user.varint(2);
      final display = _userDisplay(user);
      final portrait = user.text(5);
      if (id != 0 && (display.isNotEmpty || portrait.isNotEmpty)) {
        result[id] = [display, portrait];
      }
    }
    return result;
  }

  String _userDisplay(PbMessage? user) {
    if (user == null) return '';
    final shown = user.text(4);
    return shown.isEmpty ? user.text(3) : shown;
  }

  String _assembleContent(List<PbMessage> fragments) {
    final builder = StringBuffer();
    for (final fragment in fragments) {
      final type = fragment.varint(1);
      var text = fragment.text(2);
      if (type == 0 ||
          type == 1 ||
          type == 2 ||
          type == 4 ||
          type == 9 ||
          type == 11 ||
          type == 18 ||
          type == 27 ||
          type == 40) {
        if (type == 1 && text.isEmpty) text = fragment.text(3);
        builder.write(text);
      } else if (type == 3 || type == 20) {
        builder.write('[图片]');
      } else if (type == 5) {
        builder.write('[视频]');
      } else if (type == 10) {
        builder.write('[语音]');
      }
    }
    return builder.toString().trim();
  }

  void _checkError(PbMessage? error) {
    if (error == null) return;
    final code = error.varint(1);
    if (code != 0) {
      throw TiebaException('贴吧错误 $code ${error.text(2)}');
    }
  }

  void close() => _http.close();
}
