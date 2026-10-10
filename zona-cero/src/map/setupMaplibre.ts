import { setWorkerUrl } from 'maplibre-gl';
// MapLibre v6 busca su worker junto a su propio archivo; al empaquetar con Vite esa
// ruta cambia, así que le indicamos explícitamente dónde quedó el worker emitido.
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';

setWorkerUrl(workerUrl);
