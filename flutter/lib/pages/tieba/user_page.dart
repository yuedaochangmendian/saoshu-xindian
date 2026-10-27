import 'package:flutter/material.dart';

import '../../network/tieba_client.dart';
import '../../services/secure_store.dart';
import '../../services/system_bridge.dart';
import '../../widgets/tieba_rich_text.dart';

/// 贴吧用户资料页（浏览器链路：点楼层作者/楼主进入）。
/// 有 uid 时走 profile PB 接口（cmd=303012 friend_uid），
/// 拿不到或无 uid 时退回列表携带的头像/名字，并提供跳转 web 资料页。
class TiebaUserPage extends StatefulWidget {
  final int uid;
  final String portrait;
  final String name;

  const TiebaUserPage(
      {super.key,
      required this.uid,
      required this.portrait,
      required this.name});

  @override
  State<TiebaUserPage> createState() => _TiebaUserPageState();
}

class _TiebaUserPageState extends State<TiebaUserPage> {
  final _client = TiebaClient(
      bduss: SecureStore.get('tieba_bduss'),
      stoken: SecureStore.get('tieba_stoken'));
  TiebaUserProfile? _profile;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.uid > 0) _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _client.fetchProfile(friendUid: widget.uid);
      if (mounted) {
        setState(() {
          _loading = false;
          _profile = profile;
          if (profile == null) _error = '未获取到该用户资料';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _profile?.name ?? widget.name;
    final portrait = _profile?.portrait.isNotEmpty == true
        ? _profile!.portrait
        : widget.portrait;
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? '用户资料' : name,
            style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              TiebaAvatar(radius: 26, portrait: portrait, name: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '匿名用户' : name,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      _profile != null
                          ? 'uid ${_profile!.id}'
                          : (widget.uid > 0 ? 'uid ${widget.uid}' : '无 uid'),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: TextStyle(fontSize: 12, color: scheme.error)),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              final uri = Uri.parse(
                  'https://tieba.baidu.com/home/main?un=${Uri.encodeComponent(name)}');
              SystemBridge.openUrl(uri.toString());
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('打开 TA 的贴吧主页'),
          ),
        ],
      ),
    );
  }
}

