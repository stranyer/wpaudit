import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/hexagon.dart';

/// Joystick virtual del modo simulación. La dirección de pantalla se convierte
/// a este/norte según el rumbo del mapa; al tope del recorrido, corre.
class DemoJoystick extends StatefulWidget {
  const DemoJoystick({super.key, required this.bearingOf, this.size = 104});

  /// Rumbo actual de la cámara en grados (0 = norte arriba).
  final double Function() bearingOf;
  final double size;

  @override
  State<DemoJoystick> createState() => _DemoJoystickState();
}

class _DemoJoystickState extends State<DemoJoystick> with SingleTickerProviderStateMixin {
  static const _knob = 40.0;
  static const _dead = 0.12;
  static const _runAt = 0.92;

  late final AnimationController _spring = AnimationController(vsync: this, duration: Sutura.fast)
    ..addListener(() => setState(() => _offset = Offset.lerp(_releaseFrom, Offset.zero, Sutura.easeIn.transform(_spring.value))!));
  Offset _offset = Offset.zero;
  Offset _releaseFrom = Offset.zero;
  bool _active = false;

  double get _radius => widget.size / 2 - _knob / 2 + 4;

  @override
  void dispose() {
    _spring.dispose();
    app.location.demo?.setVelocity(0, 0);
    super.dispose();
  }

  void _update(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var v = local - center;
    if (v.distance > _radius) v = v / v.distance * _radius;
    setState(() {
      _offset = v;
      _active = true;
    });
    final n = v / _radius; // |n| <= 1
    final m = n.distance;
    final demo = app.location.demo;
    if (demo == null) return;
    if (m < _dead) {
      demo.setVelocity(0, 0);
      return;
    }
    // Pantalla (x derecha, y arriba) → este/norte, rotando por el rumbo del mapa.
    final sx = n.dx;
    final sy = -n.dy;
    final th = widget.bearingOf() * math.pi / 180;
    final east = sx * math.cos(th) + sy * math.sin(th);
    final north = -sx * math.sin(th) + sy * math.cos(th);
    final run = m >= _runAt;
    demo.setVelocity(east, north, run ? gameConfig.demo.runMultiplier : 1);
  }

  void _release() {
    app.location.demo?.setVelocity(0, 0);
    _releaseFrom = _offset;
    _active = false;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final running = _offset.distance / _radius >= _runAt;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(offset: _offset, active: _active, running: running, knob: _knob),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({required this.offset, required this.active, required this.running, required this.knob});

  final Offset offset;
  final bool active;
  final bool running;
  final double knob;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, Paint()..color = Sutura.surface1.withValues(alpha: active ? 0.85 : 0.6));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = active ? Sutura.signal.withValues(alpha: 0.6) : Sutura.lineStrong);
    // Anillo de carrera.
    canvas.drawCircle(c, r - 7, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (running ? Sutura.amber : Sutura.lineHair).withValues(alpha: running ? 0.8 : 1));
    // Retícula.
    final tick = Paint()
      ..color = Sutura.textLow
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 4), c + d * (r - 11), tick);
    }
    final k = c + offset;
    final hex = hexPath(k, knob / 2 - 2);
    if (active) {
      canvas.drawPath(hex, Paint()
        ..color = (running ? Sutura.amber : Sutura.signal).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.drawPath(hex, Paint()..color = Sutura.surface2);
    canvas.drawPath(hex, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = running ? Sutura.amber : (active ? Sutura.signal : Sutura.textMid));
    canvas.drawCircle(k, 2.5, Paint()..color = running ? Sutura.amber : Sutura.signal);
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.offset != offset || old.active != active || old.running != running;
}
