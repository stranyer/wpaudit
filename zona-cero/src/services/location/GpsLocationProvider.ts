import { Capacitor } from '@capacitor/core';
import { GAME_CONFIG } from '../../config/gameConfig';
import { GpsSmoother, shouldEmit } from './smoothing';
import type { LocationErrorCode, LocationFix, LocationProvider } from './types';

type RawFix = { lat: number; lng: number; accuracy: number; heading: number | null; timestamp: number };

/**
 * GPS real. En Android (Capacitor) usa el plugin nativo de geolocalización, que maneja
 * los permisos del sistema; en navegador usa `navigator.geolocation`.
 */
export class GpsLocationProvider implements LocationProvider {
  readonly mode = 'gps' as const;
  private webWatchId: number | null = null;
  private nativeWatchId: string | null = null;
  private smoother = new GpsSmoother();
  private lastEmitted: LocationFix | null = null;
  private onFix: ((fix: LocationFix) => void) | null = null;

  async start(onFix: (fix: LocationFix) => void, onError: (code: LocationErrorCode) => void): Promise<void> {
    this.stop();
    this.onFix = onFix;
    this.smoother.reset();
    this.lastEmitted = null;
    const opts = {
      enableHighAccuracy: true,
      maximumAge: GAME_CONFIG.gps.maximumAgeMs,
      timeout: GAME_CONFIG.gps.timeoutMs,
    };

    if (Capacitor.isNativePlatform()) {
      const { Geolocation } = await import('@capacitor/geolocation');
      try {
        const perm = await Geolocation.checkPermissions();
        if (perm.location !== 'granted') {
          const req = await Geolocation.requestPermissions({ permissions: ['location'] });
          if (req.location !== 'granted') {
            onError('denied');
            return;
          }
        }
        this.nativeWatchId = await Geolocation.watchPosition(opts, (pos, err) => {
          if (err || !pos) {
            onError(this.mapNativeError(err));
            return;
          }
          this.handle({
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
            accuracy: pos.coords.accuracy,
            heading: pos.coords.heading ?? null,
            timestamp: pos.timestamp,
          });
        });
      } catch (err) {
        onError(this.mapNativeError(err));
      }
      return;
    }

    if (!('geolocation' in navigator)) {
      onError('unsupported');
      return;
    }
    this.webWatchId = navigator.geolocation.watchPosition(
      (pos) =>
        this.handle({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
          heading: Number.isFinite(pos.coords.heading) ? pos.coords.heading : null,
          timestamp: pos.timestamp,
        }),
      (err) => onError(err.code === err.PERMISSION_DENIED ? 'denied' : err.code === err.TIMEOUT ? 'timeout' : 'unavailable'),
      opts,
    );
  }

  stop(): void {
    if (this.webWatchId !== null) {
      navigator.geolocation.clearWatch(this.webWatchId);
      this.webWatchId = null;
    }
    if (this.nativeWatchId !== null) {
      const id = this.nativeWatchId;
      this.nativeWatchId = null;
      void import('@capacitor/geolocation').then(({ Geolocation }) => Geolocation.clearWatch({ id }));
    }
    this.onFix = null;
  }

  private handle(raw: RawFix): void {
    if (!this.onFix) return;
    const smoothed = this.smoother.process({ lat: raw.lat, lng: raw.lng }, raw.accuracy, raw.timestamp);
    const fix: LocationFix = {
      position: smoothed.position,
      accuracyM: raw.accuracy,
      headingDeg: raw.heading,
      timestamp: raw.timestamp,
    };
    if (!shouldEmit(this.lastEmitted, fix, GAME_CONFIG.gps)) return;
    this.lastEmitted = fix;
    this.onFix(fix);
  }

  private mapNativeError(err: unknown): LocationErrorCode {
    const msg = err instanceof Error ? err.message.toLowerCase() : String(err ?? '').toLowerCase();
    if (msg.includes('denied') || msg.includes('permission')) return 'denied';
    if (msg.includes('timeout')) return 'timeout';
    if (msg.includes('disabled') || msg.includes('not available')) return 'unavailable';
    return 'unavailable';
  }
}
