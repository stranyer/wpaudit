import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Título en mayúsculas con la inicial de cada palabra más grande (versalitas).
class CapsTitle extends StatelessWidget {
  const CapsTitle(this.text, {super.key, this.size = 18, this.color = Sutura.textHi, this.weight = FontWeight.w500});

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final words = text.toUpperCase().split(' ');
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      spans.add(TextSpan(text: w.substring(0, 1), style: TextStyle(fontSize: size * 1.25)));
      if (w.length > 1) spans.add(TextSpan(text: w.substring(1)));
      if (i < words.length - 1) spans.add(const TextSpan(text: ' '));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: SuturaText.display.copyWith(fontSize: size, color: color, fontWeight: weight),
    );
  }
}
