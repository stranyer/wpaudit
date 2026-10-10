// Títere de recorte ("cutout puppet"): una grilla de vértices sobre el recorte
// HD de la criatura que se deforma procedimentalmente (respiración, balanceo,
// cabeza, brazos, embestidas, golpes, caída). Lógica pura (sin Flame): la capa
// de render solo copia estas posiciones a `Canvas.drawVertices`.
//
// Coordenadas locales: píxeles de la imagen relativos al punto de apoyo de los
// pies (y negativa hacia arriba). `h` = altura normalizada (0 pies → 1 coronilla).

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/types.dart';
import 'creature_view.dart' show ZombieAnim;
import 'cutout_rig.dart';

export 'creature_view.dart' show ZombieAnim;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Smoothstep (admite bordes invertidos para rampas descendentes).
double smooth(double e0, double e1, double x) {
  final t = _clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

/// Campana suave: 0 en `a`, 1 en `b`, 0 en `c`.
double bump(double x, double a, double b, double c) {
  if (x <= a || x >= c) return 0;
  return x < b ? smooth(a, b, x) : 1 - smooth(b, c, x);
}

double _easeIn(double t) => t * t;
double _easeOut(double t) => 1 - (1 - t) * (1 - t);
double _easeInOut(double t) => t < 0.5 ? 2 * t * t : 1 - (2 - 2 * t) * (2 - 2 * t) / 2;

// -----------------------------------------------------------------------------
// Malla
// -----------------------------------------------------------------------------

/// Grilla de `cols × rows` vértices sobre la caja opaca del recorte. Las filas
/// se concentran arriba (cabeza y hombros, donde más se deforma).
class PuppetMesh {
  PuppetMesh._(this.cols, this.rows, this.uv, this.rest, this.h, this.side, this.noise, this.indices);

  factory PuppetMesh.grid(CutoutRig rig, {int cols = 11, int rows = 17, double margin = 4, double rowBias = 1.3}) {
    assert(cols >= 2 && rows >= 2 && cols * rows <= 0xFFFF);
    final n = cols * rows;
    final uv = Float32List(n * 2);
    final rest = Float32List(n * 2);
    final h = Float32List(n);
    final side = Float32List(n);
    final noise = Float32List(n);
    final b = rig.body;
    final left = math.max(0.0, b.left - margin);
    final right = math.min(rig.size.width, b.right + margin);
    final top = math.max(0.0, b.top - margin);
    final bottom = math.min(rig.size.height, b.bottom + margin);
    final halfW = math.max(1.0, b.width / 2);
    for (var r = 0; r < rows; r++) {
      final s = math.pow(r / (rows - 1), rowBias).toDouble();
      final v = top + (bottom - top) * s;
      for (var c = 0; c < cols; c++) {
        final u = left + (right - left) * c / (cols - 1);
        final i = r * cols + c;
        uv[i * 2] = u;
        uv[i * 2 + 1] = v;
        rest[i * 2] = u - rig.feet.dx;
        rest[i * 2 + 1] = v - rig.feet.dy;
        h[i] = (rig.feet.dy - v) / b.height;
        side[i] = (u - rig.centroidX) / halfW;
        // Ruido determinístico por vértice (disolución al morir).
        final k = math.sin(i * 12.9898 + 78.233) * 43758.5453;
        noise[i] = k - k.floorToDouble();
      }
    }
    final idx = Uint16List((cols - 1) * (rows - 1) * 6);
    var o = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final a = r * cols + c;
        final d = a + cols;
        idx[o++] = a;
        idx[o++] = a + 1;
        idx[o++] = d;
        idx[o++] = a + 1;
        idx[o++] = d + 1;
        idx[o++] = d;
      }
    }
    return PuppetMesh._(cols, rows, uv, rest, h, side, noise, idx);
  }

  final int cols;
  final int rows;

  /// Coordenadas de textura (px de la imagen), 2 por vértice.
  final Float32List uv;

  /// Posición de reposo local (px de la imagen relativos a los pies).
  final Float32List rest;

  /// Altura normalizada (0 pies → 1 coronilla) de cada vértice en reposo.
  final Float32List h;

  /// Posición lateral normalizada respecto del centroide (−1 izquierda … 1 derecha).
  final Float32List side;

  /// Ruido 0…1 por vértice.
  final Float32List noise;
  final Uint16List indices;

  int get vertexCount => cols * rows;
}

// -----------------------------------------------------------------------------
// Pose
// -----------------------------------------------------------------------------

/// Parámetros de deformación de un instante. Las magnitudes espaciales están
/// en unidades de la altura del cuerpo (H) salvo [dentX]/[dentY]/[dentR] (px locales).
class PuppetPose {
  // Locales.
  double breath = 0; // escala lateral del torso (±0.02)
  double sway = 0; // flexión desde los pies (rad en la coronilla)
  double headAngle = 0; // rad alrededor del cuello
  double headStretch = 0; // estiramiento vertical de la cabeza (grito)
  double headDx = 0, headDy = 0;
  double armL = 0, armR = 0, armLy = 0, armRy = 0;
  double crouch = 0; // 0…1 agachado (preparar embestida); <0 se estira
  double buckle = 0; // 0…1 rodillas que ceden (muerte)
  double kneeDir = 1;
  double squash = 0; // aplastamiento del golpe
  double dent = 0, dentX = 0, dentY = 0, dentR = 1;
  double pulse = 0, pulsePhase = 0; // distorsión radial alrededor de la cabeza
  double yaw = 0; // giro del torso (rad): ilusión 3D, comprime el lado que se aleja
  // Globales.
  double scale = 1;
  double persp = 0; // las filas altas crecen más (se inclina hacia la cámara)
  double pivotH = 0.7; // altura del pivote de la escala global
  double rot = 0; // rad alrededor de los pies
  double tx = 0, ty = 0;
  // Apariencia.
  double alpha = 1;
  double dark = 0;
  double dissolve = 0;

  void reset() {
    breath = sway = headAngle = headStretch = headDx = headDy = 0;
    armL = armR = armLy = armRy = 0;
    crouch = buckle = squash = dent = pulse = pulsePhase = yaw = 0;
    kneeDir = 1;
    dentX = dentY = 0;
    dentR = 1;
    scale = 1;
    persp = 0;
    pivotH = 0.7;
    rot = tx = ty = 0;
    alpha = 1;
    dark = dissolve = 0;
  }
}

/// Aplica una [PuppetPose] a puntos locales del recorte.
class PuppetDeformer {
  PuppetDeformer(CutoutRig rig, {this.armInner = 0.5})
    : height = rig.body.height,
      halfW = math.max(1.0, rig.body.width / 2),
      cx = rig.centroidX - rig.feet.dx,
      neckX = rig.neck.dx - rig.feet.dx,
      neckY = rig.neck.dy - rig.feet.dy,
      headCx = rig.head.center.dx - rig.feet.dx,
      headCy = rig.head.center.dy - rig.feet.dy,
      headHalfW = math.max(1.0, rig.head.width / 2),
      hNeck = (rig.feet.dy - rig.neck.dy) / rig.body.height;

  final double height, halfW, cx, neckX, neckY, headCx, headCy, headHalfW, hNeck;

  /// Desde qué distancia lateral (fracción de media caja) empiezan los brazos.
  final double armInner;

  // Resultado de [apply] (sin asignaciones).
  double outX = 0, outY = 0;

  /// Deforma el punto local (`x`, `y`). Deja el resultado en [outX]/[outY].
  void apply(PuppetPose p, double x, double y) {
    final hh = height;
    final h = -y / hh;
    final hc = _clamp01(h);

    // Rodillas que ceden: se comprime la mitad inferior y baja el resto.
    if (p.buckle > 0) {
      final k = 0.42 * p.buckle;
      if (h < 0.5) {
        y *= 1 - k;
      } else {
        y += 0.5 * hh * k;
      }
      x += p.buckle * 0.06 * hh * bump(hc, 0.08, 0.27, 0.48) * p.kneeDir;
    }
    // Agacharse: compresión vertical y torso más ancho.
    if (p.crouch != 0) {
      y *= 1 - 0.085 * p.crouch;
      x = cx + (x - cx) * (1 + 0.07 * p.crouch * smooth(0.15, 0.75, hc));
    }
    // Giro del torso: el cuerpo como un cilindro que rota sobre su eje; el
    // lado que se aleja se comprime y el que se acerca se ensancha. Los pies
    // quedan plantados (el giro crece con la altura).
    if (p.yaw != 0) {
      final w = smooth(0.08, 0.55, hc);
      if (w > 0) {
        final s = ((x - cx) / halfW).clamp(-0.985, 0.985);
        final th = math.asin(s);
        final a = (th + p.yaw * w).clamp(-1.5, 1.5);
        x = cx + halfW * math.sin(a);
      }
    }
    // Respiración (torso) y hombros que suben.
    if (p.breath != 0) {
      x = cx + (x - cx) * (1 + p.breath * bump(hc, 0.4, 0.66, 0.92));
      y -= p.breath * 0.35 * hh * smooth(0.45, 1.0, hc);
    }
    // Brazos: péndulos desde los hombros (más deriva cuanto más lejos).
    final s = (x - cx) / halfW;
    final wa = smooth(armInner, math.min(1.0, armInner + 0.42), s.abs()) * smooth(0.9, 0.6, hc) * smooth(0.12, 0.32, hc);
    if (wa > 0) {
      if (s < 0) {
        x += p.armL * hh * wa;
        y += p.armLy * hh * wa;
      } else {
        x += p.armR * hh * wa;
        y += p.armRy * hh * wa;
      }
    }
    // Cabeza: rota alrededor del cuello; se estira (mandíbula) al gritar.
    final wy = smooth(hNeck - 0.05, hNeck + 0.025, hc);
    if (wy > 0) {
      final wx = 1 - smooth(1.05, 2.1, (x - headCx).abs() / headHalfW);
      final w = wy * wx;
      if (w > 0) {
        if (p.headStretch != 0) y = neckY + (y - neckY) * (1 + p.headStretch * w);
        x += p.headDx * hh * w;
        y += p.headDy * hh * w;
        final a = p.headAngle * w;
        if (a != 0) {
          final c = math.cos(a), sn = math.sin(a);
          final dx = x - neckX, dy = y - neckY;
          x = neckX + dx * c - dy * sn;
          y = neckY + dx * sn + dy * c;
        }
      }
    }
    // Aplastamiento del golpe.
    if (p.squash != 0) {
      y *= 1 - p.squash;
      x = cx + (x - cx) * (1 + p.squash * 0.7);
    }
    // Abolladura local alrededor del impacto (pellizco hacia el punto).
    if (p.dent > 0) {
      final dx = p.dentX - x, dy = p.dentY - y;
      final w = math.exp(-(dx * dx + dy * dy) / (p.dentR * p.dentR)) * p.dent;
      x += dx * w;
      y += dy * w;
    }
    // Pulso radial (onda del grito).
    if (p.pulse != 0) {
      final dx = x - headCx, dy = y - headCy;
      final r = math.sqrt(dx * dx + dy * dy);
      if (r > 1) {
        final k = math.sin(r / (hh * 0.06) - p.pulsePhase) * p.pulse * hh * math.exp(-r / (hh * 0.45));
        x += dx / r * k;
        y += dy / r * k;
      }
    }
    // Flexión desde los pies (balanceo): el ángulo crece con la altura.
    if (p.sway != 0) {
      final a = p.sway * hc * math.sqrt(hc);
      final c = math.cos(a), sn = math.sin(a);
      final nx = x * c - y * sn;
      y = x * sn + y * c;
      x = nx;
    }
    // Globales: escala con perspectiva, rotación sobre los pies y traslación.
    final k = p.scale * (1 + p.persp * hc);
    if (k != 1) {
      final py = -p.pivotH * hh;
      x = cx + (x - cx) * k;
      y = py + (y - py) * k;
    }
    if (p.rot != 0) {
      final c = math.cos(p.rot), sn = math.sin(p.rot);
      final nx = x * c - y * sn;
      y = x * sn + y * c;
      x = nx;
    }
    outX = x + p.tx * hh;
    outY = y + p.ty * hh;
  }

  /// Deforma toda la malla y escribe posiciones de pantalla en `out`
  /// (`origin` = pantalla de los pies, `scale` = px de pantalla por px de imagen).
  void deformMesh(PuppetPose p, PuppetMesh m, Float32List out, double originX, double originY, double scale) {
    final rest = m.rest;
    final n = m.vertexCount;
    for (var i = 0; i < n; i++) {
      apply(p, rest[i * 2], rest[i * 2 + 1]);
      out[i * 2] = originX + outX * scale;
      out[i * 2 + 1] = originY + outY * scale;
    }
  }
}

// -----------------------------------------------------------------------------
// Estilo por criatura
// -----------------------------------------------------------------------------

class PuppetStyle {
  const PuppetStyle({
    this.breathPeriod = 3.2,
    this.breathAmp = 0.014,
    this.swayAmp = 0.022,
    this.swayFreq = 0.3,
    this.headAmp = 0.05,
    this.armAmp = 0.012,
    this.armInner = 0.5,
    this.twitchEvery = 3.5,
    this.twitchAmp = 0.12,
    this.attackScale = 1.45,
    this.chargeScale = 1.62,
    this.tremble = 0,
    this.yawAmp = 0.11,
  });

  final double breathPeriod;
  final double breathAmp;
  final double swayAmp;
  final double swayFreq;
  final double headAmp;
  final double armAmp;
  final double armInner;
  final double twitchEvery;
  final double twitchAmp;
  final double attackScale;
  final double chargeScale;

  /// Temblor nervioso permanente (Corredor).
  final double tremble;

  /// Giro máximo del torso en reposo (rad).
  final double yawAmp;
}

const Map<ZombieTypeId, PuppetStyle> puppetStyles = {
  // Tambaleo lento, cabeza que cuelga.
  ZombieTypeId.walker: PuppetStyle(breathPeriod: 3.4, breathAmp: 0.014, swayAmp: 0.03, swayFreq: 0.26, headAmp: 0.06, armAmp: 0.014),
  // Jadeo rápido, tics frecuentes, a punto de saltar.
  ZombieTypeId.runner: PuppetStyle(
    breathPeriod: 1.15,
    breathAmp: 0.018,
    swayAmp: 0.012,
    swayFreq: 0.5,
    headAmp: 0.035,
    armAmp: 0.012,
    armInner: 0.45,
    twitchEvery: 1.7,
    twitchAmp: 0.14,
    attackScale: 1.5,
    tremble: 0.004,
  ),
  // Panza que sube y baja, bamboleo pesado.
  ZombieTypeId.bloater: PuppetStyle(breathPeriod: 4.2, breathAmp: 0.026, swayAmp: 0.016, swayFreq: 0.2, headAmp: 0.03, armAmp: 0.01, armInner: 0.62, attackScale: 1.38),
  // Deriva fantasmal, dedos largos.
  ZombieTypeId.screamer: PuppetStyle(breathPeriod: 2.5, breathAmp: 0.012, swayAmp: 0.02, swayFreq: 0.19, headAmp: 0.05, armAmp: 0.018, armInner: 0.38, twitchEvery: 2.8),
  // Masa que respira hondo, casi inmóvil.
  ZombieTypeId.brute: PuppetStyle(
    breathPeriod: 3.8,
    breathAmp: 0.02,
    swayAmp: 0.011,
    swayFreq: 0.17,
    headAmp: 0.03,
    armAmp: 0.012,
    twitchEvery: 5,
    twitchAmp: 0.08,
    attackScale: 1.4,
    chargeScale: 1.6,
  ),
};

// -----------------------------------------------------------------------------
// Animador
// -----------------------------------------------------------------------------

/// Máquina de estados de la criatura: reloj continuo + animación en curso +
/// impulsos (golpes, destellos, tics). [evaluate] es puro dado el estado.
class PuppetAnimator {
  PuppetAnimator(this.style, {int seed = 11}) : _rnd = math.Random(seed) {
    _nextTwitch = style.twitchEvery * (0.6 + _rnd.nextDouble() * 0.8);
  }

  final PuppetStyle style;
  final math.Random _rnd;

  ZombieAnim anim = ZombieAnim.idle;

  /// Segundos desde que empezó [anim].
  double t = 0;

  /// Reloj continuo (respiración, balanceo).
  double clock = 0;

  /// Sostiene la pose agachada (el Bruto carga la embestida).
  bool crouchHold = false;

  /// Destello de impacto (1 → 0) y si ya viró a rojo.
  double flash = 0;
  bool flashCrit = false;

  /// Abolladura (local, px) que decae.
  double dent = 0, dentX = 0, dentY = 0, dentR = 1;
  double _snap = 0, _snapT = 9, _snapDir = 1;
  double _twitch = 0, _twitchSide = 1, _nextTwitch = 3;
  double fallDir = 1;
  double _hitDir = 1;

  bool get dead => anim == ZombieAnim.death;

  static double durationOf(ZombieAnim a) => switch (a) {
    ZombieAnim.idle => 0,
    ZombieAnim.attack => 0.78,
    ZombieAnim.charge => 0.95,
    ZombieAnim.hit => 0.45,
    ZombieAnim.death => 2.1,
    ZombieAnim.chargePrepare => 0.55,
    ZombieAnim.scream => 1.35,
  };

  /// Momento del impacto / pico (s).
  static double keyTimeOf(ZombieAnim a) => switch (a) {
    ZombieAnim.attack => 0.40,
    ZombieAnim.charge => 0.46,
    ZombieAnim.hit => 0.06,
    ZombieAnim.death => 0.97,
    ZombieAnim.chargePrepare => 0.3,
    ZombieAnim.scream => 0.32,
    ZombieAnim.idle => 0,
  };

  /// Reproduce `a`; devuelve su duración (0 si ya está muerta).
  double play(ZombieAnim a) {
    if (dead) return 0;
    // Un golpe recibido mientras carga no interrumpe la embestida preparada.
    anim = a;
    t = 0;
    if (a == ZombieAnim.charge || a == ZombieAnim.death) crouchHold = false;
    return durationOf(a);
  }

  /// Reacción a un impacto en el punto local (`x`, `y`) del recorte.
  void hitAt(double x, double y, double radius, {bool crit = false, bool headshot = false, double strength = 1}) {
    if (dead) return;
    flash = 1;
    flashCrit = crit;
    dent = 0.32 * strength;
    dentX = x;
    dentY = y;
    dentR = radius;
    _hitDir = x >= 0 ? 1 : -1;
    fallDir = -_hitDir;
    if (headshot) {
      _snap = 1;
      _snapT = 0;
      _snapDir = x >= 0 ? -1 : 1;
    }
  }

  void update(double dt) {
    clock += dt;
    t += dt;
    flash = math.max(0, flash - dt / 0.26);
    dent = math.max(0, dent - dt * 1.9);
    _snapT += dt;
    _twitch = math.max(0, _twitch - dt / 0.11);
    if (anim == ZombieAnim.idle && !crouchHold) {
      _nextTwitch -= dt;
      if (_nextTwitch <= 0) {
        _twitch = 1;
        _twitchSide = _rnd.nextBool() ? 1 : -1;
        _nextTwitch = style.twitchEvery * (0.6 + _rnd.nextDouble() * 0.8);
      }
    }
    final d = durationOf(anim);
    if (anim != ZombieAnim.idle && anim != ZombieAnim.death && t >= d) {
      anim = ZombieAnim.idle;
      t = 0;
    }
  }

  /// Intensidad del desenfoque de movimiento (fantasmas) ahora: 0…1.
  double get motionBlur {
    if (anim != ZombieAnim.attack && anim != ZombieAnim.charge) return 0;
    final k = keyTimeOf(anim);
    final start = k - (anim == ZombieAnim.charge ? 0.14 : 0.11);
    return bump(t, start - 0.02, k, k + 0.2);
  }

  /// Envolvente de la embestida (0 reposo → 1 encima de la cámara).
  static double lungeEnvelope(ZombieAnim a, double t) {
    if (a != ZombieAnim.attack && a != ZombieAnim.charge) return 0;
    final charge = a == ZombieAnim.charge;
    final key = keyTimeOf(a);
    final wind = charge ? 0.32 : 0.30;
    final end = durationOf(a);
    if (t <= wind) return 0;
    if (t < key) return _easeIn((t - wind) / (key - wind));
    if (t < key + 0.1) return 1;
    return 1 - _easeInOut(_clamp01((t - key - 0.1) / (end - key - 0.1)));
  }

  /// Calcula la pose del instante actual (o `back` segundos antes, para los
  /// fantasmas del desenfoque de movimiento).
  void evaluate(PuppetPose p, {double back = 0}) {
    p.reset();
    final s = style;
    final tt = math.max(0.0, t - back);
    final ck = clock - back;

    // --- Reposo (siempre de fondo) ---------------------------------------
    var idleW = 1.0;
    final env = lungeEnvelope(anim, tt);
    if (anim == ZombieAnim.attack || anim == ZombieAnim.charge) idleW = 1 - env;
    if (anim == ZombieAnim.death) idleW = 1 - smooth(0, 0.3, tt);
    final br = math.sin(2 * math.pi * ck / s.breathPeriod);
    p.breath = s.breathAmp * br * idleW;
    p.sway = s.swayAmp * (math.sin(ck * 2 * math.pi * s.swayFreq) + 0.35 * math.sin(ck * 2 * math.pi * s.swayFreq * 2.3 + 1.3)) * idleW;
    p.headAngle = s.headAmp * math.sin(ck * 1.1 + 0.6) * idleW;
    // Giro lento del torso, en fase con el balanceo (lee como volumen).
    p.yaw = s.yawAmp * math.sin(ck * 2 * math.pi * s.swayFreq * 0.8 + 0.9) * idleW;
    p.headDy = 0.004 * math.sin(2 * math.pi * ck / s.breathPeriod + 0.8) * idleW;
    p.armL = s.armAmp * math.sin(ck * 1.3) * idleW;
    p.armR = s.armAmp * math.sin(ck * 1.3 + 2.1) * idleW;
    p.armLy = -0.3 * s.armAmp * math.sin(ck * 1.3 + 0.7) * idleW;
    p.armRy = -0.3 * s.armAmp * math.sin(ck * 1.3 + 2.8) * idleW;
    if (s.tremble > 0) {
      p.headDx += s.tremble * math.sin(ck * 37) * idleW;
      p.sway += s.tremble * 0.6 * math.sin(ck * 29 + 1) * idleW;
    }
    if (back == 0 && _twitch > 0) {
      final k = _twitch * _twitch;
      p.headAngle += s.twitchAmp * k * _twitchSide;
      p.armR += 0.02 * k * _twitchSide;
      p.headDx += 0.004 * k * _twitchSide;
    }
    // Agachado sostenido (embestida preparada).
    if (crouchHold || anim == ZombieAnim.chargePrepare) {
      final k = anim == ZombieAnim.chargePrepare ? _easeOut(_clamp01(tt / 0.42)) : 1.0;
      p.crouch = k;
      p.armL -= 0.035 * k;
      p.armR += 0.035 * k;
      p.headDy += 0.01 * k;
      p.sway += 0.006 * k * math.sin(ck * 27);
      p.headAngle += 0.015 * k * math.sin(ck * 31);
    }

    switch (anim) {
      case ZombieAnim.idle || ZombieAnim.chargePrepare:
        break;
      case ZombieAnim.attack || ZombieAnim.charge:
        final charge = anim == ZombieAnim.charge;
        final key = keyTimeOf(anim);
        final windEnd = charge ? 0.32 : 0.30;
        // Anticipación: se echa atrás (más chico, la cabeza se levanta, brazos arriba).
        final w = bump(tt, 0, windEnd * 0.85, key) * (1 - env);
        final big = charge ? s.chargeScale : s.attackScale;
        p.scale = 1 - 0.04 * w + (big - 1) * env;
        p.persp = -0.04 * w + (charge ? 0.32 : 0.25) * env;
        p.pivotH = 0.72;
        p.crouch += (charge ? -0.3 : 0.35) * w;
        p.headAngle += -0.1 * w * _hitDir;
        p.armL += -0.03 * w + 0.05 * env;
        p.armR += 0.03 * w - 0.05 * env;
        p.armLy += -0.035 * w;
        p.armRy += -0.035 * w;
        p.ty = (charge ? 0.14 : 0.10) * env;
        p.rot = (charge ? 0.035 : 0.05) * env * (_hitDir > 0 ? -1 : 1);
        p.yaw += -0.12 * w * _hitDir;
      case ZombieAnim.hit:
        final k = bump(tt, 0, 0.06, durationOf(ZombieAnim.hit));
        p.scale = 1 - 0.05 * k;
        p.ty = -0.012 * k;
        p.squash = 0.035 * k;
        p.rot = -0.03 * k * _hitDir;
        p.sway += -0.03 * k * _hitDir;
        p.yaw += 0.16 * k * _hitDir;
      case ZombieAnim.scream:
        final k = bump(tt, 0, 0.24, durationOf(ZombieAnim.scream));
        p.headStretch = 0.13 * k;
        p.headDy += -0.014 * k;
        p.headAngle += -0.05 * k;
        p.headDx += 0.0035 * math.sin(ck * 72) * k;
        p.armL += -0.05 * k;
        p.armR += 0.05 * k;
        p.armLy += -0.03 * k;
        p.armRy += -0.03 * k;
        p.crouch += -0.25 * k;
        p.pulse = 0.012 * smooth(0.18, 0.32, tt) * (1 - smooth(0.7, 1.3, tt));
        p.pulsePhase = tt * 26;
        p.scale = 1 + 0.025 * k;
      case ZombieAnim.death:
        final buckle = _easeOut(_clamp01(tt / 0.35));
        final fall = _easeIn(_clamp01((tt - 0.22) / 0.75));
        final bounce = bump(tt, 0.97, 1.07, 1.25);
        p.buckle = buckle;
        p.kneeDir = fallDir;
        p.rot = fallDir * (1.25 * fall - 0.07 * bounce);
        p.headAngle += fallDir * 0.35 * fall;
        p.armL += 0.04 * fall * fallDir;
        p.armR += 0.04 * fall * fallDir;
        // Cae hacia atrás y de costado: se achica, se corre hacia el centro y se hunde.
        p.scale = 1 - 0.16 * fall;
        p.pivotH = 0;
        p.tx = -fallDir * 0.12 * fall;
        p.ty = 0.03 * fall + 0.07 * _easeIn(_clamp01((tt - 1.0) / 1.0));
        p.dark = 0.75 * smooth(0.5, 1.5, tt);
        p.dissolve = smooth(1.0, 2.05, tt);
    }

    // Impulsos.
    if (_snapT < 0.5) {
      final k = bump(_snapT, 0, 0.05, 0.5) * _snap;
      p.headAngle += 0.28 * k * _snapDir;
      p.headDy += -0.01 * k;
    }
    if (back == 0 && dent > 0) {
      p.dent = dent;
      p.dentX = dentX;
      p.dentY = dentY;
      p.dentR = dentR;
    }
  }
}
