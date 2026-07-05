import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'screens/expression_scanner_page.dart';
import 'services/camera_store.dart' as camera_store;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  camera_store.cameras = await availableCameras();
  runApp(const ExpressionScannerApp());
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