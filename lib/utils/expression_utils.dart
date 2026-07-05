import 'package:flutter/material.dart';

Color expressionColorFromLabel(String label) {
  final lowerLabel = label.toLowerCase();

  if (lowerLabel.contains('marah')) {
    return const Color(0xFFEF4444); // merah
  }

  if (lowerLabel.contains('sedih')) {
    return const Color(0xFF3B82F6); // biru
  }

  if (lowerLabel.contains('senang')) {
    return const Color(0xFFFACC15); // kuning
  }

  return const Color(0xFF8B5CF6); // ungu default
}

IconData expressionIconFromLabel(String label) {
  final lowerLabel = label.toLowerCase();

  if (lowerLabel.contains('marah')) {
    return Icons.sentiment_very_dissatisfied;
  }

  if (lowerLabel.contains('sedih')) {
    return Icons.sentiment_dissatisfied;
  }

  if (lowerLabel.contains('senang')) {
    return Icons.sentiment_very_satisfied;
  }

  return Icons.face_retouching_natural;
}