import 'package:flutter/material.dart';

class DetectionResult {
  DetectionResult({
    required this.rect,
    required this.label,
    required this.score,
  });

  final Rect rect;
  final String label;
  final double score;
}