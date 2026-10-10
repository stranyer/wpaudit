import type { Faction, FactionId } from './types';

export interface FactionModifiers {
  combatXp: number;
  supplyLoot: number;
  staminaRegen: number;
}

export const FACTION_DEFS: Record<FactionId, Omit<Faction, 'members' | 'totalContribution'>> = {
  resistencia: {
    id: 'resistencia',
    name: 'La Resistencia',
    motto: 'Recuperamos la ciudad, cuadra por cuadra.',
    color: '#c8742c',
    bonusDescription: '+10% de experiencia en combate',
  },
  guardia: {
    id: 'guardia',
    name: 'Guardia del Río',
    motto: 'Lo que se guarda, se sobrevive.',
    color: '#6f8a4a',
    bonusDescription: '+15% de botín en suministros',
  },
  nomades: {
    id: 'nomades',
    name: 'Nómades del Sur',
    motto: 'Quien se queda quieto, se convierte.',
    color: '#7b8c99',
    bonusDescription: '+25% de regeneración de resistencia',
  },
};

export const FACTION_IDS = Object.keys(FACTION_DEFS) as FactionId[];

export function factionModifiers(id: FactionId | null): FactionModifiers {
  return {
    combatXp: id === 'resistencia' ? 1.1 : 1,
    supplyLoot: id === 'guardia' ? 1.15 : 1,
    staminaRegen: id === 'nomades' ? 1.25 : 1,
  };
}
