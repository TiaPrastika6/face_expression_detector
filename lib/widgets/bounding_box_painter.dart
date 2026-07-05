import 'dart:math';

import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import '../utils/expression_utils.dart';

class BoundingBoxPainter extends CustomPainter {
  BoundingBoxPainter({
    required this.detections,
    required this.imageSize,
    required this.isFrontCamera,
    required this.color,
  });

  final List<DetectionResult> detections;
  final Size imageSize;
  final bool isFrontCamera;

  // Warna ini tetap disimpan sebagai fallback/default.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = max(
      size.width / imageSize.width,
      size.height / imageSize.height,
    );

    final renderedWidth = imageSize.width * scale;
    final renderedHeight = imageSize.height * scale;

    final offsetX = (size.width - renderedWidth) / 2;
    final offsetY = (size.height - renderedHeight) / 2;

    for (final detection in detections) {
      final detectionColor = expressionColorFromLabel(detection.label);

      final boxPaint = Paint()
        ..color = detectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;

      final labelBackgroundPaint = Paint()
        ..color = detectionColor.withOpacity(0.88)
        ..style = PaintingStyle.fill;

      double left = offsetX + detection.rect.left * scale;
      double right = offsetX + detection.rect.right * scale;

      if (isFrontCamera) {
        final mirroredLeft = size.width - right;
        final mirroredRight = size.width - left;
        left = mirroredLeft;
        right = mirroredRight;
      }

      final rect = Rect.fromLTRB(
        left,
        offsetY + detection.rect.top * scale,
        right,
        offsetY + detection.rect.bottom * scale,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        boxPaint,
      );

      final labelText =
          '${detection.label} ${(detection.score * 100).toStringAsFixed(1)}%';

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = max(0.0, rect.top - textPainter.height - 10);

      final labelRect = Rect.fromLTWH(
        rect.left,
        labelTop,
        textPainter.width + 14,
        textPainter.height + 8,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(8)),
        labelBackgroundPaint,
      );

      textPainter.paint(
        canvas,
        Offset(labelRect.left + 7, labelRect.top + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.color != color;
  }
}