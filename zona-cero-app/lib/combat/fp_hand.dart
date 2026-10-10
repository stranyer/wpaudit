// Mano en primera persona: qué recorte se muestra según el arma activa, cómo
// se encuadra (entra desde el borde inferior/derecho, como en la referencia) y
// su animación (vaivén al respirar, retroceso, golpe, guardia, sacudón al
// recibir un golpe). Lógica pura, sin Flame: la capa de render (hand_layer.dart)
// solo aplica estas poses.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../core/types.dart';

/// Modo del arma activa.
enum WeaponMode { melee, firearm }

/// Recorte de la mano en primera persona.
enum HandKind {
  pistol('assets/art/fp/fp_pistol.webp'),
  shotgun('assets/art/fp/fp_shotgun.webp'),
  melee('assets/art/fp/fp_melee.webp'),
  fists('assets/art/fp/fp_fists.webp');

  const HandKind(this.asset);
  final String asset;

  bool get firearm => this == pistol || this == shotgun;

  /// Qué mostrar si falta el recorte (llegan en tandas): el cuerpo a cuerpo
  /// cae en los puños; la escopeta en la pistola.
  HandKind? get fallback => switch (this) {
    HandKind.melee => HandKind.fists,
    HandKind.shotgun => HandKind.pistol,
    _ => null,
  };
}

/// Mano según el modo y lo equipado. Sin arma cuerpo a cuerpo: puños.
HandKind handFor(WeaponMode mode, {ItemId? firearm, ItemId? melee}) {
  if (mode == WeaponMode.firearm && firearm != null) {
    return firearm == ItemId.shotgun ? HandKind.shotgun : HandKind.pistol;
  }
  return melee == null ? HandKind.fists : HandKind.melee;
}

/// Encuadre de un recorte (todo en fracciones: de la imagen para puntos de la
/// imagen, del ancho de la vista para tamaños y desbordes).
class HandSpec {
  const HandSpec({
    required this.aspect,
    required this.width,
    required this.overRight,
    required this.overBottom,
    required this.pivot,
    this.muzzle,
    this.muzzleDir = const Offset(-1, -0.2),
    this.split = false,
    this.pivotRight = const Offset(0.75, 0.6),
    this.extendLeft = false,
    this.restRot = 0,
  });

  /// Ancho / alto del recorte.
  final double aspect;

  /// Ancho mostrado (fracción del ancho de la vista).
  final double width;

  /// Cuánto se pasa del borde derecho de la vista.
  final double overRight;

  /// Cuánto baja por debajo de la base (borde superior de la botonera).
  final double overBottom;

  /// Pivote de los giros (fracción de la imagen): la muñeca para las armas
  /// de fuego; el hombro/codo (donde el brazo sale del cuadro) para golpes
  /// amplios, así el corte del brazo nunca entra en pantalla.
  final Offset pivot;

  /// Giro de reposo (rad, alrededor de [pivot]).
  final double restRot;

  /// Boca del cañón (fracción de la imagen) y hacia dónde apunta.
  final Offset? muzzle;
  final Offset muzzleDir;

  /// Dos manos independientes (mitades izquierda y derecha del recorte).
  final bool split;

  /// Pivote de la mano derecha cuando [split].
  final Offset pivotRight;

  /// El brazo también sale por el borde izquierdo (se estira ese borde).
  final bool extendLeft;
}

const Map<HandKind, HandSpec> handSpecs = {
  HandKind.pistol: HandSpec(
    aspect: 1,
    width: 0.68,
    overRight: 0.1,
    overBottom: -0.05,
    pivot: Offset(0.6, 0.6),
    muzzle: Offset(0.252, 0.207),
    muzzleDir: Offset(-0.99, -0.16),
  ),
  HandKind.shotgun: HandSpec(
    aspect: 1,
    width: 0.92,
    overRight: 0.05,
    overBottom: 0.06,
    pivot: Offset(0.74, 0.8),
    muzzle: Offset(0.36, 0.276),
    muzzleDir: Offset(-0.88, -0.48),
    extendLeft: true,
  ),
  // El bate (cualquier arma cuerpo a cuerpo) en alto a la derecha, más vertical.
  HandKind.melee: HandSpec(aspect: 1, width: 0.62, overRight: 0.1, overBottom: -0.17, pivot: Offset(0.92, 0.98), restRot: 0.28),
  HandKind.fists: HandSpec(
    aspect: 1.5,
    width: 1.06,
    overRight: 0.03,
    overBottom: -0.1,
    pivot: Offset(0.12, 1),
    pivotRight: Offset(0.88, 1),
    split: true,
    extendLeft: true,
  ),
};

/// Rectángulo (pantalla) del recorte en reposo. `base` = y del borde superior
/// de la botonera (la mano entra por debajo de ella).
({double left, double top, double width, double height}) handRect(HandSpec spec, Size view, double base) {
  final w = spec.width * view.width;
  final h = w / spec.aspect;
  final right = view.width * (1 + spec.overRight);
  final bottom = base + spec.overBottom * view.width;
  return (left: right - w, top: bottom - h, width: w, height: h);
}

/// Desplazamiento de una mano en un instante (dx, dy en fracciones del ancho
/// de la vista; rot en rad alrededor de la muñeca; escala).
class HandPose {
  double dx = 0, dy = 0, rot = 0, scale = 1;

  void reset() {
    dx = dy = rot = 0;
    scale = 1;
  }
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _smooth(double e0, double e1, double x) {
  final t = _clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

double _bump(double x, double a, double b, double c) {
  if (x <= a || x >= c) return 0;
  return x < b ? _smooth(a, b, x) : 1 - _smooth(b, c, x);
}

double _easeOut(double t) => 1 - (1 - t) * (1 - t);
double _easeIn(double t) => t * t;

/// Animación de la mano. [update] avanza el reloj; [evaluate] es pura.
class HandRig {
  HandRig(this.kind);

  /// Recorte en pantalla (cambia a mitad de [swap]).
  HandKind kind;
  HandKind? _pending;

  double time = 0;
  double _shotT = 9, _swingT = 9, _dipT = 9, _swapT = 9, _clickT = 9;
  bool _heavy = false;

  /// Mano que golpea (puños): 1 derecha, −1 izquierda.
  int punchSide = 1;

  /// Hacia dónde va el golpe (fracciones del ancho de la vista, desde la muñeca).
  Offset _target = Offset.zero;

  /// Guardia (CUBRIRSE): objetivo y valor suavizado.
  bool guard = false;
  double guardK = 0;

  /// Apuntando (se estabiliza y se acerca al centro).
  bool aiming = false;
  double aimK = 0;

  /// Mano baja (huida, caída, fin del combate).
  bool lowered = false;
  double lowerK = 0;

  static const double shotDur = 0.75;
  static const double swingDur = 0.5;
  static const double punchDur = 0.38;
  static const double dipDur = 0.45;
  static const double swapDur = 0.5;

  /// Destello de la boca del cañón (1 → 0 en ~80 ms).
  double get flash => kind.firearm && _shotT < 0.08 ? 1 - _shotT / 0.08 : 0;

  /// La mano está a mitad de un golpe (para dibujar el rastro).
  double get swingSpeed {
    if (kind.firearm) return 0;
    final d = kind == HandKind.fists ? punchDur : swingDur;
    final u = _swingT / d;
    return kind == HandKind.fists ? _bump(u, 0.12, 0.28, 0.42) : _bump(u, 0.16, 0.3, 0.46);
  }

  bool get swapping => _swapT < swapDur;

  void update(double dt) {
    time += dt;
    _shotT += dt;
    _swingT += dt;
    _dipT += dt;
    _clickT += dt;
    if (_swapT < swapDur) {
      final before = _swapT;
      _swapT += dt;
      if (before < swapDur / 2 && _swapT >= swapDur / 2 && _pending != null) {
        kind = _pending!;
        _pending = null;
      }
    }
    final k = math.min(1.0, dt * 7);
    guardK += ((guard ? 1.0 : 0.0) - guardK) * k;
    aimK += ((aiming ? 1.0 : 0.0) - aimK) * math.min(1.0, dt * 9);
    lowerK += ((lowered ? 1.0 : 0.0) - lowerK) * math.min(1.0, dt * 3.2);
  }

  /// Cambia de recorte: baja la mano, cambia y la vuelve a subir.
  void swap(HandKind next) {
    if (next == kind && _pending == null) return;
    if (_swapT >= swapDur) _swapT = 0;
    _pending = next;
    if (_swapT >= swapDur / 2) {
      kind = next;
      _pending = null;
    }
  }

  /// Muestra `next` sin animación.
  void snap(HandKind next) {
    kind = next;
    _pending = null;
    _swapT = 9;
  }

  /// Disparo: retroceso (la escopeta, más fuerte y con el bombeo).
  void shoot() {
    _shotT = 0;
    _heavy = kind == HandKind.shotgun;
  }

  /// Golpe cuerpo a cuerpo hacia `target` (fracciones del ancho de la vista,
  /// relativo a la muñeca). Los puños alternan.
  void swing(Offset target, {bool heavy = false}) {
    _swingT = 0;
    _heavy = heavy;
    _target = target;
    if (kind == HandKind.fists) punchSide = -punchSide;
  }

  /// Gatillo en seco (sin munición).
  void click() => _clickT = 0;

  /// Sacudón al recibir un golpe.
  void dip() => _dipT = 0;

  /// Pose de la mano `side` (−1 izquierda, 1 derecha; 0 = recorte entero)
  /// `back` segundos atrás (rastro del golpe).
  void evaluate(HandPose p, {int side = 0, double back = 0}) {
    p.reset();
    final t = time - back;
    final ph = side < 0 ? 1.7 : 0.0;
    final steady = 1 - 0.65 * aimK;

    // Vaivén al respirar y caminar en el lugar.
    p.dx = (0.009 * math.sin(t * 0.83 + ph) + 0.005 * math.sin(t * 0.31 + 1 + ph)) * steady;
    p.dy = (0.007 * math.sin(t * 1.9 + ph) + 0.003 * math.sin(t * 0.53)) * steady;
    p.rot = 0.014 * math.sin(t * 0.7 + ph) * steady;

    // Apuntando: hacia el centro, un poco más arriba y firme.
    p.dx -= 0.035 * aimK * (side == 0 ? 1 : side.toDouble());
    p.dy -= 0.025 * aimK;

    // Guardia.
    final g = guardK;
    if (g > 0.001) {
      switch (kind) {
        case HandKind.pistol:
          p.dx -= 0.1 * g;
          p.dy -= 0.06 * g;
          p.rot -= 0.28 * g;
          p.scale += 0.1 * g;
        case HandKind.shotgun:
          p.dx -= 0.05 * g;
          p.dy -= 0.05 * g;
          p.rot -= 0.2 * g;
          p.scale += 0.08 * g;
        case HandKind.melee:
          p.dx -= 0.12 * g;
          p.dy -= 0.05 * g;
          p.rot -= 0.55 * g;
          p.scale += 0.05 * g;
        case HandKind.fists:
          final s = side == 0 ? 1.0 : side.toDouble();
          p.dx -= 0.03 * g * s;
          p.dy -= 0.07 * g;
          p.rot -= 0.16 * g * s;
          p.scale += 0.1 * g;
      }
    }

    // Retroceso del disparo.
    final st = _shotT - back;
    if (kind.firearm && st >= 0 && st < shotDur) {
      final kick = st < 0.035 ? st / 0.035 : math.exp(-(st - 0.035) / (_heavy ? 0.12 : 0.085));
      final h = _heavy ? 1.45 : 1.0;
      p.rot += 0.15 * kick * h;
      p.dy += 0.04 * kick * h;
      p.dx += 0.025 * kick * h;
      p.scale += 0.05 * kick * h;
      if (_heavy) {
        // Bombeo: baja y vuelve.
        final pump = _bump(st, 0.3, 0.42, 0.62);
        p.dy += 0.035 * pump;
        p.dx += 0.02 * pump;
        p.rot -= 0.05 * pump;
      }
    }

    // Golpe cuerpo a cuerpo.
    final sw = _swingT - back;
    if (!kind.firearm && sw >= 0) {
      if (kind == HandKind.fists) {
        _punch(p, sw / punchDur, side);
      } else if (sw < swingDur) {
        _swing(p, sw / swingDur);
      }
    }

    // Gatillo en seco: un tironcito.
    if (_clickT < 0.2) {
      final k = _bump(_clickT, 0, 0.04, 0.2);
      p.rot += 0.03 * k;
      p.dy += 0.006 * k;
    }

    // Golpe recibido: la mano se hunde y tiembla.
    if (_dipT < dipDur) {
      final k = _bump(_dipT, 0, 0.05, dipDur);
      p.dy += 0.08 * k;
      p.dx += 0.02 * k * math.sin(_dipT * 46);
      p.rot += 0.07 * k * math.sin(_dipT * 38 + 1);
    }

    // Cambio de arma: baja y sube.
    if (_swapT < swapDur) p.dy += 0.6 * _bump(_swapT, 0, swapDur / 2, swapDur);

    // Mano baja.
    p.dy += 0.75 * lowerK * lowerK;
  }

  /// Bate/caño/machete (gira desde el hombro): amague hacia atrás, barrido
  /// de derecha a izquierda cruzando el blanco, vuelta.
  void _swing(HandPose p, double u) {
    final h = _heavy ? 1.15 : 1.0;
    if (u < 0.16) {
      final w = _easeOut(u / 0.16);
      p.rot += 0.22 * w * h;
      p.dx += 0.04 * w;
      p.dy += 0.02 * w;
    } else if (u < 0.36) {
      final s = _easeIn((u - 0.16) / 0.2);
      p.rot += (0.22 - 1.0 * s) * h;
      p.dx += 0.04 - 0.22 * s;
      p.dy += 0.02 + 0.06 * s;
      p.scale += 0.05 * s;
    } else {
      final r = _smooth(0.36, 1, u);
      p.rot += -0.78 * h * (1 - r);
      p.dx += -0.18 * (1 - r);
      p.dy += 0.08 * (1 - r) + 0.04 * _bump(u, 0.36, 0.6, 1);
      p.scale += 0.05 * (1 - r);
    }
  }

  /// Puños (giran desde el codo): el que pega sale hacia el centro y se aleja
  /// de la cámara (se achica); el otro se cubre.
  void _punch(HandPose p, double u, int side) {
    if (u >= 1) return;
    final sd = side == 0 ? 1.0 : side.toDouble();
    final hitter = side == 0 || side == punchSide;
    if (!hitter) {
      final k = _bump(u, 0, 0.3, 1);
      p.dy -= 0.03 * k;
      p.rot -= 0.06 * k * sd;
      return;
    }
    final h = _heavy ? 1.25 : 1.0;
    final wind = _bump(u, 0, 0.12, 0.3);
    p.dy += 0.025 * wind;
    p.scale += 0.03 * wind;
    final s = _bump(u, 0.1, 0.3, 1);
    p.rot += -0.22 * s * sd * h;
    p.dx += _target.dx * 0.12 * s - 0.03 * s * sd;
    p.dy += (-0.07 + _target.dy * 0.08) * s * h;
    p.scale -= 0.2 * s * h;
  }
}
