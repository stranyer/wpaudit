import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/grit.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/holo_in.dart';

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

class _BootScreenState extends State<BootScreen> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    // En pantallas bajas (360×640) se achican la red y los espacios para que todo entre.
    final h = MediaQuery.sizeOf(context).height - pad.vertical;
    final compact = h < 720;
    final netH = (h - 500).clamp(64.0, 190.0);
    return ColoredBox(
      color: Sutura.void_,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/art/bg/combat_street.webp',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.35),
              color: const Color(0x55000000),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (_, _, _) => const CustomPaint(painter: _GridPainter()),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.35, 0.62, 1],
                  colors: [Color(0xCC0A0B0C), Color(0x220A0B0C), Color(0xD90A0B0C), Color(0xFF0A0B0C)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, pad.top + (compact ? 14 : 28), 22, pad.bottom + (compact ? 12 : 22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('VITA-7 · TERMINAL DE CAMPO', style: SuturaText.label.copyWith(fontSize: 11)))),
                      const Spacer(),
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text('DESAM / C.A.B.A.', style: SuturaText.label.copyWith(fontSize: 11)))),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 26),
                  // Espacio para que se vea la calle (y el Obelisco) detrás del logo.
                  SizedBox(height: netH),
                  SizedBox(height: compact ? 8 : 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: GrungeTitle('Zona cero', size: compact ? 64 : 76, letterSpacing: 6, maxLines: 1),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('VITA-7  //  PROTOCOLO SUTURA', style: SuturaText.label.copyWith(color: Sutura.signal, letterSpacing: 4, fontSize: 14)),
                  ),
                  SizedBox(height: compact ? 10 : 22),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      // Si no entran todas las líneas, se muestran las últimas.
                      const lineH = 17.0;
                      final fit = (c.maxHeight / lineH).floor().clamp(0, _log.length);
                      final start = _log.length - fit;
                      return ClipRect(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = start; i < _log.length; i++)
                              HoloIn(
                                key: ValueKey(i),
                                child: SizedBox(
                                  height: lineH,
                                  child: Text(
                                    '> ${_log[i]}',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: SuturaText.mono.copyWith(
                                      fontSize: 11.5,
                                      color: i == _lines.length - 1 ? Sutura.accent : Sutura.textMid,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                  AnimatedOpacity(
                    opacity: _ready ? 1 : 0,
                    duration: Sutura.heavy,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BracketPanel(
                          color: Sutura.amber,
                          background: const Color(0xE6121415),
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
                        SizedBox(height: compact ? 8 : 14),
                        if (widget.returning != null) ...[
                          Center(child: Text(widget.returning!, style: SuturaText.mono.copyWith(color: Sutura.textMid, fontSize: 11))),
                          const SizedBox(height: 8),
                        ],
                        ChamferButton(
                          label: 'Conectar GPS',
                          sublabel: 'jugá caminando tu ciudad',
                          icon: Icons.satellite_alt_outlined,
                          tone: ChamferTone.primary,
                          height: compact ? 52 : 58,
                          expand: true,
                          onPressed: _ready && !widget.busy ? () => widget.onStart(true) : null,
                        ),
                        const SizedBox(height: 10),
                        ChamferButton(
                          label: 'Simulación · Buenos Aires',
                          sublabel: 'sin moverte, desde el Obelisco',
                          icon: Icons.gamepad_outlined,
                          tone: ChamferTone.neutral,
                          height: compact ? 48 : 54,
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
