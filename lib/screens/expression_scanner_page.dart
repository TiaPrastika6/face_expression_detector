import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import '../services/camera_store.dart' as camera_store;
import '../services/yolo_service.dart';
import '../utils/expression_utils.dart';
import '../widgets/app_header.dart';
import '../widgets/camera_panel.dart';
import '../widgets/control_buttons.dart';
import '../widgets/result_panel.dart';

class ExpressionScannerPage extends StatefulWidget {
  const ExpressionScannerPage({super.key});

  @override
  State<ExpressionScannerPage> createState() => _ExpressionScannerPageState();
}

class _ExpressionScannerPageState extends State<ExpressionScannerPage>
    with WidgetsBindingObserver {
  static const int detectionIntervalMs = 900;

  final YoloService _yoloService = YoloService();

  CameraController? _cameraController;

  CameraLensDirection _selectedLensDirection = CameraLensDirection.front;

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
    final result = _topResult;

    if (result == null) {
      return const Color(0xFF8B5CF6);
    }

    return expressionColorFromLabel(result.label);
  }

  IconData get _expressionIcon {
    final result = _topResult;

    if (result == null) {
      return Icons.face_retouching_natural;
    }

    return expressionIconFromLabel(result.label);
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
    _yoloService.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      final status = await _yoloService.loadModel();

      setState(() {
        _isModelReady = true;
        _status = status;
      });
    } catch (e) {
      setState(() {
        _isModelReady = false;
        _status = 'Gagal memuat model: $e';
      });
    }
  }

  CameraDescription _getSelectedCamera() {
    return camera_store.cameras.firstWhere(
      (camera) => camera.lensDirection == _selectedLensDirection,
      orElse: () => camera_store.cameras.first,
    );
  }

  String get _cameraLabel {
    if (_selectedLensDirection == CameraLensDirection.front) {
      return 'Kamera Depan';
    }

    if (_selectedLensDirection == CameraLensDirection.back) {
      return 'Kamera Belakang';
    }

    return 'Kamera';
  }

  Future<void> _switchCamera() async {
    final wasRunning = isCameraRunning;

    if (wasRunning) {
      await _stopCamera();
    }

    setState(() {
      _selectedLensDirection =
          _selectedLensDirection == CameraLensDirection.front
              ? CameraLensDirection.back
              : CameraLensDirection.front;

      _detections = [];
      _lastImageSize = null;
      _status = 'Berpindah ke $_cameraLabel...';
    });

    if (wasRunning) {
      await _startCamera();
    }
  }

  Future<void> _startCamera() async {
    if (_isStarting || isCameraRunning) return;

    if (!_isModelReady || !_yoloService.isReady) {
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
      if (camera_store.cameras.isEmpty) {
        setState(() {
          _status = 'Tidak ada kamera ditemukan.';
          _isStarting = false;
        });
        return;
      }

      final selectedCamera = _getSelectedCamera();

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
        _isStarting = false;
        _status = '$_cameraLabel aktif. Deteksi ekspresi berjalan otomatis...';
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
    if (!_isModelReady || !_yoloService.isReady) return;
    if (_isDetecting) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastInferenceTime < detectionIntervalMs) return;

    _lastInferenceTime = now;
    _isDetecting = true;

    try {
      final result = await _yoloService.processCameraImage(
        cameraImage: cameraImage,
        cameraDescription: _cameraController?.description,
      );

      if (!mounted) return;

      setState(() {
        _lastImageSize = result.imageSize;
        _detections = result.detections;

        if (result.detections.isEmpty) {
          _status = 'Belum ada wajah/ekspresi yang terdeteksi.';
        } else if (result.detections.length == 1) {
          _status = '1 wajah terdeteksi.';
        } else {
          _status = '${result.detections.length} wajah terdeteksi.';
        }
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
              AppHeader(
                color: activeColor,
                icon: _expressionIcon,
              ),
              Expanded(
                child: CameraPanel(
                  controller: _cameraController,
                  isCameraReady: _isCameraReady,
                  isStarting: _isStarting,
                  detections: _detections,
                  imageSize: _lastImageSize,
                  color: activeColor,
                ),
              ),
              ResultPanel(
                topResult: topResult,
                detections: _detections,
                status: _status,
                color: activeColor,
                icon: _expressionIcon,
              ),
              ControlButtons(
                isRunning: isCameraRunning,
                isStarting: _isStarting,
                isModelReady: _isModelReady,
                onStart: _startCamera,
                onStop: _stopCamera,
                onSwitchCamera: _switchCamera,
                color: activeColor,
                cameraLabel: _cameraLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}