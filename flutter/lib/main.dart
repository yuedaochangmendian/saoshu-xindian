import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'prefs.dart';
import 'network/tieba_client.dart';
import 'services/secure_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await AppPrefs().load();
  await SecureStore.init(prefs);
  await TiebaClient.ensureDevice(
    (key) => prefs.getString(key),
    (key, value) async {
      if (value.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    },
  );
  runApp(SaoshuApp(prefs: prefs));
}

class SaoshuApp extends StatefulWidget {
  final SharedPreferences prefs;
  const SaoshuApp({super.key, required this.prefs});

  @override
  State<SaoshuApp> createState() => _SaoshuAppState();
}

class _SaoshuAppState extends State<SaoshuApp> {
  late String _themeId;
  late Favorites _favorites;

  @override
  void initState() {
    super.initState();
    _themeId = widget.prefs.getString('theme_id') ?? 'teal';
    if (!appThemes.any((t) => t.id == _themeId)) _themeId = 'teal';
    _favorites = Favorites(widget.prefs);
    _favorites.addListener(_rebuild);
  }

  final ValueNotifier<bool> _dockHidden = ValueNotifier<bool>(false);

  /// 全局 dock 页索引（首页快捷入口/返回逻辑使用）。
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);

  /// 首页 → 书库·分类浏览 的跳转信号（分类名，消费后置 null）。
  final ValueNotifier<String?> _browseJump = ValueNotifier<String?>(null);

  /// 点击震动开关：dock 与设置页共享同一份实时状态。
  late final ValueNotifier<bool> _haptic =
      ValueNotifier<bool>(widget.prefs.getBool('haptic_enabled') ?? false);

  void _setHaptic(bool enabled) {
    _haptic.value = enabled;
    widget.prefs.setBool('haptic_enabled', enabled);
  }

  @override
  void dispose() {
    _dockHidden.dispose();
    _haptic.dispose();
    _tabIndex.dispose();
    _browseJump.dispose();
    _favorites.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _changeTheme(String id) {
    setState(() => _themeId = id);
    widget.prefs.setString('theme_id', id);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      prefs: widget.prefs,
      favorites: _favorites,
      themeId: _themeId,
      changeTheme: _changeTheme,
      dockHidden: _dockHidden,
      haptic: _haptic,
      setHaptic: _setHaptic,
      tabIndex: _tabIndex,
      browseJump: _browseJump,
      child: MaterialApp(
        title: '扫书新典',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(_themeId, Brightness.light),
        darkTheme: buildTheme(_themeId, Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
