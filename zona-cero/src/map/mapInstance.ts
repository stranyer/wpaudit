import type { Map as MapLibreMap } from 'maplibre-gl';

// Referencia global al mapa para controles que dependen de su orientación (joystick).
let instance: MapLibreMap | null = null;

export function setMapInstance(map: MapLibreMap | null): void {
  instance = map;
}

export function getMapBearing(): number {
  return instance?.getBearing() ?? 0;
}
