import type {
  Faction,
  FactionId,
  InteractionRequest,
  InteractionResult,
  LatLng,
  LeaderboardEntry,
  PlayerState,
  PublicSurvivor,
  ResourceId,
  Shelter,
} from '../../core/types';

/**
 * Contrato de persistencia y datos compartidos.
 *
 * - `LocalRepository` implementa todo con localStorage + datos simulados (sin backend).
 * - `SupabaseRepository` implementa lo mismo contra Supabase/PostGIS.
 *
 * Reglas de privacidad:
 * - Nunca se envía la ubicación real del jugador a tablas públicas.
 *   Las posiciones públicas se difuminan con `services/privacy.ts` antes de salir del cliente
 *   y el servidor vuelve a difuminarlas.
 * - Las validaciones de distancia (`validateInteraction`, `donateToShelter`) reciben la
 *   posición real solo para verificar alcance. El backend guarda únicamente la última
 *   posición validada en una tabla privada (sin acceso para ningún cliente) para el
 *   control de velocidad, y la borra a las 12 h.
 */
export interface GameRepository {
  readonly kind: 'local' | 'supabase';

  /** Inicializa sesión (anónima en Supabase). Devuelve el id del jugador. */
  init(): Promise<string>;

  loadPlayer(): Promise<PlayerState | null>;
  savePlayer(player: PlayerState): Promise<void>;

  /** Valida alcance/velocidad de una interacción. En backend real lo resuelve el servidor. */
  validateInteraction(request: InteractionRequest): Promise<InteractionResult>;

  getNearbyShelters(center: LatLng, radiusM: number): Promise<Shelter[]>;
  getShelter(id: string): Promise<Shelter | null>;
  createShelter(input: CreateShelterInput): Promise<Shelter>;
  donateToShelter(input: DonationInput): Promise<DonationResult>;

  getFactions(): Promise<Faction[]>;
  joinFaction(playerId: string, factionId: FactionId): Promise<void>;

  getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
  getNearbySurvivors(center: LatLng, radiusM: number): Promise<PublicSurvivor[]>;

  /** Publica presencia aproximada (posición ya difuminada). */
  publishPresence(player: Pick<PlayerState, 'id' | 'name' | 'level' | 'factionId'>, approxPosition: LatLng): Promise<void>;
}

export interface CreateShelterInput {
  name: string;
  ownerId: string;
  ownerName: string;
  factionId: FactionId | null;
  /** Posición pública ya ajustada (grilla + calle). */
  publicPosition: LatLng;
}

export interface DonationInput {
  shelterId: string;
  playerId: string;
  playerName: string;
  resources: Partial<Record<ResourceId, number>>;
  /** Posición real del jugador, solo para validar distancia. No se persiste. */
  playerPosition: LatLng;
  accuracyM: number;
}

export interface DonationResult {
  ok: boolean;
  reason?: 'out_of_range' | 'not_found' | 'invalid_amount';
  shelter?: Shelter;
  /** Recursos efectivamente aceptados (el excedente sobre el requisito se rechaza). */
  accepted: Partial<Record<ResourceId, number>>;
  leveledUp: boolean;
}
