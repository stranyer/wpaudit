import type { LatLng } from '../../core/types';

export interface LocationFix {
  position: LatLng;
  accuracyM: number;
  headingDeg: number | null;
  timestamp: number;
  /** Salto intencional (teletransporte del modo demo): no cuenta como velocidad ni distancia. */
  jump?: boolean;
}

export type LocationErrorCode = 'denied' | 'unavailable' | 'timeout' | 'unsupported';

export interface LocationProvider {
  readonly mode: 'gps' | 'demo';
  start(onFix: (fix: LocationFix) => void, onError: (code: LocationErrorCode) => void): Promise<void>;
  stop(): void;
}

export const LOCATION_ERROR_MESSAGES: Record<LocationErrorCode, string> = {
  denied: 'Permiso de ubicación denegado. Podés activarlo en los ajustes o jugar en modo demo.',
  unavailable: 'No se pudo obtener tu ubicación. Probá al aire libre o usá el modo demo.',
  timeout: 'El GPS tarda en responder. Seguimos intentando...',
  unsupported: 'Este dispositivo no tiene geolocalización. Usá el modo demo.',
};
