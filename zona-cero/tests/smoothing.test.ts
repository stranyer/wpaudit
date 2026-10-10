import { describe, expect, it } from 'vitest';
import { haversineM, offsetM } from '../src/core/geo';
import { GpsSmoother, shouldEmit } from '../src/services/location/smoothing';

const P = { lat: -34.6, lng: -58.38 };
const CFG = { minMoveM: 3, minIntervalMs: 1000, maxAcceptedAccuracyM: 150 };

describe('suavizado GPS', () => {
  it('reduce el ruido de lecturas imprecisas', () => {
    const s = new GpsSmoother();
    s.process(P, 5, 0);
    // Un salto de 60 m con precisión pésima apenas mueve la posición filtrada.
    const r = s.process(offsetM(P, 60, 0), 100, 1000);
    expect(haversineM(P, r.position)).toBeLessThan(10);
  });

  it('ignora movimientos mínimos y lecturas muy imprecisas', () => {
    const last = { position: P, timestamp: 0, accuracyM: 10 };
    expect(shouldEmit(null, last, CFG)).toBe(true);
    expect(shouldEmit(last, { position: offsetM(P, 1, 0), timestamp: 2000, accuracyM: 10 }, CFG)).toBe(false);
    expect(shouldEmit(last, { position: offsetM(P, 10, 0), timestamp: 2000, accuracyM: 10 }, CFG)).toBe(true);
    expect(shouldEmit(last, { position: offsetM(P, 10, 0), timestamp: 2000, accuracyM: 500 }, CFG)).toBe(false);
  });
});
