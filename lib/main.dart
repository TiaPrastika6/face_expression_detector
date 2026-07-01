import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

late final List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const ExpressionScannerApp());
}

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

class ExpressionScannerApp extends StatelessWidget {
  const ExpressionScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expression Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8B5CF6),
        useMaterial3: true,
      ),
      home: const ExpressionScannerPage(),
    );
  }
}

class ExpressionScannerPage extends StatefulWidget {
  const ExpressionScannerPage({super.key});

  @override
  State<ExpressionScannerPage> createState() => _ExpressionScannerPageState();
}

class _ExpressionScannerPageState extends State<ExpressionScannerPage>
    with WidgetsBindingObserver {
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;

  // Makin kecil makin cepat, tapi HP makin berat.
  // 900 = deteksi sekitar 1 kali per 0.9 detik.
  static const int detectionIntervalMs = 900;

  CameraController? _cameraController;
  Interpreter? _interpreter;

  List<String> _labels = [];
  List<DetectionResult> _detections = [];

  Size? _lastImageSize;

  bool _isModelReady = false;
  bool _isCameraReady = false;
  bool _isDetecting = false;
  bool _isStarting = false;

  String _status = 'Memuat model ekspresi...';
  int _lastInferenceTime = 0;

  bool get isCameraRunning {
    final controller = _cameraController;
    return controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages;
  }

  DetectionResult? get _topResult {
    if (_detections.isEmpty) return null;
    return _detections.first;
  }

  Color get _expressionColor {
    final label = _topResult?.label.toLowerCase() ?? '';

    if (label.contains('marah')) return const Color(0xFFEF4444);
    if (label.contains('sedih')) return const Color(0xFF3B82F6);
    if (label.contains('senang')) return const Color(0xFFFACC15);

    return const Color(0xFF8B5CF6);
  }

  IconData get _expressionIcon {
    final label = _topResult?.label.toLowerCase() ?? '';

    if (label.contains('marah')) {
      return Icons.sentiment_very_dissatisfied;
    }

    if (label.contains('sedih')) {
      return Icons.sentiment_dissatisfied;
    }

    if (label.contains('senang')) {
      return Icons.sentiment_very_satisfied;
    }

    return Icons.face_retouching_natural;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadModel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _interpreter?.close();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
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

      setState(() {
        _isModelReady = true;
        _status =
            'Model siap. Class: ${_labels.length} | Input: $inputShape | Output: $outputShape';
      });
    } catch (e) {
      setState(() {
        _isModelReady = false;
        _status = 'Gagal memuat model: $e';
      });
    }
  }

  Future<void> _startCamera() async {
    if (_isStarting || isCameraRunning) return;

    if (!_isModelReady || _interpreter == null) {
      setState(() {
        _status = 'Model belum siap. Tunggu sebentar.';
      });
      return;
    }

    setState(() {
      _isStarting = true;
      _status = 'Membuka kamera...';
      _detections = [];
      _lastImageSize = null;
    });

    try {
      if (cameras.isEmpty) {
        setState(() {
          _status = 'Tidak ada kamera ditemukan.';
          _isStarting = false;
        });
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
        _isStarting = false;
        _status = 'Kamera aktif. Deteksi ekspresi berjalan otomatis...';
      });

      await _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isStarting = false;
        _isCameraReady = false;
        _status = 'Gagal membuka kamera: $e';
      });
    }
  }

  Future<void> _stopCamera() async {
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      await _cameraController?.dispose();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _cameraController = null;
      _isCameraReady = false;
      _isDetecting = false;
      _detections = [];
      _lastImageSize = null;
      _status = 'Kamera berhenti. Tekan Start untuk mulai lagi.';
    });
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (!_isModelReady || _interpreter == null) return;
    if (_isDetecting) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastInferenceTime < detectionIntervalMs) return;

    _lastInferenceTime = now;
    _isDetecting = true;

    try {
      final rgbImage = _convertYUV420ToImage(cameraImage);
      img.Image processedImage = rgbImage;

      final sensorOrientation =
          _cameraController?.description.sensorOrientation ?? 0;

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

      if (!mounted) return;

      setState(() {
        _lastImageSize = Size(
          originalWidth.toDouble(),
          originalHeight.toDouble(),
        );
        _detections = detections;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = 'Error saat deteksi: $e';
      });
    } finally {
      _isDetecting = false;
    }
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

  @override
  Widget build(BuildContext context) {
    final topResult = _topResult;
    final activeColor = _expressionColor;

    return Scaffold(
      backgroundColor: const Color(0xFF09090F),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F1020),
                activeColor.withOpacity(0.22),
                const Color(0xFF09090F),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              _Header(
                color: activeColor,
                icon: _expressionIcon,
              ),
              Expanded(
                child: _CameraPanel(
                  controller: _cameraController,
                  isCameraReady: _isCameraReady,
                  isStarting: _isStarting,
                  detections: _detections,
                  imageSize: _lastImageSize,
                  color: activeColor,
                ),
              ),
              _ResultPanel(
                topResult: topResult,
                status: _status,
                color: activeColor,
                icon: _expressionIcon,
              ),
              _ControlButtons(
                isRunning: isCameraRunning,
                isStarting: _isStarting,
                isModelReady: _isModelReady,
                onStart: _startCamera,
                onStop: _stopCamera,
                color: activeColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withOpacity(0.40),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expression Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Deteksi ekspresi wajah YOLOv8 TFLite',
                  style: TextStyle(
                    color: Color(0xFFBDB7D8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
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
                _CameraPlaceholder(
                  isStarting: isStarting,
                  color: color,
                )
              else
                CameraPreview(camera),
              if (camera != null &&
                  camera.value.isInitialized &&
                  imageSize != null)
                CustomPaint(
                  painter: _BoundingBoxPainter(
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
                child: _LiveBadge(
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

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({
    required this.isStarting,
    required this.color,
  });

  final bool isStarting;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF11111C),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isStarting)
              CircularProgressIndicator(
                color: color,
              )
            else
              Container(
                height: 90,
                width: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                  border: Border.all(
                    color: color.withOpacity(0.45),
                  ),
                ),
                child: Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.white.withOpacity(0.9),
                  size: 40,
                ),
              ),
            const SizedBox(height: 18),
            Text(
              isStarting ? 'Mengaktifkan kamera...' : 'Kamera belum aktif',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tekan Start untuk memulai deteksi ekspresi.',
              style: TextStyle(
                color: Color(0xFFBDB7D8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({
    required this.isLive,
    required this.color,
  });

  final bool isLive;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLive ? color.withOpacity(0.8) : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 8,
            width: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? Colors.greenAccent : Colors.white38,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isLive ? 'LIVE' : 'OFF',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.topResult,
    required this.status,
    required this.color,
    required this.icon,
  });

  final DetectionResult? topResult;
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
                    result == null
                        ? 'Belum ada ekspresi terdeteksi'
                        : '${result.label} • ${(result.score * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
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

class _ControlButtons extends StatelessWidget {
  const _ControlButtons({
    required this.isRunning,
    required this.isStarting,
    required this.isModelReady,
    required this.onStart,
    required this.onStop,
    required this.color,
  });

  final bool isRunning;
  final bool isStarting;
  final bool isModelReady;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed:
                    (!isRunning && !isStarting && isModelReady) ? onStart : null,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white.withOpacity(0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Start',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 54,
              child: OutlinedButton.icon(
                onPressed: isRunning ? onStop : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: isRunning
                        ? Colors.redAccent
                        : Colors.white.withOpacity(0.18),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.stop_rounded),
                label: const Text(
                  'Stop',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter({
    required this.detections,
    required this.imageSize,
    required this.isFrontCamera,
    required this.color,
  });

  final List<DetectionResult> detections;
  final Size imageSize;
  final bool isFrontCamera;
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

    final boxPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final labelBackgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.78)
      ..style = PaintingStyle.fill;

    for (final detection in detections) {
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
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.color != color;
  }
}