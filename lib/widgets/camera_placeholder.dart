import 'package:flutter/material.dart';

class CameraPlaceholder extends StatelessWidget {
  const CameraPlaceholder({
    super.key,
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