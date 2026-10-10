import { describe, expect, it } from 'vitest';
import { resolveTurn, startCombat, usableItems } from '../src/core/combat';
import { createPlayer, equipItem } from '../src/core/player';
import { createRng } from '../src/core/rng';
import type { CombatAction, CombatState, PlayerState, ZombieTypeId } from '../src/core/types';

/** Estrategia simple de un jugador razonable. */
function choose(s: CombatState): CombatAction {
  if (s.zombie.charging) return { type: 'defend' };
  const heal = usableItems(s).find((id) => id === 'medicine' || id === 'medkit');
  if (s.player.health < s.player.maxHealth * 0.3 && heal) return { type: 'use_item', itemId: heal };
  if (s.player.stamina >= 15 && s.zombie.health > 12) return { type: 'heavy' };
  return { type: 'attack' };
}

function winRate(player: PlayerState, zombie: ZombieTypeId, runs = 400): number {
  let wins = 0;
  for (let i = 0; i < runs; i++) {
    const rng = createRng(`${zombie}:${player.level}:${i}`);
    let s = startCombat({ spawnId: 'x', zombieType: zombie, player, rng });
    for (let t = 0; t < 60 && s.status === 'ongoing'; t++) s = resolveTurn(s, choose(s), rng);
    if (s.status === 'won') wins++;
  }
  return wins / runs;
}

describe('balance del combate', () => {
  const novato = createPlayer('p', 'Novato', 0);

  it('un novato a puño limpio le gana casi siempre a un Caminante', () => {
    expect(winRate(novato, 'walker')).toBeGreaterThan(0.85);
  });

  it('un Bruto es una amenaza seria para un novato', () => {
    expect(winRate(novato, 'brute')).toBeLessThan(0.5);
  });

  it('con buen equipo y nivel, el Bruto se vuelve vencible', () => {
    const veterano = equipItem({ ...createPlayer('p', 'Vet', 0), level: 6, health: 140, stamina: 120, inventory: { machete: 1, medicine: 2 } }, 'machete')!;
    expect(winRate(veterano, 'brute')).toBeGreaterThan(0.7);
  });
});
