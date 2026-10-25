import 'dart:async';
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

  const ThreadSummary(
      this.tid,
      this.forum,
      this.title,
      this.author,
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
  const Floor(this.pid, this.seq, this.agree, this.author, this.text,
      {this.images = const []});
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
  const PostsPage(this.hasMore, this.title, this.author, this.createTime,
      this.replyNum, this.viewNum, this.floors);
}

class TiebaClient {
  TiebaClient({String bduss = ''}) : _bduss = bduss;
  final String _bduss;
  static const _host = 'https://tiebac.baidu.com';
  static const _userAgent = 'aiotieba/22.12.1.0';
  static const _clientVersion = '12.64.1.1';
  static const _boundary = '-*_r1999';
  static const _frsCmd = 301001;
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
    final common = PbWriter()
      ..varintField(1, 2)
      ..textField(2, _clientVersion);
    if (_bduss.isNotEmpty) {
      common.textField(10, _bduss);
    }
    final data = PbWriter()
      ..messageField(39, common)
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
      final result = await _requestPosts(tid, page);
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

  Future<PostsPage> _requestPosts(int tid, int page) async {
    final common = PbWriter()
      ..varintField(1, 2)
      ..textField(2, _clientVersion);
    if (_bduss.isNotEmpty) {
      common.textField(10, _bduss);
    }
    final data = PbWriter()
      ..messageField(25, common)
      ..varintField(4, tid)
      ..varintField(5, 0)
      ..varintField(6, 0)
      ..varintField(13, _postPageSize)
      ..varintField(18, page);
    final request = (PbWriter()..messageField(1, data)).toBytes();
    final response = await _postProto('/c/f/pb/page?cmd=$_pbCmd', request);
    return _parsePosts(response);
  }

  Future<Uint8List> _postProto(String path, Uint8List protobuf) async {
    await _throttle();
    _lastRequest = DateTime.now();
    final head = utf8.encode('--$_boundary\r\n'
        'Content-Disposition: form-data; name="data"; filename="file"\r\n'
        '\r\n');
    final tail = utf8.encode('\r\n--$_boundary--\r\n');
    final body = (BytesBuilder(copy: false)
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
    final users = _parseUsers(data.messages(17));
    final threads = <ThreadSummary>[];
    for (final item in data.messages(7)) {
      final tid = item.varint(1);
      if (tid <= 0) continue;
      final authorId = item.varint(56);
      var author = users[authorId] ?? '';
      if (author.isEmpty) author = _userDisplay(item.message(18));
      threads.add(ThreadSummary(
          tid,
          fname,
          item.text(3),
          author,
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
    final users = _parseUsers(data.messages(13));
    final floors = <Floor>[];
    for (final post in data.messages(6)) {
      final pid = post.varint(1);
      final authorId = post.varint(19);
      var floorAuthor = users[authorId] ?? '';
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
          images: images));
    }
    return PostsPage(
        hasMore, title, author, createTime, replyNum, viewNum, floors);
  }

  Map<int, String> _parseUsers(List<PbMessage> list) {
    final result = <int, String>{};
    for (final user in list) {
      final id = user.varint(2);
      final display = _userDisplay(user);
      if (id != 0 && display.isNotEmpty) {
        result[id] = display;
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
