// Fotoroll logo: the film-reel mark plus a lowercase wordmark, styled like the
// Immich logo it sits next to (same palette; wordmark #ACCBFA dark / #4251B0 light).
import 'package:flutter/material.dart';

class FotorollLogo extends StatelessWidget {
  final double size; // mark height; the wordmark scales with it
  final bool vertical;
  const FotorollLogo({super.key, this.size = 36, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mark = Image.asset('assets/branding/fotoroll.png', height: size, width: size);
    final word = Text(
      'fotoroll',
      style: TextStyle(
        color: dark ? const Color(0xFFACCBFA) : const Color(0xFF4251B0),
        fontSize: size * (vertical ? 0.5 : 0.78),
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1,
      ),
    );
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(height: size * 0.18), word])
        : Row(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(width: size * 0.22), word]);
  }
}
