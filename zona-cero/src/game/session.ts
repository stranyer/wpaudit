import { GAME_CONFIG } from '../config/gameConfig';
import { cellId, cellOf, haversineM } from '../core/geo';
import { updateSpeedGuard, type SpeedGuardState } from '../core/interaction';
import { applyRegen, createPlayer, grantXp } from '../core/player';
import { nextWindowChange } from '../core/spawns';
import type { LatLng, PlayerState } from '../core/types';
import { getRepository, type GameRepository } from '../services/data';
import { LocalRepository } from '../services/data/LocalRepository';
import { DemoLocationProvider } from '../services/location/DemoLocationProvider';
import { GpsLocationProvider } from '../services/location/GpsLocationProvider';
import { LOCATION_ERROR_MESSAGES, type LocationFix, type LocationProvider } from '../services/location/types';
import { fuzzPosition } from '../services/privacy';
import { useGameStore } from '../store/gameStore';
import { useLocationStore, type LocationMode } from '../store/locationStore';
import { useUiStore } from '../store/uiStore';
import { useWorldStore } from '../store/worldStore';

// Sesión de juego: conecta ubicación, mundo, jugador y persistencia.
// Es la "capa de motor" entre la lógica pura (core) y la interfaz (React).

let repo: GameRepository | null = null;
let provider: LocationProvider | null = null;
let demo: DemoLocationProvider | null = null;
let tickTimer: ReturnType<typeof setInterval> | null = null;
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let speedGuard: SpeedGuardState = { last: null, lockedUntil: 0 };
let lastPos: LatLng | null = null;
let nextWindowAt = 0;
let lastShelterFetch: { at: number; pos: LatLng } | null = null;
let lastPresenceAt = 0;

const SHELTER_RADIUS_M = 20_000;

export function getRepo(): GameRepository {
  if (!repo) throw new Error('Sesión no iniciada');
  return repo;
}

const NAMES = ['Sombra', 'Lobo', 'Ceniza', 'Halcón', 'Óxido', 'Zorro', 'Trueno', 'Niebla', 'Chispa', 'Cuervo'];

function randomName(): string {
  return `${NAMES[Math.floor(Math.random() * NAMES.length)]}${Math.floor(10 + Math.random() * 89)}`;
}

let booting: Promise<void> | null = null;

/** Carga (o crea) el jugador y arranca los ciclos del juego. Idempotente. */
export function bootstrap(): Promise<void> {
  booting ??= doBootstrap().catch((err: unknown) => {
    booting = null;
    throw err;
  });
  return booting;
}

async function doBootstrap(): Promise<void> {
  repo = await getRepository();
  const playerId = await repo.init();
  const now = Date.now();
  const saved = await repo.loadPlayer();
  const player = saved && saved.id === playerId ? saved : createPlayer(playerId, randomName(), now);
  useGameStore.getState().set({
    player: applyRegen(player, now, GAME_CONFIG.regen),
    backend: repo.kind,
    ready: true,
  });

  // Guardado cuando cambia el jugador (ignorando el simple avance del reloj de regeneración).
  useGameStore.subscribe((state, prev) => {
    if (!state.player || state.player === prev.player) return;
    if (prev.player && onlyClockChanged(state.player, prev.player)) return;
    scheduleSave();
  });

  if (!tickTimer) tickTimer = setInterval(tick, GAME_CONFIG.tickMs);
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('pagehide', flushSave);
}

function onlyClockChanged(a: PlayerState, b: PlayerState): boolean {
  for (const key of Object.keys(a) as (keyof PlayerState)[]) {
    if (key !== 'lastRegenAt' && a[key] !== b[key]) return false;
  }
  return true;
}

/**
 * Guardado con límite de frecuencia: como máximo uno cada `saveDebounceMs` en local
 * y cada 10 s contra el backend (siempre se guarda el estado más reciente).
 */
function scheduleSave(): void {
  if (saveTimer) return;
  const delay = repo?.kind === 'supabase' ? 10_000 : GAME_CONFIG.saveDebounceMs;
  saveTimer = setTimeout(flushSave, delay);
}

export function flushSave(): void {
  if (saveTimer) {
    clearTimeout(saveTimer);
    saveTimer = null;
  }
  const p = useGameStore.getState().player;
  if (p && repo) void repo.savePlayer(p);
}

/** Ciclo periódico: regeneración, renovación del mundo y presencia. */
function tick(): void {
  const now = Date.now();
  const game = useGameStore.getState();
  if (game.player && !game.combat) {
    game.updatePlayer((p) => applyRegen(p, now, GAME_CONFIG.regen));
  }
  // Purga de spawns agotados vencidos.
  const depleted = Object.fromEntries(Object.entries(game.depleted).filter(([, exp]) => exp > now));
  if (Object.keys(depleted).length !== Object.keys(game.depleted).length) game.set({ depleted });

  const pos = useLocationStore.getState().position;
  if (pos && now >= nextWindowAt) refreshWorld(pos, true);
  if (pos && now - lastPresenceAt > 120_000) publishPresence(pos);
}

function onVisibility(): void {
  // Ahorro de batería: sin GPS ni ciclos mientras la app está en segundo plano.
  if (document.hidden) {
    flushSave();
    if (provider?.mode === 'gps') provider.stop();
    if (tickTimer) {
      clearInterval(tickTimer);
      tickTimer = null;
    }
  } else {
    if (!tickTimer) tickTimer = setInterval(tick, GAME_CONFIG.tickMs);
    const mode = useLocationStore.getState().mode;
    if (mode === 'gps') void startLocation('gps');
    tick();
  }
}

// ---------------------------------------------------------------------------
// Ubicación
// ---------------------------------------------------------------------------

export async function startLocation(mode: LocationMode): Promise<void> {
  provider?.stop();
  const loc = useLocationStore.getState();
  loc.set({ mode, status: 'requesting', error: null });
  useGameStore.getState().set({ lastMode: mode });
  speedGuard = { last: null, lockedUntil: 0 };
  lastPos = null;

  if (mode === 'demo') {
    const start = useGameStore.getState().demoPosition ?? GAME_CONFIG.demo.start;
    demo = new DemoLocationProvider(start, GAME_CONFIG.demo.walkSpeedMps);
    provider = demo;
  } else {
    demo = null;
    provider = new GpsLocationProvider();
  }
  await provider.start(onFix, (code) => {
    const s = useLocationStore.getState();
    // Un timeout con posición previa no es grave: el GPS sigue intentando.
    if (code === 'timeout' && s.position) return;
    s.set({ status: 'error', error: code });
    useUiStore.getState().toast(LOCATION_ERROR_MESSAGES[code], 'warn');
  });
}

export function demoProvider(): DemoLocationProvider | null {
  return demo;
}

function onFix(fix: LocationFix): void {
  const loc = useLocationStore.getState();
  const game = useGameStore.getState();
  if (fix.jump) {
    // Teletransporte de demo: no es movimiento real, se reinicia el control de velocidad.
    speedGuard = { last: null, lockedUntil: 0 };
    lastPos = null;
    if (repo instanceof LocalRepository) repo.resetSpeedGuard();
  }
  speedGuard = updateSpeedGuard(
    speedGuard,
    { position: fix.position, time: fix.timestamp },
    GAME_CONFIG.maxInteractionSpeedMps,
    GAME_CONFIG.speedLockMs,
  );
  loc.set({
    status: 'active',
    error: null,
    position: fix.position,
    accuracyM: fix.accuracyM,
    headingDeg: fix.headingDeg ?? loc.headingDeg,
    speedLockedUntil: speedGuard.lockedUntil,
  });
  if (loc.mode === 'demo') game.set({ demoPosition: fix.position });

  // Distancia caminada (se ignoran saltos grandes: teletransporte o GPS errático).
  if (lastPos) {
    const d = haversineM(lastPos, fix.position);
    if (d > 0.5 && d < 100 && Date.now() >= speedGuard.lockedUntil) recordWalk(d);
  }
  lastPos = fix.position;

  exploreCell(fix.position);
  refreshWorld(fix.position, false);
}

function recordWalk(meters: number): void {
  const game = useGameStore.getState();
  let buffer = game.walkBuffer + meters;
  let xp = 0;
  while (buffer >= 250) {
    buffer -= 250;
    xp += GAME_CONFIG.xp.per250mWalked;
  }
  game.set({ walkBuffer: buffer });
  game.updatePlayer((p) => ({ ...p, stats: { ...p.stats, distanceWalkedM: p.stats.distanceWalkedM + meters } }));
  if (xp > 0) awardXp(xp, null);
}

function exploreCell(p: LatLng): void {
  const id = cellId(cellOf(p));
  const game = useGameStore.getState();
  if (game.explored[id]) return;
  const explored = { ...game.explored, [id]: true as const };
  game.set({ explored });
  game.updatePlayer((pl) => ({ ...pl, stats: { ...pl.stats, cellsExplored: pl.stats.cellsExplored + 1 } }));
  // La primera celda (donde se arranca) no da bonus.
  if (Object.keys(explored).length > 1) awardXp(GAME_CONFIG.xp.perCellExplored, 'Zona explorada');
}

/** Regenera spawns si cambió la celda central o la ventana de tiempo. */
export function refreshWorld(p: LatLng, force: boolean): void {
  const world = useWorldStore.getState();
  const now = Date.now();
  const cell = cellId(cellOf(p));
  if (force || cell !== world.centerCellId || now >= nextWindowAt) {
    world.regenerate(p, now, useGameStore.getState().depleted);
    nextWindowAt = nextWindowChange(now, {
      worldSeed: GAME_CONFIG.worldSeed,
      zombieWindowMs: GAME_CONFIG.zombieWindowMs,
      supplyWindowMs: GAME_CONFIG.supplyWindowMs,
      infestedCellChance: GAME_CONFIG.infestedCellChance,
    });
  }
  if (!lastShelterFetch || now - lastShelterFetch.at > 60_000 || haversineM(lastShelterFetch.pos, p) > 1500) {
    lastShelterFetch = { at: now, pos: p };
    void loadShelters(p);
  }
}

export async function loadShelters(p: LatLng): Promise<void> {
  if (!repo) return;
  try {
    const shelters = await repo.getNearbyShelters(p, SHELTER_RADIUS_M);
    useWorldStore.getState().setShelters(shelters);
  } catch (err) {
    console.warn('[Zona Cero] No se pudieron cargar refugios', err);
  }
}

function publishPresence(p: LatLng): void {
  const player = useGameStore.getState().player;
  if (!repo || !player) return;
  lastPresenceAt = Date.now();
  // Nunca se publica la posición real: solo una aproximación difuminada.
  void repo
    .publishPresence({ id: player.id, name: player.name, level: player.level, factionId: player.factionId }, fuzzPosition(p, player.id))
    .catch(() => undefined);
}

// ---------------------------------------------------------------------------
// Utilidades compartidas con las acciones
// ---------------------------------------------------------------------------

/** Suma XP, avisa y celebra si se sube de nivel. */
export function awardXp(amount: number, reason: string | null): number {
  let gained = 0;
  useGameStore.getState().updatePlayer((p) => {
    const r = grantXp(p, amount);
    gained = r.levelsGained;
    return r.player;
  });
  const ui = useUiStore.getState();
  if (reason) ui.toast(`${reason}: +${amount} XP`, 'good');
  if (gained > 0) {
    const level = useGameStore.getState().player?.level ?? 0;
    ui.celebrate({ title: `¡Nivel ${level}!`, subtitle: 'Salud y resistencia restauradas. Tu mochila es más grande.' });
  }
  return gained;
}

export function stopSession(): void {
  provider?.stop();
  if (tickTimer) clearInterval(tickTimer);
  tickTimer = null;
  document.removeEventListener('visibilitychange', onVisibility);
  window.removeEventListener('pagehide', flushSave);
  flushSave();
}
