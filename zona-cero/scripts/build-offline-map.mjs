// Descarga un paquete de mapa offline (tiles vectoriales + tipografías del mapa)
// para la web demo, donde la página no puede conectarse a servidores externos.
// Uso: node scripts/build-offline-map.mjs   →  genera ./offline-map/
// Datos © OpenStreetMap, tiles de OpenFreeMap (requieren atribución, ya incluida en el mapa).

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';

// Centro de Buenos Aires: Palermo/Recoleta (norte) a San Telmo/Lezama (sur).
// Los límites se comparten con el juego (que limita la caminata demo a esta zona).
const BOUNDS = JSON.parse(readFileSync('src/config/offlineMapBounds.json', 'utf8'));
const ZOOMS = [13, 14];
const FONTS = ['Noto Sans Regular', 'Noto Sans Bold'];
const RANGES = ['0-255', '256-511', '8192-8447'];
const OUT = 'offline-map';

function curl(url) {
  // curl respeta la configuración de proxy del sistema (fetch de Node no siempre).
  return execFileSync('curl', ['-sSfL', '--retry', '3', url], { maxBuffer: 64 * 1024 * 1024 });
}

function tileXY(lat, lng, z) {
  const n = 2 ** z;
  const x = Math.floor(((lng + 180) / 360) * n);
  const r = (lat * Math.PI) / 180;
  const y = Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * n);
  return { x, y };
}

if (existsSync(OUT) && !process.argv.includes('--force')) {
  console.log(`Mapa offline ya generado en ./${OUT} (usá --force para regenerarlo).`);
  process.exit(0);
}
if (existsSync(OUT)) rmSync(OUT, { recursive: true });
const tilejson = JSON.parse(curl('https://tiles.openfreemap.org/planet').toString());
const template = tilejson.tiles[0];
let total = 0;
let count = 0;

for (const z of ZOOMS) {
  const a = tileXY(BOUNDS.north, BOUNDS.west, z);
  const b = tileXY(BOUNDS.south, BOUNDS.east, z);
  for (let x = a.x; x <= b.x; x++) {
    for (let y = a.y; y <= b.y; y++) {
      const data = curl(template.replace('{z}', z).replace('{x}', x).replace('{y}', y));
      const dir = join(OUT, 'tiles', String(z), String(x));
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, `${y}.json`), JSON.stringify({ d: data.toString('base64') }));
      total += data.length;
      count++;
    }
  }
}

for (const font of FONTS) {
  for (const range of RANGES) {
    const data = curl(`https://tiles.openfreemap.org/fonts/${encodeURIComponent(font)}/${range}.pbf`);
    const dir = join(OUT, 'fonts', font.replace(/ /g, '-'));
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `${range}.json`), JSON.stringify({ d: data.toString('base64') }));
    total += data.length;
    count++;
  }
}

console.log(`Mapa offline: ${count} archivos, ${(total / 1024 / 1024).toFixed(1)} MB en ./${OUT}`);
