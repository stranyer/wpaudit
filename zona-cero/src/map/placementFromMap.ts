import type { GeoJSONFeature, Map as MapLibreMap } from 'maplibre-gl';
import type { Segment } from '../core/geo';
import type { PlacementData } from '../core/placement';
import type { LatLng } from '../core/types';
import { OMT_SOURCE } from './mapStyle';

// Extrae de los tiles vectoriales ya cargados las calles y senderos públicos
// (para ubicar spawns) y las zonas a evitar (agua, militares, vías, aeropuertos).

const WALKABLE_CLASSES = new Set(['minor', 'tertiary', 'secondary', 'primary', 'path', 'pedestrian']);
const BLOCKED_SUBCLASSES = new Set(['corridor', 'platform', 'steps', 'bridleway']);
const BLOCKED_ACCESS = new Set(['no', 'private', 'customers', 'delivery']);
const EXCLUDED_LANDUSE = new Set(['military', 'railway', 'industrial', 'quarry', 'landfill', 'cemetery', 'prison']);

type Pos = [number, number];

const toLatLng = ([lng, lat]: Pos): LatLng => ({ lat, lng });

function lineSegments(coords: Pos[], out: Segment[]): void {
  for (let i = 1; i < coords.length; i++) out.push([toLatLng(coords[i - 1]), toLatLng(coords[i])]);
}

function polygons(f: GeoJSONFeature): LatLng[][][] {
  const g = f.geometry;
  if (g.type === 'Polygon') return [g.coordinates.map((ring) => ring.map((p) => toLatLng(p as Pos)))];
  if (g.type === 'MultiPolygon') return g.coordinates.map((poly) => poly.map((ring) => ring.map((p) => toLatLng(p as Pos))));
  return [];
}

export function extractPlacementData(map: MapLibreMap): PlacementData | null {
  if (!map.getSource(OMT_SOURCE) || map.getZoom() < 14) return null;
  const roads = map.querySourceFeatures(OMT_SOURCE, { sourceLayer: 'transportation' });
  if (roads.length === 0) return null;

  const walkable: Segment[] = [];
  for (const f of roads) {
    const p = f.properties ?? {};
    if (!WALKABLE_CLASSES.has(String(p.class))) continue;
    if (p.brunnel === 'tunnel' || p.indoor === 1) continue;
    if (BLOCKED_SUBCLASSES.has(String(p.subclass))) continue;
    if (BLOCKED_ACCESS.has(String(p.access)) || p.foot === 'no') continue;
    const g = f.geometry;
    if (g.type === 'LineString') lineSegments(g.coordinates as Pos[], walkable);
    else if (g.type === 'MultiLineString') for (const line of g.coordinates) lineSegments(line as Pos[], walkable);
  }

  const excluded: LatLng[][][] = [];
  for (const f of map.querySourceFeatures(OMT_SOURCE, { sourceLayer: 'water' })) {
    if (f.properties?.brunnel !== 'tunnel') excluded.push(...polygons(f));
  }
  for (const f of map.querySourceFeatures(OMT_SOURCE, { sourceLayer: 'landuse' })) {
    if (EXCLUDED_LANDUSE.has(String(f.properties?.class))) excluded.push(...polygons(f));
  }
  for (const f of map.querySourceFeatures(OMT_SOURCE, { sourceLayer: 'aeroway' })) {
    excluded.push(...polygons(f));
  }
  return { walkable, excluded };
}
