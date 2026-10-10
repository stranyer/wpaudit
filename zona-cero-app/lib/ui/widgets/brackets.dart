import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Panel con esquinas en L (en lugar de una caja cerrada), fondo translúcido
/// y línea fina. Es el contenedor base de la interfaz.
class BracketPanel extends StatelessWidget {
  const BracketPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Sutura.lineStrong,
    this.background = Sutura.surface1,
    this.border = true,
    this.bracket = Sutura.bracket,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color background;
  final bool border;
  final double bracket;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BracketPainter(color: color, background: background, border: border, size: bracket),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color, required this.background, required this.border, required this.size});

  final Color color;
  final Color background;
  final bool border;
  final double size;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..color = background);
    if (border) {
      canvas.drawRect(r.deflate(0.5), Paint()
        ..color = Sutura.lineHair
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square;
    final k = size;
    // Cuatro esquinas en L.
    canvas.drawPath(
      Path()
        ..moveTo(0, k)
        ..lineTo(0, 0)
        ..lineTo(k, 0)
        ..moveTo(s.width - k, 0)
        ..lineTo(s.width, 0)
        ..lineTo(s.width, k)
        ..moveTo(s.width, s.height - k)
        ..lineTo(s.width, s.height)
        ..lineTo(s.width - k, s.height)
        ..moveTo(k, s.height)
        ..lineTo(0, s.height)
        ..lineTo(0, s.height - k),
      p,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.background != background || old.border != border || old.size != size;
}
