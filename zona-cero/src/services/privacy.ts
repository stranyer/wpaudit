import { offsetM, toLocalXY, fromLocalXY } from '../core/geo';
import { createRng } from '../core/rng';
import type { LatLng } from '../core/types';

// Privacidad de ubicación.
// Regla del juego: la ubicación real del jugador NUNCA se comparte. Lo que otros ven
// (presencia, refugios) pasa por estas funciones antes de salir del dispositivo.

/**
 * Difumina una posición: la ajusta a una grilla de `gridM` metros y le suma un
 * desplazamiento estable (por `salt`) de hasta 1/3 de celda. Así no se puede
 * triangular la ubicación real promediando muestras.
 */
export function fuzzPosition(p: LatLng, salt: string, gridM = 250): LatLng {
  // Grilla en metros sobre la latitud local para que sea aproximadamente cuadrada.
  const origin = { lat: Math.round(p.lat), lng: Math.round(p.lng) };
  const local = toLocalXY(origin, p);
  const snapped = {
    x: (Math.floor(local.x / gridM) + 0.5) * gridM,
    y: (Math.floor(local.y / gridM) + 0.5) * gridM,
  };
  const rng = createRng(`${salt}:${snapped.x}:${snapped.y}`);
  const jitter = gridM / 3;
  const center = fromLocalXY(origin, snapped);
  return offsetM(center, rng.range(-jitter, jitter), rng.range(-jitter, jitter));
}

/** Distancia aproximada para mostrar a otros jugadores ("~300 m"). */
export function approximateDistanceLabel(m: number): string {
  if (m < 150) return 'muy cerca';
  if (m < 1000) return `~${Math.round(m / 100) * 100} m`;
  return `~${(Math.round(m / 500) * 0.5).toFixed(1).replace('.', ',')} km`;
}
