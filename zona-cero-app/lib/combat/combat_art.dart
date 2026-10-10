// Carga del arte del combate: placa de fondo HD (`assets/art/bg/`), recorte HD
// de la criatura (`assets/art/zombies/`) y su análisis de alfa (rig), más las
// texturas generadas (atlas de partículas, grano). Nunca falla: si falta la
// placa usa un fondo procedural y si falta el recorte, una silueta procedural
// que pasa por el mismo títere.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../core/types.dart';
import 'cutout_rig.dart';
import 'procedural_zombie.dart';

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
    required this.plate,
    required this.proceduralPlate,
    required this.plateHorizon,
    required this.cutout,
    required this.fallbackCutout,
    required this.rig,
    required this.fxAtlas,
    required this.grain,
  });

  final ZombieTypeId type;

  /// Placa de fondo (calle bajo la lluvia).
  final ui.Image plate;
  final bool proceduralPlate;

  /// Altura del punto de fuga en la placa (fracción).
  final double plateHorizon;

  /// Recorte de la criatura (RGBA, fondo transparente).
  final ui.Image cutout;
  final bool fallbackCutout;
  final CutoutRig rig;
  final ui.Image fxAtlas;

  /// Ruido para el grano de película (se repite en mosaico).
  final ui.Image grain;

  Size get plateSize => Size(plate.width.toDouble(), plate.height.toDouble());

  void dispose() {
    plate.dispose();
    cutout.dispose();
    fxAtlas.dispose();
    grain.dispose();
  }

  static const plateAsset = 'assets/art/bg/combat_street.webp';
  static String cutoutAsset(ZombieTypeId type) => 'assets/art/zombies/${type.key}.webp';

  /// Carga todo lo necesario para pelear contra `type`.
  static Future<CombatArt> load(ZombieTypeId type, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final plateF = _image(b, plateAsset);
    final cutF = _image(b, cutoutAsset(type));
    final plate = await plateF;
    final loaded = await cutF;
    final hints = rigHints[type] ?? const RigHints();
    final analyzed = loaded == null ? null : await _analyze(loaded, hints);
    final ui.Image cut;
    final CutoutRig rig;
    if (loaded != null && analyzed != null) {
      cut = loaded;
      rig = analyzed;
    } else {
      // Silueta procedural: su geometría se conoce, no hace falta leer el alfa
      // (todo sincrónico: funciona igual en tests sin E/S real).
      loaded?.dispose();
      final z = ProceduralZombie(type);
      cut = z.toImage();
      rig = z.rig();
    }
    return CombatArt._(
      type: type,
      plate: plate ?? buildProceduralBackdrop(const Size(720, 1280)),
      proceduralPlate: plate == null,
      plateHorizon: plate == null ? 0.42 : 0.39,
      cutout: cut,
      fallbackCutout: !identical(cut, loaded),
      rig: rig,
      fxAtlas: buildFxAtlas(),
      grain: buildGrain(),
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

  static Future<CutoutRig?> _analyze(ui.Image img, RigHints hints) async {
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return analyzeCutout(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), img.width, img.height, hints: hints);
    } catch (e) {
      debugPrint('[combate] no se pudo analizar el recorte: $e');
      return null;
    }
  }
}

/// Mosaico de ruido para el grano de película (gris medio ± ruido, con alfa).
ui.Image buildGrain({int size = 96, int seed = 5}) {
  final rnd = math.Random(seed);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final p = Paint();
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = rnd.nextDouble();
      if (v > 0.35 && v < 0.65) continue;
      final light = v > 0.5;
      final a = ((light ? v - 0.65 : 0.35 - v) / 0.35 * 255).round().clamp(0, 255);
      p.color = light ? Color.fromARGB(a, 220, 228, 236) : Color.fromARGB(a, 0, 0, 0);
      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), p);
    }
  }
  final pic = rec.endRecording();
  final img = pic.toImageSync(size, size);
  pic.dispose();
  return img;
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
