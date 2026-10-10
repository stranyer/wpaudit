import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

enum ChamferTone { primary, neutral, danger, amber, ghost }

/// Botón con chaflán de 45° en dos esquinas. Respuesta táctil seca, sin rebote.
class ChamferButton extends StatefulWidget {
  const ChamferButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = ChamferTone.neutral,
    this.icon,
    this.sublabel,
    this.height = 50,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final String? sublabel;
  final VoidCallback? onPressed;
  final ChamferTone tone;
  final IconData? icon;
  final double height;
  final bool expand;
  final bool dense;

  @override
  State<ChamferButton> createState() => _ChamferButtonState();
}

class _ChamferButtonState extends State<ChamferButton> {
  bool _down = false;

  (Color fill, Color line, Color text) get _colors {
    final enabled = widget.onPressed != null;
    if (!enabled) return (const Color(0xCC141618), Sutura.lineHair, Sutura.textLow);
    return switch (widget.tone) {
      // Rojo de emergencia: acción principal / defensiva destacada.
      ChamferTone.primary => (const Color(0xFF3A110E), Sutura.accent, const Color(0xFFF2D9D6)),
      ChamferTone.danger => (const Color(0xFF3A110E), Sutura.danger, const Color(0xFFFFD9DB)),
      // Ámbar: entregar recursos, recuperar botín.
      ChamferTone.amber => (const Color(0xFF2E2208), Sutura.amber, Sutura.amber),
      ChamferTone.ghost => (const Color(0xB0101214), Sutura.lineStrong, Sutura.textMid),
      ChamferTone.neutral => (const Color(0xE0181A1C), Sutura.lineBright, Sutura.textHi),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fill, line, text) = _colors;
    final dense = widget.dense;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: dense ? 18 : 22, color: text),
          SizedBox(width: dense ? 8 : 12),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.icon != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SuturaText.button.copyWith(color: text, fontSize: dense ? 14.5 : 18, letterSpacing: dense ? 2.0 : 2.8),
              ),
              if (widget.sublabel != null)
                Text(
                  widget.sublabel!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SuturaText.label.copyWith(color: text.withValues(alpha: 0.7), fontSize: dense ? 10.5 : 12, letterSpacing: 1.6),
                ),
            ],
          ),
        ),
      ],
    );
    final glow = widget.onPressed != null && (widget.tone == ChamferTone.primary || widget.tone == ChamferTone.amber);
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            },
      child: AnimatedContainer(
        duration: Sutura.snap,
        transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
        height: widget.height,
        child: CustomPaint(
          painter: ChamferPainter(fill: _down ? line.withValues(alpha: 0.32) : fill, line: line, glow: glow ? line : null, stroke: 1.4),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

/// Forma de botón: rectángulo con la esquina inferior derecha cortada a 45°.
class ChamferPainter extends CustomPainter {
  ChamferPainter({required this.fill, required this.line, this.cut = Sutura.chamfer, this.stroke = 1.2, this.glow});

  final Color fill;
  final Color line;
  final double cut;
  final double stroke;
  final Color? glow;

  static Path shape(Size s, double c) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - c)
    ..lineTo(s.width - c, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape(size, cut);
    if (glow != null) {
      canvas.drawPath(path, Paint()
        ..color = glow!.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 9));
    }
    canvas.drawPath(path, Paint()..color = fill);
    // Brillo interior sutil arriba (metal).
    canvas.drawRect(Rect.fromLTWH(1, 1, size.width - 2, size.height * 0.45), Paint()..color = const Color(0x0DFFFFFF));
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(ChamferPainter old) => old.fill != fill || old.line != line || old.cut != cut || old.glow != glow;
}
