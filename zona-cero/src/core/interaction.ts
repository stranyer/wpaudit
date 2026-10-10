import { haversineM } from './geo';
import type { InteractionRequest, InteractionResult, LatLng } from './types';

// Reglas de interacción. Son las mismas que debe aplicar el servidor
// (ver supabase/migrations: validate_interaction) para evitar trampas.

export interface InteractionRules {
  interactionRadiusM: number;
  maxAccuracyBonusM: number;
  maxAccuracyForInteractionM: number;
}

export interface InteractionContext {
  speedLocked: boolean;
  depleted: boolean;
  expiresAt?: number;
}

/** Radio efectivo: radio base + tolerancia por la precisión del GPS (con tope). */
export function effectiveRadius(rules: InteractionRules, accuracyM: number): number {
  return rules.interactionRadiusM + Math.min(Math.max(0, accuracyM), rules.maxAccuracyBonusM);
}

export function isWithinReach(player: LatLng, target: LatLng, accuracyM: number, rules: InteractionRules): boolean {
  return haversineM(player, target) <= effectiveRadius(rules, accuracyM);
}

export function validateInteraction(
  req: InteractionRequest,
  rules: InteractionRules,
  ctx: InteractionContext,
): InteractionResult {
  const distanceM = haversineM(req.playerPosition, req.targetPosition);
  if (ctx.depleted) return { ok: false, reason: 'depleted', distanceM };
  if (ctx.expiresAt !== undefined && req.timestamp >= ctx.expiresAt) return { ok: false, reason: 'expired', distanceM };
  if (ctx.speedLocked) return { ok: false, reason: 'too_fast', distanceM };
  if (req.accuracyM > rules.maxAccuracyForInteractionM) return { ok: false, reason: 'low_accuracy', distanceM };
  if (distanceM > effectiveRadius(rules, req.accuracyM)) return { ok: false, reason: 'out_of_range', distanceM };
  return { ok: true, distanceM };
}

export const REJECTION_MESSAGES: Record<NonNullable<InteractionResult['reason']>, string> = {
  out_of_range: 'Está demasiado lejos. Acercate un poco más.',
  too_fast: 'Vas demasiado rápido. No se puede interactuar desde un vehículo.',
  depleted: 'Ya no queda nada acá.',
  expired: 'Este punto ya desapareció.',
  low_accuracy: 'Señal GPS débil. Esperá a tener mejor precisión.',
};

// ---------------------------------------------------------------------------
// Control de velocidad (anti-trampas y seguridad vial)
// ---------------------------------------------------------------------------

export interface SpeedSample {
  position: LatLng;
  time: number;
}

export function speedMps(a: SpeedSample, b: SpeedSample): number {
  const dt = (b.time - a.time) / 1000;
  if (dt <= 0) return 0;
  return haversineM(a.position, b.position) / dt;
}

export interface SpeedGuardState {
  last: SpeedSample | null;
  lockedUntil: number;
}

/**
 * Actualiza el guardia de velocidad. Si el jugador supera `maxMps` (p. ej. va en auto),
 * se bloquean las interacciones durante `lockMs`. Ignora intervalos muy cortos para no
 * reaccionar al ruido del GPS.
 */
export function updateSpeedGuard(
  state: SpeedGuardState,
  sample: SpeedSample,
  maxMps: number,
  lockMs: number,
): SpeedGuardState {
  if (!state.last) return { last: sample, lockedUntil: state.lockedUntil };
  const dt = sample.time - state.last.time;
  if (dt < 2000) return state;
  const v = speedMps(state.last, sample);
  return { last: sample, lockedUntil: v > maxMps ? sample.time + lockMs : state.lockedUntil };
}
