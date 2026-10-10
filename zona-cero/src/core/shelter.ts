import type { ResourceId, Shelter, ShelterContribution } from './types';
import type { Rng } from './rng';

export interface ShelterLevelDef {
  level: number;
  name: string;
  description: string;
  /** Recursos necesarios para ALCANZAR este nivel desde el anterior. */
  requirements: Partial<Record<ResourceId, number>>;
  perks: string[];
  /** Defensa contra hordas. */
  defense: number;
  /** Curación y resistencia al descansar. */
  restHealth: number;
  restStamina: number;
  /** Bonus de botín para miembros (multiplicador adicional). */
  lootBonus: number;
}

export const SHELTER_LEVELS: ShelterLevelDef[] = [
  {
    level: 1,
    name: 'Campamento improvisado',
    description: 'Una carpa, una fogata y mucha esperanza.',
    requirements: {},
    perks: ['Descansar recupera 25 de salud y resistencia'],
    defense: 5,
    restHealth: 25,
    restStamina: 25,
    lootBonus: 0,
  },
  {
    level: 2,
    name: 'Barricadas',
    description: 'Empalizadas de madera que frenan a los caminantes.',
    requirements: { wood: 20, metal: 6 },
    perks: ['Descansar recupera 40', 'Desbloquea: Chaleco de chapa'],
    defense: 15,
    restHealth: 40,
    restStamina: 40,
    lootBonus: 0,
  },
  {
    level: 3,
    name: 'Taller',
    description: 'Un banco de trabajo para fabricar equipo serio.',
    requirements: { wood: 30, metal: 25, food: 10 },
    perks: ['Desbloquea: Machete y Botiquín', '+5% de botín'],
    defense: 28,
    restHealth: 55,
    restStamina: 55,
    lootBonus: 0.05,
  },
  {
    level: 4,
    name: 'Torre de vigilancia',
    description: 'Vigías que detectan hordas antes de que lleguen.',
    requirements: { wood: 40, metal: 40, food: 20, water: 20 },
    perks: ['Desbloquea: Pistola 9 mm', '+10% de botín'],
    defense: 45,
    restHealth: 75,
    restStamina: 75,
    lootBonus: 0.1,
  },
  {
    level: 5,
    name: 'Fortaleza',
    description: 'Muros de chapa, generador y enfermería. Un faro en la Zona Cero.',
    requirements: { wood: 60, metal: 80, food: 30, water: 30, medicine: 15, ammo: 20 },
    perks: ['Descanso completo', '+15% de botín'],
    defense: 70,
    restHealth: 100,
    restStamina: 100,
    lootBonus: 0.15,
  },
];

export const MAX_SHELTER_LEVEL = SHELTER_LEVELS.length;
export const REST_COOLDOWN_MS = 10 * 60 * 1000;

export function shelterLevelDef(level: number): ShelterLevelDef {
  return SHELTER_LEVELS[Math.max(1, Math.min(MAX_SHELTER_LEVEL, level)) - 1];
}

/** Requisitos del próximo nivel, o null si ya está al máximo. */
export function nextLevelRequirements(shelter: Pick<Shelter, 'level'>): Partial<Record<ResourceId, number>> | null {
  if (shelter.level >= MAX_SHELTER_LEVEL) return null;
  return SHELTER_LEVELS[shelter.level].requirements;
}

/** Cuánto falta de cada recurso para el próximo nivel. */
export function remainingRequirements(shelter: Pick<Shelter, 'level' | 'progress'>): Partial<Record<ResourceId, number>> {
  const req = nextLevelRequirements(shelter);
  if (!req) return {};
  const out: Partial<Record<ResourceId, number>> = {};
  for (const [res, amount] of Object.entries(req) as [ResourceId, number][]) {
    const left = amount - (shelter.progress[res] ?? 0);
    if (left > 0) out[res] = left;
  }
  return out;
}

/** Progreso total 0..1 hacia el próximo nivel. */
export function upgradeProgress(shelter: Pick<Shelter, 'level' | 'progress'>): number {
  const req = nextLevelRequirements(shelter);
  if (!req) return 1;
  let total = 0;
  let done = 0;
  for (const [res, amount] of Object.entries(req) as [ResourceId, number][]) {
    total += amount;
    done += Math.min(amount, shelter.progress[res] ?? 0);
  }
  return total === 0 ? 1 : done / total;
}

export interface DonationOutcome {
  shelter: Shelter;
  accepted: Partial<Record<ResourceId, number>>;
  acceptedTotal: number;
  leveledUp: boolean;
}

/**
 * Aplica una donación. Solo se aceptan recursos que el próximo nivel necesita;
 * el excedente se devuelve al jugador. Si se completan los requisitos, sube de nivel.
 * Función pura: devuelve un refugio nuevo.
 */
export function applyDonation(
  shelter: Shelter,
  playerId: string,
  playerName: string,
  offered: Partial<Record<ResourceId, number>>,
): DonationOutcome {
  const remaining = remainingRequirements(shelter);
  const accepted: Partial<Record<ResourceId, number>> = {};
  const progress = { ...shelter.progress };
  let acceptedTotal = 0;

  for (const [res, amountRaw] of Object.entries(offered) as [ResourceId, number][]) {
    const amount = Math.floor(amountRaw);
    if (!(amount > 0)) continue;
    const take = Math.min(amount, remaining[res] ?? 0);
    if (take <= 0) continue;
    accepted[res] = take;
    progress[res] = (progress[res] ?? 0) + take;
    acceptedTotal += take;
  }

  let contributions = shelter.contributions;
  if (acceptedTotal > 0) {
    const existing = contributions.find((c) => c.playerId === playerId);
    contributions = existing
      ? contributions.map((c) => (c.playerId === playerId ? { ...c, playerName, amount: c.amount + acceptedTotal } : c))
      : [...contributions, { playerId, playerName, amount: acceptedTotal } satisfies ShelterContribution];
    contributions = [...contributions].sort((a, b) => b.amount - a.amount);
  }

  let next: Shelter = { ...shelter, progress, contributions };
  let leveledUp = false;
  if (acceptedTotal > 0 && Object.keys(remainingRequirements(next)).length === 0 && next.level < MAX_SHELTER_LEVEL) {
    next = { ...next, level: next.level + 1, progress: {} };
    leveledUp = true;
  }
  return { shelter: next, accepted, acceptedTotal, leveledUp };
}

// ---------------------------------------------------------------------------
// Eventos cooperativos: ataques de hordas (arquitectura preparada)
// ---------------------------------------------------------------------------

export interface HordeAttack {
  shelterId: string;
  /** Fuerza de la horda; escala con el nivel del refugio. */
  strength: number;
  startsAt: number;
}

export interface HordeOutcome {
  defended: boolean;
  /** Recursos perdidos si la horda rompe las defensas (fracción del progreso). */
  progressLossRatio: number;
  defenseRoll: number;
}

/** Genera una horda proporcional al nivel del refugio. */
export function planHordeAttack(shelter: Pick<Shelter, 'id' | 'level'>, startsAt: number, rng: Rng): HordeAttack {
  const base = shelterLevelDef(shelter.level).defense;
  return { shelterId: shelter.id, strength: Math.round(base * rng.range(0.7, 1.4)), startsAt };
}

/**
 * Resuelve un ataque: defensa del refugio + aportes de defensores conectados.
 * Pensado para correr en el servidor cuando exista backend (cron/edge function).
 */
export function resolveHordeAttack(
  shelter: Pick<Shelter, 'level'>,
  attack: HordeAttack,
  defendersPower: number,
  rng: Rng,
): HordeOutcome {
  const defenseRoll = shelterLevelDef(shelter.level).defense * rng.range(0.85, 1.15) + defendersPower;
  const defended = defenseRoll >= attack.strength;
  return { defended, progressLossRatio: defended ? 0 : 0.25, defenseRoll: Math.round(defenseRoll) };
}
