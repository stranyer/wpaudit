// Minijuego de puntería: mantener → la retícula se cierra; soltar → ataque.
// Lógica pura (sin Flame ni widgets) para poder testearla.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/animation.dart' show Cubic;

import '../core/balance.dart' show precisionCritThreshold;

/// Constantes de la retícula (en dp y milisegundos).
abstract final class AimTuning {
  static const double maxRadius = 64;
  static const double minRadius = 16;

  /// Tiempo en cerrarse del todo.
  static const double shrinkMs = 700;

  /// Ventana en la que se mantiene cerrada antes de empezar a "respirar".
  static const double holdMs = 240;

  /// Período y amplitud máxima de la respiración si se mantiene demasiado.
  static const double breathPeriodMs = 1300;
  static const double breathAmp = 26;

  /// Tiempo de rampa de la respiración (empieza suave y crece).
  static const double breathRampMs = 900;

  /// Mantener esto DESPUÉS de cerrarse la retícula carga el golpe fuerte.
  static const double chargeAfterMs = 450;

  /// La retícula aparece por encima del dedo para que no la tape.
  static const double fingerOffset = 60;

  /// Caída del factor "en el blanco" fuera de la caja del cuerpo.
  static const double offTargetFalloff = 56;

  /// Zona de cabeza de reserva (si el arte no permite detectarla): franja
  /// superior de la caja del cuerpo…
  static const double headHeightFrac = 0.18;

  /// …centrada y de este ancho relativo.
  static const double headWidthFrac = 0.45;

  /// Tope de precisión fuera de la cabeza (por debajo del crítico garantizado).
  static const double bodyCap = 0.85;

  /// Tirantez mínima para que un tiro a la cabeza sea crítico.
  static const double headTightness = 0.9;

  /// Curva de cierre. Arranque más lento que `Sutura.scanCurve` para que la
  /// tirantez de 0.9 llegue recién a los ~450 ms: el tiro a la cabeza hay que
  /// ganárselo (con scanCurve llegaba a los 230 ms y era trivial).
  static const Cubic curve = Cubic(0.4, 0, 0.2, 1);
}

enum AimZone { off, body, head }

/// Radio de la retícula tras `ms` milisegundos mantenida.
double reticleRadius(double ms) {
  const span = AimTuning.maxRadius - AimTuning.minRadius;
  if (ms <= 0) return AimTuning.maxRadius;
  if (ms < AimTuning.shrinkMs) {
    return AimTuning.maxRadius - span * AimTuning.curve.transform(ms / AimTuning.shrinkMs);
  }
  final b = ms - AimTuning.shrinkMs - AimTuning.holdMs;
  if (b <= 0) return AimTuning.minRadius;
  final ramp = math.min(1.0, b / AimTuning.breathRampMs);
  final wave = 0.5 - 0.5 * math.cos(2 * math.pi * b / AimTuning.breathPeriodMs);
  return AimTuning.minRadius + AimTuning.breathAmp * ramp * wave;
}

/// 0 (retícula abierta) … 1 (cerrada al mínimo).
double tightnessFor(double radius) =>
    ((AimTuning.maxRadius - radius) / (AimTuning.maxRadius - AimTuning.minRadius)).clamp(0.0, 1.0);

/// Zona de cabeza de reserva dentro de la caja del cuerpo.
Rect headRectOf(Rect body) {
  final w = body.width * AimTuning.headWidthFrac;
  return Rect.fromLTWH(body.center.dx - w / 2, body.top, w, body.height * AimTuning.headHeightFrac);
}

/// Zona bajo el punto. `head` (si se conoce) es la caja real de la cabeza.
AimZone zoneFor(Offset p, Rect body, [Rect? head]) {
  if (body.isEmpty) return AimZone.off;
  if ((head ?? headRectOf(body)).contains(p)) return AimZone.head;
  if (body.contains(p)) return AimZone.body;
  return AimZone.off;
}

/// 1 dentro de la caja del cuerpo; cae linealmente con la distancia afuera.
double onTargetFactor(Offset p, Rect body) {
  if (body.isEmpty) return 0;
  final dx = math.max(0.0, math.max(body.left - p.dx, p.dx - body.right));
  final dy = math.max(0.0, math.max(body.top - p.dy, p.dy - body.bottom));
  final d = math.sqrt(dx * dx + dy * dy);
  if (d <= 0) return 1;
  return (1 - d / AimTuning.offTargetFalloff).clamp(0.0, 1.0);
}

/// Precisión (0..1) que se envía al motor.
///
/// - Cabeza + tirantez ≥ 0.9 → 0.9…1.0 (crítico garantizado en el motor).
/// - Si no: tirantez × factor en el blanco, con tope [AimTuning.bodyCap]
///   para que solo la cabeza garantice el crítico.
double precisionFor({required double tightness, required Offset point, required Rect body, Rect? head}) {
  final t = tightness.clamp(0.0, 1.0);
  if (zoneFor(point, body, head) == AimZone.head && t >= AimTuning.headTightness) {
    final k = (t - AimTuning.headTightness) / (1 - AimTuning.headTightness);
    return (precisionCritThreshold + (1 - precisionCritThreshold) * k).clamp(precisionCritThreshold, 1.0);
  }
  return math.min(AimTuning.bodyCap, t * onTargetFactor(point, body));
}

/// Resultado de soltar la retícula.
class AimShot {
  const AimShot({
    required this.precision,
    required this.tightness,
    required this.zone,
    required this.charged,
    required this.point,
    required this.heldMs,
  });

  final double precision;
  final double tightness;
  final AimZone zone;
  final bool charged;

  /// Centro de la retícula al soltar (coordenadas del escenario).
  final Offset point;
  final double heldMs;

  /// Crítico garantizado por apuntar a la cabeza con la retícula cerrada.
  bool get headshot => precision >= precisionCritThreshold;
}

/// Eventos que produce la retícula al avanzar el tiempo (para hápticos).
enum AimSignal { none, locked, charged }

/// Estado mutable de una puntería en curso.
class AimState {
  bool active = false;
  Offset finger = Offset.zero;
  double ms = 0;
  bool canCharge = false;
  bool charged = false;
  bool _lockSignaled = false;

  Offset get point => finger.translate(0, -AimTuning.fingerOffset);
  double get radius => active ? reticleRadius(ms) : AimTuning.maxRadius;
  double get tightness => tightnessFor(radius);

  void start(Offset fingerPos, {required bool canCharge}) {
    active = true;
    finger = fingerPos;
    ms = 0;
    this.canCharge = canCharge;
    charged = false;
    _lockSignaled = false;
  }

  void move(Offset fingerPos) {
    if (active) finger = fingerPos;
  }

  /// Avanza `dtMs` y devuelve una señal si cruzó un umbral.
  AimSignal advance(double dtMs) {
    if (!active) return AimSignal.none;
    ms += dtMs;
    if (!_lockSignaled && tightness >= AimTuning.headTightness) {
      _lockSignaled = true;
      return AimSignal.locked;
    }
    if (canCharge && !charged && ms >= AimTuning.shrinkMs + AimTuning.chargeAfterMs) {
      charged = true;
      return AimSignal.charged;
    }
    return AimSignal.none;
  }

  AimShot release(Rect body, [Rect? head]) {
    final shot = AimShot(
      precision: precisionFor(tightness: tightness, point: point, body: body, head: head),
      tightness: tightness,
      zone: zoneFor(point, body, head),
      charged: charged,
      point: point,
      heldMs: ms,
    );
    cancel();
    return shot;
  }

  void cancel() {
    active = false;
    charged = false;
    ms = 0;
  }
}
