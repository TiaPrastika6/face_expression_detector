import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import '../utils/expression_utils.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.topResult,
    required this.status,
    required this.color,
    required this.icon,
    required this.detections,
  });

  final DetectionResult? topResult;
  final List<DetectionResult> detections;
  final String status;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final result = topResult;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withOpacity(0.13),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.20),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                result == null ? Icons.search_rounded : icon,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detections.isEmpty
                        ? 'Belum ada ekspresi terdeteksi'
                        : '${detections.length} wajah terdeteksi',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (detections.isNotEmpty)
                    ...detections.asMap().entries.map((entry) {
                      final index = entry.key + 1;
                      final detection = entry.value;
                      final detectionColor =
                          expressionColorFromLabel(detection.label);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$index. ${detection.label} • ${(detection.score * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: detectionColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }),
                  if (detections.isEmpty)
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBDB7D8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}