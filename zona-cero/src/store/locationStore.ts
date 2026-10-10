import { create } from 'zustand';
import type { LatLng } from '../core/types';
import type { LocationErrorCode } from '../services/location/types';

export type LocationMode = 'gps' | 'demo';
export type LocationStatus = 'idle' | 'requesting' | 'active' | 'error';

interface LocationState {
  mode: LocationMode | null;
  status: LocationStatus;
  error: LocationErrorCode | null;
  position: LatLng | null;
  accuracyM: number;
  headingDeg: number | null;
  /** Interacciones bloqueadas por velocidad excesiva hasta este momento (ms). */
  speedLockedUntil: number;
  set(partial: Partial<Omit<LocationState, 'set'>>): void;
}

export const useLocationStore = create<LocationState>((set) => ({
  mode: null,
  status: 'idle',
  error: null,
  position: null,
  accuracyM: 0,
  headingDeg: null,
  speedLockedUntil: 0,
  set: (partial) => set(partial),
}));
