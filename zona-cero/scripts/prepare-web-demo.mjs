// Arma la web demo publicable a partir de dist-web/:
// - copia el mapa empaquetado (offline-map/) junto a los assets,
// - genera zona-cero.html: solo el contenido de la página (título, estilos, raíz y script),
//   para hostings que envuelven la página en su propio <html>/<head>/<body>.
import { cpSync, readFileSync, writeFileSync } from 'node:fs';

const OUT = 'dist-web';
cpSync('offline-map', `${OUT}/offline-map`, { recursive: true });

const html = readFileSync(`${OUT}/index.html`, 'utf8');
const strip = (tag) => tag.replace(/\s+crossorigin(="[^"]*")?/g, '').replace(/="\.\//g, '="');
const scripts = [...html.matchAll(/<script type="module"[^>]*><\/script>/g)].map((m) => strip(m[0]));
const styles = [...html.matchAll(/<link rel="(?:stylesheet|modulepreload)"[^>]*>/g)].map((m) => strip(m[0]));
if (scripts.length === 0) throw new Error('No se encontró el script principal en dist-web/index.html');

const page = [
  '<title>Zona Cero</title>',
  '<meta name="theme-color" content="#0b0d0b">',
  ...styles,
  '<div id="root"></div>',
  ...scripts,
  '',
].join('\n');
writeFileSync(`${OUT}/zona-cero.html`, page);
console.log(`Web demo lista en ./${OUT} (página: zona-cero.html)`);
