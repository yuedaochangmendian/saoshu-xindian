import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/books_page.dart';
import 'pages/collection_page.dart';
import 'pages/home_page.dart';
import 'pages/network_page.dart';
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

  /// 点击震动开关的实时状态（设置页与 dock 共享）。
  final ValueNotifier<bool> haptic;
  final ValueChanged<bool> setHaptic;

  /// 当前 dock 页索引（提升到全局：首页快捷入口可直达书库/网络等页）。
  final ValueNotifier<int> tabIndex;

  /// 首页 → 分类浏览的跳转信号（值为目标分类名，消费后置 null）。
  final ValueNotifier<String?> browseJump;

  const AppScope({
    super.key,
    required this.prefs,
    required this.favorites,
    required this.themeId,
    required this.changeTheme,
    required this.dockHidden,
    required this.haptic,
    required this.setHaptic,
    required this.tabIndex,
    required this.browseJump,
    required super.child,
  });

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => themeId != old.themeId;
}

/// 主外壳：五个页面 + 可拖动悬浮胶囊 dock（Bettbox 交互模型）。
/// 页面：首页 / 书库（分类浏览+名词解释）/ 网络浏览 / 收藏与简记 / 数据。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _icons = [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.public_outlined,
    Icons.star_border,
    Icons.storage_outlined
  ];
  static const _selectedIcons = [
    Icons.home,
    Icons.grid_view,
    Icons.public,
    Icons.star,
    Icons.storage
  ];
  static const _labels = ['首页', '书库', '网络', '收藏', '数据'];

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    const pages = [
      HomePage(),
      BooksPage(),
      NetworkSection(),
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
              child: ValueListenableBuilder<int>(
                valueListenable: scope.tabIndex,
                builder: (context, index, _) =>
                    IndexedStack(index: index, children: pages),
              ),
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
              child: ValueListenableBuilder<int>(
                valueListenable: scope.tabIndex,
                builder: (context, index, child) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: scope.haptic,
                  builder: (context, hapticEnabled, _) => AppDock(
                    index: index,
                    count: 5,
                    icons: _icons,
                    selectedIcons: _selectedIcons,
                    labels: _labels,
                    hapticEnabled: hapticEnabled,
                    onTap: (i) {
                      if (i != index) {
                        scope.dockHidden.value = false;
                        scope.tabIndex.value = i;
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
