import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/hexagon.dart';
import '../widgets/holo_in.dart';
import '../widgets/seg_bar.dart';

/// Arranque de la terminal VITA-7: secuencia de conexión, aviso de seguridad
/// y elección entre GPS real o simulación.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key, required this.onStart, this.busy = false, this.returning});

  /// `true` = GPS real, `false` = simulación.
  final void Function(bool gps) onStart;
  final bool busy;

  /// Nombre y grado si ya hay una partida guardada.
  final String? returning;

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _net = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  final List<String> _log = [];
  Timer? _timer;
  bool _ready = false;

  static const _lines = [
    'VITA-7 // AUTOCAL OK',
    'MÓDULO GNSS ......... LISTO',
    'BUSCANDO RED DE RELEVO',
    'ESTABLECIENDO SUTURA… NODO 1/5',
    'ESTABLECIENDO SUTURA… NODO 3/5 · 128 MS',
    'ESTABLECIENDO SUTURA… NODO 5/5 · 96 MS',
    'RED ACTIVA. BIENVENIDO, ENLACE.',
  ];

  @override
  void initState() {
    super.initState();
    var i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 330), (t) {
      if (i >= _lines.length) {
        t.cancel();
        setState(() => _ready = true);
        return;
      }
      setState(() => _log.add(_lines[i++]));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _net.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Sutura.void_,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, pad.top + 28, 22, pad.bottom + 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      MicroText('VITA-7 · TERMINAL MÉDICA DE CAMPO'),
                      MicroText('DESAM / PROTOCOLO SUTURA'),
                    ],
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    height: 190,
                    child: AnimatedBuilder(
                      animation: _net,
                      builder: (context, _) => CustomPaint(painter: _NetworkPainter(_net.value)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ZONA CERO', style: TextStyle(fontFamily: Sutura.fLogo, fontWeight: FontWeight.w700, fontSize: 38, letterSpacing: 9, color: Sutura.textHi)),
                  ),
                  const SizedBox(height: 6),
                  Center(child: Text('PROTOCOLO SUTURA', style: SuturaText.mono.copyWith(color: Sutura.signal, letterSpacing: 6, fontSize: 12))),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, l) in _log.indexed)
                          HoloIn(
                            child: Text(
                              '> $l',
                              style: SuturaText.mono.copyWith(
                                fontSize: 11.5,
                                color: i == _lines.length - 1 ? Sutura.signal : Sutura.textMid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _ready ? 1 : 0,
                    duration: Sutura.heavy,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BracketPanel(
                          color: Sutura.amber,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Sutura.amber, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Mirá la calle, no la pantalla. No entres a propiedades privadas ni a lugares peligrosos y no juegues manejando. Tu ubicación exacta nunca se comparte.',
                                  style: SuturaText.bodyMid.copyWith(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (widget.returning != null) ...[
                          Center(child: Text(widget.returning!, style: SuturaText.mono.copyWith(color: Sutura.textMid, fontSize: 11))),
                          const SizedBox(height: 8),
                        ],
                        ChamferButton(
                          label: 'Conectar GPS',
                          sublabel: 'jugá caminando tu ciudad',
                          icon: Icons.satellite_alt_outlined,
                          tone: ChamferTone.primary,
                          height: 58,
                          expand: true,
                          onPressed: _ready && !widget.busy ? () => widget.onStart(true) : null,
                        ),
                        const SizedBox(height: 10),
                        ChamferButton(
                          label: 'Simulación · Buenos Aires',
                          sublabel: 'sin moverte, desde el Obelisco',
                          icon: Icons.gamepad_outlined,
                          tone: ChamferTone.ghost,
                          height: 54,
                          expand: true,
                          onPressed: _ready && !widget.busy ? () => widget.onStart(false) : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Sutura.lineHair.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Red de nodos hexagonales que se "suturan" progresivamente.
class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.t);
  final double t;

  static const _nodes = [
    Offset(0.5, 0.5),
    Offset(0.2, 0.25),
    Offset(0.8, 0.22),
    Offset(0.14, 0.78),
    Offset(0.86, 0.76),
    Offset(0.52, 0.06),
  ];
  static const _links = [(0, 1), (0, 2), (0, 3), (0, 4), (1, 5), (2, 5)];

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(int i) => Offset(_nodes[i].dx * size.width, _nodes[i].dy * size.height);
    for (final (i, (a, b)) in _links.indexed) {
      final start = i / _links.length * 0.7;
      final k = ((t - start) / 0.3).clamp(0.0, 1.0);
      if (k <= 0) continue;
      final pa = at(a);
      final pb = Offset.lerp(pa, at(b), k)!;
      final paint = Paint()
        ..color = Sutura.signal.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      // Línea punteada (sutura).
      final len = (pb - pa).distance;
      final dir = (pb - pa) / (len == 0 ? 1 : len);
      for (double d = 0; d < len; d += 7) {
        canvas.drawLine(pa + dir * d, pa + dir * math.min(d + 4, len), paint);
      }
    }
    for (final (i, n) in _nodes.indexed) {
      final appear = (t * 1.6 - i * 0.12).clamp(0.0, 1.0);
      if (appear <= 0) continue;
      final c = Offset(n.dx * size.width, n.dy * size.height);
      final r = i == 0 ? 22.0 : 12.0;
      final path = hexPath(c, r * appear);
      if (i == 0) {
        canvas.drawPath(path, Paint()
          ..color = Sutura.signal.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }
      canvas.drawPath(path, Paint()..color = Sutura.surface2);
      canvas.drawPath(path, Paint()
        ..color = i == 0 ? Sutura.signal : Sutura.lineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter old) => old.t != t;
}
