// Carga del arte del combate desde `assets/combat/` con reservas procedurales:
// si falta el manifiesto, el fondo o una tira, la escena sigue funcionando.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../core/types.dart';
import 'combat_manifest.dart';
import 'procedural_zombie.dart';

/// Una tira de animación cargada.
class ZombieStrip {
  ZombieStrip(this.image, this.spec, this.frames);
  final ui.Image image;
  final AnimSpec spec;

  /// Rectángulos fuente precalculados (sin asignaciones por cuadro).
  final List<Rect> frames;
}

/// Regiones del atlas de partículas.
abstract final class FxAtlas {
  static const blob = Rect.fromLTWH(0, 0, 128, 128);
  static const dot = Rect.fromLTWH(128, 0, 32, 32);
  static const streak = Rect.fromLTWH(128, 32, 32, 8);
  static const shard = Rect.fromLTWH(128, 44, 16, 16);
  static const ring = Rect.fromLTWH(128, 64, 32, 32);
}

class CombatArt {
  CombatArt._({
    required this.type,
    required this.manifest,
    required this.background,
    required this.proceduralBackground,
    required this.foreground,
    required this.strips,
    required this.placement,
    required this.bodyInFrame,
    required this.headsInFrame,
    required this.headHoldInFrame,
    required this.fxAtlas,
    required this.procedural,
  });

  final ZombieTypeId type;
  final CombatManifest manifest;
  final ui.Image background;
  final bool proceduralBackground;
  final ui.Image? foreground;
  final Map<ZombieAnim, ZombieStrip> strips;
  final ZombiePlacement placement;

  /// Caja del cuerpo en px del cuadro (para la puntería).
  final Rect bodyInFrame;

  /// Caja de la cabeza (px del cuadro) por cuadro de la animación `idle`.
  /// Vacía = usar la zona de reserva de [headRectOf]. Un solo elemento =
  /// caja fija (silueta procedural).
  final List<Rect> headsInFrame;

  /// Cabeza en el último cuadro de `charge_prepare` (pose sostenida).
  /// `Rect.zero` = no hay cabeza a la vista (el Bruto la esconde al cargar).
  final Rect? headHoldInFrame;
  final ui.Image fxAtlas;

  /// Silueta de reserva (si no hay tiras).
  final ProceduralZombie? procedural;

  bool get hasSprites => strips.containsKey(ZombieAnim.idle);
  Size get bgSize => manifest.background.size;
  Size get frameSize => manifest.frameSize;

  /// Duración de una animación (s), real o procedural.
  double durationOf(ZombieAnim a) {
    final s = strips[a];
    if (s != null) return s.spec.duration(manifest.fps);
    return ProceduralZombie.durationOf(a);
  }

  /// Momento del impacto/pico (s) de una animación.
  double keyTimeOf(ZombieAnim a) {
    final s = strips[a];
    final k = s?.spec.keyTime(manifest.fps);
    if (k != null) return k;
    return durationOf(a) * 0.55;
  }

  /// Caja de la cabeza (px del cuadro) para el cuadro `i` de `idle`.
  Rect? headInFrame(int i) {
    if (headsInFrame.isEmpty) return null;
    return headsInFrame[i.clamp(0, headsInFrame.length - 1)];
  }

  void dispose() {
    background.dispose();
    for (final s in strips.values) {
      s.image.dispose();
    }
    foreground?.dispose();
    fxAtlas.dispose();
  }

  static const String base = 'assets/combat/';

  /// Carga todo lo necesario para pelear contra `type`. Nunca falla: ante
  /// cualquier error usa la reserva procedural correspondiente.
  static Future<CombatArt> load(ZombieTypeId type, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    Set<String>? known;
    try {
      known = (await AssetManifest.loadFromAssetBundle(b)).listAssets().toSet();
    } catch (_) {
      known = null; // sin manifiesto de assets: se intenta igual
    }
    bool exists(String file) => known == null || known.contains('$base$file');

    var manifest = CombatManifest.fallback;
    if (exists('manifest.json')) {
      try {
        manifest = CombatManifest.tryParse(await b.loadString('${base}manifest.json', cache: false)) ?? CombatManifest.fallback;
      } catch (_) {
        manifest = CombatManifest.fallback;
      }
    }

    final key = type.key;
    final specs = manifest.animsFor(key);
    final bgFile = manifest.background.file;
    final fgFile = manifest.background.foreground ?? 'bg_street_fg.webp';

    final bgF = exists(bgFile) ? _image(b, '$base$bgFile') : Future<ui.Image?>.value(null);
    final fgF = exists(fgFile) ? _image(b, '$base$fgFile') : Future<ui.Image?>.value(null);
    final stripF = {for (final e in specs.entries) e.key: exists(e.value.file) ? _image(b, '$base${e.value.file}') : Future<ui.Image?>.value(null)};

    final bg = await bgF;
    final fg = await fgF;
    final strips = <ZombieAnim, ZombieStrip>{};
    for (final e in stripF.entries) {
      final img = await e.value;
      if (img == null) continue;
      final spec = specs[e.key]!;
      final cols = spec.columns ?? spec.frames;
      final rows = (spec.frames / cols).ceil();
      // Una tira más chica que lo declarado es un error de arte: se ignora.
      if (img.width < cols * manifest.frameWidth || img.height < rows * manifest.frameHeight) {
        debugPrint('[combate] ${e.value} no coincide con el manifiesto; se ignora');
        img.dispose();
        continue;
      }
      strips[e.key] = ZombieStrip(img, spec, [for (var i = 0; i < spec.frames; i++) spec.frameRect(i, manifest.frameWidth, manifest.frameHeight)]);
    }
    if (!strips.containsKey(ZombieAnim.idle)) {
      for (final s in strips.values) {
        s.image.dispose();
      }
      strips.clear();
    }

    final hasSprites = strips.isNotEmpty;
    final placement = hasSprites || manifest.placements.containsKey(key)
        ? manifest.placementFor(key)
        : (manifest.placements['walker'] ?? CombatManifest.fallback.placementFor(key));
    final procedural = hasSprites ? null : ProceduralZombie(type, groundInFrame: placement.groundInFrame);

    Rect? body = manifest.bodyBoxes[key];
    var heads = <Rect>[];
    if (hasSprites) {
      final boxes = await _alphaBoxes(strips[ZombieAnim.idle]!, manifest, placement.groundInFrame);
      body ??= boxes?.body;
      heads = boxes?.heads ?? const [];
    } else if (procedural != null) {
      heads = [procedural.headBox];
    }
    Rect? hold;
    final prep = strips[ZombieAnim.chargePrepare];
    if (prep != null) {
      hold = await _lastFrameHead(prep, manifest);
      // Si "la cabeza" detectada es mucho más ancha que la de reposo, en
      // realidad es la espalda encorvada: no hay tiro a la cabeza posible.
      final ref = heads.isEmpty ? null : heads.first;
      if (hold == null || (ref != null && hold.width > ref.width * 1.6)) hold = Rect.zero;
    }
    body ??= procedural?.bodyBox;
    body ??= Rect.fromLTRB(
      manifest.frameWidth * 0.33,
      manifest.frameHeight * 0.17,
      manifest.frameWidth * 0.67,
      manifest.frameHeight * placement.groundInFrame,
    );

    return CombatArt._(
      type: type,
      manifest: manifest,
      background: bg ?? buildProceduralBackdrop(manifest.background.size),
      proceduralBackground: bg == null,
      foreground: fg,
      strips: strips,
      placement: placement,
      bodyInFrame: body,
      headsInFrame: heads,
      headHoldInFrame: hold,
      fxAtlas: buildFxAtlas(),
      procedural: procedural,
    );
  }

  static Future<ui.Image?> _image(AssetBundle b, String path) async {
    try {
      final data = await b.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (e) {
      debugPrint('[combate] no se pudo cargar $path: $e');
      return null;
    }
  }

  static Future<Rect?> _lastFrameHead(ZombieStrip strip, CombatManifest m) async {
    try {
      final data = await strip.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return alphaHeadBox(
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        imageWidth: strip.image.width,
        frameWidth: m.frameWidth,
        frameHeight: m.frameHeight,
        frame: strip.frames.last,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<({Rect? body, List<Rect> heads})?> _alphaBoxes(ZombieStrip idle, CombatManifest m, double groundInFrame) async {
    try {
      final data = await idle.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final n = idle.frames.length;
      final pick = {0, n ~/ 3, (2 * n) ~/ 3}.where((i) => i < n).map((i) => idle.frames[i]).toList();
      final body = alphaBodyBox(
        rgba: rgba,
        imageWidth: idle.image.width,
        frameWidth: m.frameWidth,
        frameHeight: m.frameHeight,
        frames: pick,
        groundInFrame: groundInFrame,
      );
      final heads = <Rect>[];
      for (final f in idle.frames) {
        final h = alphaHeadBox(rgba: rgba, imageWidth: idle.image.width, frameWidth: m.frameWidth, frameHeight: m.frameHeight, frame: f);
        if (h == null) return (body: body, heads: const <Rect>[]);
        heads.add(h);
      }
      return (body: body, heads: heads);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Atlas de partículas (se genera una vez)
// ---------------------------------------------------------------------------

ui.Image buildFxAtlas() {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  void soft(Rect r, List<double> stops, List<Color> colors) {
    c.drawRect(r, Paint()..shader = ui.Gradient.radial(r.center, r.width / 2, colors, stops));
  }

  soft(FxAtlas.blob, const [0, 0.45, 1], const [Color(0xB0FFFFFF), Color(0x40FFFFFF), Color(0x00FFFFFF)]);
  soft(FxAtlas.dot, const [0, 0.25, 1], const [Color(0xFFFFFFFF), Color(0xC0FFFFFF), Color(0x00FFFFFF)]);
  final s = FxAtlas.streak;
  c.drawRect(
    s,
    Paint()
      ..shader = ui.Gradient.linear(s.centerLeft, s.centerRight, const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x40FFFFFF)], const [0, 0.8, 1]),
  );
  // Esquirla irregular (polvo/ceniza oscura).
  final h = FxAtlas.shard;
  c.drawPath(
    Path()
      ..moveTo(h.left + 2, h.top + 5)
      ..lineTo(h.left + 9, h.top + 1)
      ..lineTo(h.left + 15, h.top + 7)
      ..lineTo(h.left + 11, h.top + 15)
      ..lineTo(h.left + 4, h.top + 12)
      ..close(),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final r = FxAtlas.ring;
  c.drawCircle(
    r.center,
    13,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
  );
  final pic = rec.endRecording();
  final img = pic.toImageSync(160, 128);
  pic.dispose();
  return img;
}

// ---------------------------------------------------------------------------
// Fondo de reserva: calle nocturna fría, niebla y luz de emergencia
// ---------------------------------------------------------------------------

ui.Image buildProceduralBackdrop(Size size) {
  final w = size.width;
  final h = size.height;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final rnd = math.Random(7);
  final horizon = h * 0.42;
  final vp = Offset(w * 0.5, horizon);

  // Cielo.
  c.drawRect(
    Rect.fromLTWH(0, 0, w, horizon + 4),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, horizon),
        const [Color(0xFF030507), Color(0xFF0A1014), Color(0xFF1A2428)],
        const [0, 0.55, 1],
      ),
  );
  // Resplandor de ciudad incendiada muy al fondo (frío, casi gris).
  c.drawCircle(
    Offset(w * 0.62, horizon),
    w * 0.55,
    Paint()..shader = ui.Gradient.radial(Offset(w * 0.62, horizon), w * 0.55, const [Color(0x332E3A3E), Color(0x00000000)]),
  );

  // Siluetas lejanas.
  final far = Paint()..color = const Color(0xFF0C1215);
  var x = -10.0;
  while (x < w + 10) {
    final bw = 30 + rnd.nextDouble() * 70;
    final bh = 40 + rnd.nextDouble() * 150;
    c.drawRect(Rect.fromLTWH(x, horizon - bh, bw, bh + 2), far);
    if (rnd.nextDouble() < 0.35) {
      c.drawRect(Rect.fromLTWH(x + bw * 0.4, horizon - bh - 24, 3, 24), far); // antena
    }
    x += bw - 4;
  }
  final win = Paint()..color = const Color(0x553C5560);
  for (var i = 0; i < 26; i++) {
    c.drawRect(Rect.fromLTWH(rnd.nextDouble() * w, horizon - 20 - rnd.nextDouble() * 120, 3, 4), win);
  }

  // Suelo (asfalto mojado).
  c.drawRect(
    Rect.fromLTWH(0, horizon, w, h - horizon),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, horizon),
        Offset(0, h),
        const [Color(0xFF151D21), Color(0xFF0B1013), Color(0xFF07090B)],
        const [0, 0.35, 1],
      ),
  );
  // Veredas y cordón en perspectiva.
  Offset onGround(double gx, double t) => Offset.lerp(vp, Offset(gx, h * 1.02), t)!;
  final curb = Paint()
    ..color = const Color(0xFF26323A)
    ..strokeWidth = 3;
  for (final gx in [-w * 0.55, w * 1.55]) {
    c.drawLine(onGround(gx, 0.03), onGround(gx, 1), curb);
  }
  // Líneas del carril (gastadas).
  final lane = Paint()..color = const Color(0x40A4B8BD);
  for (var i = 0; i < 9; i++) {
    final t0 = math.pow((i + 0.2) / 9, 1.7).toDouble();
    final t1 = math.pow((i + 0.55) / 9, 1.7).toDouble();
    final a = onGround(w * 0.5, t0);
    final b = onGround(w * 0.5, t1);
    final hw = 1.0 + 7 * t1;
    c.drawPath(
      Path()
        ..moveTo(a.dx - hw * 0.4, a.dy)
        ..lineTo(a.dx + hw * 0.4, a.dy)
        ..lineTo(b.dx + hw, b.dy)
        ..lineTo(b.dx - hw, b.dy)
        ..close(),
      lane,
    );
  }

  // Edificios laterales en perspectiva.
  void facade(bool left) {
    final nearX = left ? 0.0 : w;
    final farX = left ? w * 0.36 : w * 0.64;
    final path = Path()
      ..moveTo(nearX, -20)
      ..lineTo(farX, horizon - h * 0.2)
      ..lineTo(farX, horizon + 6)
      ..lineTo(nearX, h * 0.80)
      ..close();
    c.drawPath(path, Paint()..shader = ui.Gradient.linear(Offset(nearX, 0), Offset(farX, 0), const [Color(0xFF0B0F12), Color(0xFF111A1E)]));
    // Ventanas en perspectiva.
    final dark = Paint()..color = const Color(0xFF070A0C);
    final lit = Paint()..color = const Color(0x664E6A72);
    for (var col = 0; col < 7; col++) {
      final t0 = col / 7;
      final t1 = t0 + 0.08;
      for (var row = 0; row < 6; row++) {
        final f0 = 0.12 + row * 0.13;
        final f1 = f0 + 0.07;
        Offset p(double t, double f) {
          final x = nearX + (farX - nearX) * t;
          final top = -20 + (horizon - h * 0.2 + 20) * t;
          final bottom = h * 0.80 + (horizon + 6 - h * 0.80) * t;
          return Offset(x, top + (bottom - top) * f);
        }

        final q = Path()
          ..moveTo(p(t0, f0).dx, p(t0, f0).dy)
          ..lineTo(p(t1, f0).dx, p(t1, f0).dy)
          ..lineTo(p(t1, f1).dx, p(t1, f1).dy)
          ..lineTo(p(t0, f1).dx, p(t0, f1).dy)
          ..close();
        c.drawPath(q, rnd.nextDouble() < 0.08 ? lit : dark);
      }
    }
  }

  facade(true);
  facade(false);

  // Farola fría a la derecha y su charco de luz.
  final pole = Paint()..color = const Color(0xFF05080A);
  final px = w * 0.83;
  c.drawRect(Rect.fromLTWH(px - 5, h * 0.24, 10, h * 0.62), pole);
  c.drawRect(Rect.fromLTWH(px - 120, h * 0.24, 125, 7), pole);
  c.drawCircle(
    Offset(px - 110, h * 0.25),
    90,
    Paint()..shader = ui.Gradient.radial(Offset(px - 110, h * 0.25), 90, const [Color(0x5AA9D4DC), Color(0x00000000)]),
  );
  c.drawOval(
    Rect.fromCenter(center: Offset(px - 120, h * 0.83), width: w * 0.9, height: h * 0.16),
    Paint()..shader = ui.Gradient.radial(Offset(px - 120, h * 0.83), w * 0.45, const [Color(0x26A9D4DC), Color(0x00000000)]),
  );

  // Auto abandonado a la izquierda y tambores.
  final car = Paint()..color = const Color(0xFF080B0D);
  c.drawPath(
    Path()
      ..moveTo(-20, h * 0.74)
      ..lineTo(w * 0.05, h * 0.66)
      ..lineTo(w * 0.22, h * 0.645)
      ..lineTo(w * 0.31, h * 0.69)
      ..lineTo(w * 0.33, h * 0.75)
      ..lineTo(-20, h * 0.79)
      ..close(),
    car,
  );
  c.drawRect(Rect.fromLTWH(w * 0.7, h * 0.64, 38, 56), car);
  c.drawRect(Rect.fromLTWH(w * 0.76, h * 0.655, 34, 50), car);

  // Luz de emergencia roja desde la izquierda (fuera de cuadro).
  c.drawCircle(
    Offset(-w * 0.05, h * 0.5),
    w * 0.75,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(-w * 0.05, h * 0.5),
        w * 0.75,
        const [Color(0x40EE3B45), Color(0x10EE3B45), Color(0x00000000)],
        const [0, 0.5, 1],
      ),
  );
  // Reflejo rojo en el piso mojado.
  c.drawOval(
    Rect.fromCenter(center: Offset(w * 0.15, h * 0.86), width: w * 0.6, height: h * 0.08),
    Paint()..shader = ui.Gradient.radial(Offset(w * 0.15, h * 0.86), w * 0.3, const [Color(0x22EE3B45), Color(0x00000000)]),
  );

  // Banda de niebla en el horizonte.
  c.drawRect(
    Rect.fromLTWH(0, horizon - h * 0.12, w, h * 0.24),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, horizon - h * 0.12),
        Offset(0, horizon + h * 0.12),
        const [Color(0x00283338), Color(0x50283338), Color(0x00283338)],
        const [0, 0.5, 1],
      ),
  );
  // Viñeta.
  c.drawRect(
    Offset.zero & size,
    Paint()..shader = ui.Gradient.radial(Offset(w / 2, h * 0.55), h * 0.75, const [Color(0x00000000), Color(0xA0000000)], const [0.55, 1]),
  );

  final pic = rec.endRecording();
  final img = pic.toImageSync(w.round(), h.round());
  pic.dispose();
  return img;
}
