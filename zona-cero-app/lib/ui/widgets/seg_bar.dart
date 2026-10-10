import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Barra segmentada (progreso, carga, aportes).
class SegBar extends StatelessWidget {
  const SegBar({super.key, required this.value, required this.max, this.segments = 12, this.color = Sutura.signal, this.height = 6});

  final double value;
  final double max;
  final int segments;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final filled = (ratio * segments).round();
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: Sutura.base,
              height: height,
              color: i < filled ? color : Sutura.lineHair,
            ),
          ),
          if (i < segments - 1) const SizedBox(width: 2),
        ],
      ],
    );
  }
}

/// Micro-texto ornamental de calibración ("VITA-7 // AUTOCAL OK").
class MicroText extends StatelessWidget {
  const MicroText(this.text, {super.key, this.color = Sutura.textLow});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: SuturaText.micro.copyWith(color: color));
}
