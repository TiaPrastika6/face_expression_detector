import 'package:flutter/material.dart';

class LiveBadge extends StatelessWidget {
  const LiveBadge({
    super.key,
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