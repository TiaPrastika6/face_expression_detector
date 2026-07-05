import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection_result.dart';
import '../models/yolo_process_result.dart';

class YoloService {
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;

  Interpreter? _interpreter;
  List<String> _labels = [];

  bool get isReady {
    return _interpreter != null;
  }

  Future<String> loadModel() async {
    final options = InterpreterOptions()..threads = 4;

    _interpreter = await Interpreter.fromAsset(
      'assets/best_float32.tflite',
      options: options,
    );

    final labelsText = await rootBundle.loadString(
      'assets/labels.txt',
    );

    _labels = labelsText
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;

    return 'Model siap. Class: ${_labels.length} | Input: $inputShape | Output: $outputShape';
  }

  Future<YoloProcessResult> processCameraImage({
    required CameraImage cameraImage,
    required CameraDescription? cameraDescription,
  }) async {
    final rgbImage = _convertYUV420ToImage(cameraImage);
    img.Image processedImage = rgbImage;

    final sensorOrientation = cameraDescription?.sensorOrientation ?? 0;

    if (sensorOrientation != 0) {
      processedImage = img.copyRotate(
        processedImage,
        angle: sensorOrientation,
      );
    }

    final originalWidth = processedImage.width;
    final originalHeight = processedImage.height;

    final resizedImage = img.copyResize(
      processedImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = _imageToInput(resizedImage);

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final output = _createOutputBuffer(outputShape);

    _interpreter!.run(input, output);

    final detections = _parseYoloOutput(
      output: output,
      outputShape: outputShape,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );

    return YoloProcessResult(
      imageSize: Size(
        originalWidth.toDouble(),
        originalHeight.toDouble(),
      ),
      detections: detections,
    );
  }

  img.Image _convertYUV420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final img.Image rgbImage = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final yp = yBytes[yIndex];
        final up = uBytes[uvIndex];
        final vp = vBytes[uvIndex];

        int r = (yp + 1.402 * (vp - 128)).round();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
        int b = (yp + 1.772 * (up - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return rgbImage;
  }

  List<List<List<List<double>>>> _imageToInput(img.Image image) {
    return List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              pixel.r.toDouble() / 255.0,
              pixel.g.toDouble() / 255.0,
              pixel.b.toDouble() / 255.0,
            ];
          },
        ),
      ),
    );
  }

  dynamic _createOutputBuffer(List<int> shape) {
    if (shape.length == 1) {
      return List<double>.filled(shape[0], 0.0);
    }

    return List.generate(
      shape[0],
      (_) => _createOutputBuffer(shape.sublist(1)),
    );
  }

  List<DetectionResult> _parseYoloOutput({
    required dynamic output,
    required List<int> outputShape,
    required int originalWidth,
    required int originalHeight,
  }) {
    if (outputShape.length != 3) {
      throw Exception('Output YOLO tidak dikenali: $outputShape');
    }

    final raw = output[0] as List;

    final numberOfClasses = _labels.length;
    final firstDim = raw.length;
    final secondDim = (raw[0] as List).length;

    late final int numberOfBoxes;
    late final int attributes;
    late final bool isTransposed;

    if (firstDim == numberOfClasses + 4 || firstDim == numberOfClasses + 5) {
      attributes = firstDim;
      numberOfBoxes = secondDim;
      isTransposed = true;
    } else {
      numberOfBoxes = firstDim;
      attributes = secondDim;
      isTransposed = false;
    }

    double valueAt(int boxIndex, int attrIndex) {
      final value = isTransposed
          ? (raw[attrIndex] as List)[boxIndex]
          : (raw[boxIndex] as List)[attrIndex];

      if (value is double) return value;
      if (value is int) return value.toDouble();
      return double.parse(value.toString());
    }

    final List<DetectionResult> candidates = [];

    for (int i = 0; i < numberOfBoxes; i++) {
      double cx = valueAt(i, 0);
      double cy = valueAt(i, 1);
      double w = valueAt(i, 2);
      double h = valueAt(i, 3);

      final bool normalized =
          cx <= 2.0 && cy <= 2.0 && w <= 2.0 && h <= 2.0;

      if (normalized) {
        cx *= inputSize;
        cy *= inputSize;
        w *= inputSize;
        h *= inputSize;
      }

      int classStartIndex = 4;
      double objectness = 1.0;

      if (attributes == numberOfClasses + 5) {
        objectness = valueAt(i, 4);
        classStartIndex = 5;
      }

      double bestClassScore = 0.0;
      int bestClassIndex = 0;

      for (int c = 0; c < numberOfClasses; c++) {
        final score = valueAt(i, classStartIndex + c);
        if (score > bestClassScore) {
          bestClassScore = score;
          bestClassIndex = c;
        }
      }

      final confidence = objectness * bestClassScore;

      if (confidence < confidenceThreshold) continue;

      double x1 = cx - (w / 2);
      double y1 = cy - (h / 2);
      double x2 = cx + (w / 2);
      double y2 = cy + (h / 2);

      x1 = x1.clamp(0, inputSize.toDouble()).toDouble();
      y1 = y1.clamp(0, inputSize.toDouble()).toDouble();
      x2 = x2.clamp(0, inputSize.toDouble()).toDouble();
      y2 = y2.clamp(0, inputSize.toDouble()).toDouble();

      final scaleX = originalWidth / inputSize;
      final scaleY = originalHeight / inputSize;

      final rect = Rect.fromLTRB(
        x1 * scaleX,
        y1 * scaleY,
        x2 * scaleX,
        y2 * scaleY,
      );

      if (rect.width <= 1 || rect.height <= 1) continue;

      final label = bestClassIndex < _labels.length
          ? _labels[bestClassIndex]
          : 'class_$bestClassIndex';

      candidates.add(
        DetectionResult(
          rect: rect,
          label: label,
          score: confidence,
        ),
      );
    }

    return _nonMaxSuppression(candidates, iouThreshold);
  }

  List<DetectionResult> _nonMaxSuppression(
    List<DetectionResult> detections,
    double threshold,
  ) {
    detections.sort((a, b) => b.score.compareTo(a.score));

    final List<DetectionResult> selected = [];

    for (final detection in detections) {
      bool shouldSelect = true;

      for (final chosen in selected) {
        if (_iou(detection.rect, chosen.rect) > threshold) {
          shouldSelect = false;
          break;
        }
      }

      if (shouldSelect) {
        selected.add(detection);
      }
    }

    return selected;
  }

  double _iou(Rect a, Rect b) {
    final x1 = max(a.left, b.left);
    final y1 = max(a.top, b.top);
    final x2 = min(a.right, b.right);
    final y2 = min(a.bottom, b.bottom);

    final intersectionWidth = max(0.0, x2 - x1);
    final intersectionHeight = max(0.0, y2 - y1);
    final intersectionArea = intersectionWidth * intersectionHeight;

    final unionArea =
        a.width * a.height + b.width * b.height - intersectionArea;

    if (unionArea <= 0) return 0.0;

    return intersectionArea / unionArea;
  }

  void dispose() {
    _interpreter?.close();
  }
}