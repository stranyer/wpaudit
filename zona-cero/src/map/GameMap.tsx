import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Map as MapLibreMap, Marker, type GeoJSONSource, type LngLat, type PositionAnchor } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import './setupMaplibre';
import { LocateFixed, Rotate3d, Skull } from 'lucide-react';
import { GAME_CONFIG } from '../config/gameConfig';
import { OFFLINE_MAP_BOUNDS, WEB_DEMO } from '../config/platform';
import { FACTION_DEFS } from '../core/factions';
import { haversineM, offsetM } from '../core/geo';
import { effectiveRadius } from '../core/interaction';
import { SUPPLIES } from '../core/supplies';
import { ZOMBIES, threatRating } from '../core/zombies';
import type { LatLng, Shelter, Spawn, SupplySpawn, Zone, ZombieSpawn } from '../core/types';
import { demoProvider } from '../game/session';
import { useGameStore } from '../store/gameStore';
import { useLocationStore } from '../store/locationStore';
import { useWorldStore, visibleSpawns } from '../store/worldStore';
import { SUPPLY_ICONS, SurvivorFigure, shelterIcon } from '../ui/components/icons';
import { buildMapStyle } from './mapStyle';
import { setMapInstance } from './mapInstance';
import { setPlacementSource } from './placementBridge';
import { extractPlacementData } from './placementFromMap';

/** Spawns más lejos que esto no se dibujan (ahorra DOM y GPU). */
const MARKER_RADIUS_M = 520;
const DEFAULT_ZOOM = 17.2;
const DEFAULT_PITCH = 52;

type FC = GeoJSON.FeatureCollection;

function circlePolygon(center: LatLng, radiusM: number, steps = 48): FC {
  const coords: [number, number][] = [];
  for (let i = 0; i <= steps; i++) {
    const a = (i / steps) * Math.PI * 2;
    const p = offsetM(center, Math.cos(a) * radiusM, Math.sin(a) * radiusM);
    coords.push([p.lng, p.lat]);
  }
  return { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [coords] } }] };
}

function zonesCollection(zones: Zone[]): FC {
  return {
    type: 'FeatureCollection',
    features: zones
      .filter((z) => z.threat === 'infested')
      .map((z) => {
        const [sw, ne] = z.bounds;
        return {
          type: 'Feature' as const,
          properties: { id: z.cellId },
          geometry: {
            type: 'Polygon' as const,
            coordinates: [
              [
                [sw.lng, sw.lat],
                [ne.lng, sw.lat],
                [ne.lng, ne.lat],
                [sw.lng, ne.lat],
                [sw.lng, sw.lat],
              ],
            ],
          },
        };
      }),
  };
}

const EMPTY: FC = { type: 'FeatureCollection', features: [] };

export function GameMap({ active }: { active: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [map, setMap] = useState<MapLibreMap | null>(null);
  const [follow, setFollow] = useState(true);
  const followRef = useRef(true);
  followRef.current = follow;
  const [pitched, setPitched] = useState(true);

  // --- Creación del mapa (una sola vez) ---------------------------------------
  useEffect(() => {
    const start = useLocationStore.getState().position ?? GAME_CONFIG.demo.start;
    const m = new MapLibreMap({
      container: containerRef.current!,
      style: buildMapStyle(),
      center: [start.lng, start.lat],
      zoom: DEFAULT_ZOOM,
      pitch: DEFAULT_PITCH,
      minZoom: 13,
      maxZoom: 19.5,
      maxPitch: 65,
      attributionControl: { compact: true },
      pixelRatio: Math.min(window.devicePixelRatio || 1, 2),
      fadeDuration: 0,
      canvasContextAttributes: { antialias: false },
      maxTileCacheSize: 60,
      // En la web demo la cámara no se aleja de la zona con mapa empaquetado.
      maxBounds: WEB_DEMO
        ? [
            [OFFLINE_MAP_BOUNDS.west - 0.01, OFFLINE_MAP_BOUNDS.south - 0.01],
            [OFFLINE_MAP_BOUNDS.east + 0.01, OFFLINE_MAP_BOUNDS.north + 0.01],
          ]
        : undefined,
    });
    m.touchZoomRotate.enableRotation();

    m.on('load', () => {
      m.addSource('zones', { type: 'geojson', data: EMPTY });
      m.addSource('reach', { type: 'geojson', data: EMPTY });
      const firstSymbol = m.getStyle().layers.find((l: { type: string; id: string }) => l.type === 'symbol' || l.type === 'fill-extrusion')?.id;
      m.addLayer(
        { id: 'zones-fill', type: 'fill', source: 'zones', paint: { 'fill-color': '#b8392c', 'fill-opacity': 0.13 } },
        firstSymbol,
      );
      m.addLayer(
        {
          id: 'zones-line',
          type: 'line',
          source: 'zones',
          paint: { 'line-color': '#e2513f', 'line-opacity': 0.55, 'line-width': 1.5, 'line-dasharray': [3, 2] },
        },
        firstSymbol,
      );
      m.addLayer(
        { id: 'reach-fill', type: 'fill', source: 'reach', paint: { 'fill-color': '#ec9442', 'fill-opacity': 0.08 } },
        firstSymbol,
      );
      m.addLayer(
        {
          id: 'reach-line',
          type: 'line',
          source: 'reach',
          paint: { 'line-color': '#ec9442', 'line-opacity': 0.75, 'line-width': 1.6, 'line-dasharray': [2, 2] },
        },
        firstSymbol,
      );
      setMap(m);
    });

    // Si el usuario arrastra el mapa, se deja de seguir al jugador.
    m.on('dragstart', () => setFollow(false));

    // Ubicación de spawns en calles: cuando el mapa termina de cargar una vista.
    let lastPlacement = 0;
    const place = () => {
      const now = performance.now();
      if (now - lastPlacement < 1200) return;
      lastPlacement = now;
      const data = extractPlacementData(m);
      if (!data || data.walkable.length === 0) return;
      const b = m.getBounds();
      useWorldStore.getState().applyPlacement(data, { south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast() });
    };
    m.on('idle', place);
    // Si el mundo se regenera sin que el mapa se mueva (cambio de ventana de tiempo),
    // los spawns nuevos también se ubican en calles.
    let placeTimer: ReturnType<typeof setTimeout> | null = null;
    const unsubscribe = useWorldStore.subscribe((state, prev) => {
      if (state.spawns === prev.spawns || !state.spawns.some((sp) => sp.placement === 'raw')) return;
      if (placeTimer) clearTimeout(placeTimer);
      placeTimer = setTimeout(() => {
        lastPlacement = 0;
        if (m.areTilesLoaded()) place();
      }, 300);
    });
    setPlacementSource(() => extractPlacementData(m));
    setMapInstance(m);

    // Teletransporte en modo demo: clic derecho (escritorio) o mantener presionado (táctil).
    const teleport = (lngLat: LngLat) => {
      if (useLocationStore.getState().mode !== 'demo') return;
      demoProvider()?.teleport({ lat: lngLat.lat, lng: lngLat.lng });
      setFollow(true);
    };
    m.on('contextmenu', (e) => teleport(e.lngLat));
    let pressTimer: ReturnType<typeof setTimeout> | null = null;
    m.on('touchstart', (e) => {
      if (e.originalEvent.touches.length !== 1) return;
      const ll = e.lngLat;
      pressTimer = setTimeout(() => teleport(ll), 650);
    });
    const cancelPress = () => {
      if (pressTimer) clearTimeout(pressTimer);
      pressTimer = null;
    };
    m.on('touchend', cancelPress);
    m.on('touchmove', cancelPress);
    m.on('click', () => useWorldStore.getState().select(null));

    return () => {
      cancelPress();
      unsubscribe();
      if (placeTimer) clearTimeout(placeTimer);
      setPlacementSource(null);
      setMapInstance(null);
      m.remove();
    };
  }, []);

  // --- Seguir al jugador y actualizar el radio de interacción -----------------
  useEffect(() => {
    if (!map) return;
    const update = (pos: LatLng | null, accuracy: number, animate: boolean) => {
      if (!pos) return;
      (map.getSource('reach') as GeoJSONSource | undefined)?.setData(circlePolygon(pos, effectiveRadius(GAME_CONFIG, accuracy)));
      if (followRef.current) {
        const demo = useLocationStore.getState().mode === 'demo';
        if (demo || !animate) map.jumpTo({ center: [pos.lng, pos.lat] });
        else map.easeTo({ center: [pos.lng, pos.lat], duration: 600, easing: (t) => t });
      }
    };
    const s = useLocationStore.getState();
    update(s.position, s.accuracyM, false);
    return useLocationStore.subscribe((state, prev) => {
      if (state.position !== prev.position || state.accuracyM !== prev.accuracyM) update(state.position, state.accuracyM, true);
    });
  }, [map]);

  // Al volver a seguir, centrar de inmediato.
  useEffect(() => {
    if (!map || !follow) return;
    const pos = useLocationStore.getState().position;
    if (pos) map.easeTo({ center: [pos.lng, pos.lat], zoom: Math.max(map.getZoom(), 16), duration: 500 });
  }, [follow, map]);

  // Zonas infestadas.
  const zones = useWorldStore((s) => s.zones);
  useEffect(() => {
    (map?.getSource('zones') as GeoJSONSource | undefined)?.setData(zonesCollection(zones));
  }, [map, zones]);

  // Al volver al mapa después de otra pantalla, recalcular tamaño.
  useEffect(() => {
    if (active) map?.resize();
  }, [active, map]);

  return (
    <>
      <div className="map-root">
        <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
      </div>
      {map && <MapEntities map={map} />}
      {map && <PlayerMarkers map={map} />}
      <div className="map-side">
        <button className={`icon-btn ${follow ? 'active' : ''}`} onClick={() => setFollow(true)} aria-label="Centrar en mi posición">
          <LocateFixed size={22} />
        </button>
        <button
          className={`icon-btn ${pitched ? 'active' : ''}`}
          onClick={() => {
            const next = !pitched;
            setPitched(next);
            map?.easeTo({ pitch: next ? DEFAULT_PITCH : 0, bearing: next ? map.getBearing() : 0, duration: 500 });
          }}
          aria-label="Vista 3D"
        >
          <Rotate3d size={22} />
        </button>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
// Marcadores (DOM + portales de React)
// ---------------------------------------------------------------------------

function MapMarker({
  map,
  position,
  children,
  anchor = 'bottom',
  zIndex = 0,
  alignToMap = false,
  onClick,
}: {
  map: MapLibreMap;
  position: LatLng;
  children: ReactNode;
  anchor?: PositionAnchor;
  zIndex?: number;
  alignToMap?: boolean;
  onClick?: () => void;
}) {
  const el = useMemo(() => document.createElement('div'), []);
  const markerRef = useRef<Marker | null>(null);
  const clickRef = useRef(onClick);
  clickRef.current = onClick;

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (!clickRef.current) return;
      e.stopPropagation();
      clickRef.current();
    };
    el.addEventListener('click', handler);
    const marker = new Marker({
      element: el,
      anchor,
      pitchAlignment: alignToMap ? 'map' : 'viewport',
      rotationAlignment: alignToMap ? 'map' : 'viewport',
    })
      .setLngLat([position.lng, position.lat])
      .addTo(map);
    markerRef.current = marker;
    return () => {
      el.removeEventListener('click', handler);
      marker.remove();
    };
    // La posición se actualiza en el efecto siguiente sin recrear el marcador.
  }, [map, el, anchor, alignToMap]);

  useEffect(() => {
    markerRef.current?.setLngLat([position.lng, position.lat]);
  }, [position.lat, position.lng]);

  useEffect(() => {
    el.style.zIndex = String(zIndex);
  }, [el, zIndex]);

  return createPortal(children, el);
}

function PlayerMarkers({ map }: { map: MapLibreMap }) {
  const position = useLocationStore((s) => s.position);
  const heading = useLocationStore((s) => s.headingDeg);
  const accent = useGameStore((s) => (s.player?.factionId ? FACTION_DEFS[s.player.factionId].color : '#ec9442'));
  if (!position) return null;
  return (
    <>
      <MapMarker map={map} position={position} anchor="center" alignToMap zIndex={1}>
        <div className="player-ground">
          <div className="pulse" />
          {heading !== null && <div className="heading" style={{ transform: `rotate(${heading}deg)` }} />}
        </div>
      </MapMarker>
      <MapMarker map={map} position={position} anchor="bottom" zIndex={5}>
        <div className="player-avatar">
          <SurvivorFigure color={accent} />
        </div>
      </MapMarker>
    </>
  );
}

/** Spawns y refugios cercanos. Solo se re-renderiza al cambiar de celda o de lista. */
function MapEntities({ map }: { map: MapLibreMap }) {
  const spawns = useWorldStore((s) => s.spawns);
  const placementAvailable = useWorldStore((s) => s.placementAvailable);
  const shelters = useWorldStore((s) => s.shelters);
  const selectedId = useWorldStore((s) => s.selectedId);
  const select = useWorldStore((s) => s.select);
  const playerLevel = useGameStore((s) => s.player?.level ?? 1);
  const playerId = useGameStore((s) => s.player?.id);
  const position = useLocationStore((s) => s.position);
  const accuracy = useLocationStore((s) => s.accuracyM);

  // Posición "gruesa" (cada ~15 m) para no recalcular en cada paso.
  const coarse = position ? `${position.lat.toFixed(4)},${position.lng.toFixed(4)}` : '';
  const shown = useMemo(() => {
    if (!position) return [] as Spawn[];
    return visibleSpawns(spawns, placementAvailable).filter((s) => haversineM(position, s.position) <= MARKER_RADIUS_M);
  }, [spawns, placementAvailable, coarse]);

  const reach = effectiveRadius(GAME_CONFIG, accuracy);
  const inReach = (p: LatLng) => !!position && haversineM(position, p) <= reach;

  return (
    <>
      {shown.map((s) => (
        <MapMarker key={s.id} map={map} position={s.position} onClick={() => select(s.id)} zIndex={s.id === selectedId ? 4 : 2}>
          {s.kind === 'zombie' ? (
            <ZombieMarker spawn={s} playerLevel={playerLevel} near={inReach(s.position)} selected={s.id === selectedId} />
          ) : (
            <SupplyMarker spawn={s} near={inReach(s.position)} selected={s.id === selectedId} />
          )}
        </MapMarker>
      ))}
      {shelters.map((sh) => (
        <MapMarker key={sh.id} map={map} position={sh.position} onClick={() => select(sh.id)} zIndex={3}>
          <ShelterMarker shelter={sh} own={sh.ownerId === playerId} near={inReach(sh.position)} selected={sh.id === selectedId} />
        </MapMarker>
      ))}
    </>
  );
}

function ZombieMarker({ spawn, playerLevel, near, selected }: { spawn: ZombieSpawn; playerLevel: number; near: boolean; selected: boolean }) {
  const threat = threatRating(ZOMBIES[spawn.zombieType], playerLevel);
  return (
    <div className={`mk mk-zombie ${threat >= 2 ? 'danger' : ''} ${threat === 3 ? 'deadly' : ''} ${near ? 'in-reach' : ''} ${selected ? 'selected' : ''}`}>
      {threat >= 2 && (
        <div className="mk-threat">
          {Array.from({ length: threat - 1 }, (_, i) => (
            <Skull key={i} />
          ))}
        </div>
      )}
      <div className="mk-badge">
        <Skull />
      </div>
      <div className="mk-stem" />
      <div className="mk-shadow" />
    </div>
  );
}

function SupplyMarker({ spawn, near, selected }: { spawn: SupplySpawn; near: boolean; selected: boolean }) {
  const def = SUPPLIES[spawn.supplyType];
  const Icon = SUPPLY_ICONS[spawn.supplyType];
  return (
    <div className={`mk mk-supply rarity-${def.rarity} ${near ? 'in-reach' : ''} ${selected ? 'selected' : ''}`}>
      <div className="mk-badge">
        <Icon />
      </div>
      <div className="mk-stem" />
      <div className="mk-shadow" />
    </div>
  );
}

function ShelterMarker({ shelter, own, near, selected }: { shelter: Shelter; own: boolean; near: boolean; selected: boolean }) {
  const Icon = shelterIcon(shelter.level);
  const color = own ? '#ec9442' : shelter.factionId ? FACTION_DEFS[shelter.factionId].color : '#6f8a4a';
  return (
    <div
      className={`mk mk-shelter ${own ? 'mk-own' : ''} ${near ? 'in-reach' : ''} ${selected ? 'selected' : ''}`}
      style={{ ['--faction' as string]: color }}
    >
      <div className="mk-badge">
        <Icon />
        <span className="mk-level">{shelter.level}</span>
      </div>
      <div className="mk-stem" />
      <div className="mk-shadow" />
    </div>
  );
}
