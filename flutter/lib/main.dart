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

  @override
  void dispose() {
    _dockHidden.dispose();
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
