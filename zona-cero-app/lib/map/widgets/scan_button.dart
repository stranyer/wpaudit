import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../state/world_controller.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/hexagon.dart';

/// Botón hexagonal del escáner: mantener 400 ms para cargar (el anillo se
/// llena) y soltar para disparar el pulso. Anillo exterior = recarga de 45 s.
class ScanButton extends StatefulWidget {
  const ScanButton({super.key, this.size = 76});

  /// Diámetro del hexágono (el anillo agrega 16 dp alrededor).
  final double size;

  @override
  State<ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<ScanButton> with TickerProviderStateMixin {
  static const _chargeMs = 400;

  late final AnimationController _charge =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _chargeMs))
        ..addStatusListener(_onChargeStatus);
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
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
    _idle.dispose();
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
      if (_idle.isAnimating) _idle.stop();
    } else {
      _timer?.cancel();
      _timer = null;
      if (_hasFix && !_idle.isAnimating) _idle.repeat();
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
    final box = widget.size + 16;
    final secs = (_left / 1000).ceil();
    final charged = _charge.isCompleted && _holding;
    final label = !_hasFix
        ? 'SIN SEÑAL'
        : _left > 0
            ? 'RECARGA'
            : charged
                ? 'SOLTÁ'
                : _holding
                    ? 'CARGANDO'
                    : 'ESCANEAR';
    return Semantics(
      button: true,
      label: 'Escanear la zona. Mantener presionado y soltar.',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: box,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_charge, _idle]),
              builder: (context, _) => CustomPaint(
                painter: _ScanPainter(
                  cooldown: _left / WorldController.scanCooldownMs,
                  charge: _charge.value,
                  breathe: _ready ? (math.sin(_idle.value * 2 * math.pi) + 1) / 2 : 0,
                  enabled: _hasFix,
                  pressed: _holding,
                ),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: widget.size * 0.30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_left > 0 && _hasFix)
                          Text(
                            '$secs',
                            style: SuturaText.mono.copyWith(fontSize: 18, height: 1, color: Sutura.textHi),
                          ),
                        Text(
                          label,
                          style: SuturaText.mono.copyWith(
                            fontSize: 8.5,
                            letterSpacing: 1.4,
                            height: 1.3,
                            color: !_hasFix
                                ? Sutura.offline
                                : _left > 0
                                    ? Sutura.textMid
                                    : charged
                                        ? Sutura.textHi
                                        : Sutura.signal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.cooldown,
    required this.charge,
    required this.breathe,
    required this.enabled,
    required this.pressed,
  });

  /// Fracción de recarga restante (1 = recién disparado, 0 = listo).
  final double cooldown;
  final double charge;
  final double breathe;
  final bool enabled;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ringR = size.shortestSide / 2 - 2;
    final hexR = ringR - 9;
    final ready = enabled && cooldown <= 0;
    final accent = ready ? Sutura.signal : Sutura.lineStrong;

    // Pista del anillo.
    canvas.drawCircle(c, ringR, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Sutura.lineHair);
    final arcRect = Rect.fromCircle(center: c, radius: ringR);
    if (enabled) {
      final progress = (1 - cooldown).clamp(0.0, 1.0);
      if (ready) {
        canvas.drawCircle(c, ringR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Sutura.signal.withValues(alpha: 0.10 + 0.18 * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
      canvas.drawArc(arcRect, -math.pi / 2, progress * 2 * math.pi, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.butt
        ..color = ready ? Sutura.signal : Sutura.signal.withValues(alpha: 0.55));
      // Marcas cada 45° (calibración).
      final tick = Paint()
        ..color = Sutura.textLow
        ..strokeWidth = 1;
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * (ringR + 3), c + d * (ringR + 6), tick);
      }
    }
    // Carga (mantener presionado).
    if (charge > 0) {
      canvas.drawArc(arcRect.deflate(4.5), -math.pi / 2, charge * 2 * math.pi, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = charge >= 1 ? Sutura.textHi : Sutura.signal);
    }

    // Hexágono.
    final hex = hexPath(c, hexR);
    if (ready) {
      canvas.drawPath(hex, Paint()
        ..color = Sutura.signal.withValues(alpha: 0.18 + 0.22 * math.max(breathe * 0.6, charge))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(hex, Paint()..color = Sutura.surface1Solid.withValues(alpha: 0.94));
    canvas.drawPath(hex, Paint()..color = accent.withValues(alpha: pressed ? 0.26 : 0.10));
    canvas.drawPath(hex, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = accent);

    // Glifo de sonar.
    final g = c.translate(0, -hexR * 0.22);
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = enabled ? (ready ? Sutura.signal : Sutura.textLow) : Sutura.offline.withValues(alpha: 0.7);
    canvas.drawCircle(g, 2.2, Paint()..color = glyph.color);
    for (final r in [6.0, 10.5]) {
      canvas.drawArc(Rect.fromCircle(center: g, radius: r), -math.pi * 0.85, math.pi * 0.7, false, glyph);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.cooldown != cooldown ||
      old.charge != charge ||
      old.breathe != breathe ||
      old.enabled != enabled ||
      old.pressed != pressed;
}
