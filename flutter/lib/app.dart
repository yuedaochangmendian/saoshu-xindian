import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/books_page.dart';
import 'pages/collection_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'prefs.dart';
import 'widgets/app_dock.dart';

/// 全局共享状态。
class AppScope extends InheritedWidget {
  final SharedPreferences prefs;
  final Favorites favorites;
  final String themeId;
  final ValueChanged<String> changeTheme;

  /// dock 滚动隐藏开关（书库页下滑隐藏、上滑出现，切页自动复位）。
  final ValueNotifier<bool> dockHidden;

  const AppScope({
    super.key,
    required this.prefs,
    required this.favorites,
    required this.themeId,
    required this.changeTheme,
    required this.dockHidden,
    required super.child,
  });

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => themeId != old.themeId;
}

/// 主外壳：四个页面 + 可拖动悬浮胶囊 dock（Bettbox 交互模型）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _icons = [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.star_border,
    Icons.storage_outlined
  ];
  static const _selectedIcons = [
    Icons.home,
    Icons.grid_view,
    Icons.star,
    Icons.storage
  ];
  static const _labels = ['首页', '书库', '收藏与简记', '数据'];

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
    // Bettbox 悬浮方案：页面铺满全屏，dock 以 Positioned 直接叠在内容上，
    // 不用 Scaffold.bottomNavigationBar 槽位（杜绝槽位区域的色带/遮罩）。
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery.removePadding(
              removeLeft: true,
              removeRight: true,
              context: context,
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: scope.dockHidden,
              builder: (context, hidden, child) => AnimatedSlide(
                offset: hidden ? const Offset(0, 1.6) : Offset.zero,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: IgnorePointer(ignoring: hidden, child: child),
              ),
              child: AppDock(
                index: _index,
                count: 4,
                icons: _icons,
                selectedIcons: _selectedIcons,
                labels: _labels,
                hapticEnabled: scope.prefs.getBool('haptic_enabled') ?? false,
                onTap: (i) {
                  if (i != _index) {
                    scope.dockHidden.value = false;
                    setState(() => _index = i);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
