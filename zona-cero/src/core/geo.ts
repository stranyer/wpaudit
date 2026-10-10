import type { LatLng } from './types';

// Utilidades geográficas puras. Para distancias cortas (< 5 km) usamos una
// proyección equirectangular local, suficientemente precisa y muy barata.

export const EARTH_RADIUS_M = 6_371_008.8;
const DEG = Math.PI / 180;

export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = (b.lat - a.lat) * DEG;
  const dLng = (b.lng - a.lng) * DEG;
  const s =
    Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * DEG) * Math.cos(b.lat * DEG) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(s)));
}

/** Desplaza un punto `northM` metros al norte y `eastM` metros al este. */
export function offsetM(origin: LatLng, northM: number, eastM: number): LatLng {
  const lat = origin.lat + (northM / EARTH_RADIUS_M) / DEG;
  const lng = origin.lng + (eastM / (EARTH_RADIUS_M * Math.cos(origin.lat * DEG))) / DEG;
  return { lat, lng: normalizeLng(lng) };
}

export function normalizeLng(lng: number): number {
  return ((((lng + 180) % 360) + 360) % 360) - 180;
}

/** Rumbo inicial de `a` hacia `b`, en grados (0 = norte, sentido horario). */
export function bearingDeg(a: LatLng, b: LatLng): number {
  const y = Math.sin((b.lng - a.lng) * DEG) * Math.cos(b.lat * DEG);
  const x =
    Math.cos(a.lat * DEG) * Math.sin(b.lat * DEG) -
    Math.sin(a.lat * DEG) * Math.cos(b.lat * DEG) * Math.cos((b.lng - a.lng) * DEG);
  return (Math.atan2(y, x) / DEG + 360) % 360;
}

export interface XY {
  x: number;
  y: number;
}

/** Proyecta a metros relativos a `origin` (x = este, y = norte). */
export function toLocalXY(origin: LatLng, p: LatLng): XY {
  return {
    x: (p.lng - origin.lng) * DEG * EARTH_RADIUS_M * Math.cos(origin.lat * DEG),
    y: (p.lat - origin.lat) * DEG * EARTH_RADIUS_M,
  };
}

export function fromLocalXY(origin: LatLng, xy: XY): LatLng {
  return offsetM(origin, xy.y, xy.x);
}

// ---------------------------------------------------------------------------
// Grilla de celdas del mundo
// ---------------------------------------------------------------------------
// Grilla fija en grados: ~200 m x ~220 m en Buenos Aires. Es determinística, así
// que todos los clientes (y el servidor) calculan las mismas celdas.

export const CELL_LAT_DEG = 0.0018;
export const CELL_LNG_DEG = 0.0024;

export interface CellCoord {
  cx: number;
  cy: number;
}

export function cellOf(p: LatLng): CellCoord {
  return { cx: Math.floor(p.lng / CELL_LNG_DEG), cy: Math.floor(p.lat / CELL_LAT_DEG) };
}

export function cellId(c: CellCoord): string {
  return `${c.cx}_${c.cy}`;
}

export function parseCellId(id: string): CellCoord {
  const [cx, cy] = id.split('_').map(Number);
  return { cx, cy };
}

export function cellBounds(c: CellCoord): [LatLng, LatLng] {
  return [
    { lat: c.cy * CELL_LAT_DEG, lng: c.cx * CELL_LNG_DEG },
    { lat: (c.cy + 1) * CELL_LAT_DEG, lng: (c.cx + 1) * CELL_LNG_DEG },
  ];
}

export function cellCenter(c: CellCoord): LatLng {
  return { lat: (c.cy + 0.5) * CELL_LAT_DEG, lng: (c.cx + 0.5) * CELL_LNG_DEG };
}

/** Celdas en un cuadrado de (2r+1)² alrededor del punto. */
export function cellsAround(p: LatLng, radiusCells: number): CellCoord[] {
  const c = cellOf(p);
  const out: CellCoord[] = [];
  for (let dy = -radiusCells; dy <= radiusCells; dy++) {
    for (let dx = -radiusCells; dx <= radiusCells; dx++) {
      out.push({ cx: c.cx + dx, cy: c.cy + dy });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Geometría para ubicar spawns sobre calles y evitar zonas excluidas
// ---------------------------------------------------------------------------

export type Segment = [LatLng, LatLng];

export function nearestPointOnSegment(p: XY, a: XY, b: XY): XY {
  const abx = b.x - a.x;
  const aby = b.y - a.y;
  const len2 = abx * abx + aby * aby;
  if (len2 === 0) return { x: a.x, y: a.y };
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2));
  return { x: a.x + abx * t, y: a.y + aby * t };
}

/**
 * Ajusta `point` al punto más cercano de `segments` si está a menos de `maxDistM`.
 * Devuelve null si no hay ninguna calle/sendero suficientemente cerca.
 */
export function snapToSegments(
  point: LatLng,
  segments: Segment[],
  maxDistM: number,
): { position: LatLng; distanceM: number } | null {
  let best: XY | null = null;
  let bestD2 = maxDistM * maxDistM;
  const origin = point;
  for (const [a, b] of segments) {
    const pa = toLocalXY(origin, a);
    const pb = toLocalXY(origin, b);
    // Descarte rápido por caja envolvente.
    if (
      Math.min(pa.x, pb.x) > maxDistM ||
      Math.max(pa.x, pb.x) < -maxDistM ||
      Math.min(pa.y, pb.y) > maxDistM ||
      Math.max(pa.y, pb.y) < -maxDistM
    ) {
      continue;
    }
    const q = nearestPointOnSegment({ x: 0, y: 0 }, pa, pb);
    const d2 = q.x * q.x + q.y * q.y;
    if (d2 <= bestD2) {
      bestD2 = d2;
      best = q;
    }
  }
  if (!best) return null;
  return { position: fromLocalXY(origin, best), distanceM: Math.sqrt(bestD2) };
}

/** Test punto-en-polígono (ray casting) sobre un anillo de coordenadas. */
export function pointInRing(p: LatLng, ring: LatLng[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const a = ring[i];
    const b = ring[j];
    const intersects =
      a.lat > p.lat !== b.lat > p.lat &&
      p.lng < ((b.lng - a.lng) * (p.lat - a.lat)) / (b.lat - a.lat) + a.lng;
    if (intersects) inside = !inside;
  }
  return inside;
}

/** Polígono con agujeros: [anillo exterior, ...agujeros]. */
export function pointInPolygon(p: LatLng, rings: LatLng[][]): boolean {
  if (rings.length === 0 || !pointInRing(p, rings[0])) return false;
  for (let i = 1; i < rings.length; i++) {
    if (pointInRing(p, rings[i])) return false;
  }
  return true;
}

export function formatDistance(m: number): string {
  if (m < 1000) return `${Math.round(m)} m`;
  return `${(m / 1000).toFixed(1).replace('.', ',')} km`;
}
