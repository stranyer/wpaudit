import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../ui/theme/tokens.dart';

/// Estado visual de un marcador.
enum MarkerState { on, echo, sel }

/// Tipo de marcador del mapa.
enum MarkKind { supply, zombie, zone, signal, node }

/// Descripción de una imagen de marcador: insignia (hexágono/círculo con
/// glifo), mástil fino hasta un punto en el suelo y, si lleva etiqueta, el
/// título en mayúsculas espaciadas (y el nombre del nodo) sobre una franja
/// oscura. La distancia la dibuja MapLibre debajo (cambia al caminar).
@immutable
class MarkSpec {
  const MarkSpec(
    this.kind,
    this.state, {
    required this.title,
    this.subtitle,
    this.labelled = false,
    this.own = false,
    this.mortal = false,
  });

  final MarkKind kind;
  final MarkerState state;
  final String title;
  final String? subtitle;
  final bool labelled;

  /// Nodo propio (ámbar en vez de azul acero).
  final bool own;

  /// Amenaza mortal para el grado del jugador (doble anillo).
  final bool mortal;

  /// Líneas de texto horneadas en la imagen (título y nombre).
  int get bakedLines => !labelled ? 0 : (subtitle == null ? 1 : 2);

  Color get color => switch (kind) {
        MarkKind.supply || MarkKind.signal => Sutura.amber,
        MarkKind.zombie || MarkKind.zone => MapIcons.hostile,
        MarkKind.node => own ? Sutura.amber : Sutura.signal,
      };

  String get name {
    final h = Object.hash(title, subtitle, own, mortal) & 0x7fffffff;
    return 'zc-m-${kind.name}-${state.name}-${labelled ? 'l' : 'c'}-$h';
  }
}

/// Íconos de mapa dibujados en tiempo de ejecución con `dart:ui` y
/// registrados como PNG en el estilo (`addImage`).
///
/// Escala: maplibre-gl-js registra las imágenes con pixelRatio 1, mientras que
/// maplibre-native Android usa la densidad del Bitmap (≈ devicePixelRatio).
/// Por eso se dibujan a `renderScale` y se corrige con `icon-size` ([baseSize]).
abstract final class MapIcons {
  static const hostile = Color(0xFFD7392F);

  static const player = 'zc-player';
  static const playerIdle = 'zc-player-idle';

  // Geometría de los marcadores (px lógicos, origen arriba a la izquierda).
  static const badge = 28.0;
  static const stemX = 4.5;
  static const _badgeCx = stemX + 10.5;
  static const _badgeCy = 5.0 + badge / 2;
  static const _labelTop = _badgeCy + badge / 2 + 3;
  static const _lineH = 12.5;
  static const _textX = stemX + 7;
  static const _dotPad = 4.0;
  static const distanceSize = 10.5;

  static const playerSize = 132.0;

  static double renderScale(double dpr) => dpr.clamp(2.0, 3.5);

  /// `icon-size` que muestra el ícono en su tamaño lógico.
  static double baseSize(double dpr) => kIsWeb ? 1 / renderScale(dpr) : dpr / renderScale(dpr);

  /// `icon-offset` (en unidades de `icon-size`) para que el punto en el suelo
  /// del marcador caiga exactamente sobre la coordenada con `icon-anchor:
  /// bottom-left`.
  static List<double> iconOffset(double base) => [-stemX / base, _dotPad / base];

  /// `text-offset` (em) de la distancia: a la derecha del mástil, debajo de las
  /// líneas horneadas.
  static List<double> distanceOffset(int bakedLines) {
    final h = _labeledHeight(bakedLines);
    final dotY = h - _dotPad;
    final baseline = _labelTop + 4 + _lineH * bakedLines + 9.5;
    // Con anchor "bottom" MapLibre deja ~0,3 em entre la línea base y el borde.
    final dy = (baseline - dotY) / distanceSize + 0.32;
    return [(_textX - stemX) / distanceSize, dy];
  }

  static double _labeledHeight(int bakedLines) => _labelTop + 4 + (bakedLines + 1) * _lineH + 3 + _dotPad + 1;

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

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

  /// Imágenes fijas: jugador (con y sin rumbo) y la "M" del subte.
  static Future<Map<String, Uint8List>> renderStatic(double dpr) async {
    final s = renderScale(dpr);
    final out = await Future.wait([
      _render(playerSize, playerSize, s, (c) => _player(c, heading: true)),
      _render(playerSize, playerSize, s, (c) => _player(c, heading: false)),
      _render(22, 22, s, _metro),
    ]);
    return {player: out[0], playerIdle: out[1], 'zc-metro': out[2]};
  }

  /// Dibuja un marcador.
  static Future<Uint8List> renderMark(MarkSpec spec, double dpr) {
    final lines = _textLines(spec);
    var w = _badgeCx + badge / 2 + 7;
    if (spec.labelled) {
      var tw = 0.0;
      for (final l in lines) {
        tw = math.max(tw, l.width);
      }
      w = math.max(w, math.max(_textX + tw + 16, 86));
    }
    final h = spec.labelled ? _labeledHeight(spec.bakedLines) : _badgeCy + badge / 2 + 16 + _dotPad + 1;
    return _render(w, h, renderScale(dpr), (c) => _mark(c, spec, w, h, lines));
  }

  /// Patrón de relleno (techos, copas) escalado a `tileDp` px lógicos.
  static Future<Uint8List> pattern(String asset, double dpr, {double tileDp = 256}) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    final px = (tileDp * (kIsWeb ? 1 : dpr)).round();
    final codec = await ui.instantiateImageCodec(bytes);
    final src = (await codec.getNextFrame()).image;
    if (src.width == px && src.height == px) {
      src.dispose();
      return bytes;
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(px, px);
    final out = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    pic.dispose();
    src.dispose();
    return out!.buffer.asUint8List();
  }

  // -------------------------------------------------------------------------
  // Piezas comunes
  // -------------------------------------------------------------------------

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

  /// Trazo punteado de un camino (para los "ecos" del escáner).
  static void _dashed(Canvas c, Path p, Paint paint, {double on = 3, double off = 2.4}) {
    for (final m in p.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
        d += on + off;
      }
    }
  }

  static Path _hex(Offset center, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final v = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        p.moveTo(v.dx, v.dy);
      } else {
        p.lineTo(v.dx, v.dy);
      }
    }
    return p..close();
  }

  static ui.Paragraph _para(String text, {required double size, required FontWeight weight, required Color color, double spacing = 0}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: Sutura.fUi,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        shadows: const [ui.Shadow(color: Color(0xE6000000), blurRadius: 2.5)],
      ))
      ..addText(text);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 190));
    return p;
  }

  static List<({ui.Paragraph p, double width})> _textLines(MarkSpec s) {
    if (!s.labelled) return const [];
    final echo = s.state == MarkerState.echo;
    final title = _para(
      s.title.toUpperCase(),
      size: 12.5,
      weight: FontWeight.w600,
      color: echo ? s.color.withValues(alpha: 0.7) : s.color,
      spacing: 1.7,
    );
    final out = [(p: title, width: title.longestLine)];
    final sub = s.subtitle;
    if (sub != null) {
      final p = _para(sub, size: 12.5, weight: FontWeight.w500, color: Sutura.textHi, spacing: 0.7);
      out.add((p: p, width: p.longestLine));
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Marcador: insignia + mástil + punto + etiqueta
  // -------------------------------------------------------------------------

  static void _mark(Canvas c, MarkSpec s, double w, double h, List<({ui.Paragraph p, double width})> lines) {
    final color = s.color;
    final echo = s.state == MarkerState.echo;
    final sel = s.state == MarkerState.sel;
    final dot = Offset(stemX, h - _dotPad);
    const center = Offset(_badgeCx, _badgeCy);

    // Franja oscura detrás de la etiqueta.
    if (s.labelled) {
      final r = Rect.fromLTRB(stemX, _labelTop, w, dot.dy + 1.5);
      c.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.centerLeft, r.centerRight, [
            const Color(0xB0090A0B),
            const Color(0x80090A0B),
            const Color(0x00090A0B),
          ], [0, 0.6, 1]),
      );
    }

    // Mástil: desde el borde inferior izquierdo de la insignia hasta el suelo.
    final stem = _stroke(color.withValues(alpha: echo ? 0.55 : 0.9), 1.3);
    final top = _badgeCy + badge / 2 - 4;
    if (echo) {
      _dashed(c, Path()..moveTo(stemX, top)..lineTo(stemX, dot.dy - 2), stem, on: 2.5, off: 2.5);
    } else {
      c.drawLine(Offset(stemX, top), Offset(stemX, dot.dy - 2), stem);
    }
    // Punto en el suelo.
    c.drawCircle(dot, 3.6, _fill(const Color(0x99000000)));
    c.drawCircle(dot, 2.6, _fill(color.withValues(alpha: echo ? 0.6 : 1)));

    // Insignia.
    switch (s.kind) {
      case MarkKind.supply:
        _hexBadge(c, center, color, echo: echo, sel: sel, glyph: _cube);
      case MarkKind.node:
        _hexBadge(c, center, color, echo: echo, sel: sel, glyph: _house);
      case MarkKind.zombie:
        _circleBadge(c, center, color, echo: echo, sel: sel, glyph: _biohazard, outer: s.mortal ? 'solid' : null);
      case MarkKind.zone:
        _circleBadge(c, center, color, echo: echo, sel: sel, glyph: _biohazard, outer: 'dashed');
      case MarkKind.signal:
        _circleBadge(c, center, color, echo: echo, sel: sel, glyph: _antenna);
    }
    if (sel) _brackets(c, center);

    // Texto horneado.
    var y = _labelTop + 4;
    for (final l in lines) {
      final baseline = y + 9.5;
      c.drawParagraph(l.p, Offset(_textX, baseline - l.p.alphabeticBaseline));
      y += _lineH;
    }
  }

  static void _hexBadge(Canvas c, Offset center, Color color,
      {required bool echo, required bool sel, required void Function(Canvas, Offset, Color) glyph}) {
    final hex = _hex(center, badge / 2 + 0.5);
    if (!echo) _glow(c, hex, color, sel ? 7 : 5, sel ? 0.55 : 0.32);
    c.drawPath(hex, _fill(const Color(0xE60E0F10)));
    c.drawPath(hex, _fill(color.withValues(alpha: echo ? 0.05 : 0.12)));
    final line = _stroke(color.withValues(alpha: echo ? 0.7 : 1), sel ? 2.2 : 1.8);
    if (echo) {
      _dashed(c, hex, line);
    } else {
      c.drawPath(hex, line);
    }
    glyph(c, center, echo ? color.withValues(alpha: 0.55) : color);
  }

  static void _circleBadge(Canvas c, Offset center, Color color,
      {required bool echo, required bool sel, required void Function(Canvas, Offset, Color) glyph, String? outer}) {
    const r = badge / 2 - 0.5;
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    if (!echo) _glow(c, circle, color, sel ? 7 : 5, sel ? 0.6 : 0.35);
    c.drawPath(circle, _fill(const Color(0xE60E0F10)));
    c.drawPath(circle, _fill(color.withValues(alpha: echo ? 0.05 : 0.14)));
    final line = _stroke(color.withValues(alpha: echo ? 0.7 : 1), sel ? 2.2 : 1.8);
    if (echo) {
      _dashed(c, circle, line);
    } else {
      c.drawPath(circle, line);
    }
    if (outer != null && !echo) {
      final ring = Path()..addOval(Rect.fromCircle(center: center, radius: r + 3.2));
      final p = _stroke(color.withValues(alpha: 0.6), 1);
      if (outer == 'dashed') {
        _dashed(c, ring, p, on: 2.2, off: 2.2);
      } else {
        c.drawPath(ring, p);
      }
    }
    glyph(c, center, echo ? color.withValues(alpha: 0.55) : color);
  }

  /// Corchetes de "objetivo fijado" alrededor de la insignia.
  static void _brackets(Canvas c, Offset center) {
    const e = badge / 2 + 4;
    const k = 5.5;
    final l = center.dx - e, t = center.dy - e, r = center.dx + e, b = center.dy + e;
    final p = _stroke(Sutura.textHi, 1.5)..strokeCap = StrokeCap.square;
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
  // Glifos
  // -------------------------------------------------------------------------

  /// Caja isométrica (botín).
  static void _cube(Canvas c, Offset o, Color color) {
    const s = 7.0;
    final h = s * math.sin(math.pi / 6);
    final w = s * math.cos(math.pi / 6);
    final top = o + Offset(0, -s * 0.95);
    final mid = o + Offset(0, -s * 0.95 + 2 * h);
    final left = Path()
      ..moveTo(o.dx - w, top.dy + h)
      ..lineTo(mid.dx, mid.dy)
      ..lineTo(mid.dx, mid.dy + s)
      ..lineTo(o.dx - w, top.dy + h + s)
      ..close();
    final right = Path()
      ..moveTo(o.dx + w, top.dy + h)
      ..lineTo(mid.dx, mid.dy)
      ..lineTo(mid.dx, mid.dy + s)
      ..lineTo(o.dx + w, top.dy + h + s)
      ..close();
    final lid = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(o.dx + w, top.dy + h)
      ..lineTo(mid.dx, mid.dy)
      ..lineTo(o.dx - w, top.dy + h)
      ..close();
    c.drawPath(left, _fill(color));
    c.drawPath(right, _fill(Color.lerp(color, const Color(0xFF000000), 0.35)!));
    c.drawPath(lid, _fill(Color.lerp(color, const Color(0xFFFFFFFF), 0.28)!));
    // Cinta.
    c.drawLine(Offset(o.dx - w * 0.5, top.dy + h * 0.5), Offset(o.dx + w * 0.5, top.dy + h * 1.5),
        _stroke(Color.lerp(color, const Color(0xFF000000), 0.45)!, 1));
  }

  /// Casa (refugio).
  static void _house(Canvas c, Offset o, Color color) {
    final p = Path()
      ..moveTo(o.dx, o.dy - 7.5)
      ..lineTo(o.dx + 7.5, o.dy - 1)
      ..lineTo(o.dx + 5.6, o.dy - 1)
      ..lineTo(o.dx + 5.6, o.dy + 6.5)
      ..lineTo(o.dx - 5.6, o.dy + 6.5)
      ..lineTo(o.dx - 5.6, o.dy - 1)
      ..lineTo(o.dx - 7.5, o.dy - 1)
      ..close();
    c.drawPath(p, _fill(color));
    c.drawRect(Rect.fromLTRB(o.dx - 1.9, o.dy + 1.2, o.dx + 1.9, o.dy + 6.5), _fill(const Color(0xFF0E0F10)));
  }

  /// Símbolo de riesgo biológico.
  static void _biohazard(Canvas c, Offset o, Color color) {
    const r = 9.0;
    var shape = Path();
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a));
      final outer = Path()..addOval(Rect.fromCircle(center: o + d * (r * 0.42), radius: r * 0.5));
      final cut = Path()..addOval(Rect.fromCircle(center: o + d * (r * 0.56), radius: r * 0.36));
      final crescent = Path.combine(PathOperation.difference, outer, cut);
      shape = i == 0 ? crescent : Path.combine(PathOperation.union, shape, crescent);
    }
    final hole = Path()..addOval(Rect.fromCircle(center: o, radius: r * 0.15));
    shape = Path.combine(PathOperation.difference, shape, hole);
    c.drawPath(shape, _fill(color));
    // Anillo central interrumpido.
    final ring = _stroke(color, 1.3);
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + math.pi / 3 + i * 2 * math.pi / 3;
      c.drawArc(Rect.fromCircle(center: o, radius: r * 0.42), a - 0.55, 1.1, false, ring);
    }
  }

  /// Antena con ondas de radio (señal de auxilio).
  static void _antenna(Canvas c, Offset o, Color color) {
    final head = o + const Offset(0, -2.6);
    c.drawCircle(head, 2.1, _fill(color));
    final st = _stroke(color, 1.4)..strokeCap = StrokeCap.round;
    for (final r in [5.0, 8.2]) {
      final rect = Rect.fromCircle(center: head, radius: r);
      c.drawArc(rect, -math.pi * 0.22, math.pi * 0.44, false, st);
      c.drawArc(rect, math.pi * 0.78, math.pi * 0.44, false, st);
    }
    // Mástil con patas.
    c.drawLine(head, o + const Offset(0, 8), st);
    c.drawLine(o + const Offset(0, 2.5), o + const Offset(-3.2, 8), st);
    c.drawLine(o + const Offset(0, 2.5), o + const Offset(3.2, 8), st);
  }

  // -------------------------------------------------------------------------
  // Jugador: anillo blanco con punto y cono de visión azul acero
  // -------------------------------------------------------------------------

  static void _player(Canvas c, {required bool heading}) {
    const center = Offset(playerSize / 2, playerSize / 2);
    if (heading) {
      const len = 58.0;
      const half = 0.36;
      final cone = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: len), -math.pi / 2 - half, half * 2, false)
        ..close();
      c.drawPath(
        cone,
        Paint()
          ..shader = ui.Gradient.radial(center, len, [
            const Color(0xCCD7E7F0),
            Sutura.signal.withValues(alpha: 0.55),
            Sutura.signal.withValues(alpha: 0.18),
            Sutura.signal.withValues(alpha: 0),
          ], [0.12, 0.3, 0.65, 1]),
      );
    }
    // Sombra para despegarlo del mapa.
    c.drawCircle(center, 13, Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    c.drawCircle(center, 10.5, _fill(const Color(0xE0121517)));
    c.drawCircle(center, 10.5, _stroke(const Color(0xFFF2F4F5), 2.4));
    c.drawCircle(center, 4.2, _fill(const Color(0xFFF2F4F5)));
  }

  /// Estación de subte: "M" en un círculo.
  static void _metro(Canvas c) {
    const o = Offset(11, 11);
    c.drawCircle(o, 9.2, _fill(const Color(0xE6151617)));
    c.drawCircle(o, 9.2, _stroke(const Color(0xFFD5D8D9), 1.4));
    final p = _para('M', size: 12.5, weight: FontWeight.w700, color: const Color(0xFFE3E5E6));
    c.drawParagraph(p, Offset(o.dx - p.longestLine / 2, o.dy - p.height / 2));
  }
}
