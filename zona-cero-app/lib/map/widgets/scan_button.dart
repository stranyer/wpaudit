import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../state/world_controller.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/grit.dart';
import 'hud.dart';

/// Botón cuadrado del escáner (columna derecha del mapa): radar con anillo de
/// recarga y rótulo "ESCANEAR" / segundos. Mantener 400 ms para cargar (el
/// anillo interior se llena) y soltar para disparar el pulso.
class ScanButton extends StatefulWidget {
  const ScanButton({super.key, this.width = 44, this.height = 62});

  final double width;
  final double height;

  @override
  State<ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<ScanButton> with TickerProviderStateMixin {
  static const _chargeMs = 400;

  late final AnimationController _charge =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _chargeMs))
        ..addStatusListener(_onChargeStatus);
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  Timer? _timer;
  int _left = 0;
  bool _hasFix = false;
  bool _holding = false;

  int get _now => DateTime.now().millisecondsSinceEpoch;
  bool get _ready => _left == 0 && _hasFix;

  @override
  void initState() {
    super.initState();
    app.world.addListener(_sync);
    app.location.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    app.world.removeListener(_sync);
    app.location.removeListener(_sync);
    _timer?.cancel();
    _charge.dispose();
    _sweep.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final left = app.world.scanCooldownLeft(_now);
    final fix = app.location.position != null;
    // Redondeo a décimas de segundo: basta para el anillo y evita repintar de más.
    final l = (left / 100).ceil() * 100;
    if (l != _left || fix != _hasFix) {
      setState(() {
        _left = l;
        _hasFix = fix;
      });
    }
    if (_left > 0) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _sync());
      if (_sweep.isAnimating) _sweep.stop();
    } else {
      _timer?.cancel();
      _timer = null;
      if (_hasFix && !_sweep.isAnimating) _sweep.repeat();
    }
  }

  void _onChargeStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      HapticFeedback.mediumImpact();
      setState(() {});
    }
  }

  void _down(PointerDownEvent _) {
    if (!_ready) return;
    _holding = true;
    HapticFeedback.selectionClick();
    _charge.forward(from: 0);
    setState(() {});
  }

  void _up(PointerUpEvent _) {
    if (!_ready) {
      // Durante la recarga, un toque informa el tiempo restante.
      app.scan();
      return;
    }
    if (!_holding) return;
    _holding = false;
    if (_charge.isCompleted) {
      _charge.value = 0;
      app.scan();
    } else {
      _charge.reverse();
    }
    setState(() {});
  }

  void _cancel(PointerCancelEvent _) {
    _holding = false;
    _charge.reverse();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final secs = (_left / 1000).ceil();
    final charged = _charge.isCompleted && _holding;
    final label = !_hasFix
        ? 'SIN GNSS'
        : _left > 0
            ? '$secs S'
            : charged
                ? 'SOLTÁ'
                : _holding
                    ? 'CARGA'
                    : 'ESCANEAR';
    final labelColor = !_hasFix
        ? Sutura.danger
        : _left > 0
            ? Sutura.textMid
            : charged
                ? Sutura.textHi
                : Sutura.signal;
    return Semantics(
      button: true,
      label: _left > 0 ? 'Escáner recargando, $secs segundos' : 'Escanear la zona. Mantené presionado y soltá.',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: GritPanel(
            padding: const EdgeInsets.fromLTRB(2, 5, 2, 5),
            background: _holding ? const Color(0xF0132029) : kMapControlFill,
            border: _ready ? Sutura.signal.withValues(alpha: 0.75) : kMapControlBorder,
            corners: null,
            glow: charged ? Sutura.signal : null,
            child: Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_charge, _sweep]),
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _RadarPainter(
                          cooldown: _left / WorldController.scanCooldownMs,
                          charge: _charge.value,
                          sweep: _ready ? _sweep.value : -1,
                          enabled: _hasFix,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: SuturaText.label.copyWith(fontSize: 7.5, letterSpacing: 1.1, color: labelColor, height: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.cooldown, required this.charge, required this.sweep, required this.enabled});

  /// Fracción de recarga restante (1 = recién disparado, 0 = listo).
  final double cooldown;
  final double charge;

  /// Barrido del radar en reposo (0..1), negativo = quieto.
  final double sweep;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 2;
    final ready = enabled && cooldown <= 0;
    final accent = !enabled ? Sutura.danger : (ready ? Sutura.signal : Sutura.textLow);

    // Pista del anillo de recarga.
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Sutura.lineHair);
    final progress = enabled ? (1 - cooldown).clamp(0.0, 1.0) : 0.0;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, progress * 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ready ? Sutura.signal : Sutura.signal.withValues(alpha: 0.55));

    // Retícula del radar.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.45);
    canvas.drawCircle(c, r * 0.55, grid);
    canvas.drawLine(c.translate(-r + 4, 0), c.translate(r - 4, 0), grid);
    canvas.drawLine(c.translate(0, -r + 4), c.translate(0, r - 4), grid);

    // Barrido.
    if (sweep >= 0) {
      final a = -math.pi / 2 + sweep * 2 * math.pi;
      final rect = Rect.fromCircle(center: c, radius: r - 3);
      canvas.drawArc(rect, a - 0.9, 0.9, true, Paint()
        ..shader = SweepGradient(
          endAngle: 0.9,
          colors: [Sutura.signal.withValues(alpha: 0), Sutura.signal.withValues(alpha: 0.45)],
          transform: GradientRotation(a - 0.9),
        ).createShader(rect));
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r - 3), Paint()
        ..strokeWidth = 1.2
        ..color = Sutura.signal);
    }

    // Carga (mantener presionado).
    if (charge > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 4), -math.pi / 2, charge * 2 * math.pi, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = charge >= 1 ? Sutura.textHi : Sutura.signal);
    }
    canvas.drawCircle(c, 2.2, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.cooldown != cooldown || old.charge != charge || old.sweep != sweep || old.enabled != enabled;
}
