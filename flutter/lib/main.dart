import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'prefs.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await AppPrefs().load();
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
  late bool _frosted;
  late Favorites _favorites;

  @override
  void initState() {
    super.initState();
    _themeId = widget.prefs.getString('theme_id') ?? 'teal';
    if (!appThemes.any((t) => t.id == _themeId)) _themeId = 'teal';
    _frosted = widget.prefs.getBool('dock_frosted') ?? false;
    _favorites = Favorites(widget.prefs);
    _favorites.addListener(_rebuild);
  }

  @override
  void dispose() {
    _favorites.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _changeTheme(String id) {
    setState(() => _themeId = id);
    widget.prefs.setString('theme_id', id);
  }

  void _toggleFrosted() {
    setState(() => _frosted = !_frosted);
    widget.prefs.setBool('dock_frosted', _frosted);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      prefs: widget.prefs,
      favorites: _favorites,
      frosted: _frosted,
      themeId: _themeId,
      changeTheme: _changeTheme,
      toggleFrosted: _toggleFrosted,
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
