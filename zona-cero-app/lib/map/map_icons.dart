import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../core/core.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/hexagon.dart';

/// Estado visual de un marcador.
enum MarkerState { on, echo, sel }

/// Íconos de mapa dibujados en tiempo de ejecución con `dart:ui` y
/// registrados como PNG en el estilo (`addImage`).
///
/// Escala: maplibre-gl-js registra las imágenes con pixelRatio 1, mientras que
/// maplibre-native Android usa la densidad del Bitmap (≈ devicePixelRatio).
/// Por eso se dibujan a `renderScale` y se corrige con `icon-size` ([baseSize]).
abstract final class MapIcons {
  /// Tamaño lógico de los marcadores (forma arriba, mástil y marca en el suelo).
  static const w = 44.0;
  static const h = 58.0;
  static const playerSize = 52.0;

  static String zombie(int rating, MarkerState s) => 'zc-z$rating-${s.name}';
  static String supply(SupplyTypeId t, MarkerState s) => 'zc-s-${t.key}-${s.name}';
  static String node({required bool own, required int level, required bool selected}) =>
      'zc-n-${own ? 'own' : 'net'}-${level.clamp(1, 5)}-${selected ? 'sel' : 'on'}';
  static const player = 'zc-player';
  static const playerIdle = 'zc-player-idle';

  static double renderScale(double dpr) => dpr.clamp(2.0, 3.5);

  /// `icon-size` que muestra el ícono en su tamaño lógico.
  static double baseSize(double dpr) => kIsWeb ? 1 / renderScale(dpr) : dpr / renderScale(dpr);

  static final Map<String, Uint8List> _cache = {};
  static double _cacheScale = 0;

  /// Dibuja (o reutiliza) y registra todos los íconos en el estilo actual.
  static Future<void> register(ml.MapLibreMapController c, double dpr) async {
    final scale = renderScale(dpr);
    if (scale != _cacheScale) {
      _cache.clear();
      _cacheScale = scale;
    }
    final specs = _specs();
    // Primero se dibuja todo (en paralelo) y después se registra.
    await Future.wait([
      for (final e in specs.entries)
        if (!_cache.containsKey(e.key))
          _render(e.value.$1, e.value.$2, scale, e.value.$3).then((b) => _cache[e.key] = b),
    ]);
    for (final name in specs.keys) {
      await c.addImage(name, _cache[name]!);
    }
  }

  static Map<String, (double, double, void Function(Canvas))> _specs() {
    final out = <String, (double, double, void Function(Canvas))>{
      player: (playerSize, playerSize, (c) => _player(c, heading: true)),
      playerIdle: (playerSize, playerSize, (c) => _player(c, heading: false)),
    };
    for (var r = 0; r <= 3; r++) {
      for (final s in MarkerState.values) {
        out[zombie(r, s)] = (w, h, (c) => _threat(c, r, s));
      }
    }
    for (final t in SupplyTypeId.values) {
      for (final s in MarkerState.values) {
        out[supply(t, s)] = (w, h, (c) => _supply(c, t, s));
      }
    }
    for (final own in [true, false]) {
      for (var l = 1; l <= 5; l++) {
        for (final sel in [false, true]) {
          out[node(own: own, level: l, selected: sel)] = (w, h, (c) => _node(c, own, l, sel));
        }
      }
    }
    return out;
  }

  static Future<Uint8List> _render(double lw, double lh, double scale, void Function(Canvas) paint) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, lw * scale, lh * scale));
    canvas.scale(scale);
    paint(canvas);
    final picture = rec.endRecording();
    final img = await picture.toImage((lw * scale).ceil(), (lh * scale).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  // -------------------------------------------------------------------------
  // Piezas comunes
  // -------------------------------------------------------------------------

  static const _cx = 22.0;
  static const _ground = 54.5;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.miter
    ..isAntiAlias = true;

  static Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  static void _glow(Canvas c, Path p, Color color, double sigma, double alpha) {
    c.drawPath(p, Paint()
      ..color = color.withValues(alpha: alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
  }

  /// Mástil y marca en el suelo (da lectura 3D con el mapa inclinado).
  static void _stem(Canvas c, double fromY, Color color, {bool dashed = false, double width = 1}) {
    final p = _stroke(color.withValues(alpha: 0.55), width);
    if (dashed) {
      for (var y = fromY; y < _ground - 2; y += 4) {
        c.drawLine(Offset(_cx, y), Offset(_cx, math.min(y + 2, _ground - 2)), p);
      }
    } else {
      c.drawLine(Offset(_cx, fromY), Offset(_cx, _ground - 2), p);
    }
    final ground = Rect.fromCenter(center: const Offset(_cx, _ground), width: 11, height: 3.6);
    c.drawOval(ground, _fill(color.withValues(alpha: 0.22)));
    c.drawOval(ground, _stroke(color.withValues(alpha: 0.7), 1));
  }

  /// Corchetes de "objetivo fijado" alrededor de la forma.
  static void _brackets(Canvas c) {
    const l = 5.0, t = 5.0, r = 39.0, b = 42.0, k = 6.0;
    final p = _stroke(Sutura.textHi, 1.6)..strokeCap = StrokeCap.square;
    c.drawPath(
      Path()
        ..moveTo(l, t + k)
        ..lineTo(l, t)
        ..lineTo(l + k, t)
        ..moveTo(r - k, t)
        ..lineTo(r, t)
        ..lineTo(r, t + k)
        ..moveTo(r, b - k)
        ..lineTo(r, b)
        ..lineTo(r - k, b)
        ..moveTo(l + k, b)
        ..lineTo(l, b)
        ..lineTo(l, b - k),
      p,
    );
  }

  // -------------------------------------------------------------------------
  // Amenaza (zombie): rombo rojo + marcas de peligro relativo
  // -------------------------------------------------------------------------

  static void _threat(Canvas c, int rating, MarkerState s) {
    const cy = 24.0, rr = 13.0;
    final diamond = Path()
      ..moveTo(_cx, cy - rr)
      ..lineTo(_cx + rr, cy)
      ..lineTo(_cx, cy + rr)
      ..lineTo(_cx - rr, cy)
      ..close();
    const red = Sutura.danger;
    final echo = s == MarkerState.echo;
    _stem(c, cy + rr + 2, red, dashed: echo);
    if (echo) {
      c.drawPath(diamond, _fill(Sutura.void_.withValues(alpha: 0.45)));
      c.drawPath(diamond, _stroke(red.withValues(alpha: 0.9), 1.4));
      c.drawCircle(const Offset(_cx, cy), 2, _fill(red.withValues(alpha: 0.8)));
    } else {
      _glow(c, diamond, red, s == MarkerState.sel ? 7 : 4, s == MarkerState.sel ? 0.75 : 0.5);
      c.drawPath(diamond, _fill(red.withValues(alpha: 0.92)));
      c.drawPath(diamond, _stroke(const Color(0xFFFF9BA1), s == MarkerState.sel ? 1.6 : 1.1));
      // Núcleo clínico: rombo interior oscuro.
      const ir = 5.5;
      final inner = Path()
        ..moveTo(_cx, cy - ir)
        ..lineTo(_cx + ir, cy)
        ..lineTo(_cx, cy + ir)
        ..lineTo(_cx - ir, cy)
        ..close();
      c.drawPath(inner, _stroke(Sutura.void_.withValues(alpha: 0.85), 1.6));
    }
    if (rating == 3 && !echo) {
      // Mortal: doble contorno.
      const or = rr + 3.5;
      c.drawPath(
        Path()
          ..moveTo(_cx, cy - or)
          ..lineTo(_cx + or, cy)
          ..lineTo(_cx, cy + or)
          ..lineTo(_cx - or, cy)
          ..close(),
        _stroke(red.withValues(alpha: 0.7), 1),
      );
    }
    // Marcas de amenaza relativas al grado del jugador (1-3).
    if (rating > 0) {
      const tw = 2.4, gap = 2.6;
      final total = rating * tw + (rating - 1) * gap;
      var x = _cx - total / 2;
      final tick = _fill(echo ? red.withValues(alpha: 0.6) : (s == MarkerState.sel ? Sutura.textHi : red));
      for (var i = 0; i < rating; i++) {
        c.drawRect(Rect.fromLTWH(x, 1.5, tw, 5), tick);
        x += tw + gap;
      }
    }
    if (s == MarkerState.sel) _brackets(c);
  }

  // -------------------------------------------------------------------------
  // Suministro: cuadrado con chaflán + glifo
  // -------------------------------------------------------------------------

  static Color supplyColor(SupplyTypeId t) => switch (supplyDefs[t]!.rarity) {
        Rarity.epic => Sutura.rarityEpic,
        Rarity.legendary => Sutura.rarityLegendary,
        _ => Sutura.amber,
      };

  static void _supply(Canvas c, SupplyTypeId t, MarkerState s) {
    const l = 10.0, top = 11.0, size = 24.0, k = 6.0;
    final shape = Path()
      ..moveTo(l + k, top)
      ..lineTo(l + size, top)
      ..lineTo(l + size, top + size - k)
      ..lineTo(l + size - k, top + size)
      ..lineTo(l, top + size)
      ..lineTo(l, top + k)
      ..close();
    final color = supplyColor(t);
    final echo = s == MarkerState.echo;
    _stem(c, top + size + 2, color, dashed: echo);
    if (echo) {
      c.drawPath(shape, _fill(Sutura.void_.withValues(alpha: 0.45)));
      c.drawPath(shape, _stroke(color.withValues(alpha: 0.75), 1.3));
    } else {
      _glow(c, shape, color, s == MarkerState.sel ? 7 : 3.5, s == MarkerState.sel ? 0.6 : 0.35);
      c.drawPath(shape, _fill(Sutura.void_.withValues(alpha: 0.82)));
      c.drawPath(shape, _fill(color.withValues(alpha: 0.18)));
      c.drawPath(shape, _stroke(color, s == MarkerState.sel ? 1.8 : 1.5));
    }
    _supplyGlyph(c, t, echo ? color.withValues(alpha: 0.6) : color);
    if (s == MarkerState.sel) _brackets(c);
  }

  static void _supplyGlyph(Canvas c, SupplyTypeId t, Color color) {
    final st = _stroke(color, 1.4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fl = _fill(color);
    switch (t) {
      case SupplyTypeId.backpack:
        c.drawRRect(RRect.fromLTRBR(16.5, 19.5, 27.5, 29.5, const Radius.circular(2)), st);
        c.drawLine(const Offset(16.5, 23.5), const Offset(27.5, 23.5), st);
        c.drawPath(
          Path()
            ..moveTo(19.5, 19.5)
            ..quadraticBezierTo(22, 15.2, 24.5, 19.5),
          st,
        );
      case SupplyTypeId.car:
        c.drawPath(
          Path()
            ..moveTo(15.5, 27)
            ..lineTo(15.5, 23.5)
            ..lineTo(18, 22.8)
            ..lineTo(19.8, 19.5)
            ..lineTo(24.6, 19.5)
            ..lineTo(26.4, 22.8)
            ..lineTo(28.5, 23.5)
            ..lineTo(28.5, 27)
            ..close(),
          st,
        );
        c.drawCircle(const Offset(19, 27.8), 1.7, fl);
        c.drawCircle(const Offset(25, 27.8), 1.7, fl);
      case SupplyTypeId.debris:
        c.drawPath(
          Path()
            ..moveTo(16, 29)
            ..lineTo(19.5, 21.5)
            ..lineTo(22.5, 25)
            ..lineTo(25, 18)
            ..lineTo(28.5, 29)
            ..close(),
          st,
        );
        c.drawLine(const Offset(15.5, 29.2), const Offset(28.8, 29.2), st);
      case SupplyTypeId.grocery:
        final awning = Path()..moveTo(16, 19);
        awning.lineTo(28, 19);
        c.drawPath(awning, st);
        for (var i = 0; i < 4; i++) {
          final x = 16 + i * 3.0;
          c.drawArc(Rect.fromLTWH(x, 18.2, 3, 3.6), 0, math.pi, false, st);
        }
        c.drawRect(const Rect.fromLTRB(17, 22.5, 27, 29.5), st);
        c.drawRect(const Rect.fromLTRB(20.6, 25, 23.4, 29.5), fl);
      case SupplyTypeId.pharmacy:
        c.drawRect(const Rect.fromLTRB(20.4, 16.8, 23.6, 29.2), fl);
        c.drawRect(const Rect.fromLTRB(15.8, 21.4, 28.2, 24.6), fl);
      case SupplyTypeId.hardware:
        // Martillo.
        c.drawPath(
          Path()
            ..moveTo(16, 18)
            ..lineTo(26, 18)
            ..lineTo(28, 20)
            ..lineTo(26, 21.6)
            ..lineTo(16, 21.6)
            ..close(),
          fl,
        );
        c.drawRRect(RRect.fromLTRBR(20.6, 21.6, 23.4, 29.8, const Radius.circular(1)), fl);
      case SupplyTypeId.military:
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5;
          final r = i.isEven ? 6.6 : 2.7;
          final p = Offset(22 + r * math.cos(a), 23.6 + r * math.sin(a));
          if (i == 0) {
            star.moveTo(p.dx, p.dy);
          } else {
            star.lineTo(p.dx, p.dy);
          }
        }
        star.close();
        c.drawPath(star, fl);
    }
  }

  // -------------------------------------------------------------------------
  // Nodo (refugio): hexágono sobre un mástil, barras de nivel de antena
  // -------------------------------------------------------------------------

  static void _node(Canvas c, bool own, int level, bool selected) {
    const cy = 24.0;
    final color = own ? Sutura.amber : Sutura.signal;
    final hex = hexPath(const Offset(_cx, cy), 14);
    _stem(c, cy + 14, color, width: 1.6);
    _glow(c, hex, color, selected ? 8 : 4, own || selected ? 0.6 : 0.35);
    c.drawPath(hex, _fill(Sutura.surface2.withValues(alpha: 0.95)));
    c.drawPath(hex, _fill(color.withValues(alpha: 0.10)));
    c.drawPath(hex, _stroke(color, selected ? 1.9 : 1.6));
    // Barras de señal (nivel de antena 1-5).
    const bw = 2.0, gap = 1.5;
    const total = 5 * bw + 4 * gap;
    var x = _cx - total / 2;
    for (var i = 0; i < 5; i++) {
      final bh = 3.0 + i * 2.0;
      final r = Rect.fromLTWH(x, cy + 6 - bh, bw, bh);
      c.drawRect(r, _fill(i < level ? color : Sutura.lineStrong.withValues(alpha: 0.7)));
      x += bw + gap;
    }
    if (selected) _brackets(c);
  }

  // -------------------------------------------------------------------------
  // Jugador: chevrón blanco con halo cian (se apoya sobre el suelo)
  // -------------------------------------------------------------------------

  static void _player(Canvas c, {required bool heading}) {
    const center = Offset(playerSize / 2, playerSize / 2);
    c.drawCircle(
      center,
      24,
      Paint()
        ..shader = ui.Gradient.radial(center, 24, [
          Sutura.signal.withValues(alpha: 0.38),
          Sutura.signal.withValues(alpha: 0.10),
          Sutura.signal.withValues(alpha: 0),
        ], [0, 0.55, 1]),
    );
    c.drawCircle(center, 14.5, _stroke(Sutura.signal.withValues(alpha: 0.65), 1.1));
    if (heading) {
      final chevron = Path()
        ..moveTo(center.dx, center.dy - 13)
        ..lineTo(center.dx + 9.5, center.dy + 10)
        ..lineTo(center.dx, center.dy + 4.5)
        ..lineTo(center.dx - 9.5, center.dy + 10)
        ..close();
      _glow(c, chevron, Sutura.signal, 3, 0.8);
      c.drawPath(chevron, _fill(const Color(0xFFFFFFFF)));
      c.drawPath(chevron, _stroke(Sutura.signal, 1));
    } else {
      final dot = Path()..addOval(Rect.fromCircle(center: center, radius: 6.5));
      _glow(c, dot, Sutura.signal, 3, 0.8);
      c.drawPath(dot, _fill(const Color(0xFFFFFFFF)));
      c.drawPath(dot, _stroke(Sutura.signal, 1));
    }
  }
}
