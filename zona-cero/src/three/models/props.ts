// Utilería low-poly para las escenas: auto abandonado, barriles, farola, cajas, escombros,
// suelo de asfalto agrietado, edificios en silueta, cielo y fuego.
//
// Convenciones: metros, y = 0 es el suelo. Cada función devuelve un `THREE.Group` cuyo origen
// es la base del objeto. Las piezas estáticas usan `PartBatch` (mallas fusionables) y se
// pueden aplanar con `mergeStatic` en la escena para ahorrar draw calls.

import * as THREE from 'three';
import {
  PALETTE,
  PartBatch,
  basic,
  cloneMat,
  glowDisc,
  mat,
  rng,
  vcBasic,
  vcLambert,
} from './materials';

// ---------------------------------------------------------------------------
// Ruido
// ---------------------------------------------------------------------------

function hash2(x: number, z: number, seed: number): number {
  const h = Math.sin(x * 127.1 + z * 311.7 + seed * 74.7) * 43758.5453;
  return h - Math.floor(h);
}

/** Ruido de valor 2D suave en [0, 1]. */
export function valueNoise(x: number, z: number, seed = 0): number {
  const xi = Math.floor(x);
  const zi = Math.floor(z);
  const xf = x - xi;
  const zf = z - zi;
  const u = xf * xf * (3 - 2 * xf);
  const v = zf * zf * (3 - 2 * zf);
  const a = hash2(xi, zi, seed);
  const b = hash2(xi + 1, zi, seed);
  const c = hash2(xi, zi + 1, seed);
  const d = hash2(xi + 1, zi + 1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/**
 * Parpadeo pseudoaleatorio de una luz vieja en [0, 1]: casi siempre encendida, con temblores
 * y cortes ocasionales. Determinista en función del tiempo.
 */
export function flicker(t: number, seed = 0): number {
  const base = 0.88 + Math.sin(t * 7.3 + seed) * 0.04 + Math.sin(t * 13.1 + seed * 2) * 0.03;
  const slot = Math.floor(t * 4 + seed * 17);
  const r = hash2(slot, seed, 3.1);
  // ~6% de los cuartos de segundo tienen un corte o bajón
  if (r > 0.94) {
    const local = t * 4 + seed * 17 - slot;
    return local < 0.5 ? 0.15 + r * 0.2 : base * 0.6;
  }
  return Math.min(1, base);
}

// ---------------------------------------------------------------------------
// Suelo
// ---------------------------------------------------------------------------

export interface GroundOptions {
  width?: number;
  depth?: number;
  /** Tamaño aproximado de cada faceta (m). */
  cell?: number;
  seed?: number;
  kind?: 'asphalt' | 'dirt';
  /** Calle a lo largo de Z: ancho de la calzada (las aceras quedan a los lados). 0 = sin calle. */
  road?: number;
  /** Cantidad de grietas. */
  cracks?: number;
}

/**
 * Suelo facetado con variación de color por vértice, manchas oscuras, grietas y (opcional)
 * calle con aceras y líneas pintadas gastadas. Centrado en el origen.
 */
export function createGround(opts: GroundOptions = {}): THREE.Group {
  const width = opts.width ?? 40;
  const depth = opts.depth ?? 40;
  const cell = opts.cell ?? 1.4;
  const seed = opts.seed ?? 3;
  const kind = opts.kind ?? 'asphalt';
  const road = opts.road ?? 0;
  const r = rng(seed);
  const group = new THREE.Group();
  group.name = 'ground';

  const base = new THREE.Color(kind === 'asphalt' ? PALETTE.asphalt : PALETTE.dirt);
  const alt = new THREE.Color(kind === 'asphalt' ? '#2a2d2e' : PALETTE.dirtLight);
  const sidewalk = new THREE.Color('#34383a');

  // Malla base: rejilla no indexada con alturas y colores ruidosos
  const segX = Math.max(2, Math.round(width / cell));
  const segZ = Math.max(2, Math.round(depth / cell));
  const pos: number[] = [];
  const col: number[] = [];
  const nor: number[] = [];
  const tmp = new THREE.Color();
  const hx = width / 2;
  const hz = depth / 2;
  const heightAt = (x: number, z: number) => {
    const edge = Math.abs(x) >= hx - 1e-3 || Math.abs(z) >= hz - 1e-3;
    if (edge) return 0;
    let y = (valueNoise(x * 0.9, z * 0.9, seed) - 0.5) * (kind === 'asphalt' ? 0.03 : 0.12);
    if (road > 0 && Math.abs(x) > road / 2) y += 0.14; // acera
    return y;
  };
  const va = new THREE.Vector3();
  const vb = new THREE.Vector3();
  const vc = new THREE.Vector3();
  const pushTri = (ax: number, az: number, bx: number, bz: number, cx: number, cz: number) => {
    va.set(ax, heightAt(ax, az), az);
    vb.set(bx, heightAt(bx, bz), bz);
    vc.set(cx, heightAt(cx, cz), cz);
    const mx = (ax + bx + cx) / 3;
    const mz = (az + bz + cz) / 3;
    const onWalk = road > 0 && Math.abs(mx) > road / 2;
    const n1 = valueNoise(mx * 0.35, mz * 0.35, seed + 1);
    const n2 = valueNoise(mx * 1.3, mz * 1.3, seed + 2);
    tmp.copy(onWalk ? sidewalk : base).lerp(alt, onWalk ? n2 * 0.4 : n1 * 0.55);
    const shade = 0.82 + n2 * 0.3 + (r() - 0.5) * 0.08;
    // Bordes más oscuros para que el suelo se funda con la niebla
    const fade = 1 - Math.min(1, Math.max(0, (Math.hypot(mx / hx, mz / hz) - 0.75) * 1.6)) * 0.4;
    tmp.multiplyScalar(shade * fade);
    vb.sub(va);
    vc.sub(va);
    const n = vb.clone().cross(vc).normalize();
    vb.add(va);
    vc.add(va);
    pos.push(va.x, va.y, va.z, vb.x, vb.y, vb.z, vc.x, vc.y, vc.z);
    for (let k = 0; k < 3; k++) {
      nor.push(n.x, n.y, n.z);
      col.push(tmp.r, tmp.g, tmp.b);
    }
  };
  // Si hay calle, forzamos líneas de rejilla en el borde de la acera
  const xs: number[] = [];
  for (let i = 0; i <= segX; i++) xs.push(-hx + (width * i) / segX);
  if (road > 0) {
    for (const edge of [-road / 2, road / 2]) {
      // reemplaza la línea más cercana por el borde exacto y añade una gemela 1 cm hacia afuera:
      // así el escalón de la acera es vertical (queda tapado por el bordillo).
      let best = 0;
      for (let i = 1; i < xs.length; i++) if (Math.abs(xs[i] - edge) < Math.abs(xs[best] - edge)) best = i;
      xs[best] = edge;
      xs.push(edge + Math.sign(edge) * 0.01);
    }
    xs.sort((a, b) => a - b);
  }
  for (let ix = 0; ix < xs.length - 1; ix++) {
    for (let iz = 0; iz < segZ; iz++) {
      const x0 = xs[ix];
      const x1 = xs[ix + 1];
      const z0 = -hz + (depth * iz) / segZ;
      const z1 = -hz + (depth * (iz + 1)) / segZ;
      // Evita triángulos inclinados entre calzada y acera: el borde exacto mantiene la altura de la calzada
      if ((ix + iz) % 2 === 0) {
        pushTri(x0, z0, x0, z1, x1, z1);
        pushTri(x0, z0, x1, z1, x1, z0);
      } else {
        pushTri(x0, z0, x0, z1, x1, z0);
        pushTri(x1, z0, x0, z1, x1, z1);
      }
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeBoundingSphere();
  const plane = new THREE.Mesh(g, vcLambert());
  plane.name = 'groundPlane';
  plane.userData.mergeable = true;
  group.add(plane);

  // Detalles: grietas, manchas, líneas pintadas, bordillo
  const det = new PartBatch(seed + 7, 0.05);
  const y0 = kind === 'asphalt' ? 0.022 : 0.07;
  const crackCount = opts.cracks ?? Math.round((width * depth) / 60);
  const lim = road > 0 ? road / 2 - 0.2 : hx * 0.85;
  for (let i = 0; i < crackCount; i++) {
    let x = (r() - 0.5) * 2 * lim;
    let z = (r() - 0.5) * depth * 0.8;
    let a = r() * Math.PI * 2;
    const segs = 4 + Math.floor(r() * 6);
    for (let s = 0; s < segs; s++) {
      const len = 0.25 + r() * 0.45;
      a += (r() - 0.5) * 1.1;
      const nx = x + Math.cos(a) * len;
      const nz = z + Math.sin(a) * len;
      const w = 0.035 * (1 - s / segs) + 0.012;
      det.flat(len + 0.03, w, '#08090a', { p: [(x + nx) / 2, y0, (z + nz) / 2], r: [0, -a, 0] }, 0);
      if (r() < 0.25) {
        const ba = a + (r() < 0.5 ? 1 : -1) * (0.6 + r() * 0.5);
        const bl = 0.2 + r() * 0.3;
        det.flat(bl, w * 0.7, '#0a0b0c', {
          p: [x + Math.cos(ba) * bl * 0.5, y0, z + Math.sin(ba) * bl * 0.5],
          r: [0, -ba, 0],
        }, 0);
      }
      x = nx;
      z = nz;
    }
  }
  const patchCount = Math.round((width * depth) / 90);
  for (let i = 0; i < patchCount; i++) {
    const x = (r() - 0.5) * 2 * lim;
    const z = (r() - 0.5) * depth * 0.85;
    const sx = 0.5 + r() * 1.6;
    const sz = 0.4 + r() * 1.2;
    const circle = new THREE.CircleGeometry(1, 7);
    circle.rotateX(-Math.PI / 2);
    det.add(circle, r() < 0.3 ? '#101314' : '#15191a', { p: [x, y0 - 0.006, z], r: [0, r() * 3, 0], s: [sx, 1, sz] }, 0.04);
    circle.dispose();
  }
  if (road > 0) {
    // Línea central discontinua gastada
    for (let z = -hz + 1; z < hz - 1; z += 3.4) {
      if (r() < 0.2) continue;
      const len = 1.1 + r() * 0.6;
      det.flat(0.13, len, '#6d6233', { p: [(r() - 0.5) * 0.04, y0 + 0.002, z], r: [0, (r() - 0.5) * 0.03, 0] }, 0.1);
    }
    // Bordillos
    for (const sd of [-1, 1]) {
      det.box(0.16, 0.17, depth, '#45494b', { p: [sd * (road / 2 + 0.06), 0.075, 0] }, 0.05);
      // Juntas de las baldosas de la acera
      for (let z = -hz + 1.5; z < hz; z += 1.5) {
        det.flat(width / 2 - road / 2 - 0.3, 0.025, '#24282a', {
          p: [sd * (road / 2 + (width / 2 - road / 2) / 2), 0.152, z],
        }, 0);
      }
    }
    // Alcantarilla
    det.cyl(0.36, 0.36, 0.02, 10, '#2c2f30', { p: [-road / 2 + 1.2, y0, -2.5] });
    det.box(0.5, 0.03, 0.04, '#191b1c', { p: [-road / 2 + 1.2, y0 + 0.012, -2.5] });
  }
  det.attachTo(group, vcLambert(), 'groundDetails');
  return group;
}

// ---------------------------------------------------------------------------
// Auto abandonado
// ---------------------------------------------------------------------------

export interface CarOptions {
  color?: string;
  seed?: number;
}

/** Sedán abandonado con vidrios rotos, óxido y una rueda pinchada. Largo en X (frente +X). */
export function createCar(opts: CarOptions = {}): THREE.Group {
  const seed = opts.seed ?? 5;
  const r = rng(seed);
  const c = new THREE.Color(opts.color ?? '#4d5a55');
  const body = '#' + c.getHexString();
  const bodyDark = '#' + c.clone().multiplyScalar(0.6).getHexString();
  const glass = '#121a1f';
  const hole = '#050606';
  const rust = ['#6e3f1f', '#5a3420', '#8a4a22'];
  const b = new PartBatch(seed, 0.06);

  const wheelY = 0.34;
  // Carrocería baja
  b.tbox(4.2, 0.5, 1.76, { sx: 0.98, sz: 0.96 }, body, { p: [0, 0.6, 0] });
  b.box(4.24, 0.16, 1.7, bodyDark, { p: [0, 0.31, 0] }); // faldón
  b.tbox(1.2, 0.07, 1.68, { sx: 0.98, sz: 0.97 }, body, { p: [1.45, 0.88, 0], r: [0, 0, -0.03] }); // capó
  // Cabina
  const cy = 1.13;
  b.tbox(2.3, 0.5, 1.6, { sx: 0.6, sz: 0.8, dx: -0.15 }, body, { p: [-0.2, cy, 0] });
  b.tbox(1.4, 0.05, 1.3, { sx: 0.98, sz: 0.98 }, body, { p: [-0.35, cy + 0.27, 0] }); // techo
  // Parabrisas (roto)
  const fwLean = Math.atan((1.15 - 0.54) / 0.5);
  const fwLen = Math.hypot(0.61, 0.5) * 0.86;
  b.box(0.025, fwLen, 1.18, glass, { p: [-0.2 + 0.86, cy, 0], r: [0, 0, fwLean] }, 0);
  b.box(0.03, 0.22, 0.32, hole, { p: [-0.2 + 0.88, cy + 0.03, 0.22], r: [0, 0, fwLean] }, 0);
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 + r() * 0.5;
    b.box(0.032, 0.012, 0.28 + r() * 0.2, '#7d8c92', {
      p: [-0.2 + 0.885, cy + 0.03 + Math.sin(a) * 0.1, 0.22 + Math.cos(a) * 0.12],
      r: [a, 0, fwLean],
    }, 0);
  }
  // Luneta trasera
  const rwLean = Math.atan((1.15 - 0.84) / 0.5);
  b.box(0.025, Math.hypot(0.31, 0.5) * 0.82, 1.15, glass, { p: [-0.2 - 1.0, cy, 0], r: [0, 0, -rwLean] }, 0);
  // Ventanas laterales: una rota con fragmentos
  const swLean = Math.atan((0.8 - 0.64) / 0.5);
  for (const sd of [1, -1]) {
    for (const [wx, wl, broken] of [
      [0.25, 0.75, sd === 1],
      [-0.6, 0.7, false],
    ] as const) {
      const zc = sd * 0.725;
      b.box(wl, 0.36, 0.02, broken ? hole : glass, { p: [wx - 0.2, cy + 0.01, zc], r: [sd * -swLean, 0, 0] }, 0);
      if (broken) {
        b.tri([wx - 0.2 - wl / 2, cy - 0.17, zc + sd * 0.025], [wx - 0.2 - wl / 2 + 0.25, cy - 0.17, zc + sd * 0.025], [wx - 0.2 - wl / 2 + 0.05, cy + 0.08, zc + sd * 0.01], glass, true);
        b.tri([wx - 0.2 + wl / 2, cy - 0.17, zc + sd * 0.025], [wx - 0.2 + wl / 2 - 0.15, cy - 0.17, zc + sd * 0.025], [wx - 0.2 + wl / 2 - 0.02, cy + 0.12, zc + sd * 0.0], glass, true);
      }
    }
    // Pilar B
    b.box(0.08, 0.4, 0.03, bodyDark, { p: [-0.37, cy + 0.01, sd * 0.73], r: [sd * -swLean, 0, 0] }, 0);
    // Juntas de puertas y manijas
    b.box(0.02, 0.42, 0.01, '#1a1d1e', { p: [0.55, 0.62, sd * 0.86] }, 0);
    b.box(0.02, 0.42, 0.01, '#1a1d1e', { p: [-0.45, 0.62, sd * 0.86] }, 0);
    b.box(0.14, 0.03, 0.02, '#2a2d2e', { p: [0.3, 0.74, sd * 0.87] }, 0);
    b.box(0.14, 0.03, 0.02, '#2a2d2e', { p: [-0.7, 0.74, sd * 0.87] }, 0);
    // Óxido
    for (let i = 0; i < 4; i++) {
      b.box(0.2 + r() * 0.5, 0.08 + r() * 0.2, 0.012, rust[i % rust.length], {
        p: [(r() - 0.5) * 3.6, 0.42 + r() * 0.3, sd * 0.875],
      }, 0.1);
    }
  }
  // Paragolpes, faros, parrilla
  b.box(0.14, 0.17, 1.74, '#25292b', { p: [2.12, 0.42, 0] });
  b.box(0.14, 0.17, 1.74, '#25292b', { p: [-2.12, 0.42, 0] });
  b.box(0.04, 0.16, 0.9, '#121415', { p: [2.1, 0.66, 0] });
  b.box(0.05, 0.12, 0.3, '#8c8c7a', { p: [2.1, 0.68, 0.62] });
  b.box(0.05, 0.12, 0.3, '#151515', { p: [2.1, 0.68, -0.62] });
  b.box(0.05, 0.12, 0.28, '#4a1010', { p: [-2.1, 0.7, 0.64] });
  b.box(0.05, 0.12, 0.28, '#2a0c0c', { p: [-2.1, 0.7, -0.64] });
  // Óxido en el capó y techo
  b.box(0.5, 0.012, 0.6, rust[0], { p: [1.3, 0.92, 0.3] }, 0.1);
  b.box(0.4, 0.012, 0.35, rust[2], { p: [-0.5, cy + 0.3, -0.25] }, 0.1);
  // Ruedas (delantera izquierda pinchada)
  for (const [wx, wz] of [
    [1.35, 0.8],
    [1.35, -0.8],
    [-1.35, 0.8],
    [-1.35, -0.8],
  ] as const) {
    const flat = wx > 0 && wz > 0;
    const sy = flat ? 0.72 : 1;
    b.cyl(0.34, 0.34, 0.24, 9, '#151617', { p: [wx, wheelY * sy, wz], r: [Math.PI / 2, 0, 0], s: [1, 1, sy] });
    b.cyl(0.17, 0.17, 0.25, 6, '#3d4244', { p: [wx, wheelY * sy, wz], r: [Math.PI / 2, 0, 0], s: [1, 1, sy] });
  }
  // Interior apenas visible (asientos)
  b.box(0.5, 0.35, 1.3, '#1d1a17', { p: [0.0, 0.95, 0] });
  b.box(0.5, 0.35, 1.3, '#1d1a17', { p: [-0.8, 0.95, 0] });

  const group = new THREE.Group();
  group.name = 'car';
  b.attachTo(group, vcLambert(), 'carBody');
  return group;
}

// ---------------------------------------------------------------------------
// Barriles
// ---------------------------------------------------------------------------

export type BarrelVariant = 'rust' | 'green' | 'grey' | 'orange';

const BARREL_COLORS: Record<BarrelVariant, [string, string]> = {
  rust: ['#6e3f1f', '#8a4a22'],
  green: [PALETTE.olive, '#2f3a20'],
  grey: ['#4a4f52', '#363a3c'],
  orange: [PALETTE.rust, '#8a4a22'],
};

function addBarrel(b: PartBatch, variant: BarrelVariant, r: () => number, x = 0, z = 0, tip = 0): void {
  const [main, ring] = BARREL_COLORS[variant];
  const h = 0.88;
  b.cyl(0.29, 0.29, h, 10, main, { p: [x, h / 2, z], r: [tip, 0, 0] });
  for (const y of [0.25, 0.63]) {
    b.cyl(0.302, 0.302, 0.04, 10, ring, { p: [x, y, z], r: [tip, 0, 0] });
  }
  b.cyl(0.27, 0.27, 0.02, 10, '#1e2122', { p: [x, h + 0.005, z] });
  // Parches de óxido
  for (let i = 0; i < 3; i++) {
    const a = r() * Math.PI * 2;
    b.box(0.12 + r() * 0.12, 0.1 + r() * 0.2, 0.01, i % 2 ? '#5a3420' : '#7a4520', {
      p: [x + Math.sin(a) * 0.292, 0.2 + r() * 0.5, z + Math.cos(a) * 0.292],
      r: [0, a, 0],
    }, 0.1);
  }
}

/** Barril metálico (0.88 m de alto). */
export function createBarrel(variant: BarrelVariant = 'rust', seed = 1): THREE.Group {
  const b = new PartBatch(seed, 0.06);
  addBarrel(b, variant, rng(seed));
  const g = new THREE.Group();
  g.name = 'barrel';
  b.attachTo(g, vcLambert(), 'barrel');
  return g;
}

// ---------------------------------------------------------------------------
// Fuego
// ---------------------------------------------------------------------------

export interface Flames {
  root: THREE.Group;
  update(t: number): void;
}

/** Llamas estilizadas (conos emisivos que parpadean) + resplandor en el suelo + brasas. */
export function createFlames(
  scale = 1,
  opts: { embers?: boolean; groundGlow?: boolean; seed?: number; /** Altura local del resplandor (sin escalar). */ glowY?: number } = {},
): Flames {
  const root = new THREE.Group();
  root.name = 'flames';
  const seed = opts.seed ?? 1;
  const outer = basic(PALETTE.flame);
  const mid = basic('#f0a040');
  const core = basic(PALETTE.flameCore);
  const cones: { m: THREE.Mesh; h: number; ph: number; sp: number }[] = [];
  const add = (material: THREE.Material, rad: number, h: number, x: number, z: number, ph: number) => {
    const g = new THREE.ConeGeometry(rad, h, 5, 1);
    g.translate(0, h / 2, 0);
    const m = new THREE.Mesh(g, material);
    m.position.set(x, 0, z);
    root.add(m);
    cones.push({ m, h, ph, sp: 9 + ph * 3 });
  };
  add(outer, 0.24, 0.62, 0, 0, seed * 0.7);
  add(outer, 0.15, 0.42, 0.13, 0.07, seed * 1.3 + 1);
  add(outer, 0.14, 0.38, -0.12, -0.06, seed * 0.4 + 2);
  add(mid, 0.16, 0.48, 0.02, 0.03, seed * 1.9 + 3);
  add(core, 0.1, 0.32, 0, 0.05, seed * 2.3 + 4);

  let glow: THREE.Mesh | null = null;
  if (opts.groundGlow ?? true) {
    glow = glowDisc(PALETTE.ember, 1.6, 0.35);
    glow.material = cloneMat(glow.material as THREE.MeshBasicMaterial);
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = opts.glowY ?? 0.03;
    root.add(glow);
  }

  let embers: THREE.Points | null = null;
  const EMBERS = 14;
  const emberSeeds = new Float32Array(EMBERS * 3);
  if (opts.embers) {
    const r = rng(seed * 31 + 7);
    for (let i = 0; i < EMBERS * 3; i++) emberSeeds[i] = r();
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(EMBERS * 3), 3));
    const pm = new THREE.PointsMaterial({
      color: '#ffb060',
      size: 0.06,
      transparent: true,
      opacity: 0.9,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    embers = new THREE.Points(geo, pm);
    embers.frustumCulled = false;
    root.add(embers);
  }

  root.scale.setScalar(scale);
  return {
    root,
    update(t: number) {
      for (let i = 0; i < cones.length; i++) {
        const c = cones[i];
        const n = Math.sin(t * c.sp + c.ph) * 0.5 + Math.sin(t * c.sp * 1.7 + c.ph * 2.1) * 0.3;
        const sy = 0.85 + n * 0.28;
        const sx = 1 - n * 0.12;
        c.m.scale.set(sx, sy, sx);
        c.m.rotation.y = t * (1.5 + i * 0.4) + c.ph;
        c.m.rotation.z = Math.sin(t * 3.1 + c.ph) * 0.08;
      }
      if (glow) {
        (glow.material as THREE.MeshBasicMaterial).opacity = 0.28 + Math.sin(t * 9.1) * 0.04 + Math.sin(t * 15.7) * 0.03;
      }
      if (embers) {
        const attr = embers.geometry.getAttribute('position') as THREE.BufferAttribute;
        const arr = attr.array as Float32Array;
        for (let i = 0; i < EMBERS; i++) {
          const a = emberSeeds[i * 3];
          const b = emberSeeds[i * 3 + 1];
          const c = emberSeeds[i * 3 + 2];
          const life = (t * (0.35 + a * 0.3) + b) % 1;
          arr[i * 3] = Math.sin(t * (1 + c) + a * 6) * 0.12 + (a - 0.5) * 0.2 + life * (c - 0.5) * 0.4;
          arr[i * 3 + 1] = 0.2 + life * 1.6;
          arr[i * 3 + 2] = Math.cos(t * (1.2 + b) + c * 6) * 0.12 + (b - 0.5) * 0.2;
        }
        attr.needsUpdate = true;
      }
    },
  };
}

/** Barril con fuego dentro. `lightPosition` en coordenadas locales. */
export function createFireBarrel(seed = 2): { root: THREE.Group; update(t: number): void; lightPosition: THREE.Vector3 } {
  const root = createBarrel('rust', seed);
  const flames = createFlames(0.8, { embers: true, groundGlow: true, seed, glowY: (-0.86 + 0.03) / 0.8 });
  flames.root.position.y = 0.86;
  root.add(flames.root);
  return { root, update: flames.update, lightPosition: new THREE.Vector3(0, 1.3, 0) };
}

// ---------------------------------------------------------------------------
// Farola
// ---------------------------------------------------------------------------

export interface StreetLamp {
  root: THREE.Group;
  /** Posición de la bombilla en coordenadas locales de `root` (para colgar una PointLight). */
  lightPosition: THREE.Vector3;
  /** Ajusta el brillo de bombilla/cono/charco de luz (0..1, p. ej. con `flicker`). */
  setIntensity(f: number): void;
}

/** Farola vieja con brazo hacia +X, bombilla naranja, cono de luz falso y charco en el suelo. */
export function createStreetLamp(opts: { height?: number; seed?: number } = {}): StreetLamp {
  const h = opts.height ?? 4.6;
  const b = new PartBatch(opts.seed ?? 9, 0.05);
  const metal = '#24282a';
  b.box(0.32, 0.3, 0.32, '#2e3234', { p: [0, 0.15, 0] });
  b.cyl(0.07, 0.1, h, 6, metal, { p: [0, h / 2, 0] });
  b.cyl(0.12, 0.12, 0.25, 6, metal, { p: [0, 0.4, 0] });
  // brazo curvo
  b.box(0.9, 0.06, 0.06, metal, { p: [0.42, h + 0.05, 0], r: [0, 0, 0.12] });
  b.box(0.3, 0.06, 0.06, metal, { p: [0.0, h - 0.05, 0], r: [0, 0, 1.0] });
  // cabezal
  b.tbox(0.5, 0.16, 0.3, { sx: 0.5, sz: 0.7 }, '#1e2122', { p: [0.88, h + 0.04, 0] });
  // cartel viejo pegado al poste
  b.box(0.02, 0.3, 0.22, '#5a5a4a', { p: [0.08, 2.0, 0], r: [0, 0, 0.03] });
  const root = new THREE.Group();
  root.name = 'streetLamp';
  b.attachTo(root, vcLambert(), 'lampBody');

  const bulbMat = cloneMat(basic('#ffcf8a'));
  const bulb = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.05, 0.16), bulbMat);
  bulb.position.set(0.88, h - 0.05, 0);
  root.add(bulb);

  const coneH = h - 0.1;
  const coneGeo = new THREE.CylinderGeometry(0.12, 1.5, coneH, 12, 1, true);
  const coneMat = cloneMat(mat(PALETTE.ember, { kind: 'basic', additive: true, opacity: 0.06, fog: true }));
  const cone = new THREE.Mesh(coneGeo, coneMat);
  cone.position.set(0.88, coneH / 2, 0);
  cone.renderOrder = 3;
  root.add(cone);

  const pool = glowDisc(PALETTE.ember, 2.2, 0.22);
  const poolMat = cloneMat(pool.material as THREE.MeshBasicMaterial);
  pool.material = poolMat;
  pool.rotation.x = -Math.PI / 2;
  pool.position.set(0.88, 0.03, 0);
  root.add(pool);

  const bulbOn = new THREE.Color('#ffd9a0');
  const bulbOff = new THREE.Color('#3a2a1a');
  return {
    root,
    lightPosition: new THREE.Vector3(0.88, h - 0.15, 0),
    setIntensity(f: number) {
      bulbMat.color.lerpColors(bulbOff, bulbOn, f);
      coneMat.opacity = 0.065 * f;
      poolMat.opacity = 0.24 * f;
    },
  };
}

// ---------------------------------------------------------------------------
// Cajas
// ---------------------------------------------------------------------------

export type CrateVariant = 'wood' | 'military';

export function addCrate(b: PartBatch, size: number, variant: CrateVariant, xf: { p: [number, number, number]; ry?: number }): void {
  const s = size;
  const [x, y, z] = xf.p;
  const ry = xf.ry ?? 0;
  const main = variant === 'wood' ? PALETTE.wood : PALETTE.olive;
  const edge = variant === 'wood' ? PALETTE.woodDark : '#2a331d';
  const cy = y + s / 2;
  const cs = Math.cos(ry);
  const sn = Math.sin(ry);
  const at = (lx: number, lz: number): [number, number] => [x + lx * cs + lz * sn, z - lx * sn + lz * cs];
  b.box(s, s, s, main, { p: [x, cy, z], r: [0, ry, 0] });
  const t = s * 0.08;
  // aristas verticales
  for (const [lx, lz] of [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ] as const) {
    const [px, pz] = at((lx * (s - t)) / 2 + lx * 0.004, (lz * (s - t)) / 2 + lz * 0.004);
    b.box(t, s * 1.01, t, edge, { p: [px, cy, pz], r: [0, ry, 0] });
  }
  // aristas horizontales arriba/abajo
  for (const yy of [y + t / 2, y + s - t / 2]) {
    for (const lz of [1, -1]) {
      const [px, pz] = at(0, (lz * (s - t)) / 2 + lz * 0.006);
      b.box(s * 1.01, t, t, edge, { p: [px, yy, pz], r: [0, ry, 0] });
    }
    for (const lx of [1, -1]) {
      const [px, pz] = at((lx * (s - t)) / 2 + lx * 0.006, 0);
      b.box(t, t, s * 1.01, edge, { p: [px, yy, pz], r: [0, ry, 0] });
    }
  }
  if (variant === 'wood') {
    // diagonales en dos caras
    for (const lz of [1, -1]) {
      const [px, pz] = at(0, (lz * s) / 2 + lz * 0.008);
      b.box(s * 1.15, t * 0.9, 0.012, edge, { p: [px, cy, pz], r: [0, ry, Math.PI / 4] });
    }
  } else {
    // franja de esténcil
    const [px, pz] = at(0, s / 2 + 0.008);
    b.box(s * 0.6, s * 0.12, 0.01, '#8a8a6a', { p: [px, cy + s * 0.15, pz], r: [0, ry, 0] }, 0);
  }
}

export function createCrate(size = 0.6, variant: CrateVariant = 'wood', seed = 4): THREE.Group {
  const b = new PartBatch(seed, 0.07);
  addCrate(b, size, variant, { p: [0, 0, 0] });
  const g = new THREE.Group();
  g.name = 'crate';
  b.attachTo(g, vcLambert(), 'crate');
  return g;
}

// ---------------------------------------------------------------------------
// Escombros
// ---------------------------------------------------------------------------

export interface RubbleOptions {
  seed?: number;
  count?: number;
  radius?: number;
  /** Altura del montón (0 = escombros dispersos planos). */
  height?: number;
  /** Incluir ladrillos/varillas/tablas. */
  mixed?: boolean;
}

export function addRubble(b: PartBatch, opts: RubbleOptions = {}, ox = 0, oz = 0): void {
  const r = rng(opts.seed ?? 8);
  const count = opts.count ?? 18;
  const radius = opts.radius ?? 1.2;
  const height = opts.height ?? 0.5;
  const concrete = ['#4a4f52', '#5a5f60', '#3e4244', '#66696a'];
  for (let i = 0; i < count; i++) {
    const a = r() * Math.PI * 2;
    const d = Math.sqrt(r()) * radius;
    const x = ox + Math.cos(a) * d;
    const z = oz + Math.sin(a) * d;
    const pile = height * Math.max(0, 1 - d / radius);
    const size = 0.1 + r() * 0.22 * (1 - (d / radius) * 0.5);
    const kind = r();
    if (opts.mixed !== false && kind < 0.18) {
      b.box(0.22, 0.07, 0.1, r() < 0.5 ? '#5a3a2e' : '#6a4434', {
        p: [x, pile * 0.8 + 0.035, z],
        r: [(r() - 0.5) * 0.6, r() * 3, (r() - 0.5) * 0.6],
      });
    } else if (opts.mixed !== false && kind < 0.24) {
      b.box(0.6 + r() * 0.5, 0.025, 0.025, '#5a3420', {
        p: [x, pile * 0.7 + 0.1, z],
        r: [(r() - 0.5) * 0.5, r() * 3, (r() - 0.5) * 0.8],
      }, 0);
    } else if (opts.mixed !== false && kind < 0.3) {
      b.box(0.9 + r() * 0.4, 0.04, 0.14, PALETTE.woodDark, {
        p: [x, pile * 0.7 + 0.04, z],
        r: [(r() - 0.5) * 0.3, r() * 3, (r() - 0.5) * 0.4],
      });
    } else {
      b.dodeca(size, concrete[Math.floor(r() * concrete.length)], {
        p: [x, pile * 0.75 + size * 0.45, z],
        r: [r() * 3, r() * 3, r() * 3],
        s: [1, 0.55 + r() * 0.4, 0.8 + r() * 0.4],
      });
    }
  }
}

export function createRubble(opts: RubbleOptions = {}): THREE.Group {
  const b = new PartBatch(opts.seed ?? 8, 0.08);
  addRubble(b, opts);
  const g = new THREE.Group();
  g.name = 'rubble';
  b.attachTo(g, vcLambert(), 'rubble');
  return g;
}

/** Basura dispersa: papeles, latas, bolsas negras y neumáticos. */
export function addDebris(b: PartBatch, opts: { seed?: number; count?: number; width?: number; depth?: number; ox?: number; oz?: number } = {}): void {
  const r = rng(opts.seed ?? 12);
  const count = opts.count ?? 20;
  const w = opts.width ?? 6;
  const d = opts.depth ?? 6;
  const ox = opts.ox ?? 0;
  const oz = opts.oz ?? 0;
  for (let i = 0; i < count; i++) {
    const x = ox + (r() - 0.5) * w;
    const z = oz + (r() - 0.5) * d;
    const k = r();
    if (k < 0.45) {
      b.flat(0.18 + r() * 0.12, 0.22 + r() * 0.1, r() < 0.5 ? '#6b675a' : '#4f4c42', {
        p: [x, 0.03, z],
        r: [(r() - 0.5) * 0.1, r() * 3, (r() - 0.5) * 0.1],
      }, 0.05);
    } else if (k < 0.65) {
      b.cyl(0.035, 0.035, 0.12, 6, r() < 0.5 ? '#7a2a1e' : '#56605e', {
        p: [x, 0.04, z],
        r: [Math.PI / 2, r() * 3, 0],
      });
    } else if (k < 0.85) {
      b.ico(0.22 + r() * 0.12, '#141618', { p: [x, 0.15, z], s: [1.1, 0.75, 1], r: [0, r() * 3, 0] });
    } else {
      const tire = new THREE.TorusGeometry(0.3, 0.1, 5, 9);
      b.add(tire, '#121314', { p: [x, 0.08, z], r: [Math.PI / 2 + (r() - 0.5) * 0.2, 0, 0] });
      tire.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Edificios en silueta
// ---------------------------------------------------------------------------

export interface BuildingOptions {
  width: number;
  height: number;
  depth: number;
  seed?: number;
  /** Proporción de ventanas encendidas (0..1). */
  lit?: number;
  color?: string;
}

/**
 * Bloque de edificio oscuro con ventanas (algunas encendidas en naranja tenue), cornisa y
 * algo de equipamiento en la azotea. Las ventanas se ponen en las caras ±X y +Z.
 */
export function createBuilding(o: BuildingOptions): THREE.Group {
  const seed = o.seed ?? 1;
  const r = rng(seed);
  const lit = o.lit ?? 0.08;
  const col = o.color ?? '#101214';
  const body = new PartBatch(seed, 0.05);
  const glow = new PartBatch(seed + 1, 0.25);
  const { width: w, height: h, depth: d } = o;
  body.box(w, h, d, col, { p: [0, h / 2, 0] });
  body.box(w + 0.2, 0.25, d + 0.2, '#22262a', { p: [0, h + 0.1, 0] }); // cornisa
  if (r() < 0.6) body.box(1.2, 1.0, 1.2, '#1e2123', { p: [(r() - 0.5) * w * 0.5, h + 0.6, (r() - 0.5) * d * 0.5] });
  if (r() < 0.5) {
    const tx = (r() - 0.5) * w * 0.4;
    body.cyl(0.6, 0.6, 1.1, 7, '#1b1e20', { p: [tx, h + 1.4, 0] });
    for (const [lx, lz] of [
      [0.4, 0.4],
      [-0.4, 0.4],
      [0.4, -0.4],
      [-0.4, -0.4],
    ] as const) {
      body.box(0.06, 0.8, 0.06, '#15181a', { p: [tx + lx, h + 0.45, lz] });
    }
  }
  const floorH = 3;
  const winW = 0.9;
  const winH = 1.3;
  const dark = '#0c0e0f';
  const lit1 = new THREE.Color(PALETTE.windowLit);
  const faces: { axis: 'x' | 'z'; sign: number; span: number; off: number }[] = [
    { axis: 'x', sign: 1, span: d, off: w / 2 },
    { axis: 'x', sign: -1, span: d, off: w / 2 },
    { axis: 'z', sign: 1, span: w, off: d / 2 },
  ];
  for (const f of faces) {
    const cols = Math.max(1, Math.floor((f.span - 1) / 2.2));
    for (let fl = 0; fl < Math.floor((h - 1.5) / floorH); fl++) {
      const y = 2.2 + fl * floorH;
      for (let c = 0; c < cols; c++) {
        const t = ((c + 0.5) / cols - 0.5) * (f.span - 1.2);
        const isLit = r() < lit;
        const p: [number, number, number] =
          f.axis === 'x' ? [f.sign * (f.off + 0.02), y, t] : [t, y, f.off + 0.02];
        const rot: [number, number, number] = f.axis === 'x' ? [0, (f.sign * Math.PI) / 2, 0] : [0, 0, 0];
        if (isLit) {
          const k = 0.35 + r() * 0.5;
          glow.plane(winW, winH, '#' + lit1.clone().multiplyScalar(k).getHexString(), { p, r: rot }, 0);
        } else if (r() < 0.85) {
          body.plane(winW, winH, dark, { p, r: rot }, 0.15);
        }
      }
    }
  }
  const g = new THREE.Group();
  g.name = 'building';
  body.attachTo(g, vcLambert(), 'buildingBody');
  glow.attachTo(g, vcBasic(), 'buildingWindows');
  return g;
}

// ---------------------------------------------------------------------------
// Cielo
// ---------------------------------------------------------------------------

export interface SkyOptions {
  radius?: number;
  top?: string;
  horizon?: string;
  /** Resplandor cálido lejano (incendios) hacia -Z. */
  glow?: string;
}

/** Cúpula de cielo con degradado por vértice (sin niebla, detrás de todo). */
export function createSkyDome(o: SkyOptions = {}): THREE.Mesh {
  const radius = o.radius ?? 90;
  const g = new THREE.SphereGeometry(radius, 16, 10);
  const top = new THREE.Color(o.top ?? '#040608');
  const hor = new THREE.Color(o.horizon ?? PALETTE.fog);
  const glow = new THREE.Color(o.glow ?? '#2a1a10');
  const pos = g.getAttribute('position');
  const colors = new Float32Array(pos.count * 3);
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i) / radius;
    const z = pos.getZ(i) / radius;
    const x = pos.getX(i) / radius;
    const t = Math.max(0, Math.min(1, (y + 0.05) / 0.6));
    c.copy(hor).lerp(top, Math.pow(t, 0.7));
    // brillo cálido bajo en el horizonte hacia -Z (y un poco a la derecha)
    const dir = Math.max(0, -z * 0.8 + x * 0.3);
    const low = Math.max(0, 1 - Math.abs(y - 0.02) / 0.25);
    c.lerp(glow, dir * low * 0.6);
    colors[i * 3] = c.r;
    colors[i * 3 + 1] = c.g;
    colors[i * 3 + 2] = c.b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  const m = new THREE.Mesh(
    g,
    mat('#ffffff', { kind: 'basic', vertexColors: true, side: THREE.BackSide, fog: false, depthWrite: false }),
  );
  m.name = 'sky';
  m.renderOrder = -10;
  m.frustumCulled = false;
  return m;
}

/** Luna pálida con halo, para colgar lejos en el cielo. */
export function createMoon(radius = 3): THREE.Group {
  const g = new THREE.Group();
  g.name = 'moon';
  const disc = new THREE.Mesh(new THREE.CircleGeometry(radius, 14), basic('#9aa6aa', { fog: false }));
  const halo = glowDisc('#7a8a96', radius * 3.2, 0.25);
  halo.position.z = -0.1;
  g.add(halo, disc);
  return g;
}
