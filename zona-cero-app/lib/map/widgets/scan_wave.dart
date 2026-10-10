import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../state/world_controller.dart';
import '../../ui/theme/tokens.dart';
import '../game_map.dart';

/// Ruta del shader de refracción (hay que declararlo en `flutter: shaders:`).
const kScanRippleShader = 'lib/map/shaders/scan_ripple.frag';

/// Onda de choque del escáner, encima del mapa y debajo del HUD.
///
/// - Con Impeller (Android/iOS) y el shader [kScanRippleShader] disponible, un
///   `BackdropFilter` con `ImageFilter.shader` refracta de verdad todo lo que
///   hay debajo (el mapa es una textura de Flutter en Android: Virtual
///   Display / TextureView) alrededor del frente de onda.
/// - Siempre (y como única capa en web, donde el mapa es un elemento del DOM
///   que Flutter no puede muestrear) se dibuja la onda: anillo brillante con
///   desenfoque radial, separación cromática, líneas de interferencia y un
///   destello; además sacude levemente la vista ([shake]).
///
/// El frente avanza con la misma curva y duración que el revelado de
/// contactos del mapa, así cada contacto "se enciende" cuando la onda lo toca.
class ScanWave extends StatefulWidget {
  const ScanWave({super.key, required this.camera, required this.shake});

  final GameMapController camera;

  /// Desplazamiento (px) que la pantalla aplica al mapa para el sacudón.
  final ValueNotifier<Offset> shake;

  @override
  State<ScanWave> createState() => _ScanWaveState();
}

class _ScanWaveState extends State<ScanWave> with SingleTickerProviderStateMixin {
  static const _tailMs = 420;
  static const _totalMs = WorldController.scanDurationMs + _tailMs;
  static const _shakeMs = 420;

  static Future<ui.FragmentProgram?>? _program;
  ui.FragmentShader? _shader;

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _totalMs))
    ..addListener(_onTick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.shake.value = Offset.zero;
        if (mounted) setState(() {});
      }
    });
  int _seen = 0;
  LatLng? _origin;
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    _seen = app.world.lastScanAt;
    app.world.addListener(_onWorld);
    unawaited(_loadShader());
  }

  @override
  void dispose() {
    app.world.removeListener(_onWorld);
    _c.dispose();
    _shader?.dispose();
    super.dispose();
  }

  /// Solo con Impeller existe `ImageFilter.shader`; sin el shader declarado
  /// en el pubspec la carga falla y queda la onda dibujada.
  Future<void> _loadShader() async {
    if (kIsWeb || !ui.ImageFilter.isShaderFilterSupported) return;
    _program ??= ui.FragmentProgram.fromAsset(kScanRippleShader).then<ui.FragmentProgram?>((p) => p).catchError((Object e) {
      debugPrint('[Zona Cero] Shader de la onda no disponible ($e): se usa la onda dibujada.');
      return null;
    });
    final p = await _program;
    if (!mounted || p == null) return;
    try {
      _shader = p.fragmentShader();
    } catch (e) {
      debugPrint('[Zona Cero] Shader de la onda: $e');
    }
  }

  void _onWorld() {
    final w = app.world;
    if (w.lastScanAt == _seen) return;
    _seen = w.lastScanAt;
    final dt = DateTime.now().millisecondsSinceEpoch - w.lastScanAt;
    if (dt < 0 || dt >= WorldController.scanDurationMs) return;
    _origin = w.lastScanOrigin ?? app.location.position;
    _seed = w.lastScanAt;
    _c.forward(from: dt / _totalMs);
    setState(() {});
  }

  void _onTick() {
    final t = _c.value * _totalMs;
    if (t < _shakeMs) {
      final k = 1 - t / _shakeMs;
      final r = math.Random(_seed ^ (t ~/ 16));
      final a = r.nextDouble() * 2 * math.pi;
      final amp = 3.4 * k * k;
      widget.shake.value = Offset(math.cos(a), math.sin(a)) * amp;
    } else if (widget.shake.value != Offset.zero) {
      widget.shake.value = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.isAnimating) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final size = box.biggest;
            final t = _c.value * _totalMs;
            final o = _origin;
            final center = (o == null ? null : widget.camera.screenOffsetOf(o, size)) ?? size.center(Offset.zero);
            final rMax = WorldController.scanRadiusM / widget.camera.metersPerPx;
            final tilt = math.cos(widget.camera.tilt * math.pi / 180);
            final wave = ScanWaveFrame.at(t);
            final shader = _shader;
            return Stack(
              children: [
                if (shader != null && wave.strength > 0.01) Positioned.fill(child: _ripple(context, shader, center, rMax, wave)),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WavePainter(t: t, center: center, rMax: rMax, tilt: tilt, seed: _seed, frame: wave),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Refracción real de lo que hay debajo (Impeller).
  Widget _ripple(BuildContext context, ui.FragmentShader shader, Offset center, double rMax, ScanWaveFrame wave) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
    final size = MediaQuery.sizeOf(context) * dpr;
    final c = (origin + center) * dpr;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, c.dx)
      ..setFloat(3, c.dy)
      ..setFloat(4, wave.radius * rMax * dpr)
      ..setFloat(5, (24 + 34 * wave.radius) * dpr)
      ..setFloat(6, 15 * wave.strength * dpr);
    return BackdropFilter(filter: ui.ImageFilter.shader(shader), child: const SizedBox.expand());
  }
}

/// Estado de la onda en el instante `t` (ms desde el disparo). Puro, para
/// probarlo: radio relativo (0..1, curva del escáner), intensidad del anillo,
/// de la distorsión y de la interferencia.
@immutable
class ScanWaveFrame {
  const ScanWaveFrame({required this.radius, required this.ring, required this.strength, required this.glitch, required this.flash});

  factory ScanWaveFrame.at(double t) {
    const d = WorldController.scanDurationMs;
    final p = (t / d).clamp(0.0, 1.0);
    final radius = Sutura.scanCurve.transform(p);
    final appear = (t / 70).clamp(0.0, 1.0);
    final ring = t >= d ? 0.0 : math.pow(1 - p, 1.15).toDouble() * appear;
    // La distorsión es fuerte al salir y se apaga antes que el anillo.
    final strength = t >= d ? 0.0 : math.pow(1 - p, 1.6).toDouble() * appear;
    final glitch = t < 520 ? 1 - t / 520 : (t < d + 300 ? 0.18 : 0.0);
    final flash = t < 110 ? 1 - t / 110 : 0.0;
    return ScanWaveFrame(radius: radius, ring: ring, strength: strength, glitch: glitch, flash: flash);
  }

  final double radius;
  final double ring;
  final double strength;
  final double glitch;
  final double flash;
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.center, required this.rMax, required this.tilt, required this.seed, required this.frame});

  final double t;
  final Offset center;
  final double rMax;
  final double tilt;
  final int seed;
  final ScanWaveFrame frame;

  static const _steel = Sutura.signal;
  static const _red = Color(0xFFFF4A3D);
  static const _cyan = Color(0xFF7FE6FF);

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f.flash > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDDE8EE).withValues(alpha: 0.08 * f.flash));
    }
    final r = f.radius * rMax;
    if (f.ring > 0.002 && r > 1) {
      canvas.save();
      // Con la vista inclinada el anillo es una elipse sobre el suelo.
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, tilt);
      canvas.translate(-center.dx, -center.dy);
      final a = f.ring;
      // Lavado interior: más denso cerca del frente.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(center, r, [
            _steel.withValues(alpha: 0),
            _steel.withValues(alpha: 0),
            _steel.withValues(alpha: 0.10 * a),
            _steel.withValues(alpha: 0.02 * a),
          ], [0, 0.5, 0.96, 1]),
      );
      Paint ring(Color c, double w, double alpha, {double blur = 0, BlendMode mode = BlendMode.srcOver}) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = c.withValues(alpha: alpha.clamp(0.0, 1.0))
          ..blendMode = mode;
        if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
        return p;
      }

      // Estela hacia adentro (desenfoque radial).
      for (var i = 1; i <= 5; i++) {
        final ri = r - i * (4 + 5 * f.radius);
        if (ri <= 0) break;
        canvas.drawCircle(center, ri, ring(_steel, 2.4, 0.16 * a * (1 - i / 6), blur: 1.5 + i * 0.6));
      }
      // Resplandor del frente.
      canvas.drawCircle(center, r, ring(_steel, 12, 0.42 * a, blur: 7));
      // Separación cromática.
      canvas.drawCircle(center, r + 2.6, ring(_red, 1.6, 0.42 * a, mode: BlendMode.plus));
      canvas.drawCircle(center, r - 2.6, ring(_cyan, 1.6, 0.42 * a, mode: BlendMode.plus));
      // Núcleo del anillo.
      canvas.drawCircle(center, r, ring(const Color(0xFFF1F6F8), 1.8, 0.95 * a));
      // Marcas de radar sobre el frente.
      final tick = ring(const Color(0xFFF1F6F8), 1.4, 0.55 * a);
      final rot = t / 1000 * 0.6;
      for (var i = 0; i < 48; i++) {
        final ang = rot + i * math.pi / 24;
        final d = Offset(math.cos(ang), math.sin(ang));
        final len = i % 4 == 0 ? 7.0 : 3.0;
        canvas.drawLine(center + d * (r + 3), center + d * (r + 3 + len), tick);
      }
      canvas.restore();
    }

    // Interferencia: barras horizontales que parpadean (más al salir).
    if (f.glitch > 0) {
      final rng = math.Random(seed ^ (t ~/ 45));
      final n = 2 + rng.nextInt(4);
      for (var i = 0; i < n; i++) {
        if (f.glitch < 0.3 && rng.nextDouble() > 0.35) continue;
        final y = (center.dy + (rng.nextDouble() * 2 - 1) * math.max(r, 60)).clamp(0.0, size.height);
        final h = 1.0 + rng.nextDouble() * 2.5;
        final x0 = rng.nextDouble() * size.width * 0.5;
        final w = size.width * (0.25 + rng.nextDouble() * 0.75);
        final c = [_red, _cyan, const Color(0xFFFFFFFF)][rng.nextInt(3)];
        canvas.drawRect(
          Rect.fromLTWH(x0, y, w, h),
          Paint()
            ..color = c.withValues(alpha: (0.07 + rng.nextDouble() * 0.16) * f.glitch)
            ..blendMode = BlendMode.plus,
        );
      }
      // Bordes con separación cromática al disparar.
      if (t < 360) {
        final k = 1 - t / 360;
        canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), Paint()..color = _red.withValues(alpha: 0.22 * k));
        canvas.drawRect(Rect.fromLTWH(size.width - 3, 0, 3, size.height), Paint()..color = _cyan.withValues(alpha: 0.22 * k));
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.center != center || old.rMax != rMax || old.tilt != tilt;
}
