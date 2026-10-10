import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

enum VitalState { fine, caution, cautionHigh, danger }

VitalState vitalFor(double ratio) {
  if (ratio > 0.66) return VitalState.fine;
  if (ratio > 0.4) return VitalState.caution;
  if (ratio > 0.2) return VitalState.cautionHigh;
  return VitalState.danger;
}

Color vitalColor(VitalState s) => switch (s) {
      VitalState.fine => Sutura.fine,
      VitalState.caution => Sutura.caution,
      VitalState.cautionHigh => Sutura.caution2,
      VitalState.danger => Sutura.danger,
    };

String vitalLabel(VitalState s) => switch (s) {
      VitalState.fine => 'ESTABLE',
      VitalState.caution => 'PRECAUCIÓN',
      VitalState.cautionHigh => 'PRECAUCIÓN',
      VitalState.danger => 'PELIGRO',
    };

/// Monitor ECG animado: el ritmo y el color dependen de la salud.
/// Con la salud baja el pulso se acelera y el trazo tiembla.
class EcgMonitor extends StatefulWidget {
  const EcgMonitor({super.key, required this.ratio, this.width = 96, this.height = 28, this.showLabel = true});

  final double ratio;
  final double width;
  final double height;
  final bool showLabel;

  @override
  State<EcgMonitor> createState() => _EcgMonitorState();
}

class _EcgMonitorState extends State<EcgMonitor> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => setState(() => _t = elapsed.inMicroseconds / 1e6))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = vitalFor(widget.ratio);
    final color = vitalColor(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _EcgPainter(t: _t, color: color, ratio: widget.ratio),
          ),
        ),
        if (widget.showLabel) ...[
          const SizedBox(width: 8),
          Text(vitalLabel(state), style: SuturaText.mono.copyWith(color: color, fontSize: 12, letterSpacing: 1.6)),
        ],
      ],
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter({required this.t, required this.color, required this.ratio});

  final double t;
  final Color color;
  final double ratio;

  /// Forma de un latido normalizada (0..1 en x, -1..1 en y).
  static double beat(double x) {
    if (x < 0.30) return 0.05 * math.sin(x * 40);
    if (x < 0.36) return -0.15;
    if (x < 0.40) return 1.0;
    if (x < 0.44) return -0.55;
    if (x < 0.52) return 0.0;
    if (x < 0.66) return 0.22 * math.sin((x - 0.52) / 0.14 * math.pi);
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Grilla tenue.
    final grid = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final bpm = 62 + (1 - ratio.clamp(0, 1)) * 70;
    final period = 60 / bpm;
    final jitter = ratio < 0.2 ? 0.12 : 0.0;
    final path = Path();
    const samples = 64;
    for (var i = 0; i <= samples; i++) {
      final x = i / samples;
      // La onda se desplaza hacia la izquierda.
      final phase = ((t / period) - x * 1.6) % 1.0;
      final y = beat(phase) + (jitter > 0 ? jitter * math.sin(t * 37 + i) : 0);
      final dy = size.height / 2 - y * size.height * 0.42;
      final dx = x * size.width;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_EcgPainter old) => old.t != t || old.color != color || old.ratio != ratio;
}
