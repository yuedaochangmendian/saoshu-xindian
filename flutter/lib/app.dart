import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/books_page.dart';
import 'pages/collection_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'prefs.dart';

/// 全局共享状态。
class AppScope extends InheritedWidget {
  final SharedPreferences prefs;
  final Favorites favorites;
  final bool frosted;
  final String themeId;
  final ValueChanged<String> changeTheme;
  final VoidCallback toggleFrosted;

  const AppScope({
    super.key,
    required this.prefs,
    required this.favorites,
    required this.frosted,
    required this.themeId,
    required this.changeTheme,
    required this.toggleFrosted,
    required super.child,
  });

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      frosted != old.frosted || themeId != old.themeId;
}

/// 主外壳：四个页面 + 悬浮胶囊 dock（Bettbox 风格）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

const _dockIcons = [
  Icons.home_outlined,
  Icons.grid_view_outlined,
  Icons.star_border,
  Icons.storage_outlined
];
const _dockSelectedIcons = [Icons.home, Icons.grid_view, Icons.star, Icons.storage];
const _dockLabels = ['首页', '书库', '收藏与简记', '数据'];

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pages = const [
      HomePage(),
      BooksPage(),
      CollectionPage(),
      SettingsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _Dock(
        frosted: scope.frosted,
        scheme: scheme,
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 悬浮胶囊 dock：近不透明表面色 + 软阴影，选中主色、未选中灰。
class _Dock extends StatelessWidget {
  final bool frosted;
  final ColorScheme scheme;
  final int index;
  final ValueChanged<int> onTap;

  const _Dock({
    required this.frosted,
    required this.scheme,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = frosted
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.85)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.98);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                offset: const Offset(0, 6),
                color: scheme.shadow.withValues(alpha: 0.08),
              ),
              BoxShadow(
                blurRadius: 3,
                offset: const Offset(0, 1),
                color: scheme.shadow.withValues(alpha: 0.04),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => onTap(i),
                        child: SizedBox.expand(
                          child: Center(
                            child: Icon(
                              i == index
                                  ? _dockSelectedIcons[i]
                                  : _dockIcons[i],
                              size: 24,
                              color: i == index
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              semanticLabel: _dockLabels[i],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
