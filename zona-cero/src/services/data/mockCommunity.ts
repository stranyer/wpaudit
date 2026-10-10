import { offsetM } from '../../core/geo';
import { createRng } from '../../core/rng';
import type { FactionId, LatLng, PublicSurvivor, Shelter } from '../../core/types';
import { fuzzPosition } from '../privacy';

// Datos simulados de comunidad para jugar sin backend.
// Los refugios comunitarios están en plazas y parques públicos de Buenos Aires.

export interface MockSurvivor {
  id: string;
  name: string;
  level: number;
  factionId: FactionId | null;
}

export const MOCK_SURVIVORS: MockSurvivor[] = [
  { id: 'npc-lucia', name: 'Lucía_Z', level: 14, factionId: 'resistencia' },
  { id: 'npc-tano', name: 'ElTano', level: 11, factionId: 'guardia' },
  { id: 'npc-mati', name: 'Mati.Rx', level: 9, factionId: 'nomades' },
  { id: 'npc-caro', name: 'Caro Sobrevive', level: 17, factionId: 'guardia' },
  { id: 'npc-nacho', name: 'Nacho del Sur', level: 7, factionId: 'nomades' },
  { id: 'npc-vero', name: 'VeroKill', level: 21, factionId: 'resistencia' },
  { id: 'npc-gaucho', name: 'Gaucho77', level: 5, factionId: null },
  { id: 'npc-flaca', name: 'La Flaca', level: 12, factionId: 'resistencia' },
  { id: 'npc-tincho', name: 'Tincho', level: 3, factionId: 'guardia' },
  { id: 'npc-rulo', name: 'Rulo', level: 8, factionId: 'nomades' },
  { id: 'npc-pato', name: 'Pato_BA', level: 19, factionId: 'guardia' },
  { id: 'npc-juli', name: 'Juli Nómade', level: 10, factionId: 'nomades' },
];

interface ShelterSeed {
  id: string;
  name: string;
  position: LatLng;
  level: number;
  factionId: FactionId | null;
  owner: string;
}

const SHELTER_SEEDS: ShelterSeed[] = [
  { id: 'cm-lavalle', name: 'Campamento Lavalle', position: { lat: -34.60165, lng: -58.38418 }, level: 1, factionId: 'nomades', owner: 'npc-rulo' },
  { id: 'cm-mayo', name: 'Bastión de Mayo', position: { lat: -34.6083, lng: -58.3712 }, level: 4, factionId: 'resistencia', owner: 'npc-vero' },
  { id: 'cm-congreso', name: 'Trinchera Congreso', position: { lat: -34.6094, lng: -58.3925 }, level: 2, factionId: 'nomades', owner: 'npc-mati' },
  { id: 'cm-centenario', name: 'El Centenario', position: { lat: -34.6063, lng: -58.4355 }, level: 3, factionId: 'guardia', owner: 'npc-caro' },
  { id: 'cm-serrano', name: 'Refugio Serrano', position: { lat: -34.5886, lng: -58.4302 }, level: 2, factionId: 'nomades', owner: 'npc-juli' },
  { id: 'cm-lezama', name: 'Fuerte Lezama', position: { lat: -34.628, lng: -58.3696 }, level: 3, factionId: 'resistencia', owner: 'npc-flaca' },
  { id: 'cm-francia', name: 'Recoleta Libre', position: { lat: -34.5838, lng: -58.3931 }, level: 2, factionId: 'guardia', owner: 'npc-tano' },
  { id: 'cm-dorrego', name: 'San Telmo Resiste', position: { lat: -34.6205, lng: -58.3714 }, level: 2, factionId: 'resistencia', owner: 'npc-lucia' },
  { id: 'cm-rosedal', name: 'Los del Rosedal', position: { lat: -34.5717, lng: -58.4176 }, level: 5, factionId: 'guardia', owner: 'npc-pato' },
];

export function buildMockShelters(): Shelter[] {
  return SHELTER_SEEDS.map((seed) => {
    const rng = createRng(`mock-shelter:${seed.id}`);
    const owner = MOCK_SURVIVORS.find((s) => s.id === seed.owner)!;
    const contributors = [owner, ...MOCK_SURVIVORS.filter((s) => s.id !== owner.id && rng.chance(0.35))];
    const contributions = contributors
      .map((s, i) => ({ playerId: s.id, playerName: s.name, amount: rng.int(10, 40) * seed.level + (i === 0 ? 40 : 0) }))
      .sort((a, b) => b.amount - a.amount);
    return {
      id: seed.id,
      name: seed.name,
      ownerId: owner.id,
      ownerName: owner.name,
      factionId: seed.factionId,
      level: seed.level,
      position: seed.position,
      progress: seed.level < 5 ? { wood: rng.int(2, 10), metal: rng.int(0, 5) } : {},
      contributions,
      createdAt: Date.UTC(2026, 8, 1) + rng.int(0, 30) * 86_400_000,
    };
  });
}

/** Sobrevivientes simulados alrededor del jugador, con posiciones ya difuminadas. */
export function mockSurvivorsAround(center: LatLng, now: number): PublicSurvivor[] {
  // Cambian cada 5 minutos para simular actividad.
  const window = Math.floor(now / 300_000);
  return MOCK_SURVIVORS.map((s) => {
    const rng = createRng(`presence:${s.id}:${window}`);
    const raw = offsetM(center, rng.range(-1800, 1800), rng.range(-1800, 1800));
    return {
      id: s.id,
      name: s.name,
      level: s.level,
      factionId: s.factionId,
      approxPosition: fuzzPosition(raw, s.id),
      lastSeenAt: now - rng.int(1, 25) * 60_000,
    };
  });
}
