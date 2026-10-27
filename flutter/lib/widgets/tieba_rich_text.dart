import 'package:flutter/material.dart';

/// 贴吧富文本渲染：把正文里的 `#(哈哈)` 表情代码渲染成官方表情图片，
/// 并提供楼主头像 URL 构造（对齐 TiebaLite StringUtil.getAvatarUrl：
/// `tb.himg.baidu.com/sys/portrait/item/<token>`，token 已是完整 URL 则原样）。
///
/// 表情映射与图片域名均取自 TiebaLite（ZaiLinn main 分支）：
/// EmoticonManager.DEFAULT_EMOTICON_MAPPING +
/// static.tieba.baidu.com/tb/editor/images/client/image_emoticonN.png。
/// （https 在该路径 404/拒连，仅 http 可用——Dart HttpClient 不受
/// Android cleartext 策略限制，可直接加载。）

/// 表情名 → 官方 image_emoticonN 序号（58 条，TiebaLite 默认表）。
const Map<String, int> tiebaEmoticonIds = {
  '呵呵': 1,
  '哈哈': 2,
  '吐舌': 3,
  '啊': 4,
  '酷': 5,
  '怒': 6,
  '开心': 7,
  '汗': 8,
  '泪': 9,
  '黑线': 10,
  '鄙视': 11,
  '不高兴': 12,
  '真棒': 13,
  '钱': 14,
  '疑问': 15,
  '阴险': 16,
  '吐': 17,
  '咦': 18,
  '委屈': 19,
  '花心': 20,
  '呼~': 21,
  '笑眼': 22,
  '冷': 23,
  '太开心': 24,
  '滑稽': 25,
  '勉强': 26,
  '狂汗': 27,
  '乖': 28,
  '睡觉': 29,
  '惊哭': 30,
  '生气': 31,
  '惊讶': 32,
  '喷': 33,
  '爱心': 34,
  '心碎': 35,
  '玫瑰': 36,
  '礼物': 37,
  '彩虹': 38,
  '星星月亮': 39,
  '太阳': 40,
  '钱币': 41,
  '灯泡': 42,
  '茶杯': 43,
  '蛋糕': 44,
  '音乐': 45,
  'haha': 46,
  '胜利': 47,
  '大拇指': 48,
  '弱': 49,
  'OK': 50,
  '沙发': 77,
  '手纸': 78,
  '香蕉': 79,
  '便便': 80,
  '药丸': 81,
  '红领巾': 82,
  '蜡烛': 83,
  '三道杠': 84,
};

String _emoticonUrl(int id) =>
    'http://static.tieba.baidu.com/tb/editor/images/client/image_emoticon$id'
    '.png';

/// 楼主头像 URL。TiebaLite 主用 portrait（无 n 后缀）；
/// portraitn 是历史变体，保留作为加载失败后的第二回落。
String tiebaAvatarUrl(String portrait) {
  if (portrait.startsWith('http://') || portrait.startsWith('https://')) {
    return portrait;
  }
  return 'https://tb.himg.baidu.com/sys/portrait/item/$portrait';
}

final RegExp _emoticonPattern = RegExp(r'#\((([一-龥A-Za-z0-9~]+))\)');

/// 把含 `#(x)` 的正文编译成 InlineSpan 列表。
/// fontSize 决定表情图尺寸（0.9 行高，同 TiebaLite EmoticonUtil 比例）。
List<InlineSpan> buildTiebaSpans(
    String content, TextStyle style, double fontSize) {
  if (!content.contains('#(')) {
    return [TextSpan(text: content, style: style)];
  }
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in _emoticonPattern.allMatches(content)) {
    if (match.start > last) {
      spans.add(
          TextSpan(text: content.substring(last, match.start), style: style));
    }
    final id = tiebaEmoticonIds[match.group(2)];
    final size = fontSize * 0.9;
    if (id == null) {
      // 表里没有的表情代码原样保留文本，不吞内容。
      spans.add(TextSpan(text: match.group(0), style: style));
    } else {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            _emoticonUrl(id),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => Text(
              match.group(0)!,
              style: style,
            ),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ),
      ));
    }
    last = match.end;
  }
  if (last < content.length) {
    spans.add(TextSpan(text: content.substring(last), style: style));
  }
  return spans;
}

/// 可选中贴吧正文（reader 用）。
class SelectableTiebaText extends StatelessWidget {
  final String content;
  final TextStyle style;
  const SelectableTiebaText(
      {super.key, required this.content, required this.style});

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: buildTiebaSpans(content, style, style.fontSize ?? 15)),
      style: style,
    );
  }
}

/// 楼主头像（列表行内）：加载失败/无 portrait 时回退名字首字符。
class TiebaAvatar extends StatelessWidget {
  final String portrait;
  final String name;
  final double radius;
  const TiebaAvatar(
      {super.key,
      required this.portrait,
      required this.name,
      this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (portrait.isEmpty) return _fallback(scheme);
    return ClipOval(
      child: Image.network(
        tiebaAvatarUrl(portrait),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _fallback(scheme),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fallback(scheme),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) => Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
            color: scheme.primaryContainer, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(
              fontSize: radius,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer),
        ),
      );
}
