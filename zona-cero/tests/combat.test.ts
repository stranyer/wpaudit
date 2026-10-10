import { describe, expect, it } from 'vitest';
import { canShoot, combatReward, describeEvent, resolveTurn, startCombat } from '../src/core/combat';
import { createPlayer } from '../src/core/player';
import { createRng, type Rng } from '../src/core/rng';
import type { CombatState, PlayerState } from '../src/core/types';

/** RNG controlado: devuelve una secuencia fija de valores. */
function scripted(values: number[]): Rng {
  let i = 0;
  const base = createRng(1);
  const next = () => values[i++ % values.length];
  return {
    ...base,
    next,
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    range: (min, max) => min + next() * (max - min),
    chance: (p) => next() < p,
  };
}

function player(overrides: Partial<PlayerState> = {}): PlayerState {
  return { ...createPlayer('p1', 'Tester', 0), ...overrides };
}

describe('combate', () => {
  it('inicia con estadísticas escaladas y armas equipadas', () => {
    const p = player({ inventory: { pipe: 1, pistol: 1, ammo: 3 }, equipment: { melee: 'pipe', firearm: 'pistol', armor: null } });
    const s = startCombat({ spawnId: 's', zombieType: 'walker', player: p, rng: createRng(3) });
    expect(s.zombie.health).toBeGreaterThan(0);
    expect(s.player.meleeName).toBe('Caño de plomo');
    expect(canShoot(s)).toBe(true);
    expect(s.available.ammo).toBe(3);
  });

  it('un ataque que acierta reduce la vida del zombie y consume resistencia', () => {
    const s = startCombat({ spawnId: 's', zombieType: 'walker', player: player(), rng: scripted([0.5]) });
    // 0.0 => acierta, sin crítico (0.99), daño mínimo; luego el zombie falla (0.99)
    const next = resolveTurn(s, { type: 'attack' }, scripted([0.0, 0.99, 0.0, 0.99]));
    expect(next.zombie.health).toBeLessThan(s.zombie.health);
    expect(next.player.stamina).toBe(s.player.stamina - 6);
    expect(next.lastEvents.map((e) => e.kind)).toEqual(['player_hit', 'zombie_miss']);
  });

  it('el combate termina en victoria y da recompensas', () => {
    let s = startCombat({ spawnId: 's', zombieType: 'walker', player: player(), rng: createRng(7) });
    s = { ...s, zombie: { ...s.zombie, health: 1 } };
    const next = resolveTurn(s, { type: 'attack' }, scripted([0.0, 0.99, 0.0]));
    expect(next.status).toBe('won');
    const reward = combatReward(next, createRng(2));
    expect(reward.xp).toBeGreaterThan(0);
  });

  it('el jugador puede caer', () => {
    let s = startCombat({ spawnId: 's', zombieType: 'walker', player: player(), rng: createRng(7) });
    s = { ...s, player: { ...s.player, health: 1 } };
    // Falla el ataque (0.99), el zombie acierta (0.0)
    const next = resolveTurn(s, { type: 'attack' }, scripted([0.99, 0.0, 0.5]));
    expect(next.status).toBe('lost');
    expect(next.lastEvents.at(-1)?.kind).toBe('player_down');
  });

  it('defenderse frente a la embestida del Bruto lo aturde', () => {
    let s: CombatState = startCombat({ spawnId: 's', zombieType: 'brute', player: player({ level: 6 }), rng: createRng(1) });
    s = { ...s, zombie: { ...s.zombie, charging: true } };
    const next = resolveTurn(s, { type: 'defend' }, scripted([0.5]));
    expect(next.zombie.stunned).toBe(true);
    expect(next.player.health).toBe(s.player.health);
    // El siguiente golpe contra un aturdido es crítico garantizado.
    const after = resolveTurn(next, { type: 'attack' }, scripted([0.0, 0.5]));
    const hit = after.lastEvents.find((e) => e.kind === 'player_hit');
    expect(hit && hit.kind === 'player_hit' && hit.crit && hit.stunBonus).toBe(true);
  });

  it('disparar sin munición no consume el turno', () => {
    const p = player({ inventory: { pistol: 1 }, equipment: { melee: null, firearm: 'pistol', armor: null } });
    const s = startCombat({ spawnId: 's', zombieType: 'walker', player: p, rng: createRng(1) });
    const next = resolveTurn(s, { type: 'shoot' }, createRng(5));
    expect(next.turn).toBe(s.turn);
    expect(next.lastEvents[0].kind).toBe('no_ammo');
  });

  it('usar un objeto lo descuenta del combate y cura', () => {
    const p = player({ health: 40, inventory: { medicine: 1 } });
    const s = startCombat({ spawnId: 's', zombieType: 'walker', player: p, rng: createRng(1) });
    const next = resolveTurn(s, { type: 'use_item', itemId: 'medicine' }, scripted([0.99]));
    expect(next.consumed.medicine).toBe(1);
    expect(next.player.health).toBe(70);
  });

  it('el Hinchado explota al morir cuerpo a cuerpo pero nunca remata', () => {
    let s = startCombat({ spawnId: 's', zombieType: 'bloater', player: player({ level: 3 }), rng: createRng(1) });
    s = { ...s, zombie: { ...s.zombie, health: 1 }, player: { ...s.player, health: 3 } };
    const next = resolveTurn(s, { type: 'attack' }, scripted([0.0, 0.99, 0.0, 0.99]));
    expect(next.status).toBe('won');
    expect(next.player.health).toBe(1);
    expect(next.lastEvents.map((e) => e.kind)).toContain('toxic_burst');
  });

  it('todos los eventos tienen texto en español', () => {
    let s = startCombat({ spawnId: 's', zombieType: 'runner', player: player(), rng: createRng(1) });
    const rng = createRng(99);
    for (let i = 0; i < 30 && s.status === 'ongoing'; i++) {
      s = resolveTurn(s, { type: i % 4 === 3 ? 'defend' : 'attack' }, rng);
    }
    for (const e of s.log) expect(describeEvent(e, s).length).toBeGreaterThan(3);
  });
});
