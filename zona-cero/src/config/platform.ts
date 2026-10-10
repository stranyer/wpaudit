import offlineBounds from './offlineMapBounds.json';

/**
 * Web demo: build publicada como página web de prueba (`npm run build:web-demo`).
 * Esa página no puede conectarse a servidores externos ni usar el GPS, así que el
 * mapa viene empaquetado (centro de Buenos Aires) y solo se juega en modo demo.
 */
export const WEB_DEMO = import.meta.env.VITE_WEB_DEMO === '1';

/** Zona cubierta por el mapa empaquetado de la web demo. */
export const OFFLINE_MAP_BOUNDS: { south: number; west: number; north: number; east: number } = offlineBounds;
