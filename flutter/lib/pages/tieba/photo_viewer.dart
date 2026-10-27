import 'package:flutter/material.dart';

/// 全屏大图浏览（对齐 TiebaLite 图集体验）：左右滑动 + 双指缩放，
/// 点击任意处关闭，多图显示页码。
class PhotoViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const PhotoViewerPage(
      {super.key, required this.urls, required this.initialIndex});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(widget.urls[i],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => const Text(
                            '图片加载失败',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 13))),
                  ),
                ),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text('${_index + 1}/${widget.urls.length}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 8,
            child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
