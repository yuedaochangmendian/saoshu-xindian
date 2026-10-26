// 协议自检：frs + profile + pb 三接口
import 'package:saoshu_xindian/network/tieba_client.dart';
// ignore_for_file: avoid_print

Future<void> main() async {
  final client = TiebaClient();
  try {
    final page = await client.requestThreads('yy小说吧', 1);
    print('frs OK: ${page.threads.length} threads, fid=${page.fid}');
    final profile = await client.fetchProfile();
    print('profile: ${profile == null ? "未登录（BDUSS 为空）" : profile.name}');
    final thread = await client.fetchThread('yy小说吧', page.threads.last.tid, maxFloors: 5);
    print('pb OK: floors=${thread.floors.length}');
  } catch (e) {
    print('FAIL: $e');
  } finally {
    client.close();
  }
}
