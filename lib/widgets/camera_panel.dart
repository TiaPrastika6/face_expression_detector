import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import 'bounding_box_painter.dart';
import 'camera_placeholder.dart';
import 'live_badge.dart';

class CameraPanel extends StatelessWidget {
  const CameraPanel({
    super.key,
    required this.controller,
    required this.isCameraReady,
    required this.isStarting,
    required this.detections,
    required this.imageSize,
    required this.color,
  });

  final CameraController? controller;
  final bool isCameraReady;
  final bool isStarting;
  final List<DetectionResult> detections;
  final Size? imageSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final camera = controller;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withOpacity(0.13),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.16),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!isCameraReady ||
                  camera == null ||
                  !camera.value.isInitialized)
                CameraPlaceholder(
                  isStarting: isStarting,
                  color: color,
                )
              else
                CameraPreview(camera),
              if (camera != null &&
                  camera.value.isInitialized &&
                  imageSize != null)
                CustomPaint(
                  painter: BoundingBoxPainter(
                    detections: detections,
                    imageSize: imageSize!,
                    isFrontCamera: camera.description.lensDirection ==
                        CameraLensDirection.front,
                    color: color,
                  ),
                ),
              Positioned(
                top: 16,
                left: 16,
                child: LiveBadge(
                  isLive: isCameraReady,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}