// 独立网络层自检：dart run tool/network_check.dart [贴吧名]
import 'dart:io';

import 'package:saoshu_xindian/network/tieba_client.dart';

Future<void> main(List<String> args) async {
  final forum = args.isNotEmpty ? args[0] : 'yy小说吧';
  final client = TiebaClient();
  try {
    final page = await client.requestThreads(forum, 1);
    stdout.writeln('forum=$forum fid=${page.fid} hasMore=${page.hasMore} '
        'threads=${page.threads.length}');
    for (final thread in page.threads.take(5)) {
      stdout.writeln('  tid=${thread.tid} replies=${thread.replyCount} '
          'author=${thread.author} ${thread.title.substring(0, thread.title.length.clamp(0, 30))}');
    }
    final target = page.threads.firstWhere((t) => !t.top && t.replyCount > 3,
        orElse: () => page.threads.first);
    stdout.writeln('抓取目标 tid=${target.tid}');
    final collected = await client.fetchThread(forum, target.tid,
        maxFloors: 60, onStatus: (s) => stdout.write('\r$s        '));
    stdout.writeln();
    stdout.writeln('结果: 楼层=${collected.floors.length} '
        '回复=${collected.replyNum} 赞=${collected.maxAgree}');
    final combined = collected.combinedText();
    stdout.writeln('正文长度=${combined.length}');
    stdout.writeln(combined.substring(0, combined.length.clamp(0, 200)));
  } catch (error) {
    stderr.writeln('失败: $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}
