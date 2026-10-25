import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 悬浮胶囊 dock（迁移自 Bettbox google_bottom_nav_bar 的交互模型）：
/// - 指示药丸随手指连续滑动（CustomPaint 按槽位绘制），释放后按速度投影吸附；
/// - 图标随指示器距离做颜色 + 缩放双插值（选中态除颜色外还有放大变化）；
/// - 跨槽位震动反馈，纵向大幅移动取消拖拽；
/// - 表面固定半透明（无磨砂模糊）。
class AppDock extends StatefulWidget {
  final int index;
  final int count;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final List<String> labels;
  final ValueChanged<int> onTap;
  final bool hapticEnabled;

  const AppDock({
    super.key,
    required this.index,
    required this.count,
    required this.icons,
    required this.selectedIcons,
    required this.labels,
    required this.onTap,
    this.hapticEnabled = false,
  });

  @override
  State<AppDock> createState() => _AppDockState();
}

class _AppDockState extends State<AppDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pos = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    lowerBound: 0,
    upperBound: (widget.count - 1).toDouble(),
  );
  int? _activePointer;
  Offset? _downPosition;
  VelocityTracker? _velocity;
  double _dragOffset = 0;
  double _anchorSlot = 0;
  int _lastSnapped = 0;
  bool _dragging = false;
  bool _dragCanceled = false;
  double _slotWidth = 0;

  @override
  void initState() {
    super.initState();
    _pos.value = widget.index.toDouble();
    _anchorSlot = widget.index.toDouble();
    _lastSnapped = widget.index;
  }

  @override
  void didUpdateWidget(covariant AppDock old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !_dragging) {
      _glideTo(widget.index.toDouble(), 200);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _haptic() {
    if (widget.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  int _slotFromDx(double dx) {
    if (_slotWidth <= 0) return widget.index;
    return (dx / _slotWidth).floor().clamp(0, widget.count - 1);
  }

  void _glideTo(double target, int ms) {
    _pos.animateTo(target.clamp(0, (widget.count - 1).toDouble()),
        duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic);
  }

  void _handleDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _downPosition = event.localPosition;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _dragging = false;
    _dragCanceled = false;
    _dragOffset = 0;
    final slot = _slotFromDx(event.localPosition.dx);
    _anchorSlot = slot.toDouble();
    _lastSnapped = slot;
    if (slot != widget.index) {
      // Bettbox 行为：按下仅做药丸预览滑动与触感，切页等抬起再提交。
      _haptic();
      _glideTo(slot.toDouble(), 200);
    }
  }

  void _handleMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _dragCanceled) return;
    final down = _downPosition;
    if (down == null) return;
    _velocity?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - down;
    if (delta.dy < -50 || delta.dy > 80) {
      _dragCanceled = true;
      _dragging = false;
      _velocity = null;
      _dragOffset = 0;
      _glideTo(widget.index.toDouble(), 180);
      return;
    }
    if (!_dragging && delta.dx.abs() > 4) {
      _dragging = true;
    }
    if (!_dragging || _slotWidth <= 0) return;
    setState(() {
      _dragOffset = delta.dx / _slotWidth;
      final slot =
          (_anchorSlot + _dragOffset).round().clamp(0, widget.count - 1);
      if (slot != _lastSnapped) {
        _lastSnapped = slot;
        _haptic();
      }
    });
  }

  void _handleUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    if (_dragCanceled) {
      _dragCanceled = false;
      _velocity = null;
      return;
    }
    var target = _slotFromDx(event.localPosition.dx);
    if (_dragging && _slotWidth > 0) {
      final velocity = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0.0;
      final current = _anchorSlot + _dragOffset;
      final fling = (velocity / _slotWidth * 0.16).clamp(-1.2, 1.2);
      var projected = (current + fling).round();
      if (velocity.abs() > 240) {
        final base = current.round();
        if (projected == base) {
          projected += velocity.sign.toInt();
        }
      }
      target = projected.clamp(0, widget.count - 1);
    }
    _velocity = null;
    _dragging = false;
    _dragOffset = 0;
    _glideTo(target.toDouble(), 180);
    if (target != widget.index) {
      widget.onTap(target);
    }
  }

  void _handleCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _dragging = false;
    _dragCanceled = false;
    _velocity = null;
    _dragOffset = 0;
    _glideTo(widget.index.toDouble(), 180);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final dockColor = scheme.surfaceContainerHigh.withValues(alpha: 0.88);
    final radius = BorderRadius.circular(28);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handleDown,
          onPointerMove: _handleMove,
          onPointerUp: _handleUp,
          onPointerCancel: _handleCancel,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: dockColor,
              borderRadius: radius,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                _slotWidth = constraints.maxWidth / widget.count;
                return AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) {
                    final position = (_pos.value + _dragOffset)
                        .clamp(0.0, (widget.count - 1).toDouble());
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _DockPillPainter(
                              position: position,
                              count: widget.count,
                              color: scheme.primary,
                              dark: isDark,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < widget.count; i++)
                              Expanded(
                                child: Center(
                                  child: _DockIcon(
                                    icon: widget.icons[i],
                                    selectedIcon: widget.selectedIcons[i],
                                    label: widget.labels[i],
                                    selectFactor:
                                        _factorFor(position, i),
                                    baseColor: scheme.onSurfaceVariant,
                                    selectColor: scheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double _factorFor(double position, int index) {
    final distance = (position - index).abs().clamp(0.0, 1.0);
    return 1.0 - Curves.easeOut.transform(distance);
  }
}

/// 指示药丸：随连续槽位位置绘制主色低透明度胶囊，选中槽内略放大。
class _DockPillPainter extends CustomPainter {
  final double position;
  final int count;
  final Color color;
  final bool dark;

  const _DockPillPainter({
    required this.position,
    required this.count,
    required this.color,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / count;
    final pillWidth = slot * 0.72;
    final left = position * slot + (slot - pillWidth) / 2;
    final pillHeight = size.height * 0.68;
    final top = (size.height - pillHeight) / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, pillWidth, pillHeight),
      Radius.circular(pillHeight / 2),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: dark ? 0.26 : 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(_DockPillPainter old) =>
      old.position != position || old.color != color || old.dark != dark;
}

/// 单个图标：颜色与缩放随选中因子插值（除颜色外的放大变化）。
class _DockIcon extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final double selectFactor;
  final Color baseColor;
  final Color selectColor;

  const _DockIcon({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selectFactor,
    required this.baseColor,
    required this.selectColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = selectFactor.clamp(0.0, 1.0);
    final color = Color.lerp(baseColor, selectColor, t)!;
    final data = t > 0.5 ? selectedIcon : icon;
    return Semantics(
      button: true,
      label: label,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: 1.0 + 0.14 * t),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Icon(data, size: 24, color: color),
      ),
    );
  }
}
