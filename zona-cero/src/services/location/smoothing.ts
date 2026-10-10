import { haversineM } from '../../core/geo';
import type { LatLng } from '../../core/types';

/**
 * Filtro de Kalman simple para posiciones GPS.
 * Suaviza el "temblor" del GPS sin agregar mucho retraso, ponderando cada lectura
 * por su precisión. `qMps` es cuánto creemos que puede moverse el jugador por segundo.
 */
export class GpsSmoother {
  private lat = 0;
  private lng = 0;
  private variance = -1;
  private lastTime = 0;

  constructor(private readonly qMps = 3) {}

  reset(): void {
    this.variance = -1;
  }

  process(p: LatLng, accuracyM: number, timestamp: number): { position: LatLng; accuracyM: number } {
    const acc = Math.max(1, accuracyM);
    if (this.variance < 0) {
      this.lat = p.lat;
      this.lng = p.lng;
      this.variance = acc * acc;
      this.lastTime = timestamp;
    } else {
      const dt = timestamp - this.lastTime;
      if (dt > 0) {
        this.variance += (dt * this.qMps * this.qMps) / 1000;
        this.lastTime = timestamp;
      }
      const k = this.variance / (this.variance + acc * acc);
      this.lat += k * (p.lat - this.lat);
      this.lng += k * (p.lng - this.lng);
      this.variance = (1 - k) * this.variance;
    }
    return { position: { lat: this.lat, lng: this.lng }, accuracyM: Math.sqrt(this.variance) };
  }
}

export interface ThrottleConfig {
  minMoveM: number;
  minIntervalMs: number;
  maxAcceptedAccuracyM: number;
}

/**
 * Decide si una nueva lectura merece actualizar el juego. Ahorra batería y renders:
 * ignora lecturas muy imprecisas (salvo la primera) y movimientos mínimos.
 */
export function shouldEmit(
  last: { position: LatLng; timestamp: number; accuracyM: number } | null,
  next: { position: LatLng; timestamp: number; accuracyM: number },
  cfg: ThrottleConfig,
): boolean {
  if (!last) return true;
  if (next.accuracyM > cfg.maxAcceptedAccuracyM) return false;
  const dt = next.timestamp - last.timestamp;
  if (dt < cfg.minIntervalMs) return false;
  const moved = haversineM(last.position, next.position);
  if (moved >= cfg.minMoveM) return true;
  // Refresco periódico o mejora notable de precisión aunque no se haya movido.
  return dt > 15_000 || next.accuracyM < last.accuracyM * 0.6;
}
