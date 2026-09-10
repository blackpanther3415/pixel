import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The Pixel mark: a rounded-square bolt with the wordmark.
class PixelMark extends StatelessWidget {
  final double size;
  const PixelMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: const [
              BoxShadow(color: AppColors.primary, blurRadius: 18),
            ],
          ),
          child: Icon(Icons.bolt, color: Colors.white, size: size * 0.55),
        ),
        const SizedBox(width: 10),
        const Text(
          'PIXEL',
          style: TextStyle(
            color: AppColors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}