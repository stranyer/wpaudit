import { GAME_CONFIG } from '../../config/gameConfig';
import { FACTION_DEFS, FACTION_IDS } from '../../core/factions';
import { haversineM } from '../../core/geo';
import { updateSpeedGuard, validateInteraction, type SpeedGuardState } from '../../core/interaction';
import { applyDonation } from '../../core/shelter';
import type {
  Faction,
  FactionId,
  InteractionRequest,
  InteractionResult,
  LatLng,
  LeaderboardEntry,
  PlayerState,
  PublicSurvivor,
  Shelter,
} from '../../core/types';
import type { CreateShelterInput, DonationInput, DonationResult, GameRepository } from './GameRepository';
import { buildMockShelters, MOCK_SURVIVORS, mockSurvivorsAround } from './mockCommunity';
import { readJson, safeLocalStorage, writeJson, type KeyValueStorage } from './storage';

const KEYS = {
  playerId: 'zc:playerId',
  player: 'zc:player',
  shelters: 'zc:shelters',
  claims: 'zc:claims',
} as const;

/**
 * Repositorio local: persiste en localStorage y simula la comunidad.
 * Replica las validaciones que hará el servidor (alcance, velocidad, reclamos)
 * para que el juego se comporte igual con o sin backend.
 */
export class LocalRepository implements GameRepository {
  readonly kind = 'local' as const;
  private speedGuard: SpeedGuardState = { last: null, lockedUntil: 0 };

  constructor(
    private readonly storage: KeyValueStorage = safeLocalStorage(),
    private readonly now: () => number = Date.now,
  ) {}

  async init(): Promise<string> {
    let id = this.storage.getItem(KEYS.playerId);
    if (!id) {
      id = `local-${Math.random().toString(36).slice(2, 10)}`;
      this.storage.setItem(KEYS.playerId, id);
    }
    return id;
  }

  async loadPlayer(): Promise<PlayerState | null> {
    return readJson<PlayerState | null>(this.storage, KEYS.player, null);
  }

  async savePlayer(player: PlayerState): Promise<void> {
    writeJson(this.storage, KEYS.player, player);
  }

  async validateInteraction(request: InteractionRequest): Promise<InteractionResult> {
    const claims = this.readClaims();
    this.speedGuard = updateSpeedGuard(
      this.speedGuard,
      { position: request.playerPosition, time: request.timestamp },
      GAME_CONFIG.maxInteractionSpeedMps,
      GAME_CONFIG.speedLockMs,
    );
    const result = validateInteraction(request, GAME_CONFIG, {
      speedLocked: request.timestamp < this.speedGuard.lockedUntil,
      depleted: request.action === 'scavenge' && claims[request.targetId] !== undefined,
      expiresAt: request.targetExpiresAt,
    });
    if (result.ok && request.action === 'scavenge') {
      claims[request.targetId] = request.targetExpiresAt ?? request.timestamp + 3_600_000;
      writeJson(this.storage, KEYS.claims, claims);
    }
    return result;
  }

  /** Olvida la última posición validada (teletransporte del modo demo). */
  resetSpeedGuard(): void {
    this.speedGuard = { last: null, lockedUntil: 0 };
  }

  /** Reclamos vigentes (spawnId -> vencimiento); purga los vencidos. */
  private readClaims(): Record<string, number> {
    const claims = readJson<Record<string, number>>(this.storage, KEYS.claims, {});
    const now = this.now();
    let changed = false;
    for (const [id, exp] of Object.entries(claims)) {
      if (exp <= now) {
        delete claims[id];
        changed = true;
      }
    }
    if (changed) writeJson(this.storage, KEYS.claims, claims);
    return claims;
  }

  private allShelters(): Shelter[] {
    const stored = readJson<Record<string, Shelter>>(this.storage, KEYS.shelters, {});
    const merged = new Map<string, Shelter>();
    for (const s of buildMockShelters()) merged.set(s.id, s);
    for (const s of Object.values(stored)) merged.set(s.id, s);
    return [...merged.values()];
  }

  private persistShelter(shelter: Shelter): void {
    const stored = readJson<Record<string, Shelter>>(this.storage, KEYS.shelters, {});
    stored[shelter.id] = shelter;
    writeJson(this.storage, KEYS.shelters, stored);
  }

  async getNearbyShelters(center: LatLng, radiusM: number): Promise<Shelter[]> {
    return this.allShelters()
      .filter((s) => haversineM(center, s.position) <= radiusM)
      .sort((a, b) => haversineM(center, a.position) - haversineM(center, b.position));
  }

  async getShelter(id: string): Promise<Shelter | null> {
    return this.allShelters().find((s) => s.id === id) ?? null;
  }

  async createShelter(input: CreateShelterInput): Promise<Shelter> {
    const existing = this.allShelters().find((s) => s.ownerId === input.ownerId);
    if (existing) return existing;
    const shelter: Shelter = {
      id: `sh-${input.ownerId}`,
      name: input.name,
      ownerId: input.ownerId,
      ownerName: input.ownerName,
      factionId: input.factionId,
      level: 1,
      position: input.publicPosition,
      progress: {},
      contributions: [],
      createdAt: this.now(),
    };
    this.persistShelter(shelter);
    return shelter;
  }

  async donateToShelter(input: DonationInput): Promise<DonationResult> {
    const shelter = await this.getShelter(input.shelterId);
    if (!shelter) return { ok: false, reason: 'not_found', accepted: {}, leveledUp: false };
    const check = validateInteraction(
      {
        playerId: input.playerId,
        action: 'shelter',
        targetId: shelter.id,
        targetPosition: shelter.position,
        playerPosition: input.playerPosition,
        accuracyM: input.accuracyM,
        timestamp: this.now(),
      },
      GAME_CONFIG,
      { speedLocked: false, depleted: false },
    );
    if (!check.ok) return { ok: false, reason: 'out_of_range', accepted: {}, leveledUp: false };
    const outcome = applyDonation(shelter, input.playerId, input.playerName, input.resources);
    if (outcome.acceptedTotal === 0) return { ok: false, reason: 'invalid_amount', accepted: {}, leveledUp: false, shelter };
    this.persistShelter(outcome.shelter);
    return { ok: true, shelter: outcome.shelter, accepted: outcome.accepted, leveledUp: outcome.leveledUp };
  }

  async getFactions(): Promise<Faction[]> {
    const player = await this.loadPlayer();
    const shelters = this.allShelters();
    return FACTION_IDS.map((id) => {
      const members = MOCK_SURVIVORS.filter((s) => s.factionId === id).length * 37 + (player?.factionId === id ? 1 : 0);
      const totalContribution = shelters
        .filter((s) => s.factionId === id)
        .reduce((acc, s) => acc + s.contributions.reduce((a, c) => a + c.amount, 0), 0);
      return { ...FACTION_DEFS[id], members, totalContribution };
    });
  }

  async joinFaction(_playerId: string, _factionId: FactionId): Promise<void> {
    // La facción se guarda en el estado del jugador (savePlayer). En backend real se
    // registra en `profiles.faction_id` vía RPC `join_faction`.
  }

  async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
    const totals = new Map<string, number>();
    for (const s of this.allShelters()) {
      for (const c of s.contributions) totals.set(c.playerId, (totals.get(c.playerId) ?? 0) + c.amount);
    }
    const player = await this.loadPlayer();
    const entries: LeaderboardEntry[] = MOCK_SURVIVORS.map((s) => ({
      playerId: s.id,
      playerName: s.name,
      factionId: s.factionId,
      level: s.level,
      contribution: totals.get(s.id) ?? 0,
    }));
    if (player) {
      entries.push({
        playerId: player.id,
        playerName: player.name,
        factionId: player.factionId,
        level: player.level,
        contribution: totals.get(player.id) ?? 0,
      });
    }
    return entries.sort((a, b) => b.contribution - a.contribution).slice(0, limit);
  }

  async getNearbySurvivors(center: LatLng, radiusM: number): Promise<PublicSurvivor[]> {
    return mockSurvivorsAround(center, this.now())
      .filter((s) => haversineM(center, s.approxPosition) <= radiusM)
      .sort((a, b) => haversineM(center, a.approxPosition) - haversineM(center, b.approxPosition));
  }

  async publishPresence(): Promise<void> {
    // Sin backend no hay a quién publicar. La posición ya llega difuminada.
  }

  /** Borra todo el progreso local (ajustes → reiniciar). */
  reset(): void {
    for (const key of Object.values(KEYS)) this.storage.removeItem(key);
  }
}
