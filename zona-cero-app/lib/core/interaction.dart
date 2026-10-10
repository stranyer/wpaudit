// Reglas de interacción. Son las mismas que debe aplicar el servidor
// (ver supabase/migrations: validate_interaction) para evitar trampas.

import 'dart:math' as math;

import 'geo.dart';
import 'types.dart';

class InteractionRules {
  const InteractionRules({
    required this.interactionRadiusM,
    required this.maxAccuracyBonusM,
    required this.maxAccuracyForInteractionM,
  });

  final double interactionRadiusM;
  final double maxAccuracyBonusM;
  final double maxAccuracyForInteractionM;
}

class InteractionContext {
  const InteractionContext({required this.speedLocked, required this.depleted, this.expiresAt});
  final bool speedLocked;
  final bool depleted;
  final int? expiresAt;
}

/// Radio efectivo: radio base + tolerancia por la precisión del GPS (con tope).
double effectiveRadius(InteractionRules rules, num accuracyM) =>
    rules.interactionRadiusM + math.min(math.max(0, accuracyM), rules.maxAccuracyBonusM);

bool isWithinReach(LatLng player, LatLng target, num accuracyM, InteractionRules rules) =>
    haversineM(player, target) <= effectiveRadius(rules, accuracyM);

InteractionResult validateInteraction(InteractionRequest req, InteractionRules rules, InteractionContext ctx) {
  final distanceM = haversineM(req.playerPosition, req.targetPosition);
  if (ctx.depleted) return InteractionResult(ok: false, reason: InteractionRejection.depleted, distanceM: distanceM);
  final expiresAt = ctx.expiresAt;
  if (expiresAt != null && req.timestamp >= expiresAt) {
    return InteractionResult(ok: false, reason: InteractionRejection.expired, distanceM: distanceM);
  }
  if (ctx.speedLocked) return InteractionResult(ok: false, reason: InteractionRejection.tooFast, distanceM: distanceM);
  if (req.accuracyM > rules.maxAccuracyForInteractionM) {
    return InteractionResult(ok: false, reason: InteractionRejection.lowAccuracy, distanceM: distanceM);
  }
  if (distanceM > effectiveRadius(rules, req.accuracyM)) {
    return InteractionResult(ok: false, reason: InteractionRejection.outOfRange, distanceM: distanceM);
  }
  return InteractionResult(ok: true, distanceM: distanceM);
}

const Map<InteractionRejection, String> rejectionMessages = {
  InteractionRejection.outOfRange: 'Está demasiado lejos. Acercate un poco más.',
  InteractionRejection.tooFast: 'Vas demasiado rápido. No se puede interactuar desde un vehículo.',
  InteractionRejection.depleted: 'Ya no queda nada acá.',
  InteractionRejection.expired: 'Este punto ya desapareció.',
  InteractionRejection.lowAccuracy: 'Señal GPS débil. Esperá a tener mejor precisión.',
};

extension InteractionRejectionMessage on InteractionRejection {
  /// Mensaje en español para mostrar al jugador.
  String get message => rejectionMessages[this]!;
}

// ---------------------------------------------------------------------------
// Control de velocidad (anti-trampas y seguridad vial)
// ---------------------------------------------------------------------------

class SpeedSample {
  const SpeedSample({required this.position, required this.time});
  final LatLng position;
  final int time;
}

double speedMps(SpeedSample a, SpeedSample b) {
  final dt = (b.time - a.time) / 1000;
  if (dt <= 0) return 0;
  return haversineM(a.position, b.position) / dt;
}

class SpeedGuardState {
  const SpeedGuardState({this.last, this.lockedUntil = 0});

  static const SpeedGuardState initial = SpeedGuardState();

  final SpeedSample? last;
  final int lockedUntil;

  /// ¿Están bloqueadas las interacciones en `now`?
  bool isLocked(int now) => now < lockedUntil;
}

/// Actualiza el guardia de velocidad. Si el jugador supera `maxMps` (p. ej. va en auto),
/// se bloquean las interacciones durante `lockMs`. Ignora intervalos muy cortos para no
/// reaccionar al ruido del GPS.
SpeedGuardState updateSpeedGuard(SpeedGuardState state, SpeedSample sample, num maxMps, int lockMs) {
  final last = state.last;
  if (last == null) return SpeedGuardState(last: sample, lockedUntil: state.lockedUntil);
  final dt = sample.time - last.time;
  if (dt < 2000) return state;
  final v = speedMps(last, sample);
  return SpeedGuardState(last: sample, lockedUntil: v > maxMps ? sample.time + lockMs : state.lockedUntil);
}
