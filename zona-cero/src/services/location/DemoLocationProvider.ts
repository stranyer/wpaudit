import { bearingDeg, haversineM, offsetM } from '../../core/geo';
import type { LatLng } from '../../core/types';
import type { LocationErrorCode, LocationFix, LocationProvider } from './types';

/**
 * Ubicación simulada para jugar desde una computadora.
 * Se mueve con un vector de dirección (joystick / teclado) o teletransportándose.
 */
export class DemoLocationProvider implements LocationProvider {
  readonly mode = 'demo' as const;
  private position: LatLng;
  private heading: number | null = null;
  private velocity = { x: 0, y: 0 }; // -1..1 (x = este, y = norte)
  /** Destino de la caminata automática ("caminar hasta acá"). */
  private target: LatLng | null = null;
  private speedMps: number;
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastTick = 0;
  private onFix: ((fix: LocationFix) => void) | null = null;

  constructor(
    start: LatLng,
    speedMps: number,
    /** Zona permitida (web demo: solo donde hay mapa empaquetado). */
    private readonly bounds: { south: number; west: number; north: number; east: number } | null = null,
  ) {
    this.position = this.clamp(start);
    this.speedMps = speedMps;
  }

  private clamp(p: LatLng): LatLng {
    const b = this.bounds;
    if (!b) return p;
    return {
      lat: Math.min(b.north, Math.max(b.south, p.lat)),
      lng: Math.min(b.east, Math.max(b.west, p.lng)),
    };
  }

  async start(onFix: (fix: LocationFix) => void, _onError: (code: LocationErrorCode) => void): Promise<void> {
    this.onFix = onFix;
    this.emit();
  }

  stop(): void {
    this.setVelocity(0, 0);
    this.onFix = null;
  }

  get current(): LatLng {
    return this.position;
  }

  /** Dirección de movimiento normalizada; (0,0) detiene. `multiplier` acelera (correr). */
  setVelocity(x: number, y: number, multiplier = 1): void {
    this.target = null;
    this.applyVelocity(x, y, multiplier);
  }

  /** Camina automáticamente hasta un punto (se detiene a `stopAtM` metros). */
  walkTo(p: LatLng, stopAtM = 12): void {
    if (haversineM(this.position, p) <= stopAtM) return;
    this.target = p;
    this.stopAtM = stopAtM;
    this.steerToTarget();
  }

  get walking(): boolean {
    return this.target !== null;
  }

  private stopAtM = 12;

  private steerToTarget(): void {
    if (!this.target) return;
    const b = (bearingDeg(this.position, this.target) * Math.PI) / 180;
    this.applyVelocity(Math.sin(b), Math.cos(b), 1.6);
  }

  private applyVelocity(x: number, y: number, multiplier: number): void {
    const len = Math.hypot(x, y);
    const k = len > 1 ? 1 / len : 1;
    this.velocity = { x: x * k * multiplier, y: y * k * multiplier };
    const moving = this.velocity.x !== 0 || this.velocity.y !== 0;
    if (moving && !this.timer) {
      this.lastTick = performance.now();
      this.timer = setInterval(() => this.tick(), 100);
    } else if (!moving && this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  teleport(p: LatLng): void {
    this.target = null;
    this.applyVelocity(0, 0, 1);
    const target = this.clamp(p);
    this.heading = bearingDeg(this.position, target);
    this.position = target;
    this.emit(true);
  }

  private tick(): void {
    const now = performance.now();
    const dt = Math.min(0.5, (now - this.lastTick) / 1000);
    this.lastTick = now;
    const north = this.velocity.y * this.speedMps * dt;
    const east = this.velocity.x * this.speedMps * dt;
    if (north === 0 && east === 0) return;
    this.heading = ((Math.atan2(east, north) * 180) / Math.PI + 360) % 360;
    this.position = this.clamp(offsetM(this.position, north, east));
    if (this.target) {
      if (haversineM(this.position, this.target) <= this.stopAtM) {
        this.target = null;
        this.applyVelocity(0, 0, 1);
      } else {
        this.steerToTarget();
      }
    }
    this.emit();
  }

  private emit(jump = false): void {
    this.onFix?.({ position: this.position, accuracyM: 5, headingDeg: this.heading, timestamp: Date.now(), jump });
  }
}
