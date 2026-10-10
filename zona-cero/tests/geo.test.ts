import { describe, expect, it } from 'vitest';
import {
  cellId,
  cellOf,
  cellsAround,
  formatDistance,
  haversineM,
  offsetM,
  pointInPolygon,
  snapToSegments,
} from '../src/core/geo';

const OBELISCO = { lat: -34.60372, lng: -58.38159 };
const PLAZA_DE_MAYO = { lat: -34.6083, lng: -58.3712 };

describe('geo', () => {
  it('calcula distancias reales con haversine', () => {
    const d = haversineM(OBELISCO, PLAZA_DE_MAYO);
    expect(d).toBeGreaterThan(1000);
    expect(d).toBeLessThan(1150);
  });

  it('offsetM desplaza la cantidad de metros pedida', () => {
    const p = offsetM(OBELISCO, 100, 0);
    expect(haversineM(OBELISCO, p)).toBeCloseTo(100, 0);
    const q = offsetM(OBELISCO, 0, -250);
    expect(haversineM(OBELISCO, q)).toBeCloseTo(250, 0);
  });

  it('la grilla de celdas es determinística y vecina', () => {
    const c = cellOf(OBELISCO);
    expect(cellId(cellOf(OBELISCO))).toBe(cellId(c));
    const around = cellsAround(OBELISCO, 2);
    expect(around).toHaveLength(25);
    expect(around.map(cellId)).toContain(cellId(c));
  });

  it('ajusta un punto al segmento más cercano dentro del máximo', () => {
    const a = offsetM(OBELISCO, 0, -100);
    const b = offsetM(OBELISCO, 0, 100);
    const raw = offsetM(OBELISCO, 30, 10);
    const snapped = snapToSegments(raw, [[a, b]], 50);
    expect(snapped).not.toBeNull();
    expect(snapped!.distanceM).toBeCloseTo(30, 0);
    expect(snapToSegments(offsetM(OBELISCO, 80, 0), [[a, b]], 50)).toBeNull();
  });

  it('detecta puntos dentro de polígonos con agujeros', () => {
    const outer = [offsetM(OBELISCO, -100, -100), offsetM(OBELISCO, -100, 100), offsetM(OBELISCO, 100, 100), offsetM(OBELISCO, 100, -100)];
    const hole = [offsetM(OBELISCO, -20, -20), offsetM(OBELISCO, -20, 20), offsetM(OBELISCO, 20, 20), offsetM(OBELISCO, 20, -20)];
    expect(pointInPolygon(offsetM(OBELISCO, 50, 50), [outer, hole])).toBe(true);
    expect(pointInPolygon(OBELISCO, [outer, hole])).toBe(false);
    expect(pointInPolygon(offsetM(OBELISCO, 200, 0), [outer])).toBe(false);
  });

  it('formatea distancias en español', () => {
    expect(formatDistance(35.4)).toBe('35 m');
    expect(formatDistance(1234)).toBe('1,2 km');
  });
});
