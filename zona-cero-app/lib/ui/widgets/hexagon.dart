import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

Path hexPath(Offset c, double r, {bool pointy = true}) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = (pointy ? -math.pi / 2 : 0) + i * math.pi / 3;
    final v = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    if (i == 0) {
      p.moveTo(v.dx, v.dy);
    } else {
      p.lineTo(v.dx, v.dy);
    }
  }
  return p..close();
}

/// Hexágono (nodo de red / refugio) con contenido centrado.
class HexBadge extends StatelessWidget {
  const HexBadge({
    super.key,
    required this.size,
    this.child,
    this.fill = Sutura.surface2,
    this.line = Sutura.signal,
    this.stroke = 1.5,
    this.glow = false,
  });

  final double size;
  final Widget? child;
  final Color fill;
  final Color line;
  final double stroke;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _HexPainter(fill: fill, line: line, stroke: stroke, glow: glow),
        child: Center(child: child),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({required this.fill, required this.line, required this.stroke, required this.glow});

  final Color fill;
  final Color line;
  final double stroke;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke;
    final path = hexPath(c, r);
    if (glow) {
      canvas.drawPath(path, Paint()
        ..color = line.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.fill != fill || old.line != line || old.stroke != stroke || old.glow != glow;
}
