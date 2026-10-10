import type { PlacementData } from '../core/placement';

// Puente entre el mapa (que conoce las calles de los tiles vectoriales) y la lógica
// de juego, sin que el motor dependa de MapLibre.

let source: (() => PlacementData | null) | null = null;

export function setPlacementSource(fn: (() => PlacementData | null) | null): void {
  source = fn;
}

export function getMapPlacementData(): PlacementData | null {
  try {
    return source ? source() : null;
  } catch {
    return null;
  }
}
