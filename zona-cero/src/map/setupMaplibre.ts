import { addProtocol, setWorkerUrl } from 'maplibre-gl';
// MapLibre v6 busca su worker junto a su propio archivo; al empaquetar con Vite esa
// ruta cambia, así que le indicamos explícitamente dónde quedó el worker emitido.
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';
import { WEB_DEMO } from '../config/platform';

setWorkerUrl(workerUrl);

function decodeBase64(b64: string): ArrayBuffer {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

if (WEB_DEMO) {
  // zc://tiles/14/5534/9872  ->  ./offline-map/tiles/14/5534/9872.json
  // zc://fonts/Noto Sans Regular/0-255  ->  ./offline-map/fonts/Noto-Sans-Regular/0-255.json
  addProtocol('zc', async (params, abort) => {
    const path = decodeURIComponent(params.url.replace(/^zc:\/\//, '')).replace(/ /g, '-');
    const res = await fetch(new URL(`offline-map/${path}.json`, document.baseURI), { signal: abort.signal });
    // Fuera de la zona empaquetada no hay datos: se devuelve un tile vacío.
    if (!res.ok) return { data: new ArrayBuffer(0) };
    const { d } = (await res.json()) as { d: string };
    return { data: decodeBase64(d) };
  });
}
