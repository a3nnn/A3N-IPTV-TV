import 'package:flutter/material.dart';

import '../config.dart';

/// The A3N logo + app name. [size] controls the overall scale.
class BrandMark extends StatelessWidget {
  final double size;
  final bool showName;
  const BrandMark({super.key, this.size = 48, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final logo = size * 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo.png',
          width: logo,
          height: logo,
          filterQuality: FilterQuality.none, // keep the pixel-art sharp
        ),
        if (showName) ...[
          SizedBox(height: size * 0.3),
          Text(
            'IPTV PLAYER',
            style: TextStyle(
              fontSize: size * 0.24,
              letterSpacing: size * 0.09,
              color: AppConfig.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
