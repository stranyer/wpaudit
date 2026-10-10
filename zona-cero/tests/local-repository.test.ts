import { beforeEach, describe, expect, it } from 'vitest';
import { offsetM } from '../src/core/geo';
import { createPlayer } from '../src/core/player';
import { LocalRepository } from '../src/services/data/LocalRepository';
import { MemoryStorage } from '../src/services/data/storage';

const LAVALLE = { lat: -34.60165, lng: -58.38418 };
const NOW = 1_760_000_000_000;

describe('LocalRepository (modo sin backend)', () => {
  let repo: LocalRepository;
  let id: string;

  beforeEach(async () => {
    repo = new LocalRepository(new MemoryStorage(), () => NOW);
    id = await repo.init();
  });

  it('guarda y recupera el progreso del jugador', async () => {
    expect(await repo.loadPlayer()).toBeNull();
    const p = { ...createPlayer(id, 'Tester', NOW), xp: 42 };
    await repo.savePlayer(p);
    expect((await repo.loadPlayer())?.xp).toBe(42);
  });

  it('incluye refugios comunitarios simulados en lugares públicos', async () => {
    const near = await repo.getNearbyShelters(LAVALLE, 500);
    expect(near[0]?.id).toBe('cm-lavalle');
  });

  it('un suministro solo se puede saquear una vez', async () => {
    const req = {
      playerId: id,
      action: 'scavenge' as const,
      targetId: 's:1_1:0:0',
      targetExpiresAt: NOW + 60_000,
      targetPosition: LAVALLE,
      playerPosition: offsetM(LAVALLE, 10, 0),
      accuracyM: 5,
      timestamp: NOW,
    };
    expect((await repo.validateInteraction(req)).ok).toBe(true);
    expect((await repo.validateInteraction({ ...req, timestamp: NOW + 5000 })).reason).toBe('depleted');
    // Los encuentros no agotan el punto (si huís, el zombie sigue ahí).
    const enc = { ...req, action: 'encounter' as const, targetId: 'z:1_1:0:0' };
    expect((await repo.validateInteraction({ ...enc, timestamp: NOW + 9000 })).ok).toBe(true);
    expect((await repo.validateInteraction({ ...enc, timestamp: NOW + 12000 })).ok).toBe(true);
  });

  it('las donaciones validan distancia y mejoran el refugio', async () => {
    const far = await repo.donateToShelter({
      shelterId: 'cm-lavalle',
      playerId: id,
      playerName: 'Tester',
      resources: { wood: 5 },
      playerPosition: offsetM(LAVALLE, 300, 0),
      accuracyM: 5,
    });
    expect(far).toMatchObject({ ok: false, reason: 'out_of_range' });

    const ok = await repo.donateToShelter({
      shelterId: 'cm-lavalle',
      playerId: id,
      playerName: 'Tester',
      resources: { wood: 100, metal: 100 },
      playerPosition: offsetM(LAVALLE, 15, 0),
      accuracyM: 5,
    });
    expect(ok.ok).toBe(true);
    expect(ok.leveledUp).toBe(true);
    expect(ok.shelter?.level).toBe(2);
    // Persistido: al volver a consultar sigue en nivel 2 y el jugador figura en el ranking.
    expect((await repo.getShelter('cm-lavalle'))?.level).toBe(2);
    await repo.savePlayer(createPlayer(id, 'Tester', NOW));
    const board = await repo.getLeaderboard(50);
    expect(board.some((e) => e.playerId === id && e.contribution > 0)).toBe(true);
  });

  it('crea un único refugio por jugador', async () => {
    const input = { name: 'Base', ownerId: id, ownerName: 'Tester', factionId: null, publicPosition: LAVALLE };
    const a = await repo.createShelter(input);
    const b = await repo.createShelter({ ...input, name: 'Otra' });
    expect(b.id).toBe(a.id);
  });

  it('los sobrevivientes cercanos tienen posiciones difuminadas', async () => {
    const list = await repo.getNearbySurvivors(LAVALLE, 5000);
    expect(list.length).toBeGreaterThan(0);
    for (const s of list) expect(s.approxPosition).not.toEqual(LAVALLE);
  });
});
