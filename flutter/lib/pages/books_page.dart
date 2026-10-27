import 'package:flutter/material.dart';

import '../app.dart';
import 'browse_page.dart';
import 'glossary_page.dart';

/// 书库：网络浏览 / 分类浏览 / 名词解释 三个并列视图。
///
/// 切换逻辑：自定义滑动式分段控件（动画药丸指示器）+ AnimatedSwitcher 内容淡入，
/// 状态全部保活（IndexedStack）；页签与 dock 只在滑动时隐藏，切换页签立即回显。
class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  int _index = 0;

  static const _tabLabels = ['分类浏览', '名词解释'];

  AppScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首页快捷入口跳进来时，先把内容切回「分类浏览」页签。
    final scope = AppScope.of(context);
    if (_scope != scope) {
      _scope?.browseJump.removeListener(_onBrowseJump);
      scope.browseJump.addListener(_onBrowseJump);
      _scope = scope;
    }
  }

  void _onBrowseJump() {
    final scope = _scope;
    if (scope != null &&
        scope.browseJump.value != null &&
        _index != 0 &&
        mounted) {
      _select(0);
    }
  }

  @override
  void dispose() {
    _scope?.browseJump.removeListener(_onBrowseJump);
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    // 切换页签时复位隐藏状态：页签只随滑动隐藏，切页必回显。
    AppScope.of(context).dockHidden.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('书库',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<bool>(
                valueListenable: AppScope.of(context).dockHidden,
                builder: (context, hidden, child) => AnimatedSlide(
                  offset: hidden ? const Offset(0, -1.6) : Offset.zero,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: hidden
                        ? const SizedBox(width: double.infinity, height: 0)
                        : child!,
                  ),
                ),
                child: _SegmentedControl(
                  labels: _tabLabels,
                  index: _index,
                  onSelect: _select,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: (notification) {
                    // 下滑隐藏 dock 与二级页签，上滑立即出现。
                    // 横向滚动（分类芯片、日期筛选）不触发隐藏。
                    if (notification.metrics.axis != Axis.vertical) {
                      return false;
                    }
                    final hidden = AppScope.of(context).dockHidden;
                    if (notification.scrollDelta == null) return false;
                    final delta = notification.scrollDelta!;
                    if (delta > 6 &&
                        notification.metrics.pixels > 60 &&
                        !hidden.value) {
                      hidden.value = true;
                    } else if (delta < -6 && hidden.value) {
                      hidden.value = false;
                    }
                    return false;
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                                begin: const Offset(0, 0.02), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: _pageFor(_index),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageFor(int index) {
    switch (index) {
      case 0:
        return BrowseSection(key: ValueKey('page-$index'));
      default:
        return GlossarySection(key: ValueKey('page-\$index'));
    }
  }
}

/// 滑动式分段控件：白色药丸随选中项平滑滑动，与底栏/滑块同一设计语言。
class _SegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  const _SegmentedControl(
      {required this.labels, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-1 + 2 * index / (labels.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / labels.length,
                  child: Container(
                    height: double.infinity,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: i == index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == index
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
