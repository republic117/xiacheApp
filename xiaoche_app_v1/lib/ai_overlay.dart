import 'package:flutter/material.dart';

class DetectionBox {
  DetectionBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.label,
    this.conf,
    this.color,
  });

  /// 归一化坐标（0~1），相对“原始图像宽高”
  final double x1, y1, x2, y2;
  final String? label;
  final double? conf;
  final Color? color;
}

class DetectionMetadata {
  DetectionMetadata({
    required this.tsMs,
    required this.imgW,
    required this.imgH,
    required this.boxes,
  });

  final int tsMs;
  final int imgW;
  final int imgH;
  final List<DetectionBox> boxes;
}

/// 叠加绘制：
/// - 目前默认“视频渲染区域 == 叠加区域”
/// - boxes 使用 0~1 归一化坐标映射到 size
class AiOverlayPainter extends CustomPainter {
  AiOverlayPainter({
    required this.metadata,
    required this.showLabels,
  });

  final DetectionMetadata? metadata;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final meta = metadata;
    if (meta == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      height: 1.1,
      fontWeight: FontWeight.w700,
    );

    for (final b in meta.boxes) {
      final color = b.color ?? const Color(0xFF2F6BFF);
      paint.color = color;

      final rect = Rect.fromLTRB(
        (b.x1.clamp(0.0, 1.0)) * size.width,
        (b.y1.clamp(0.0, 1.0)) * size.height,
        (b.x2.clamp(0.0, 1.0)) * size.width,
        (b.y2.clamp(0.0, 1.0)) * size.height,
      );

      // 画框
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );

      if (!showLabels) continue;

      // 画标签文本
      final label = b.label ?? 'obj';
      final conf = b.conf == null ? '' : ' ${(b.conf! * 100).toStringAsFixed(0)}%';
      final text = '$label$conf';

      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // 标签背景
      final bgPaint = Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.fill;

      final padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
      final bgRect = Rect.fromLTWH(
        rect.left,
        (rect.top - tp.height - padding.vertical).clamp(0.0, size.height),
        tp.width + padding.horizontal,
        tp.height + padding.vertical,
      );

      canvas.drawRect(bgRect, bgPaint);

      tp.paint(
        canvas,
        Offset(bgRect.left + padding.left, bgRect.top + padding.top),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AiOverlayPainter oldDelegate) {
    return oldDelegate.metadata != metadata || oldDelegate.showLabels != showLabels;
  }
}
