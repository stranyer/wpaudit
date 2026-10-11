import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../ui/theme/tokens.dart';
import 'map_math.dart';

/// Estado visual de un marcador.
enum MarkerState { on, echo, sel }

/// Tipo de marcador del mapa.
enum MarkKind { supply, zombie, zone, signal, node }

/// Descripción de una imagen de marcador (como en la referencia, sin mástil):
/// insignia arriba (rombo, hexágono, antena o retrato de la criatura) y, si
/// lleva etiqueta, el título centrado debajo en mayúsculas espaciadas (una o
/// dos líneas). La distancia la dibuja MapLibre debajo del título (cambia al
/// caminar), del color del tipo.
@immutable
class MarkSpec {
  const MarkSpec(this.kind, this.state, {required this.title, this.labelled = false, this.own = false, this.mortal = false, this.avatar});

  final MarkKind kind;
  final MarkerState state;
  final String title;
  final bool labelled;

  /// Nodo propio (ámbar en vez de verde refugio).
  final bool own;

  /// Amenaza mortal para el grado del jugador (doble anillo).
  final bool mortal;

  /// Infectado: criatura cuyo retrato va en la insignia.
  final ZombieTypeId? avatar;

  /// Líneas del título horneadas en la imagen.
  List<String> get lines => labelled ? markTitleLines(title) : const [];

  Color get color => markColor(kind, own: own);

  String get name {
    final h = Object.hash(title, own, mortal, avatar) & 0x7fffffff;
    return 'zc-m-${kind.name}-${state.name}-${labelled ? 'l' : 'c'}-$h';
  }
}

/// Color de un tipo de marcador (insignia y distancia).
Color markColor(MarkKind kind, {bool own = false}) => switch (kind) {
  MarkKind.supply || MarkKind.signal => Sutura.amber,
  MarkKind.zombie || MarkKind.zone => MapIcons.hostile,
  MarkKind.node => own ? Sutura.amber : Sutura.refuge,
};

/// "#RRGGBB" para las expresiones de MapLibre.
String hexColor(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Íconos de mapa dibujados en tiempo de ejecución con `dart:ui` y
/// registrados como PNG en el estilo (`addImage`).
///
/// Escala: maplibre-gl-js registra las imágenes con pixelRatio 1, mientras que
/// maplibre-native Android usa la densidad del Bitmap (≈ devicePixelRatio).
/// Por eso se dibujan a `renderScale` y se corrige con `icon-size` ([baseSize]).
abstract final class MapIcons {
  static const hostile = Color(0xFFE0453A);

  static const player = 'zc-player';
  static const playerIdle = 'zc-player-idle';
  static const metro = 'zc-metro';

  // Geometría de los marcadores (px lógicos, origen arriba a la izquierda).
  /// Margen para el resplandor alrededor de la insignia.
  static const _pad = 9.0;

  /// Caja más grande de una insignia (retrato de la criatura).
  static const _maxBox = 34.0;

  /// Centro vertical de la insignia: igual para todos los tipos, así el
  /// `icon-offset` es constante y la insignia cae sobre la coordenada.
  static const badgeCy = _pad + _maxBox / 2;
  static const _lineH = 12.5;
  static const _titleSize = 11.5;
  static const distanceSize = 10.5;
  static const minWidth = 2 * _pad + _maxBox;

  static const playerSize = 132.0;

  static double renderScale(double dpr) => dpr.clamp(2.0, 3.5);

  /// `icon-size` que muestra el ícono en su tamaño lógico.
  static double baseSize(double dpr) => kIsWeb ? 1 / renderScale(dpr) : dpr / renderScale(dpr);

  /// `icon-offset` (en unidades de `icon-size`) para que, con `icon-anchor:
  /// top`, el centro de la insignia caiga exactamente sobre la coordenada.
  static List<double> iconOffset(double base) => [0, -badgeCy / base];

  /// Caja (lado) de la insignia de cada tipo.
  static double boxOf(MarkKind kind) => switch (kind) {
    MarkKind.zombie => _maxBox,
    MarkKind.zone => 30,
    MarkKind.signal => 30,
    MarkKind.supply || MarkKind.node => 28,
  };

  static double _labelTop(MarkKind kind) => badgeCy + boxOf(kind) / 2 + 4;

  /// `text-offset` (em) de la distancia: centrada, debajo de las líneas
  /// horneadas del título (con `text-anchor: top`).
  static List<double> distanceOffset(MarkKind kind, int lines) {
    final bottom = _labelTop(kind) + lines * _lineH;
    // Con anchor "top" MapLibre deja ~0,2 em entre el borde y la tinta.
    return [0, (bottom - badgeCy + 1) / distanceSize - 0.12];
  }

  /// Ancho aproximado (px) de la etiqueta de un marcador (título y distancia),
  /// para evitar choques entre etiquetas.
  static double labelWidth(String title) {
    var w = 46.0;
    for (final l in markTitleLines(title)) {
      w = math.max(w, l.length * 7.4 + 8);
    }
    return w;
  }

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
    return {player: out[0], playerIdle: out[1], metro: out[2]};
  }

  /// Dibuja un marcador (con el retrato de la criatura si corresponde).
  static Future<Uint8List> renderMark(MarkSpec spec, double dpr) async {
    final face = spec.avatar == null ? null : await avatar(spec.avatar!);
    final lines = [for (final l in spec.lines) _para(l, size: _titleSize, weight: FontWeight.w600, color: _titleColor(spec), spacing: 1.7)];
    var w = minWidth;
    for (final p in lines) {
      w = math.max(w, p.longestLine + 10);
    }
    w = w.ceilToDouble();
    final h = (lines.isEmpty ? badgeCy + _maxBox / 2 + _pad : _labelTop(spec.kind) + lines.length * _lineH + 4).ceilToDouble();
    return _render(w, h, renderScale(dpr), (c) => _mark(c, spec, w, lines, face));
  }

  static Color _titleColor(MarkSpec s) => s.state == MarkerState.echo ? const Color(0xFFB7B4AE) : const Color(0xFFECE9E2);

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
  // Retratos de las criaturas
  // -------------------------------------------------------------------------

  static String avatarAsset(ZombieTypeId t) => 'assets/art/avatars/${t.key}.webp';

  static final Map<ZombieTypeId, Future<ui.Image?>> _avatars = {};

  /// Retrato (256×256) decodificado a 128 px. null si el asset no está.
  static Future<ui.Image?> avatar(ZombieTypeId t) => _avatars[t] ??= () async {
    try {
      final data = await rootBundle.load(avatarAsset(t));
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 128, targetHeight: 128);
      return (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('[Zona Cero] Retrato ${t.key} no disponible: $e');
      return null;
    }
  }();

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
    c.drawPath(
      p,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
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

  static Path _diamond(Offset o, double r) => Path()
    ..moveTo(o.dx, o.dy - r)
    ..lineTo(o.dx + r, o.dy)
    ..lineTo(o.dx, o.dy + r)
    ..lineTo(o.dx - r, o.dy)
    ..close();

  static ui.Paragraph _para(String text, {required double size, required FontWeight weight, required Color color, double spacing = 0}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, ellipsis: '…'))
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontFamily: Sutura.fUi,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          shadows: const [
            ui.Shadow(color: Color(0xF0000000), blurRadius: 3),
            ui.Shadow(color: Color(0xC0000000), blurRadius: 1, offset: Offset(0, 1)),
          ],
        ),
      )
      ..addText(text);
    return b.build()..layout(const ui.ParagraphConstraints(width: 200));
  }

  // -------------------------------------------------------------------------
  // Marcador: insignia + título centrado
  // -------------------------------------------------------------------------

  static void _mark(Canvas c, MarkSpec s, double w, List<ui.Paragraph> lines, ui.Image? face) {
    final color = s.color;
    final echo = s.state == MarkerState.echo;
    final sel = s.state == MarkerState.sel;
    final center = Offset(w / 2, badgeCy);
    final box = boxOf(s.kind);

    switch (s.kind) {
      case MarkKind.supply:
        _hexBadge(c, center, box / 2, color, echo: echo, sel: sel, glyph: _crate);
      case MarkKind.node:
        _hexBadge(c, center, box / 2, color, echo: echo, sel: sel, glyph: _house);
      case MarkKind.zone:
        _diamondBadge(c, center, box / 2, color, echo: echo, sel: sel);
      case MarkKind.signal:
        _tower(c, center, color, echo: echo, sel: sel);
      case MarkKind.zombie:
        if (face != null) {
          _avatarBadge(c, center, box / 2, color, face, echo: echo, sel: sel, mortal: s.mortal);
        } else {
          _circleBadge(c, center, box / 2 - 2, color, echo: echo, sel: sel, mortal: s.mortal);
        }
    }
    if (sel) _brackets(c, center, box / 2 + 4);

    // Título horneado, centrado.
    var y = _labelTop(s.kind);
    for (final p in lines) {
      final baseline = y + 9.5;
      c.drawParagraph(p, Offset((w - p.longestLine) / 2, baseline - p.alphabeticBaseline));
      y += _lineH;
    }
  }

  static void _hexBadge(
    Canvas c,
    Offset center,
    double r,
    Color color, {
    required bool echo,
    required bool sel,
    required void Function(Canvas, Offset, Color) glyph,
  }) {
    final hex = _hex(center, r);
    if (!echo) _glow(c, hex, color, sel ? 7 : 5, sel ? 0.55 : 0.34);
    c.drawPath(hex, _fill(const Color(0xE00C0D0E)));
    c.drawPath(hex, _fill(color.withValues(alpha: echo ? 0.04 : 0.1)));
    final line = _stroke(color.withValues(alpha: echo ? 0.65 : 1), sel ? 2 : 1.6);
    if (echo) {
      _dashed(c, hex, line);
    } else {
      c.drawPath(hex, line);
    }
    glyph(c, center, echo ? color.withValues(alpha: 0.55) : color);
  }

  static void _diamondBadge(Canvas c, Offset center, double r, Color color, {required bool echo, required bool sel}) {
    final d = _diamond(center, r);
    if (!echo) _glow(c, d, color, sel ? 7 : 5, sel ? 0.55 : 0.38);
    c.drawPath(d, _fill(const Color(0xE00C0D0E)));
    c.drawPath(d, _fill(color.withValues(alpha: echo ? 0.04 : 0.12)));
    final line = _stroke(color.withValues(alpha: echo ? 0.65 : 1), sel ? 2 : 1.6);
    if (echo) {
      _dashed(c, d, line);
    } else {
      c.drawPath(d, line);
    }
    _biohazard(c, center, echo ? color.withValues(alpha: 0.55) : color, r: r * 0.6);
  }

  static void _circleBadge(Canvas c, Offset center, double r, Color color, {required bool echo, required bool sel, required bool mortal}) {
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    if (!echo) _glow(c, circle, color, sel ? 7 : 5, sel ? 0.6 : 0.38);
    c.drawPath(circle, _fill(const Color(0xE00C0D0E)));
    c.drawPath(circle, _fill(color.withValues(alpha: echo ? 0.05 : 0.14)));
    final line = _stroke(color.withValues(alpha: echo ? 0.65 : 1), sel ? 2 : 1.6);
    if (echo) {
      _dashed(c, circle, line);
    } else {
      c.drawPath(circle, line);
    }
    if (mortal && !echo) c.drawCircle(center, r + 3.2, _stroke(color.withValues(alpha: 0.6), 1));
    _biohazard(c, center, echo ? color.withValues(alpha: 0.55) : color, r: r * 0.62);
  }

  /// Retrato circular de la criatura con anillo rojo y resplandor.
  static void _avatarBadge(
    Canvas c,
    Offset center,
    double r,
    Color color,
    ui.Image face, {
    required bool echo,
    required bool sel,
    required bool mortal,
  }) {
    final ring = Rect.fromCircle(center: center, radius: r);
    if (!echo) {
      c.drawCircle(
        center,
        r + 1,
        Paint()
          ..color = color.withValues(alpha: sel ? 0.75 : 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, sel ? 7 : 5),
      );
    }
    c.drawCircle(center, r, _fill(const Color(0xFF0C0D0E)));
    c.save();
    c.clipPath(Path()..addOval(ring.deflate(1.4)));
    final src = Rect.fromLTWH(0, 0, face.width.toDouble(), face.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    if (echo) {
      // Eco: último contacto conocido, en gris y apagado.
      paint.colorFilter = const ColorFilter.matrix([
        0.22, 0.42, 0.08, 0, 0, //
        0.22, 0.42, 0.08, 0, 0,
        0.22, 0.42, 0.08, 0, 0,
        0, 0, 0, 0.6, 0,
      ]);
    }
    // Un poco de zoom sobre la cara.
    c.drawImageRect(face, src, ring.inflate(r * 0.08), paint);
    // Viñeta interior: el retrato se funde con el anillo.
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [const Color(0x00000000), const Color(0x00000000), const Color(0x99140404)], [0, 0.62, 1]),
    );
    c.restore();
    final line = _stroke(color.withValues(alpha: echo ? 0.6 : 1), sel ? 2.2 : 1.8);
    final circle = Path()..addOval(ring);
    if (echo) {
      _dashed(c, circle, line, on: 3.2, off: 2.6);
    } else {
      c.drawPath(circle, line);
    }
    if (mortal && !echo) c.drawCircle(center, r + 3.4, _stroke(color.withValues(alpha: 0.65), 1));
  }

  /// Corchetes de "objetivo fijado" alrededor de la insignia.
  static void _brackets(Canvas c, Offset center, double e) {
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

  /// Caja de suministros con tapa y cierre (saqueo).
  static void _crate(Canvas c, Offset o, Color color) {
    final body = Rect.fromCenter(center: o + const Offset(0, 1.2), width: 13, height: 9.5);
    final st = _stroke(color, 1.4)..strokeJoin = StrokeJoin.round;
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(1.2)), st);
    // Tapa.
    c.drawLine(Offset(body.left, body.top + 3.2), Offset(body.right, body.top + 3.2), st);
    // Asa.
    c.drawPath(
      Path()
        ..moveTo(o.dx - 3, body.top)
        ..lineTo(o.dx - 3, body.top - 2.2)
        ..lineTo(o.dx + 3, body.top - 2.2)
        ..lineTo(o.dx + 3, body.top),
      st,
    );
    // Cierre.
    c.drawRect(Rect.fromCenter(center: Offset(o.dx, body.top + 3.6), width: 3.2, height: 2.6), _fill(color));
  }

  /// Casa (refugio): pentágono lleno con puerta oscura.
  static void _house(Canvas c, Offset o, Color color) {
    final p = Path()
      ..moveTo(o.dx, o.dy - 7.2)
      ..lineTo(o.dx + 7.4, o.dy - 0.6)
      ..lineTo(o.dx + 5.4, o.dy - 0.6)
      ..lineTo(o.dx + 5.4, o.dy + 6.4)
      ..lineTo(o.dx - 5.4, o.dy + 6.4)
      ..lineTo(o.dx - 5.4, o.dy - 0.6)
      ..lineTo(o.dx - 7.4, o.dy - 0.6)
      ..close();
    c.drawPath(p, _fill(color));
    c.drawRect(Rect.fromLTRB(o.dx - 1.8, o.dy + 1.6, o.dx + 1.8, o.dy + 6.4), _fill(const Color(0xFF0E0F10)));
  }

  /// Símbolo de riesgo biológico de radio `r`.
  static void _biohazard(Canvas c, Offset o, Color color, {double r = 9}) {
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
    final ring = _stroke(color, r * 0.14);
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + math.pi / 3 + i * 2 * math.pi / 3;
      c.drawArc(Rect.fromCircle(center: o, radius: r * 0.42), a - 0.55, 1.1, false, ring);
    }
  }

  /// Torre de radio con ondas (señal de auxilio), sin marco.
  static void _tower(Canvas c, Offset o, Color color, {required bool echo, required bool sel}) {
    final col = echo ? color.withValues(alpha: 0.55) : color;
    final head = o + const Offset(0, -7.5);
    final base = o.dy + 12;
    final path = Path()
      // Patas.
      ..moveTo(head.dx, head.dy + 2)
      ..lineTo(head.dx - 6, base)
      ..moveTo(head.dx, head.dy + 2)
      ..lineTo(head.dx + 6, base)
      // Riostras en X.
      ..moveTo(head.dx - 2.4, o.dy - 0.5)
      ..lineTo(head.dx + 3.9, o.dy + 5.5)
      ..moveTo(head.dx + 2.4, o.dy - 0.5)
      ..lineTo(head.dx - 3.9, o.dy + 5.5)
      ..moveTo(head.dx - 2.4, o.dy - 0.5)
      ..lineTo(head.dx + 2.4, o.dy - 0.5)
      ..moveTo(head.dx - 3.9, o.dy + 5.5)
      ..lineTo(head.dx + 3.9, o.dy + 5.5);
    final arcs = Path();
    for (final r in [5.2, 9.0, 12.8]) {
      final rect = Rect.fromCircle(center: head, radius: r);
      arcs
        ..addArc(rect, -math.pi * 0.2, math.pi * 0.4)
        ..addArc(rect, math.pi * 0.8, math.pi * 0.4);
    }
    if (!echo) {
      final glow = Paint()
        ..color = color.withValues(alpha: sel ? 0.7 : 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sel ? 5 : 3.5);
      c.drawPath(path, glow);
      c.drawPath(arcs, glow);
    }
    final st = _stroke(col, 1.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(path, st);
    c.drawPath(arcs, _stroke(col, 1.5)..strokeCap = StrokeCap.round);
    c.drawCircle(head, 2.2, _fill(col));
  }

  // -------------------------------------------------------------------------
  // Jugador: flecha blanca de navegación en un anillo, con cono de visión
  // -------------------------------------------------------------------------

  static void _player(Canvas c, {required bool heading}) {
    const center = Offset(playerSize / 2, playerSize / 2);
    const ring = 12.5;
    // Cono de visión. Sin rumbo conocido apunta al norte, más tenue.
    final k = heading ? 1.0 : 0.45;
    {
      const len = 60.0;
      const half = 0.34;
      final cone = Path()
        ..moveTo(center.dx + math.sin(half) * (ring - 1), center.dy - math.cos(half) * (ring - 1))
        ..lineTo(center.dx + math.sin(half) * len, center.dy - math.cos(half) * len)
        ..arcToPoint(
          Offset(center.dx - math.sin(half) * len, center.dy - math.cos(half) * len),
          radius: const Radius.circular(len),
          clockwise: false,
        )
        ..lineTo(center.dx - math.sin(half) * (ring - 1), center.dy - math.cos(half) * (ring - 1))
        ..close();
      c.drawPath(
        cone,
        Paint()
          ..shader = ui.Gradient.linear(
            center + const Offset(0, -ring),
            center + const Offset(0, -len),
            [const Color(0x8CF4F6F7), const Color(0x52E9EDEF), const Color(0x14E9EDEF)].map((x) => x.withValues(alpha: x.a * k)).toList(),
            [0, 0.55, 1],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
    }
    // Sombra para despegarlo del mapa.
    c.drawCircle(
      center,
      ring + 3,
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    c.drawCircle(center, ring, _fill(const Color(0x66101214)));
    c.drawCircle(center, ring, _stroke(const Color(0xFFF2F4F5), 1.8));
    // Flecha de navegación con muesca.
    final arrow = Path()
      ..moveTo(center.dx, center.dy - 7.4)
      ..lineTo(center.dx + 5.4, center.dy + 6)
      ..lineTo(center.dx, center.dy + 2.8)
      ..lineTo(center.dx - 5.4, center.dy + 6)
      ..close();
    c.drawPath(
      arrow,
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    c.drawPath(arrow, _fill(const Color(0xFFF4F6F7)));
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
