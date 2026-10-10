// Manifiesto de arte del combate (`assets/combat/manifest.json`) y geometría
// del escenario. Lógica pura: no carga imágenes ni depende de Flame.
//
// Forma esperada (todas las claves salvo `zombies` son opcionales):
//
// {
//   "frameWidth": 360, "frameHeight": 480, "fps": 15,
//   "anchor": {"x": 0.5, "y": 1.0},             // abajo-centro del CUADRO, fracción (o px) del fondo
//   "spriteScale": 2,                            // px del fondo por px del cuadro
//   "background": {"file": "bg_street.jpg", "foreground": "bg_street_fg.png",
//                  "width": 720, "height": 1280},
//   "zombies": {"walker": {"idle": {"file": "walker_idle.png", "frames": 12, "loop": true},
//                          "attack": {"file": "...", "frames": 10, "impactFrame": 6}, ...}},
//   "placement": {"walker": {"bgRect": [x, y, w, h],
//                            "groundContact": {"x": 360, "y": 1203},
//                            "groundContactInFrame": {"x": 0.5, "y": 0.92}}},
//   "bbox": {"walker": [x, y, w, h]}               // cuerpo, en px del cuadro
// }

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Animaciones del zombie que la escena sabe reproducir.
enum ZombieAnim {
  idle('idle'),
  attack('attack'),
  hit('hit'),
  death('death'),
  chargePrepare('charge_prepare'),
  charge('charge'),
  scream('scream');

  const ZombieAnim(this.key);
  final String key;

  static ZombieAnim? tryFromKey(String key) {
    for (final a in values) {
      if (a.key == key) return a;
    }
    return null;
  }
}

/// Una tira horizontal (o grilla) de cuadros.
class AnimSpec {
  const AnimSpec({
    required this.file,
    required this.frames,
    this.loop = false,
    this.holdLast = false,
    this.impactFrame,
    this.peakFrame,
    this.fps,
    this.columns,
  });

  final String file;
  final int frames;
  final bool loop;

  /// Al terminar se queda en el último cuadro (muerte, preparación de embestida).
  final bool holdLast;

  /// Cuadro del impacto de un ataque (para sincronizar el temblor y el daño).
  final int? impactFrame;

  /// Cuadro de máxima intensidad (grito).
  final int? peakFrame;
  final double? fps;

  /// Columnas si la tira es una grilla; `null` = una sola fila.
  final int? columns;

  double fpsOr(double fallback) => fps ?? fallback;

  /// Duración total en segundos.
  double duration(double defaultFps) => frames / fpsOr(defaultFps);

  /// Segundo en el que ocurre el impacto (o el pico), si se conoce.
  double? keyTime(double defaultFps) {
    final f = impactFrame ?? peakFrame;
    return f == null ? null : (f + 0.5) / fpsOr(defaultFps);
  }

  /// Rectángulo fuente del cuadro `i` dentro de la imagen.
  Rect frameRect(int i, int frameWidth, int frameHeight) {
    final cols = columns ?? frames;
    final c = i % cols;
    final r = i ~/ cols;
    return Rect.fromLTWH((c * frameWidth).toDouble(), (r * frameHeight).toDouble(), frameWidth.toDouble(), frameHeight.toDouble());
  }

  static AnimSpec? fromJson(Object? json, {required String key}) {
    if (json is! Map) return null;
    final file = json['file'];
    final frames = _int(json['frames']);
    if (file is! String || file.isEmpty || frames == null || frames <= 0) return null;
    return AnimSpec(
      file: file,
      frames: frames,
      loop: json['loop'] is bool ? json['loop'] as bool : key == 'idle',
      holdLast: json['holdLast'] == true || key == 'death',
      impactFrame: _int(json['impactFrame']),
      peakFrame: _int(json['peakFrame']),
      fps: _dbl(json['fps']),
      columns: _int(json['columns']),
    );
  }
}

class BackgroundSpec {
  const BackgroundSpec({this.file = 'bg_street.jpg', this.foreground, this.width = 720, this.height = 1280});

  final String file;
  final String? foreground;
  final double width;
  final double height;

  Size get size => Size(width, height);

  static BackgroundSpec fromJson(Object? json) {
    if (json is! Map) return const BackgroundSpec(foreground: 'bg_street_fg.png');
    final f = json['file'];
    final fg = json['foreground'];
    return BackgroundSpec(
      file: f is String && f.isNotEmpty ? f : 'bg_street.jpg',
      foreground: fg is String && fg.isNotEmpty ? fg : null,
      width: _dbl(json['width']) ?? 720,
      height: _dbl(json['height']) ?? 1280,
    );
  }
}

/// Dónde se dibuja el cuadro completo del zombie sobre el fondo.
class ZombiePlacement {
  const ZombiePlacement({required this.bgRect, required this.groundBgY, required this.groundInFrame});

  /// Rectángulo (px del fondo) que ocupa el cuadro entero del sprite.
  final Rect bgRect;

  /// Línea de suelo (px del fondo) donde apoyan los pies.
  final double groundBgY;

  /// Fracción (0..1) de la altura del cuadro donde están los pies.
  final double groundInFrame;
}

class CombatManifest {
  const CombatManifest({
    this.frameWidth = 360,
    this.frameHeight = 480,
    this.fps = 15,
    this.background = const BackgroundSpec(),
    this.anchor = defaultAnchor,
    this.spriteScale = 2,
    this.zombies = const {},
    this.placements = const {},
    this.bodyBoxes = const {},
    this.isFallback = false,
  });

  /// Ancla por defecto: el borde inferior-central del cuadro va al pie del
  /// fondo (360, 1280), como en el arte final.
  static const defaultAnchor = Offset(0.5, 1.0);

  /// Altura de los pies dentro del cuadro si el manifiesto no la declara.
  static const defaultGroundInFrame = 0.92;

  final int frameWidth;
  final int frameHeight;
  final double fps;
  final BackgroundSpec background;

  /// Dónde cae el borde inferior-central del cuadro (fracción del fondo) si no
  /// hay `placement` para el tipo.
  final Offset anchor;

  /// px del fondo por px del sprite cuando no hay `placement`.
  final double spriteScale;
  final Map<String, Map<ZombieAnim, AnimSpec>> zombies;
  final Map<String, ZombiePlacement> placements;

  /// Caja del cuerpo declarada en el manifiesto (px del cuadro).
  final Map<String, Rect> bodyBoxes;

  /// `true` si no se encontró el manifiesto (arte procedural).
  final bool isFallback;

  /// Manifiesto de reserva: sin tiras, el zombie y el fondo se dibujan por código.
  /// Usa el mismo encuadre que el arte real (cuadro ×2 apoyado en el pie del fondo).
  static const fallback = CombatManifest(background: BackgroundSpec(), isFallback: true);

  Size get frameSize => Size(frameWidth.toDouble(), frameHeight.toDouble());

  Map<ZombieAnim, AnimSpec> animsFor(String type) => zombies[type] ?? const {};

  bool hasSprites(String type) => animsFor(type).containsKey(ZombieAnim.idle);

  ZombiePlacement placementFor(String type) {
    final p = placements[type];
    if (p != null) return p;
    final bw = background.width;
    final bh = background.height;
    final ax = anchor.dx * bw;
    final ay = anchor.dy * bh;
    final w = frameWidth * spriteScale;
    final h = frameHeight * spriteScale;
    return ZombiePlacement(
      bgRect: Rect.fromLTWH(ax - w / 2, ay - h, w, h),
      groundBgY: ay - h * (1 - defaultGroundInFrame),
      groundInFrame: defaultGroundInFrame,
    );
  }

  /// Archivos de imagen que necesita un tipo (fondo, primer plano y tiras).
  List<String> filesFor(String type) => [
    background.file,
    if (background.foreground != null) background.foreground!,
    for (final a in animsFor(type).values) a.file,
  ];

  static CombatManifest? tryParse(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      return parse(source);
    } catch (_) {
      return null;
    }
  }

  /// Lanza [FormatException] si el JSON no es un objeto.
  static CombatManifest parse(String source) {
    final root = jsonDecode(source);
    if (root is! Map) throw const FormatException('manifest.json debe ser un objeto');
    final fw = _int(root['frameWidth']) ?? 360;
    final fh = _int(root['frameHeight']) ?? 480;
    final bg = BackgroundSpec.fromJson(root['background']);

    final zombies = <String, Map<ZombieAnim, AnimSpec>>{};
    final zs = root['zombies'];
    if (zs is Map) {
      for (final e in zs.entries) {
        final anims = <ZombieAnim, AnimSpec>{};
        final v = e.value;
        if (v is! Map) continue;
        for (final a in v.entries) {
          final kind = ZombieAnim.tryFromKey('${a.key}');
          final spec = kind == null ? null : AnimSpec.fromJson(a.value, key: kind.key);
          if (kind != null && spec != null) anims[kind] = spec;
        }
        if (anims.isNotEmpty) zombies['${e.key}'] = anims;
      }
    }

    final placements = <String, ZombiePlacement>{};
    final ps = root['placement'];
    if (ps is Map) {
      for (final e in ps.entries) {
        final p = _placement(e.value, fw, fh);
        if (p != null) placements['${e.key}'] = p;
      }
    }

    final boxes = <String, Rect>{};
    final bb = root['bbox'];
    if (bb is Map) {
      for (final e in bb.entries) {
        final r = _rect(e.value);
        if (r != null && r.width > 0 && r.height > 0) boxes['${e.key}'] = r;
      }
    }

    return CombatManifest(
      frameWidth: fw,
      frameHeight: fh,
      fps: math.max(1, _dbl(root['fps']) ?? 15),
      background: bg,
      anchor: _anchor(root['anchor'], bg) ?? defaultAnchor,
      spriteScale: _dbl(root['spriteScale']) ?? 2,
      zombies: zombies,
      placements: placements,
      bodyBoxes: boxes,
    );
  }

  static ZombiePlacement? _placement(Object? json, int fw, int fh) {
    if (json is! Map) return null;
    final r = _rect(json['bgRect']);
    if (r == null || r.width <= 0 || r.height <= 0) return null;
    final inFrame = _point(json['groundContactInFrame']);
    final contact = _point(json['groundContact']);
    final gf = inFrame?.dy ?? (contact != null ? (contact.dy - r.top) / r.height : defaultGroundInFrame);
    final gy = contact?.dy ?? r.top + gf * r.height;
    return ZombiePlacement(bgRect: r, groundBgY: gy, groundInFrame: gf.clamp(0.05, 1.0));
  }

  static Offset? _anchor(Object? json, BackgroundSpec bg) {
    final p = _point(json);
    if (p == null) return null;
    // Valores > 1.5 se interpretan como píxeles del fondo.
    final x = p.dx > 1.5 ? p.dx / bg.width : p.dx;
    final y = p.dy > 1.5 ? p.dy / bg.height : p.dy;
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }
}

// ---------------------------------------------------------------------------
// Geometría del escenario
// ---------------------------------------------------------------------------

/// Transformación fondo → pantalla. El fondo se escala para cubrir la vista
/// ("cover") y se apoya en el borde inferior: la línea de suelo queda siempre a
/// la misma altura relativa al pie de la pantalla, sea cual sea la proporción
/// del teléfono (en pantallas más altas se recortan los costados; en más
/// anchas, el cielo).
class StageLayout {
  const StageLayout({required this.view, required this.bgSize, required this.scale, required this.offset});

  final Size view;
  final Size bgSize;
  final double scale;
  final Offset offset;

  /// `frameBgHeight` (alto del cuadro del zombie en px del fondo) limita la
  /// escala en vistas muy anchas para que el zombie no ocupe más de
  /// `maxZombieScreenFrac` de la altura.
  factory StageLayout.compute({required Size view, required Size bg, double frameBgHeight = 960, double maxZombieScreenFrac = 0.82}) {
    if (view.isEmpty || bg.isEmpty) {
      return StageLayout(view: view, bgSize: bg, scale: 1, offset: Offset.zero);
    }
    final cover = math.max(view.width / bg.width, view.height / bg.height);
    final cap = view.height * maxZombieScreenFrac / math.max(1, frameBgHeight);
    final s = math.max(view.height / bg.height, math.min(cover, cap));
    final ox = (view.width - bg.width * s) / 2;
    final oy = view.height - bg.height * s;
    return StageLayout(view: view, bgSize: bg, scale: s, offset: Offset(ox, oy));
  }

  Offset toScreen(Offset bg) => Offset(offset.dx + bg.dx * scale, offset.dy + bg.dy * scale);

  Rect rectToScreen(Rect r) => Rect.fromLTWH(offset.dx + r.left * scale, offset.dy + r.top * scale, r.width * scale, r.height * scale);

  Rect get bgScreenRect => rectToScreen(Offset.zero & bgSize);
}

/// Mapea una caja en px del cuadro a pantalla, dado dónde se dibuja el cuadro.
Rect frameBoxToScreen(Rect frameBox, Size frameSize, Rect frameScreen) {
  final sx = frameScreen.width / frameSize.width;
  final sy = frameScreen.height / frameSize.height;
  return Rect.fromLTWH(frameScreen.left + frameBox.left * sx, frameScreen.top + frameBox.top * sy, frameBox.width * sx, frameBox.height * sy);
}

/// Caja del cuerpo a partir del alfa de los cuadros (RGBA8 sin premultiplicar
/// o premultiplicado: solo se mira el canal alfa). Recorre los cuadros
/// `frames` de una tira de `imageWidth` px de ancho. Devuelve `null` si no hay
/// píxeles opacos. El borde inferior se recorta en `groundInFrame` para no
/// contar el reflejo en el piso mojado.
Rect? alphaBodyBox({
  required List<int> rgba,
  required int imageWidth,
  required int frameWidth,
  required int frameHeight,
  required List<Rect> frames,
  int threshold = 96,
  int step = 2,
  double groundInFrame = 1,
}) {
  var minX = frameWidth, minY = frameHeight, maxX = -1, maxY = -1;
  for (final f in frames) {
    final fx = f.left.toInt();
    final fy = f.top.toInt();
    for (var y = 0; y < frameHeight; y += step) {
      final row = (fy + y) * imageWidth;
      for (var x = 0; x < frameWidth; x += step) {
        final i = (row + fx + x) * 4 + 3;
        if (i >= rgba.length) continue;
        if (rgba[i] >= threshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
  }
  if (maxX < 0) return null;
  final bottom = math.min(maxY + step.toDouble(), groundInFrame * frameHeight);
  if (bottom <= minY) return null;
  return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), (maxX + step).toDouble(), bottom);
}

/// Caja de la cabeza en UN cuadro, a partir del alfa.
///
/// Se recorre la silueta desde arriba siguiendo el tramo opaco continuo que
/// contiene el centro de la cabeza (así una mano a la misma altura no cuenta).
/// La cabeza termina en la primera fila (pasado [minFrac] del cuadro) que es
/// más de [widen] veces más ancha que el máximo de las filas anteriores con
/// [lag] filas de retraso: detecta los hombros aunque se ensanchen de a poco,
/// sin confundir la coronilla redondeada. Se descarta el último [neckCut]
/// (cuello) y el ancho se mide solo en las filas que quedan. Devuelve `null`
/// si el cuadro está vacío.
Rect? alphaHeadBox({
  required List<int> rgba,
  required int imageWidth,
  required int frameWidth,
  required int frameHeight,
  required Rect frame,
  int threshold = 96,
  double minFrac = 0.05,
  double maxFrac = 0.16,
  double widen = 1.25,
  double neckCut = 0.12,
  int lag = 4,
  int gap = 2,
}) {
  final fx = frame.left.toInt();
  final fy = frame.top.toInt();
  bool on(int x, int y) {
    final i = ((fy + y) * imageWidth + fx + x) * 4 + 3;
    return i >= 0 && i < rgba.length && rgba[i] >= threshold;
  }

  (int, int)? runAt(int y, int cx) {
    var c = -1;
    if (on(cx, y)) {
      c = cx;
    } else {
      for (var d = 1; d < 12 && c < 0; d++) {
        if (cx - d >= 0 && on(cx - d, y)) {
          c = cx - d;
        } else if (cx + d < frameWidth && on(cx + d, y)) {
          c = cx + d;
        }
      }
    }
    if (c < 0) return null;
    var lo = c, miss = 0;
    for (var x = c - 1; x >= 0; x--) {
      if (on(x, y)) {
        lo = x;
        miss = 0;
      } else if (++miss > gap) {
        break;
      }
    }
    var hi = c;
    miss = 0;
    for (var x = c + 1; x < frameWidth; x++) {
      if (on(x, y)) {
        hi = x;
        miss = 0;
      } else if (++miss > gap) {
        break;
      }
    }
    return (lo, hi);
  }

  var top = -1, cx = 0;
  for (var y = 0; y < frameHeight && top < 0; y++) {
    var lo = -1, hi = -1;
    for (var x = 0; x < frameWidth; x++) {
      if (on(x, y)) {
        if (lo < 0) lo = x;
        hi = x;
      }
    }
    if (lo >= 0) {
      top = y;
      cx = (lo + hi) ~/ 2;
    }
  }
  if (top < 0) return null;
  final minH = (minFrac * frameHeight).round();
  final maxH = (maxFrac * frameHeight).round();
  final rows = <(int, int, int)>[]; // (y, lo, hi)
  for (var y = top; y < math.min(frameHeight, top + maxH); y++) {
    final r = runAt(y, cx);
    if (r == null) {
      if (y - top >= minH) break;
      continue;
    }
    final w = r.$2 - r.$1 + 1;
    if (y - top >= minH) {
      var ref = 0;
      for (final q in rows) {
        if (q.$1 >= top + minH ~/ 2 && q.$1 <= y - lag) ref = math.max(ref, q.$3 - q.$2 + 1);
      }
      if (ref > 0 && w > widen * ref) break;
    }
    rows.add((y, r.$1, r.$2));
    cx = (r.$1 + r.$2) ~/ 2;
  }
  if (rows.isEmpty) return null;
  final keepTo = top + (rows.last.$1 - top + 1) * (1 - neckCut);
  var minX = frameWidth, maxX = -1;
  for (final r in rows) {
    if (r.$1 > keepTo) break;
    if (r.$2 < minX) minX = r.$2;
    if (r.$3 > maxX) maxX = r.$3;
  }
  if (maxX < 0) return null;
  return Rect.fromLTRB(minX.toDouble(), top.toDouble(), (maxX + 1).toDouble(), keepTo);
}

// ---------------------------------------------------------------------------
// Lectura defensiva
// ---------------------------------------------------------------------------

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.round();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round();
  return null;
}

double? _dbl(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

Offset? _point(Object? v) {
  if (v is Map) {
    final x = _dbl(v['x']);
    final y = _dbl(v['y']);
    return x == null || y == null ? null : Offset(x, y);
  }
  if (v is List && v.length >= 2) {
    final x = _dbl(v[0]);
    final y = _dbl(v[1]);
    return x == null || y == null ? null : Offset(x, y);
  }
  return null;
}

Rect? _rect(Object? v) {
  if (v is List && v.length >= 4) {
    final n = [for (final e in v.take(4)) _dbl(e)];
    if (n.any((e) => e == null)) return null;
    return Rect.fromLTWH(n[0]!, n[1]!, n[2]!, n[3]!);
  }
  if (v is Map) {
    final x = _dbl(v['x']);
    final y = _dbl(v['y']);
    final w = _dbl(v['w'] ?? v['width']);
    final h = _dbl(v['h'] ?? v['height']);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }
  return null;
}
