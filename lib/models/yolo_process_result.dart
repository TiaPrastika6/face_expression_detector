import 'package:flutter/material.dart';

import 'detection_result.dart';

class YoloProcessResult {
  YoloProcessResult({
    required this.imageSize,
    required this.detections,
  });

  final Size imageSize;
  final List<DetectionResult> detections;
}