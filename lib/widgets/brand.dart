// Fotoroll logo: the app icon plus the wordmark in the icon's gradient.
import 'package:flutter/material.dart';

const _gradient = LinearGradient(colors: [Color(0xFFFFA23F), Color(0xFFFF6B4A), Color(0xFFD9346C)]);

class FotorollLogo extends StatelessWidget {
  final double size; // icon height; the wordmark scales with it
  final bool vertical;
  const FotorollLogo({super.key, this.size = 36, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final icon = Image.asset('assets/branding/fotoroll.png', height: size, width: size);
    final word = ShaderMask(
      shaderCallback: (r) => _gradient.createShader(r),
      child: Text(
        'Fotoroll',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * (vertical ? 0.5 : 0.72),
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1,
        ),
      ),
    );
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [icon, SizedBox(height: size * 0.18), word])
        : Row(mainAxisSize: MainAxisSize.min, children: [icon, SizedBox(width: size * 0.28), word]);
  }
}
