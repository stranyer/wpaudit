import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { FACTION_DEFS, FACTION_IDS } from '../../core/factions';
import { haversineM } from '../../core/geo';
import { RESOURCE_IDS } from '../../core/items';
import { createPlayer } from '../../core/player';
import { MAX_SHELTER_LEVEL } from '../../core/shelter';
import type {
  Faction,
  FactionId,
  InteractionRejection,
  InteractionRequest,
  InteractionResult,
  LatLng,
  LeaderboardEntry,
  PlayerState,
  PublicSurvivor,
  ResourceId,
  Shelter,
  ShelterContribution,
} from '../../core/types';
import { fuzzPosition } from '../privacy';
import type { CreateShelterInput, DonationInput, DonationResult, GameRepository } from './GameRepository';

// Repositorio de producción contra Supabase (Postgres + PostGIS).
// El esquema y las RPC están en supabase/migrations/0001_init.sql.
//
// - Identidad: sesión anónima de Supabase (`auth.uid()`); el id del jugador es el uid.
// - Toda validación que importa (alcance, velocidad, reclamos, donaciones) la hace el
//   servidor con funciones SECURITY DEFINER; acá solo se mapean las respuestas.
// - Privacidad: la posición real solo viaja como argumento de RPC de validación.
//   La presencia se difumina acá (fuzzPosition) y el servidor la vuelve a engrosar.

type Row = Record<string, unknown>;

/** Dueño de los refugios comunitarios (owner_id NULL en la base). */
const SYSTEM_OWNER_ID = 'comunidad';
const SYSTEM_OWNER_NAME = 'Comunidad';
const DEFAULT_PLAYER_NAME = 'Superviviente';
const MAX_NAME_LENGTH = 40;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const INTERACTION_REJECTIONS: readonly InteractionRejection[] = [
  'out_of_range',
  'too_fast',
  'depleted',
  'expired',
  'low_accuracy',
];

type DonationRejection = NonNullable<DonationResult['reason']>;
const DONATION_REJECTIONS: readonly DonationRejection[] = ['out_of_range', 'not_found', 'invalid_amount'];

/** Mensajes para los errores que lanzan las RPC (`raise exception '<código>'`). */
const SERVER_ERRORS: Partial<Record<string, string>> = {
  not_authenticated: 'No hay sesión iniciada con el servidor.',
  invalid_name: 'El nombre del refugio debe tener entre 2 y 40 caracteres.',
  invalid_position: 'La posición no es válida.',
  unsafe_location: 'Ese lugar no es un espacio público seguro (zona excluida). Probá en una plaza o un parque.',
  invalid_faction: 'Facción desconocida.',
  invalid_action: 'Tipo de interacción inválido.',
  invalid_spawn_id: 'Identificador de punto inválido.',
};

interface ErrorLike {
  message: string;
  code?: string | null;
}

export class SupabaseRepository implements GameRepository {
  readonly kind = 'supabase' as const;
  private readonly client: SupabaseClient;
  private userId: string | null = null;
  private initPromise: Promise<string> | null = null;

  constructor(url: string, anonKey: string) {
    this.client = createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        storageKey: 'zc:supabase-auth',
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Sesión y partida
  // ---------------------------------------------------------------------------

  init(): Promise<string> {
    if (this.userId) return Promise.resolve(this.userId);
    this.initPromise ??= this.startSession().catch((error: unknown) => {
      this.initPromise = null;
      throw error;
    });
    return this.initPromise;
  }

  private async startSession(): Promise<string> {
    const { data: sessionData, error: sessionError } = await this.client.auth.getSession();
    let user = sessionError ? null : (sessionData.session?.user ?? null);
    if (!user) {
      const { data, error } = await this.client.auth.signInAnonymously();
      if (error) throw anonymousSignInError(error);
      user = data.user;
      if (!user) throw new Error('Supabase: no se pudo crear la sesión anónima.');
    }

    // Crea el perfil si no existe (INSERT ... ON CONFLICT DO NOTHING; no pisa datos).
    const { error: profileError } = await this.client
      .from('profiles')
      .upsert({ id: user.id }, { onConflict: 'id', ignoreDuplicates: true });
    if (profileError) throw serverError('Supabase: no se pudo crear el perfil', profileError);

    this.userId = user.id;
    return user.id;
  }

  private async requireUser(): Promise<string> {
    return this.userId ?? this.init();
  }

  async loadPlayer(): Promise<PlayerState | null> {
    const uid = await this.requireUser();
    const { data, error } = await this.client.from('player_saves').select('save').eq('player_id', uid).maybeSingle();
    if (error) throw serverError('Supabase: no se pudo cargar la partida', error);
    const row: unknown = data;
    if (!isRecord(row)) return null;
    return normalizePlayer(row.save, uid);
  }

  async savePlayer(player: PlayerState): Promise<void> {
    const uid = await this.requireUser();
    // El id guardado siempre es el uid de la sesión.
    const save: PlayerState = { ...player, id: uid };
    const { error } = await this.client.from('player_saves').upsert({ player_id: uid, save }, { onConflict: 'player_id' });
    if (error) throw serverError('Supabase: no se pudo guardar la partida', error);

    // Espejo público (solo columnas seguras; RLS: solo el propio perfil).
    const { error: profileError } = await this.client
      .from('profiles')
      .update({
        name: sanitizeName(player.name),
        level: clampInt(player.level, 1, 1000, 1),
        xp: clampInt(player.xp, 0, Number.MAX_SAFE_INTEGER, 0),
        faction_id: player.factionId,
      })
      .eq('id', uid);
    if (profileError) {
      // La partida ya quedó guardada; el perfil público se reintenta en el próximo guardado.
      console.warn('[SupabaseRepository] No se pudo actualizar el perfil público:', profileError.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Interacciones (validadas por el servidor)
  // ---------------------------------------------------------------------------

  async validateInteraction(request: InteractionRequest): Promise<InteractionResult> {
    await this.requireUser();
    const expiresAt = request.targetExpiresAt;
    const raw = await this.rpc('validate_interaction', {
      p_spawn_id: request.targetId,
      p_target_lat: finiteOrNull(request.targetPosition.lat),
      p_target_lng: finiteOrNull(request.targetPosition.lng),
      p_lat: finiteOrNull(request.playerPosition.lat),
      p_lng: finiteOrNull(request.playerPosition.lng),
      p_accuracy: finiteOrNull(request.accuracyM),
      p_expires_at: expiresAt !== undefined && Number.isFinite(expiresAt) ? new Date(expiresAt).toISOString() : null,
      p_action: request.action,
    });
    if (!isRecord(raw)) throw new Error('Supabase: respuesta inválida de validate_interaction.');

    const distanceM = toNumber(raw.distance_m, haversineM(request.playerPosition, request.targetPosition));
    if (toBool(raw.ok)) return { ok: true, distanceM };
    return { ok: false, reason: pickOne(raw.reason, INTERACTION_REJECTIONS) ?? 'out_of_range', distanceM };
  }

  // ---------------------------------------------------------------------------
  // Refugios
  // ---------------------------------------------------------------------------

  async getNearbyShelters(center: LatLng, radiusM: number): Promise<Shelter[]> {
    await this.requireUser();
    const raw = await this.rpc('nearby_shelters', {
      p_lat: finiteOrNull(center.lat),
      p_lng: finiteOrNull(center.lng),
      p_radius_m: Math.max(0, toNumber(radiusM, 0)),
    });
    const out: Shelter[] = [];
    for (const row of toRows(raw)) {
      const shelter = mapShelter(row);
      if (shelter) out.push(shelter);
    }
    return out;
  }

  async getShelter(id: string): Promise<Shelter | null> {
    if (!UUID_RE.test(id)) return null;
    await this.requireUser();
    return mapShelter(await this.rpc('get_shelter', { p_shelter_id: id }));
  }

  async createShelter(input: CreateShelterInput): Promise<Shelter> {
    // Dueño, nombre del dueño y facción los fija el servidor (auth.uid() + profiles).
    await this.requireUser();
    const raw = await this.rpc('create_shelter', {
      p_name: input.name,
      p_lat: finiteOrNull(input.publicPosition.lat),
      p_lng: finiteOrNull(input.publicPosition.lng),
    });
    const shelter = mapShelter(raw);
    if (!shelter) throw new Error('Supabase: respuesta inválida al crear el refugio.');
    return shelter;
  }

  async donateToShelter(input: DonationInput): Promise<DonationResult> {
    if (!UUID_RE.test(input.shelterId)) return { ok: false, reason: 'not_found', accepted: {}, leveledUp: false };
    await this.requireUser();
    const raw = await this.rpc('donate_to_shelter', {
      p_shelter_id: input.shelterId,
      p_resources: toResourceMap(input.resources),
      p_lat: finiteOrNull(input.playerPosition.lat),
      p_lng: finiteOrNull(input.playerPosition.lng),
      p_accuracy: finiteOrNull(input.accuracyM),
    });
    if (!isRecord(raw)) throw new Error('Supabase: respuesta inválida de donate_to_shelter.');

    const ok = toBool(raw.ok);
    const result: DonationResult = {
      ok,
      accepted: ok ? toResourceMap(raw.accepted) : {},
      leveledUp: ok && toBool(raw.leveled_up),
    };
    if (!ok) result.reason = pickOne(raw.reason, DONATION_REJECTIONS) ?? 'invalid_amount';
    const shelter = mapShelter(raw.shelter);
    if (shelter) result.shelter = shelter;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Facciones, ranking y comunidad
  // ---------------------------------------------------------------------------

  async getFactions(): Promise<Faction[]> {
    await this.requireUser();
    const out: Faction[] = [];
    for (const row of toRows(await this.rpc('factions_overview'))) {
      const id = toFactionId(row.id);
      if (!id) continue;
      const def = FACTION_DEFS[id];
      out.push({
        id,
        name: toStr(row.name, def.name),
        motto: toStr(row.motto, def.motto),
        color: toStr(row.color, def.color),
        bonusDescription: toStr(row.bonus_description, def.bonusDescription),
        members: clampInt(row.members, 0, Number.MAX_SAFE_INTEGER, 0),
        totalContribution: clampInt(row.total_contribution, 0, Number.MAX_SAFE_INTEGER, 0),
      });
    }
    // Base sin datos de referencia: se muestran las facciones del cliente sin estadísticas.
    if (out.length === 0) return FACTION_IDS.map((id) => ({ ...FACTION_DEFS[id], members: 0, totalContribution: 0 }));
    return out;
  }

  async joinFaction(_playerId: string, factionId: FactionId): Promise<void> {
    // El servidor usa auth.uid(); el id del jugador local coincide con el uid de la sesión.
    await this.requireUser();
    await this.rpc('join_faction', { p_faction_id: factionId });
  }

  async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
    await this.requireUser();
    const out: LeaderboardEntry[] = [];
    for (const row of toRows(await this.rpc('leaderboard', { p_limit: clampInt(limit, 1, 100, 20) }))) {
      const playerId = toStr(row.player_id, '');
      if (!playerId) continue;
      out.push({
        playerId,
        playerName: toStr(row.player_name, DEFAULT_PLAYER_NAME),
        factionId: toFactionId(row.faction_id),
        level: clampInt(row.level, 1, 1000, 1),
        contribution: clampInt(row.contribution, 0, Number.MAX_SAFE_INTEGER, 0),
      });
    }
    return out.sort((a, b) => b.contribution - a.contribution);
  }

  async getNearbySurvivors(center: LatLng, radiusM: number): Promise<PublicSurvivor[]> {
    await this.requireUser();
    const raw = await this.rpc('nearby_survivors', {
      p_lat: finiteOrNull(center.lat),
      p_lng: finiteOrNull(center.lng),
      p_radius_m: Math.max(0, toNumber(radiusM, 0)),
    });
    const out: PublicSurvivor[] = [];
    for (const row of toRows(raw)) {
      const id = toStr(row.player_id, '');
      const approxPosition = toLatLng(row.lat, row.lng);
      if (!id || !approxPosition) continue;
      out.push({
        id,
        name: toStr(row.name, DEFAULT_PLAYER_NAME),
        level: clampInt(row.level, 1, 1000, 1),
        factionId: toFactionId(row.faction_id),
        approxPosition,
        lastSeenAt: toTimeMs(row.last_seen_at, Date.now()),
      });
    }
    return out;
  }

  async publishPresence(
    player: Pick<PlayerState, 'id' | 'name' | 'level' | 'factionId'>,
    approxPosition: LatLng,
  ): Promise<void> {
    if (!Number.isFinite(approxPosition.lat) || !Number.isFinite(approxPosition.lng)) return;
    await this.requireUser();
    // Difuminado en el cliente (estable por jugador); el servidor vuelve a engrosar a grilla.
    // Nombre, nivel y facción salen del perfil público (espejado en savePlayer).
    const fuzzed = fuzzPosition(approxPosition, player.id);
    await this.rpc('publish_presence', { p_lat: fuzzed.lat, p_lng: fuzzed.lng });
  }

  // ---------------------------------------------------------------------------

  private async rpc(fn: string, args: Row = {}): Promise<unknown> {
    const { data, error } = await this.client.rpc(fn, args);
    if (error) throw serverError(`Supabase (${fn})`, error);
    const result: unknown = data;
    return result;
  }
}

// =============================================================================
// Errores
// =============================================================================

function serverError(context: string, error: ErrorLike): Error {
  const friendly = SERVER_ERRORS[error.message.trim()];
  return new Error(friendly ?? `${context}: ${error.message}`, { cause: error });
}

function anonymousSignInError(error: ErrorLike): Error {
  const disabled = error.code === 'anonymous_provider_disabled' || /anonymous/i.test(error.message);
  if (disabled) {
    return new Error(
      'Supabase: el inicio de sesión anónimo está deshabilitado. Activalo en el Dashboard → ' +
        'Authentication → Providers → Anonymous ("Allow anonymous sign-ins"), o quitá ' +
        'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY para jugar en modo local.',
      { cause: error },
    );
  }
  return new Error(`Supabase: no se pudo iniciar la sesión anónima (${error.message}).`, { cause: error });
}

// =============================================================================
// Normalización defensiva (los números pueden llegar como texto, el jsonb como string…)
// =============================================================================

function isRecord(value: unknown): value is Row {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseJsonish(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    const parsed: unknown = JSON.parse(value);
    return parsed;
  } catch {
    return value;
  }
}

function toRows(value: unknown): Row[] {
  const parsed = parseJsonish(value);
  if (isRecord(parsed)) return [parsed];
  const items: unknown[] = Array.isArray(parsed) ? parsed : [];
  return items.filter(isRecord);
}

function toNumber(value: unknown, fallback: number): number {
  const n =
    typeof value === 'number' ? value : typeof value === 'string' && value.trim() !== '' ? Number(value) : Number.NaN;
  return Number.isFinite(n) ? n : fallback;
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  return Math.min(max, Math.max(min, Math.round(toNumber(value, fallback))));
}

function finiteOrNull(value: number): number | null {
  return Number.isFinite(value) ? value : null;
}

function toStr(value: unknown, fallback: string): string {
  if (typeof value === 'string') return value;
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return fallback;
}

function toBool(value: unknown): boolean {
  return value === true || value === 'true' || value === 't' || value === 1;
}

/** Epoch en ms desde ISO (con microsegundos de Postgres), número o texto numérico. */
function toTimeMs(value: unknown, fallback: number): number {
  if (typeof value === 'number') return Number.isFinite(value) ? value : fallback;
  if (typeof value !== 'string' || value.trim() === '') return fallback;
  const trimmed = value.trim();
  if (/^\d+(\.\d+)?$/.test(trimmed)) return toNumber(trimmed, fallback);
  const iso = trimmed
    .replace(' ', 'T')
    .replace(/(\.\d{3})\d+/, '$1')
    .replace(/([+-]\d{2})$/, '$1:00');
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : fallback;
}

function pickOne<T extends string>(value: unknown, allowed: readonly T[]): T | undefined {
  return allowed.find((candidate) => candidate === value);
}

function toFactionId(value: unknown): FactionId | null {
  return pickOne(value, FACTION_IDS) ?? null;
}

function toLatLng(lat: unknown, lng: unknown): LatLng | null {
  const la = toNumber(lat, Number.NaN);
  const ln = toNumber(lng, Number.NaN);
  if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) return null;
  return { lat: la, lng: ln };
}

/** Solo recursos conocidos, enteros y positivos. */
function toResourceMap(value: unknown): Partial<Record<ResourceId, number>> {
  const src = parseJsonish(value);
  const out: Partial<Record<ResourceId, number>> = {};
  if (!isRecord(src)) return out;
  for (const id of RESOURCE_IDS) {
    const n = Math.floor(toNumber(src[id], 0));
    if (n > 0) out[id] = n;
  }
  return out;
}

function sanitizeName(name: string): string {
  // eslint-disable-next-line no-control-regex
  const clean = name.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, MAX_NAME_LENGTH);
  return clean || DEFAULT_PLAYER_NAME;
}

function mapContributions(value: unknown): ShelterContribution[] {
  const parsed = parseJsonish(value);
  const items: unknown[] = Array.isArray(parsed) ? parsed : [];
  const out: ShelterContribution[] = [];
  for (const item of items) {
    if (!isRecord(item)) continue;
    const playerId = toStr(item.player_id ?? item.playerId, '');
    if (!playerId) continue;
    out.push({
      playerId,
      playerName: toStr(item.player_name ?? item.playerName, DEFAULT_PLAYER_NAME),
      amount: clampInt(item.amount, 0, Number.MAX_SAFE_INTEGER, 0),
    });
  }
  return out.sort((a, b) => b.amount - a.amount);
}

/** Fila de `nearby_shelters` o jsonb de `get_shelter`/`create_shelter` (mismas claves). */
function mapShelter(value: unknown): Shelter | null {
  const row = parseJsonish(value);
  if (!isRecord(row)) return null;
  const id = toStr(row.id, '');
  const position = toLatLng(row.lat, row.lng);
  if (!id || !position) return null;
  const ownerId = toStr(row.owner_id, '');
  return {
    id,
    name: toStr(row.name, 'Refugio'),
    ownerId: ownerId || SYSTEM_OWNER_ID,
    ownerName: toStr(row.owner_name, SYSTEM_OWNER_NAME),
    factionId: toFactionId(row.faction_id),
    level: clampInt(row.level, 1, MAX_SHELTER_LEVEL, 1),
    position,
    progress: toResourceMap(row.progress),
    contributions: mapContributions(row.contributions),
    createdAt: toTimeMs(row.created_at, Date.now()),
  };
}

/**
 * Reconstruye un PlayerState desde el jsonb guardado. Parte de `createPlayer` para
 * completar campos que falten (partidas de versiones anteriores) y solo acepta valores
 * del mismo tipo que el valor por defecto. El inventario se REEMPLAZA (no se mezcla con
 * el inicial, que devolvería objetos ya gastados); los demás objetos anidados
 * (equipo, estadísticas) se combinan con sus valores por defecto.
 */
function normalizePlayer(value: unknown, uid: string): PlayerState | null {
  const save = parseJsonish(value);
  if (!isRecord(save) || typeof save.name !== 'string') return null;

  const base = createPlayer(uid, save.name, Date.now());
  const merged: Row = { ...base };
  for (const [key, fallback] of Object.entries(base)) {
    const incoming = save[key];
    if (incoming === undefined) continue;
    if (isRecord(fallback)) {
      if (isRecord(incoming)) merged[key] = key === 'inventory' ? { ...incoming } : { ...fallback, ...incoming };
    } else if (fallback === null) {
      if (incoming === null || typeof incoming !== 'object') merged[key] = incoming;
    } else if (typeof incoming === typeof fallback && (typeof incoming !== 'number' || Number.isFinite(incoming))) {
      merged[key] = incoming;
    }
  }
  merged.id = uid;
  merged.factionId = toFactionId(save.factionId);
  // Cada campo conocido quedó con el tipo de su valor por defecto.
  return merged as unknown as PlayerState;
}
