import { pointInPolygon, snapToSegments, type Segment } from './geo';
import type { LatLng, Spawn } from './types';

// Ubicación segura de spawns.
// Los puntos generados al azar se mueven a la calle, vereda o sendero público más
// cercano. Si no hay ninguno cerca, o cae dentro de una zona excluida (agua,
// instalaciones militares, vías de tren, autopistas...), el spawn se descarta.

export interface PlacementData {
  /** Segmentos transitables a pie y de acceso público. */
  walkable: Segment[];
  /** Polígonos excluidos ([anillo exterior, ...agujeros]). */
  excluded: LatLng[][][];
}

export function placePoint(raw: LatLng, data: PlacementData, maxDistM: number): LatLng | null {
  const snapped = snapToSegments(raw, data.walkable, maxDistM);
  if (!snapped) return null;
  if (data.excluded.some((poly) => pointInPolygon(snapped.position, poly))) return null;
  return snapped.position;
}

/** Ajusta spawns "raw"; descarta los que no tienen ubicación segura. */
export function placeSpawns(spawns: Spawn[], data: PlacementData, maxDistM: number): Spawn[] {
  const out: Spawn[] = [];
  for (const s of spawns) {
    if (s.placement === 'snapped') {
      out.push(s);
      continue;
    }
    const pos = placePoint(s.position, data, maxDistM);
    if (pos) out.push({ ...s, position: pos, placement: 'snapped' });
  }
  return out;
}
