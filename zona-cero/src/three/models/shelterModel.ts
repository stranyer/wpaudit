// Refugio por niveles (1–5), acumulativo, sobre un disco-diorama de ~14 m de diámetro.
//
//   L1 Campamento improvisado: carpa, fogata, cajas, saco de dormir, troncos para sentarse.
//   L2 Barricadas:             + empalizada en arco con tablones, sacos terreros, caballos de frisa.
//   L3 Taller:                 + banco de trabajo con herramientas, lona sobre postes, chatarra.
//   L4 Torre de vigilancia:    + torre de madera con reflector giratorio (cono volumétrico falso).
//   L5 Fortaleza:              + muros de chapa ondulada (reemplazan la empalizada), portón,
//                                generador, reflectores en postes y bandera de facción.
//
// Convenciones: metros, y = 0 es la superficie del disco, centro en el origen. La entrada del
// campamento mira hacia +Z (la cámara por defecto está en +Z/+X mirando al centro).
// Todo lo estático se fusiona en 2 mallas (lambert + emisivo); lo animado va aparte.

import * as THREE from 'three';
import {
  PALETTE,
  PartBatch,
  basic,
  cloneMat,
  glowDisc,
  lambert,
  mat,
  rng,
  vcBasic,
  vcLambert,
} from './materials';
import { addCrate, addDebris, addRubble, createFlames, valueNoise } from './props';

export interface ShelterModel {
  root: THREE.Group;
  /** `elapsed` en segundos (tiempo absoluto, no delta). */
  update(elapsed: number): void;
  /** Centro de la fogata (local a `root`) para colgar una PointLight. */
  firePosition: THREE.Vector3;
}

export interface ShelterModelOptions {
  /** Color de la bandera de facción (nivel 5). */
  flagColor?: string;
}

export const SHELTER_RADIUS = 7;

const FIRE = new THREE.Vector3(0, 0, 0.5);
const GATE_HALF_ANGLE = 0.62; // rad: hueco de la entrada (hacia +Z)

type V3 = [number, number, number];

/** Punto sobre un anillo; el ángulo 0 apunta a +Z y crece hacia +X. */
function ring(r: number, a: number, y = 0): V3 {
  return [Math.sin(a) * r, y, Math.cos(a) * r];
}

// ---------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------

function buildBase(level: number): THREE.Mesh {
  const R = SHELTER_RADIUS;
  const rings = 8;
  const seg = 32;
  const r = rng(91);
  const pos: number[] = [];
  const nor: number[] = [];
  const col: number[] = [];
  const dirt = new THREE.Color(PALETTE.dirt);
  const dirtL = new THREE.Color(PALETTE.dirtLight);
  const ash = new THREE.Color('#191714');
  const gravel = new THREE.Color('#3a3b38');
  const tmp = new THREE.Color();
  const vert = (i: number, j: number): V3 => {
    const rad = (R * i) / rings;
    const a = ((j + (i % 2) * 0.5) / seg) * Math.PI * 2;
    const x = Math.sin(a) * rad;
    const z = Math.cos(a) * rad;
    const y = i === rings ? 0 : (valueNoise(x * 0.8, z * 0.8, 5) - 0.5) * 0.1;
    return [x, y, z];
  };
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  const c = new THREE.Vector3();
  const n = new THREE.Vector3();
  const tri = (p: V3, q: V3, s: V3) => {
    a.set(...p);
    b.set(...q);
    c.set(...s);
    n.subVectors(c, b).cross(new THREE.Vector3().subVectors(a, b)).normalize();
    if (n.y < 0) {
      n.negate();
      const t = b.clone();
      b.copy(c);
      c.copy(t);
    }
    const mx = (a.x + b.x + c.x) / 3;
    const mz = (a.z + b.z + c.z) / 3;
    const d = Math.hypot(mx, mz);
    const nz = valueNoise(mx * 0.5, mz * 0.5, 9);
    tmp.copy(dirt).lerp(dirtL, nz * 0.8);
    // sendero claro desde la entrada hasta la fogata
    if (mz > 0 && Math.abs(mx) < 1.0 + mz * 0.1) tmp.lerp(dirtL, 0.35);
    const fd = Math.hypot(mx - FIRE.x, mz - FIRE.z);
    if (fd < 1.3) tmp.lerp(ash, (1 - fd / 1.3) * 0.8);
    if (level >= 5 && valueNoise(mx * 0.7, mz * 0.7, 21) > 0.62) tmp.lerp(gravel, 0.6);
    tmp.multiplyScalar((0.85 + r() * 0.2) * (1 - Math.max(0, d - R * 0.8) * 0.12));
    pos.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
    for (let k = 0; k < 3; k++) {
      nor.push(n.x, n.y, n.z);
      col.push(tmp.r, tmp.g, tmp.b);
    }
  };
  for (let j = 0; j < seg; j++) tri([0, 0, 0], vert(1, j), vert(1, j + 1));
  for (let i = 1; i < rings; i++) {
    for (let j = 0; j < seg; j++) {
      if (i % 2 === 0) {
        tri(vert(i, j), vert(i + 1, j), vert(i + 1, j + 1));
        tri(vert(i, j), vert(i + 1, j + 1), vert(i, j + 1));
      } else {
        tri(vert(i, j), vert(i + 1, j + 1), vert(i, j + 1));
        tri(vert(i, j + 1), vert(i + 1, j + 1), vert(i + 1, j + 2));
      }
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeBoundingSphere();
  const m = new THREE.Mesh(g, vcLambert());
  m.name = 'shelterBase';
  return m;
}

// ---------------------------------------------------------------------------
// Piezas (en coordenadas locales; se fusionan en la batch estática)
// ---------------------------------------------------------------------------

function tent(): PartBatch {
  const b = new PartBatch(31, 0.06);
  const canvas = PALETTE.canvas;
  const canvasDark = '#3c4228';
  const len = 2.3;
  const h = 1.35;
  const half = 1.0;
  const slope = Math.hypot(half, h);
  const ang = Math.atan2(h, half);
  // dos faldones
  for (const sd of [1, -1]) {
    b.box(0.04, slope, len, canvas, { p: [(sd * half) / 2, h / 2, 0], r: [0, 0, sd * (Math.PI / 2 - ang)] });
  }
  // fondo triangular y entrada con solapas abiertas
  b.tri([-half, 0, -len / 2], [0, h, -len / 2], [half, 0, -len / 2], canvasDark, true);
  b.tri([-half, 0, len / 2], [-0.25, h * 0.75, len / 2 + 0.02], [-0.05, 0, len / 2 + 0.25], canvasDark, true);
  b.tri([half, 0, len / 2], [0.25, h * 0.75, len / 2 + 0.02], [0.05, 0, len / 2 + 0.25], canvasDark, true);
  b.tri([-0.2, h * 0.8, len / 2 - 0.02], [0.2, h * 0.8, len / 2 - 0.02], [0, h, len / 2 - 0.02], canvasDark, true);
  b.box(0.9, 0.02, len * 0.9, '#121410', { p: [0, 0.01, 0] }); // interior oscuro
  // cumbrera, palos y vientos
  b.cyl(0.03, 0.03, len + 0.3, 5, PALETTE.woodDark, { p: [0, h + 0.02, 0], r: [Math.PI / 2, 0, 0] });
  for (const z of [-len / 2 - 0.1, len / 2 + 0.1]) {
    b.cyl(0.03, 0.03, h + 0.1, 5, PALETTE.woodDark, { p: [0, (h + 0.1) / 2, z] });
    b.box(0.015, 0.015, 1.2, '#8a8270', { p: [0, h * 0.55, z + Math.sign(z) * 0.55], r: [Math.sign(z) * 1.05, 0, 0] }, 0);
  }
  // parches de reparación
  b.box(0.3, 0.25, 0.01, '#5a4a30', { p: [0.52, 0.65, 0.3], r: [0, 0, -(Math.PI / 2 - ang)] });
  return b;
}

function campfire(S: PartBatch): void {
  const r = rng(41);
  const [fx, , fz] = [FIRE.x, 0, FIRE.z];
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 + r() * 0.2;
    S.dodeca(0.13 + r() * 0.05, i % 3 ? '#4a4f52' : '#5a5f60', {
      p: [fx + Math.sin(a) * 0.6, 0.06, fz + Math.cos(a) * 0.6],
      r: [r() * 3, r() * 3, r() * 3],
      s: [1, 0.7, 1],
    });
  }
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.3;
    S.cyl(0.06, 0.07, 0.9, 6, i % 2 ? PALETTE.woodDark : '#2a1f16', {
      p: [fx + Math.sin(a) * 0.15, 0.12, fz + Math.cos(a) * 0.15],
      r: [0.3, a, Math.PI / 2 - 0.25],
    });
  }
  S.cyl(0.35, 0.4, 0.04, 8, '#0f0d0b', { p: [fx, 0.02, fz] }); // ceniza
  // trípode con olla
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2 + 0.5;
    S.cyl(0.02, 0.025, 1.5, 5, PALETTE.woodDark, {
      p: [fx + Math.sin(a) * 0.35, 0.68, fz + Math.cos(a) * 0.35],
      r: [Math.cos(a) * -0.27, 0, Math.sin(a) * 0.27],
    });
  }
  S.box(0.01, 0.35, 0.01, '#222', { p: [fx, 1.12, fz] }, 0);
  S.cyl(0.13, 0.11, 0.16, 8, '#2a2d2e', { p: [fx, 0.88, fz] });
}

function logSeat(len: number): PartBatch {
  const b = new PartBatch(43, 0.08);
  b.cyl(0.17, 0.19, len, 7, PALETTE.wood, { p: [0, 0.17, 0], r: [0, 0, Math.PI / 2] });
  b.cyl(0.12, 0.12, 0.02, 7, PALETTE.woodLight, { p: [len / 2 + 0.005, 0.17, 0], r: [0, 0, Math.PI / 2] });
  b.cyl(0.12, 0.12, 0.02, 7, PALETTE.woodLight, { p: [-len / 2 - 0.005, 0.17, 0], r: [0, 0, Math.PI / 2] });
  return b;
}

function bedroll(): PartBatch {
  const b = new PartBatch(47, 0.07);
  b.box(0.75, 0.05, 1.9, '#3b3a2c', { p: [0, 0.025, 0] }); // colchoneta
  b.box(0.7, 0.12, 1.3, '#5a2f24', { p: [0, 0.09, -0.25] }); // saco abierto
  b.cyl(0.13, 0.13, 0.72, 8, '#5a2f24', { p: [0, 0.13, 0.62], r: [0, 0, Math.PI / 2] }); // enrollado
  b.box(0.38, 0.1, 0.25, '#6b6250', { p: [0, 0.1, -0.85] }); // almohada/mochila
  return b;
}

function palisade(S: PartBatch, R: number): void {
  const r = rng(53);
  const start = GATE_HALF_ANGLE;
  const end = Math.PI * 2 - GATE_HALF_ANGLE;
  const step = 0.36 / R;
  const posts: V3[] = [];
  for (let a = start; a <= end + 1e-6; a += step) {
    const h = 1.7 + r() * 0.45;
    const [x, , z] = ring(R + (r() - 0.5) * 0.08, a);
    const col = r() < 0.5 ? PALETTE.wood : r() < 0.5 ? PALETTE.woodDark : '#4d3a2a';
    const lean = (r() - 0.5) * 0.08;
    S.cyl(0.1, 0.12, h, 5, col, { p: [x, h / 2, z], r: [lean, a, lean * 0.5] });
    S.cone(0.1, 0.32, 5, PALETTE.woodLight, { p: [x, h + 0.15, z], r: [lean, a, 0] });
    posts.push([x, h, z]);
  }
  // travesaños cada pocos postes (por dentro)
  for (let i = 0; i + 3 < posts.length; i += 3) {
    const p0 = posts[i];
    const p1 = posts[i + 3];
    const mx = (p0[0] + p1[0]) / 2;
    const mz = (p0[2] + p1[2]) / 2;
    const len = Math.hypot(p1[0] - p0[0], p1[2] - p0[2]) + 0.25;
    const ang = Math.atan2(p1[0] - p0[0], p1[2] - p0[2]);
    const inward = 0.14 / Math.hypot(mx, mz);
    for (const y of [0.55, 1.3]) {
      S.box(0.05, 0.14, len, PALETTE.woodDark, { p: [mx * (1 - inward), y + (r() - 0.5) * 0.08, mz * (1 - inward)], r: [0, ang, (r() - 0.5) * 0.06] });
    }
  }
  // tablones clavados en diagonal por fuera
  for (let i = 0; i < 8; i++) {
    const a = start + 0.2 + r() * (end - start - 0.4);
    const [x, , z] = ring(R + 0.15, a);
    S.box(1.3, 0.16, 0.04, '#6a5038', { p: [x, 0.9 + r() * 0.4, z], r: [0, a, (r() < 0.5 ? 1 : -1) * (0.5 + r() * 0.3)] });
  }
}

function sandbagStack(S: PartBatch, x: number, z: number, ry: number, rows: number, perRow: number): void {
  const r = rng(Math.floor(x * 13 + z * 7 + 61));
  const bw = 0.52;
  const bh = 0.17;
  const cs = Math.cos(ry);
  const sn = Math.sin(ry);
  for (let row = 0; row < rows; row++) {
    const n = perRow - (row % 2);
    for (let i = 0; i < n; i++) {
      const lx = (i - (n - 1) / 2) * bw * 0.96;
      const px = x + lx * cs;
      const pz = z - lx * sn;
      S.tbox(bw, bh, 0.32, { sx: 0.82, sz: 0.85 }, r() < 0.5 ? PALETTE.khaki : '#5e5640', {
        p: [px, row * bh * 0.92 + bh / 2, pz],
        r: [0, ry + (r() - 0.5) * 0.12, (r() - 0.5) * 0.04],
      });
    }
  }
}

function chevalDeFrise(S: PartBatch, x: number, z: number, ry: number): void {
  const len = 1.8;
  S.cyl(0.07, 0.07, len, 6, PALETTE.woodDark, { p: [x, 0.42, z], r: [0, ry, Math.PI / 2] });
  for (let i = 0; i < 4; i++) {
    const t = (i / 3 - 0.5) * (len - 0.3);
    const px = x + Math.cos(ry) * t;
    const pz = z - Math.sin(ry) * t;
    for (const s of [1, -1]) {
      S.cyl(0.04, 0.05, 1.2, 5, PALETTE.wood, { p: [px, 0.42, pz], r: [0, ry + Math.PI / 2, s * 0.8] });
    }
  }
}

function workbench(): PartBatch {
  const b = new PartBatch(67, 0.07);
  const w = 1.7;
  const d = 0.7;
  const h = 0.9;
  b.box(w, 0.08, d, PALETTE.woodLight, { p: [0, h, 0] });
  for (const [x, z] of [
    [w / 2 - 0.08, d / 2 - 0.08],
    [-w / 2 + 0.08, d / 2 - 0.08],
    [w / 2 - 0.08, -d / 2 + 0.08],
    [-w / 2 + 0.08, -d / 2 + 0.08],
  ] as const) {
    b.box(0.08, h, 0.08, PALETTE.woodDark, { p: [x, h / 2, z] });
  }
  b.box(w - 0.1, 0.04, d - 0.1, PALETTE.wood, { p: [0, 0.25, 0] }); // estante
  b.box(0.35, 0.18, 0.3, '#3d4244', { p: [-0.5, 0.36, 0] }); // caja de herramientas
  b.box(0.36, 0.04, 0.31, PALETTE.rust, { p: [-0.5, 0.46, 0] });
  // tornillo de banco
  b.box(0.16, 0.12, 0.14, '#3d4a50', { p: [w / 2 - 0.15, h + 0.1, d / 2 - 0.1] });
  b.box(0.04, 0.04, 0.22, '#8a9093', { p: [w / 2 - 0.15, h + 0.1, d / 2 + 0.05] });
  // martillo
  b.box(0.3, 0.025, 0.03, '#5a3a22', { p: [0.1, h + 0.055, 0.12], r: [0, 0.4, 0] });
  b.box(0.04, 0.05, 0.11, '#2a2e30', { p: [0.24, h + 0.07, 0.06], r: [0, 0.4, 0] });
  // serrucho
  b.tri([-0.45, h + 0.045, -0.15], [0.05, h + 0.045, -0.2], [-0.45, h + 0.045, -0.02], '#9aa0a3', true);
  b.box(0.1, 0.03, 0.08, '#5a3a22', { p: [-0.5, h + 0.055, -0.09] });
  // llave inglesa y tuercas
  b.box(0.22, 0.015, 0.04, '#7a8084', { p: [-0.15, h + 0.05, 0.2], r: [0, -0.6, 0] });
  b.box(0.06, 0.015, 0.05, '#7a8084', { p: [0.4, h + 0.05, -0.15] });
  // panel de herramientas detrás
  b.box(w, 0.8, 0.04, '#4d3a2a', { p: [0, h + 0.5, -d / 2 + 0.02] });
  b.box(0.04, 0.3, 0.02, '#7a8084', { p: [-0.5, h + 0.55, -d / 2 + 0.05] });
  b.box(0.25, 0.04, 0.02, '#5a3a22', { p: [-0.2, h + 0.6, -d / 2 + 0.05], r: [0, 0, 0.5] });
  b.box(0.05, 0.22, 0.02, '#8a9093', { p: [0.25, h + 0.5, -d / 2 + 0.05], r: [0, 0, -0.3] });
  b.cyl(0.08, 0.08, 0.03, 8, '#2a2e30', { p: [0.55, h + 0.6, -d / 2 + 0.06], r: [Math.PI / 2, 0, 0] });
  return b;
}

function tarpShelter(): PartBatch {
  const b = new PartBatch(71, 0.06);
  const tarp = '#4a5530';
  const pole = PALETTE.woodDark;
  const hw = 1.3;
  const hd = 1.0;
  const hf = 2.25;
  const hb = 1.85;
  for (const [x, z, h] of [
    [hw, hd, hf],
    [-hw, hd, hf],
    [hw, -hd, hb],
    [-hw, -hd, hb],
  ] as const) {
    b.cyl(0.04, 0.05, h, 5, pole, { p: [x, h / 2, z] });
  }
  const tilt = Math.atan2(hf - hb, hd * 2);
  // lona con una leve caída en el centro (dos paños)
  for (const sd of [1, -1]) {
    b.box(hw + 0.15, 0.025, hd * 2 + 0.3, tarp, {
      p: [(sd * (hw + 0.15)) / 2, (hf + hb) / 2 + 0.02 - 0.06, 0],
      r: [-tilt, 0, sd * 0.06],
    });
  }
  b.box(0.08, 0.06, hd * 2 + 0.3, '#3a4426', { p: [0, (hf + hb) / 2 - 0.08, 0], r: [-tilt, 0, 0] });
  // vientos
  b.box(0.012, 0.012, 1.3, '#8a8270', { p: [hw + 0.3, hf - 0.6, hd + 0.4], r: [0.9, 0.5, 0] }, 0);
  b.box(0.012, 0.012, 1.3, '#8a8270', { p: [-hw - 0.3, hf - 0.6, hd + 0.4], r: [0.9, -0.5, 0] }, 0);
  return b;
}

function scrapPile(): PartBatch {
  const b = new PartBatch(73, 0.08);
  const r = rng(73);
  for (let i = 0; i < 5; i++) {
    b.box(0.9 + r() * 0.4, 0.02, 0.6 + r() * 0.3, i % 2 ? '#5c6366' : '#6e4a2e', {
      p: [(r() - 0.5) * 0.4, 0.05 + i * 0.05, (r() - 0.5) * 0.3],
      r: [(r() - 0.5) * 0.3, r() * 3, (r() - 0.5) * 0.3],
    });
  }
  for (let i = 0; i < 4; i++) {
    b.cyl(0.04, 0.04, 1.2, 6, '#4a4f52', { p: [(r() - 0.5) * 0.5, 0.3, (r() - 0.5) * 0.5], r: [Math.PI / 2 + (r() - 0.5) * 0.4, r() * 3, 0] });
  }
  b.box(0.25, 0.35, 0.15, '#7a2a1e', { p: [0.7, 0.175, 0.2], r: [0, 0.4, 0] }); // bidón
  b.box(0.06, 0.05, 0.1, '#5a1e16', { p: [0.7, 0.37, 0.2], r: [0, 0.4, 0] });
  return b;
}

function watchtower(): PartBatch {
  const b = new PartBatch(79, 0.07);
  const H = 3.6;
  const base = 1.0;
  const top = 0.8;
  const lean = Math.atan((base - top) / H);
  for (const [sx, sz] of [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ] as const) {
    b.box(0.14, H + 0.05, 0.14, PALETTE.wood, {
      p: [(sx * (base + top)) / 2, H / 2, (sz * (base + top)) / 2],
      r: [sz * lean, 0, -sx * lean],
    });
  }
  // riostras en X en las cuatro caras
  for (const s of [1, -1]) {
    for (const lvl of [0, 1]) {
      const y0 = 0.25 + lvl * 1.65;
      const yc = y0 + 0.8;
      const off = base - ((base - top) * yc) / H;
      const span = off * 2;
      const len = Math.hypot(span, 1.6);
      const ang = Math.atan2(1.6, span);
      for (const d of [1, -1]) {
        b.box(0.05, 0.09, len, PALETTE.woodDark, { p: [s * (off + 0.1), yc, 0], r: [d * ang, 0, 0] });
        b.box(len, 0.09, 0.05, PALETTE.woodDark, { p: [0, yc, s * (off + 0.1)], r: [0, 0, d * ang] });
      }
    }
  }
  // plataforma
  b.box(2.0, 0.12, 2.0, PALETTE.woodLight, { p: [0, H, 0] });
  for (let i = 0; i < 5; i++) b.box(0.02, 0.125, 2.0, PALETTE.woodDark, { p: [-0.8 + i * 0.4, H + 0.005, 0] }, 0);
  // barandas y parapeto de tablas
  for (const [sx, sz] of [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ] as const) {
    b.box(0.09, 1.0, 0.09, PALETTE.wood, { p: [sx * 0.95, H + 0.5, sz * 0.95] });
  }
  for (const s of [1, -1]) {
    b.box(1.95, 0.5, 0.05, '#4d3a2a', { p: [0, H + 0.32, s * 0.97] });
    b.box(0.05, 0.5, 1.95, '#4d3a2a', { p: [s * 0.97, H + 0.32, 0] });
    b.box(2.0, 0.07, 0.07, PALETTE.woodDark, { p: [0, H + 0.98, s * 0.97] });
    b.box(0.07, 0.07, 2.0, PALETTE.woodDark, { p: [s * 0.97, H + 0.98, 0] });
  }
  // techo a cuatro aguas de chapa
  for (const [sx, sz] of [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ] as const) {
    b.box(0.06, 0.95, 0.06, PALETTE.woodDark, { p: [sx * 0.9, H + 1.45, sz * 0.9] });
  }
  b.cone(1.65, 0.75, 4, '#55595b', { p: [0, H + 2.25, 0], r: [0, Math.PI / 4, 0] });
  // escalera
  for (const s of [1, -1]) {
    b.box(0.05, H + 0.6, 0.05, PALETTE.woodDark, { p: [s * 0.25, (H + 0.6) / 2 - 0.1, 1.25], r: [-0.12, 0, 0] });
  }
  for (let i = 0; i < 9; i++) {
    const y = 0.3 + i * 0.42;
    b.box(0.5, 0.04, 0.04, PALETTE.wood, { p: [0, y, 1.25 - Math.sin(0.12) * (y - H / 2) + 0.02] });
  }
  return b;
}

function corrugatedWall(S: PartBatch, R: number): void {
  const r = rng(83);
  const start = GATE_HALF_ANGLE;
  const end = Math.PI * 2 - GATE_HALF_ANGLE;
  const pw = 1.25;
  const step = pw / R;
  const colors = ['#5c6366', '#4a4f52', '#6e4a2e', '#55595b', '#7a4a26', '#3e4446'];
  for (let a = start + step / 2; a < end; a += step) {
    const h = 2.3 + r() * 0.35;
    const [x, , z] = ring(R, a);
    const col = colors[Math.floor(r() * colors.length)];
    const rot: [number, number, number] = [(r() - 0.5) * 0.04, a, (r() - 0.5) * 0.03];
    S.box(pw * 1.02, h, 0.03, col, { p: [x, h / 2, z], r: rot });
    // ondulado: costillas verticales
    for (let k = 0; k < 5; k++) {
      const t = (k / 4 - 0.5) * (pw - 0.2);
      const px = x + Math.cos(a) * t;
      const pz = z - Math.sin(a) * t;
      S.box(0.06, h, 0.05, col, { p: [px, h / 2, pz], r: rot }, 0.12);
    }
    // postes detrás
    if (Math.round(a / step) % 2 === 0) {
      const [px, , pz] = ring(R - 0.12, a - step / 2);
      S.box(0.1, 2.7, 0.1, '#2a2e30', { p: [px, 1.35, pz] });
    }
    // alambre de púas arriba (zigzag)
    for (let k = 0; k < 3; k++) {
      const t = (k / 2 - 0.5) * pw * 0.66;
      const px = x + Math.cos(a) * t;
      const pz = z - Math.sin(a) * t;
      S.box(0.012, 0.25, 0.012, '#6a6f72', { p: [px, h + 0.08, pz], r: [0, a, k % 2 ? 0.7 : -0.7] }, 0);
    }
  }
  // portón abierto hacia afuera
  for (const s of [1, -1]) {
    const a = s * GATE_HALF_ANGLE;
    const [hx, , hz] = ring(R, a);
    // dirección "cerrada" (hacia el hueco) y normal hacia afuera
    const dx = -s * Math.cos(a);
    const dz = s * Math.sin(a);
    const nx = Math.sin(a);
    const nz = Math.cos(a);
    const open = 1.0;
    const ox = dx * Math.cos(open) + nx * Math.sin(open);
    const oz = dz * Math.cos(open) + nz * Math.sin(open);
    const gw = 1.9;
    S.box(gw, 2.4, 0.06, '#3e4446', { p: [hx + (ox * gw) / 2, 1.25, hz + (oz * gw) / 2], r: [0, Math.atan2(-oz, ox), 0] });
    S.box(gw * 0.9, 0.08, 0.08, '#25292b', { p: [hx + (ox * gw) / 2, 0.5, hz + (oz * gw) / 2], r: [0, Math.atan2(-oz, ox), 0.9] });
    S.box(0.18, 2.9, 0.18, '#25292b', { p: [hx, 1.45, hz] });
  }
}

function generator(): PartBatch {
  const b = new PartBatch(89, 0.07);
  b.box(1.1, 0.12, 0.7, '#2a2e30', { p: [0, 0.06, 0] });
  b.box(1.0, 0.62, 0.62, PALETTE.army, { p: [0, 0.43, 0] });
  b.box(0.5, 0.4, 0.02, '#2f3818', { p: [-0.15, 0.45, 0.315] });
  for (let i = 0; i < 4; i++) b.box(0.4, 0.025, 0.02, '#1e2412', { p: [-0.15, 0.32 + i * 0.08, 0.33] }, 0);
  b.box(0.22, 0.18, 0.03, '#1b1e20', { p: [0.3, 0.52, 0.32] }); // panel
  b.cyl(0.05, 0.05, 0.5, 6, '#3a3f42', { p: [0.38, 0.95, -0.18] }); // escape
  b.cyl(0.07, 0.07, 0.08, 6, '#1b1e20', { p: [0.38, 1.2, -0.18] });
  b.box(0.55, 0.32, 0.36, '#7a2a1e', { p: [-0.9, 0.16, 0.05], r: [0, 0.3, 0] }); // bidones
  b.box(0.08, 0.06, 0.12, '#5a1e16', { p: [-0.95, 0.35, 0.05], r: [0, 0.3, 0] });
  return b;
}

function floodlightPole(S: PartBatch, E: PartBatch, x: number, z: number): void {
  const h = 3.6;
  const face = Math.atan2(-x, -z); // mira al centro del campamento
  S.cyl(0.06, 0.08, h, 6, '#2a2e30', { p: [x, h / 2, z] });
  S.box(0.8, 0.06, 0.06, '#2a2e30', { p: [x, h, z], r: [0, face, 0] });
  for (const s of [1, -1]) {
    const lx = x + Math.cos(face) * 0.3 * s;
    const lz = z - Math.sin(face) * 0.3 * s;
    S.box(0.3, 0.24, 0.16, '#1b1e20', { p: [lx, h + 0.15, lz], r: [0.5, face, 0], o: 'YXZ' });
    const fx = lx + Math.sin(face) * 0.085;
    const fz = lz + Math.cos(face) * 0.085;
    E.box(0.24, 0.18, 0.02, '#fff2c8', { p: [fx, h + 0.11, fz], r: [0.5, face, 0], o: 'YXZ' }, 0);
  }
}

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

export function createShelterModel(level: number, opts: ShelterModelOptions = {}): ShelterModel {
  const L = Math.max(1, Math.min(5, Math.round(level || 1)));
  const root = new THREE.Group();
  root.name = `shelter:L${L}`;
  const S = new PartBatch(101, 0.07);
  const E = new PartBatch(102, 0);
  const updaters: ((t: number) => void)[] = [];

  root.add(buildBase(L));
  // falda del diorama
  S.cyl(SHELTER_RADIUS, SHELTER_RADIUS * 0.9, 0.8, 32, '#1d1913', { p: [0, -0.4, 0] }, 0.1);
  S.cyl(SHELTER_RADIUS * 0.9, SHELTER_RADIUS * 0.75, 0.5, 32, '#141210', { p: [0, -1.05, 0] }, 0.1);

  // ---------------- L1: campamento ----------------
  campfire(S);
  const flames = createFlames(1, { embers: true, seed: 3 });
  flames.root.position.copy(FIRE).setY(0.05);
  root.add(flames.root);
  updaters.push(flames.update);

  S.merge(tent(), { p: [-2.3, 0, -1.7], r: [0, 0.75, 0] });
  S.merge(bedroll(), { p: [1.7, 0, -1.1], r: [0, -0.35, 0] });
  S.merge(logSeat(1.4), { p: [-1.45, 0, 1.3], r: [0, 1.1, 0] });
  S.merge(logSeat(1.2), { p: [1.4, 0, 1.4], r: [0, -1.0, 0] });
  addCrate(S, 0.6, 'wood', { p: [2.6, 0, -2.3], ry: 0.3 });
  addCrate(S, 0.5, 'wood', { p: [2.55, 0.6, -2.3], ry: 0.6 });
  addCrate(S, 0.55, 'military', { p: [3.2, 0, -1.6], ry: -0.2 });
  addCrate(S, 0.45, 'wood', { p: [-0.9, 0, -2.6], ry: 0.9 });
  addDebris(S, { seed: 5, count: 10, width: 9, depth: 9 });
  // linterna junto a la carpa (emisiva, sin luz real)
  S.box(0.12, 0.2, 0.12, '#2a2e30', { p: [-1.3, 0.1, -0.9] });
  E.box(0.08, 0.1, 0.08, '#ffb75a', { p: [-1.3, 0.13, -0.9] }, 0);

  // ---------------- L2: barricadas ----------------
  if (L >= 2) {
    if (L < 5) palisade(S, 5.7);
    const sa = GATE_HALF_ANGLE - 0.2;
    const [ax, , az] = ring(5.55, sa);
    const [bx, , bz] = ring(5.55, -sa);
    sandbagStack(S, ax, az, sa, 3, 4);
    sandbagStack(S, bx, bz, -sa, 3, 4);
    const [cx, , cz] = ring(6.4, 0.25);
    chevalDeFrise(S, cx, cz, 0.25);
    const [dx, , dz] = ring(6.3, -0.3);
    chevalDeFrise(S, dx, dz, -0.3);
    addRubble(S, { seed: 17, count: 9, radius: 0.7, height: 0.25 }, -4.6, 2.6);
  }

  // ---------------- L3: taller ----------------
  if (L >= 3) {
    const wb: V3 = [-3.0, 0, 1.6];
    S.merge(workbench(), { p: wb, r: [0, 1.25, 0] });
    S.merge(tarpShelter(), { p: [wb[0] + 0.2, 0, wb[2]], r: [0, 1.25, 0] });
    S.merge(scrapPile(), { p: [-3.3, 0, -0.4], r: [0, 0.4, 0] });
    // lámpara colgante bajo la lona
    E.box(0.1, 0.14, 0.1, '#ffc87a', { p: [wb[0] + 0.25, 1.75, wb[2]] }, 0);
    S.box(0.01, 0.25, 0.01, '#222222', { p: [wb[0] + 0.25, 1.92, wb[2]] }, 0);
  }

  // ---------------- L4: torre de vigilancia ----------------
  if (L >= 4) {
    const tp: V3 = [3.3, 0, -3.3];
    S.merge(watchtower(), { p: tp, r: [0, -0.75, 0] });
    // reflector giratorio
    const pivot = new THREE.Group();
    pivot.position.set(tp[0], 3.6 + 1.05, tp[2]);
    root.add(pivot);
    const lampB = new PartBatch(111, 0.05);
    lampB.cyl(0.18, 0.22, 0.35, 8, '#1b1e20', { p: [0, 0, 0], r: [Math.PI / 2, 0, 0] });
    lampB.box(0.06, 0.25, 0.06, '#2a2e30', { p: [0, -0.18, 0] });
    const lampMesh = lampB.mesh(vcLambert(), 'spotlightBody');
    lampMesh.userData.mergeable = false;
    pivot.add(lampMesh);
    const lens = new THREE.Mesh(new THREE.CircleGeometry(0.17, 10), basic('#fff6d8'));
    lens.position.z = 0.18;
    pivot.add(lens);
    const beamLen = 10;
    const beamGeo = new THREE.CylinderGeometry(0.16, 2.0, beamLen, 14, 1, true);
    beamGeo.translate(0, -beamLen / 2, 0);
    beamGeo.rotateX(-Math.PI / 2);
    const beamMat = cloneMat(mat('#ffe9b0', { kind: 'basic', additive: true, opacity: 0.085, fog: true }));
    const beam = new THREE.Mesh(beamGeo, beamMat);
    beam.position.z = 0.15;
    beam.renderOrder = 4;
    pivot.add(beam);
    const lensGlow = glowDisc('#fff1c0', 0.55, 0.7);
    lensGlow.position.z = 0.2;
    pivot.add(lensGlow);
    pivot.rotation.x = 0.42;
    updaters.push((t) => {
      pivot.rotation.y = 2.4 + Math.sin(t * 0.32) * 1.2;
      beamMat.opacity = 0.075 + Math.sin(t * 11) * 0.004;
    });
  }

  // ---------------- L5: fortaleza ----------------
  if (L >= 5) {
    corrugatedWall(S, 5.9);
    const gp: V3 = [-3.4, 0, -2.9];
    S.merge(generator(), { p: gp, r: [0, 0.85, 0] });
    // cables por el suelo hacia los reflectores
    S.box(0.03, 0.02, 3.2, '#0d0d0d', { p: [-1.9, 0.02, -3.6], r: [0, 1.25, 0] }, 0);
    S.box(0.03, 0.02, 2.6, '#0d0d0d', { p: [-4.2, 0.02, -0.9], r: [0, 0.15, 0] }, 0);
    floodlightPole(S, E, -4.9, 0.6);
    floodlightPole(S, E, -0.9, -5.2);
    floodlightPole(S, E, 5.0, 1.0);
    // LED parpadeante del generador
    const ledMat = cloneMat(basic('#ff3a2a'));
    const led = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 0.03), ledMat);
    const ledLocal = new THREE.Vector3(0.3, 0.68, 0.33).applyAxisAngle(new THREE.Vector3(0, 1, 0), 0.85);
    led.position.set(gp[0] + ledLocal.x, ledLocal.y, gp[2] + ledLocal.z);
    led.rotation.y = 0.85;
    root.add(led);
    const ledOn = new THREE.Color('#ff3a2a');
    const ledOff = new THREE.Color('#3a0a08');
    updaters.push((t) => {
      ledMat.color.copy(Math.sin(t * 6) > 0.3 ? ledOn : ledOff);
    });

    // Bandera de facción
    const fp: V3 = [0.6, 0, -4.9];
    S.cyl(0.05, 0.07, 6.0, 6, '#3a3f42', { p: [fp[0], 3.0, fp[2]] });
    S.ico(0.09, '#8a9093', { p: [fp[0], 6.05, fp[2]] });
    const flagW = 1.6;
    const flagH = 1.0;
    const flagGeo = new THREE.PlaneGeometry(flagW, flagH, 8, 4);
    flagGeo.translate(flagW / 2, 0, 0);
    const fpos = flagGeo.getAttribute('position') as THREE.BufferAttribute;
    const baseX = new Float32Array(fpos.count);
    const fcol = new Float32Array(fpos.count * 3);
    const flagColor = new THREE.Color(opts.flagColor ?? PALETTE.rust);
    const emblem = new THREE.Color('#15181a');
    const cc = new THREE.Color();
    for (let i = 0; i < fpos.count; i++) {
      baseX[i] = fpos.getX(i);
      const u = fpos.getX(i) / flagW;
      const v = fpos.getY(i) / flagH + 0.5;
      // franja diagonal oscura (emblema simple)
      const band = Math.abs(u * 0.9 - v * 0.55 - 0.2) < 0.12;
      cc.copy(band ? emblem : flagColor).multiplyScalar(0.85 + ((i * 7) % 5) * 0.04);
      fcol[i * 3] = cc.r;
      fcol[i * 3 + 1] = cc.g;
      fcol[i * 3 + 2] = cc.b;
    }
    flagGeo.setAttribute('color', new THREE.BufferAttribute(fcol, 3));
    const flagMat = cloneMat(lambert('#ffffff', { vertexColors: true, side: THREE.DoubleSide }));
    const flag = new THREE.Mesh(flagGeo, flagMat);
    flag.position.set(fp[0] + 0.05, 5.4, fp[2]);
    flag.rotation.y = 0.4;
    flag.frustumCulled = false;
    root.add(flag);
    updaters.push((t) => {
      for (let i = 0; i < fpos.count; i++) {
        const x = baseX[i];
        const k = x / flagW;
        fpos.setZ(i, Math.sin(x * 3.2 - t * 4.2) * 0.14 * k + Math.sin(x * 5.1 - t * 6.3) * 0.04 * k);
      }
      fpos.needsUpdate = true;
    });
  }

  // Fusiona todo lo estático en 2 mallas
  S.attachTo(root, vcLambert(), 'shelterStatic');
  E.attachTo(root, vcBasic(), 'shelterEmissive');

  return {
    root,
    firePosition: new THREE.Vector3(FIRE.x, 0.6, FIRE.z),
    update(elapsed: number) {
      for (let i = 0; i < updaters.length; i++) updaters[i](elapsed);
    },
  };
}
