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
    if (!enabled) return (Sutura.surface2.withValues(alpha: 0.6), Sutura.lineHair, Sutura.textLow);
    return switch (widget.tone) {
      ChamferTone.primary => (Sutura.signal.withValues(alpha: 0.14), Sutura.signal, Sutura.signal),
      ChamferTone.danger => (Sutura.danger.withValues(alpha: 0.16), Sutura.danger, const Color(0xFFFFD9DB)),
      ChamferTone.amber => (Sutura.amber.withValues(alpha: 0.14), Sutura.amber, Sutura.amber),
      ChamferTone.ghost => (const Color(0x00000000), Sutura.lineStrong, Sutura.textMid),
      ChamferTone.neutral => (Sutura.surface2, Sutura.lineStrong, Sutura.textHi),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fill, line, text) = _colors;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.dense ? 16 : 18, color: text),
          SizedBox(width: widget.dense ? 6 : 8),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SuturaText.button.copyWith(color: text, fontSize: widget.dense ? 13 : 15),
              ),
              if (widget.sublabel != null)
                Text(widget.sublabel!, style: SuturaText.micro.copyWith(color: text.withValues(alpha: 0.75), fontSize: 9.5)),
            ],
          ),
        ),
      ],
    );
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
          painter: ChamferPainter(fill: _down ? line.withValues(alpha: 0.28) : fill, line: line),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 18),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

/// Forma con chaflán arriba-izquierda y abajo-derecha.
class ChamferPainter extends CustomPainter {
  ChamferPainter({required this.fill, required this.line, this.cut = Sutura.chamfer, this.stroke = 1.2});

  final Color fill;
  final Color line;
  final double cut;
  final double stroke;

  static Path shape(Size s, double c) => Path()
    ..moveTo(c, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - c)
    ..lineTo(s.width - c, s.height)
    ..lineTo(0, s.height)
    ..lineTo(0, c)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape(size, cut);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(ChamferPainter old) => old.fill != fill || old.line != line || old.cut != cut;
}
