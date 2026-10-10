// Paleta, caché de materiales y utilidades de geometría low-poly compartidas.
//
// Estrategia de rendimiento:
// - Los materiales salen de una caché global (`mat`, `lambert`, `basic`) y se marcan con
//   `userData.shared = true`. Nunca se mutan: si una instancia necesita cambiar color u
//   opacidad (p. ej. el destello rojo de un zombie al recibir un golpe) se usa `cloneMat`.
// - La mayoría de los modelos se construyen con `PartBatch`, que fusiona muchas piezas
//   (cajas, cilindros, icosaedros…) en UNA geometría no indexada con colores por vértice.
//   Así un modelo entero se dibuja con un solo material (`vcLambert`) y pocas llamadas.
// - `mergeStatic` fusiona las mallas estáticas de un grupo por material (1 draw call por material).

import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Paleta
// ---------------------------------------------------------------------------

export const PALETTE = {
  // Base oscura
  black: '#0b0d0b',
  coal: '#15181a',
  charcoal: '#2a2e30',
  slate: '#4a4f52',
  concrete: '#5a5f60',
  // Verdes militares
  olive: '#3d4a2a',
  army: '#4b5320',
  moss: '#6f8a4a',
  // Acentos naranjas
  rust: '#c8742c',
  ember: '#e08a3c',
  // Pieles zombie
  skinWalker: '#7d8a6a',
  skinPale: '#8f9a78',
  skinBloater: '#9aa45a',
  skinBrute: '#6f7b5c',
  // Varios
  blood: '#4a0808',
  bloodBright: '#7a1212',
  toxic: '#8fa83a',
  bone: '#b9b29a',
  wood: '#5a4330',
  woodDark: '#3b2c20',
  woodLight: '#7a5d40',
  canvas: '#545c38',
  dirt: '#2e2920',
  dirtLight: '#3d362a',
  asphalt: '#1d2022',
  metal: '#5c6366',
  metalDark: '#363b3e',
  denim: '#2c3742',
  cloth: '#6b6250',
  khaki: '#6e6448',
  eye: '#ffa531',
  eyeHot: '#fff0a8',
  flame: '#e08a3c',
  flameCore: '#ffd27a',
  windowLit: '#c8742c',
  fog: '#0c1012',
  sky: '#06080a',
} as const;

// ---------------------------------------------------------------------------
// Caché de materiales
// ---------------------------------------------------------------------------

export type MatKind = 'lambert' | 'basic' | 'standard';

export interface MatOptions {
  kind?: MatKind;
  /** flatShading (por defecto true en lambert/standard). */
  flat?: boolean;
  transparent?: boolean;
  opacity?: number;
  emissive?: THREE.ColorRepresentation;
  emissiveIntensity?: number;
  side?: THREE.Side;
  vertexColors?: boolean;
  depthWrite?: boolean;
  /** Blending aditivo (brillos, fuego, conos de luz). */
  additive?: boolean;
  fog?: boolean;
  roughness?: number;
  metalness?: number;
  toneMapped?: boolean;
}

const materialCache = new Map<string, THREE.Material>();

function colorKey(color: THREE.ColorRepresentation): string {
  return new THREE.Color(color).getHexString();
}

function optsKey(color: THREE.ColorRepresentation, o: MatOptions): string {
  return [
    o.kind ?? 'lambert',
    colorKey(color),
    o.flat ?? '',
    o.transparent ?? '',
    o.opacity ?? '',
    o.emissive !== undefined ? colorKey(o.emissive) : '',
    o.emissiveIntensity ?? '',
    o.side ?? '',
    o.vertexColors ?? '',
    o.depthWrite ?? '',
    o.additive ?? '',
    o.fog ?? '',
    o.roughness ?? '',
    o.metalness ?? '',
    o.toneMapped ?? '',
  ].join('|');
}

function createMaterial(color: THREE.ColorRepresentation, o: MatOptions): THREE.Material {
  const kind = o.kind ?? 'lambert';
  const common = {
    color,
    transparent: o.transparent ?? (o.additive || (o.opacity !== undefined && o.opacity < 1)),
    opacity: o.opacity ?? 1,
    side: o.side ?? THREE.FrontSide,
    vertexColors: o.vertexColors ?? false,
    fog: o.fog ?? true,
  };
  let m: THREE.Material;
  if (kind === 'basic') {
    m = new THREE.MeshBasicMaterial(common);
  } else if (kind === 'standard') {
    m = new THREE.MeshStandardMaterial({
      ...common,
      flatShading: o.flat ?? true,
      roughness: o.roughness ?? 0.9,
      metalness: o.metalness ?? 0,
      emissive: o.emissive ?? 0x000000,
      emissiveIntensity: o.emissiveIntensity ?? 1,
    });
  } else {
    m = new THREE.MeshLambertMaterial({
      ...common,
      flatShading: o.flat ?? true,
      emissive: o.emissive ?? 0x000000,
      emissiveIntensity: o.emissiveIntensity ?? 1,
    });
  }
  if (o.depthWrite !== undefined) m.depthWrite = o.depthWrite;
  if (o.additive) {
    m.blending = THREE.AdditiveBlending;
    if (o.depthWrite === undefined) m.depthWrite = false;
  }
  if (o.toneMapped !== undefined) m.toneMapped = o.toneMapped;
  return m;
}

/**
 * Material cacheado y COMPARTIDO. No lo mutes: para cambios por instancia usa `cloneMat`.
 */
export function mat(color: THREE.ColorRepresentation, opts: MatOptions = {}): THREE.Material {
  const key = optsKey(color, opts);
  let m = materialCache.get(key);
  if (!m) {
    m = createMaterial(color, opts);
    m.userData.shared = true;
    m.name = `shared:${key}`;
    materialCache.set(key, m);
  }
  return m;
}

export function lambert(color: THREE.ColorRepresentation, opts: Omit<MatOptions, 'kind'> = {}): THREE.MeshLambertMaterial {
  return mat(color, { ...opts, kind: 'lambert' }) as THREE.MeshLambertMaterial;
}

export function basic(color: THREE.ColorRepresentation, opts: Omit<MatOptions, 'kind'> = {}): THREE.MeshBasicMaterial {
  return mat(color, { ...opts, kind: 'basic' }) as THREE.MeshBasicMaterial;
}

/** Lambert facetado con colores por vértice (el material de casi todos los modelos). */
export function vcLambert(): THREE.MeshLambertMaterial {
  return lambert('#ffffff', { vertexColors: true });
}

/** Material sin iluminación con colores por vértice (ventanas encendidas, bombillas, ojos). */
export function vcBasic(): THREE.MeshBasicMaterial {
  return basic('#ffffff', { vertexColors: true });
}

/** Copia NO compartida de un material (para mutarlo por instancia sin tocar la caché). */
export function cloneMat<T extends THREE.Material>(m: T): T {
  const c = m.clone() as T;
  c.userData = { ...m.userData, shared: false };
  c.name = m.name.replace(/^shared:/, 'instance:');
  return c;
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

/** PRNG determinista (mulberry32) para que los modelos se vean igual siempre. */
export function rng(seed: number): () => number {
  let a = seed >>> 0 || 0x9e3779b9;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function clamp01(x: number): number {
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

export function smooth01(x: number): number {
  const t = clamp01(x);
  return t * t * (3 - 2 * t);
}

/**
 * Libera geometrías y materiales de un árbol de objetos.
 * Con `keepShared` conserva los recursos marcados como compartidos (caché),
 * útil para reconstruir un modelo sin forzar la recompilación de shaders.
 */
export function disposeTree(root: THREE.Object3D, keepShared = false): void {
  const seen = new Set<object>();
  const release = (r: THREE.BufferGeometry | THREE.Material) => {
    if (seen.has(r)) return;
    seen.add(r);
    if (keepShared && r.userData.shared) return;
    if (r instanceof THREE.Material) {
      // Liberar texturas si las hubiera (los modelos actuales no usan).
      for (const value of Object.values(r)) {
        if (value instanceof THREE.Texture) value.dispose();
      }
    }
    r.dispose();
  };
  root.traverse((obj) => {
    const o = obj as THREE.Object3D & {
      geometry?: THREE.BufferGeometry;
      material?: THREE.Material | THREE.Material[];
    };
    if (o.geometry instanceof THREE.BufferGeometry) release(o.geometry);
    if (Array.isArray(o.material)) o.material.forEach(release);
    else if (o.material instanceof THREE.Material) release(o.material);
  });
}

/** Cuenta triángulos aproximados de un árbol (para depurar el presupuesto). */
export function countTriangles(root: THREE.Object3D): number {
  let tris = 0;
  root.traverse((obj) => {
    const m = obj as THREE.Mesh;
    if (!m.isMesh || !m.geometry) return;
    const g = m.geometry;
    const n = g.index ? g.index.count : (g.getAttribute('position')?.count ?? 0);
    const count = Math.min(n, g.drawRange.count);
    const inst = (m as THREE.InstancedMesh).isInstancedMesh ? (m as THREE.InstancedMesh).count : 1;
    tris += Math.floor(count / 3) * inst;
  });
  return tris;
}

// ---------------------------------------------------------------------------
// Geometrías compartidas
// ---------------------------------------------------------------------------

const geometryCache = new Map<string, THREE.BufferGeometry>();

function sharedGeometry(key: string, make: () => THREE.BufferGeometry): THREE.BufferGeometry {
  let g = geometryCache.get(key);
  if (!g) {
    g = make();
    g.userData.shared = true;
    geometryCache.set(key, g);
  }
  return g;
}

/** Disco con degradado radial de alfa (vértice central opaco, borde transparente). */
export function radialDiscGeometry(segments = 20): THREE.BufferGeometry {
  return sharedGeometry(`radialDisc:${segments}`, () => {
    const g = new THREE.CircleGeometry(1, segments);
    const count = g.getAttribute('position').count;
    const colors = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) {
      colors[i * 4] = 1;
      colors[i * 4 + 1] = 1;
      colors[i * 4 + 2] = 1;
      colors[i * 4 + 3] = i === 0 ? 1 : 0; // el vértice 0 es el centro
    }
    g.setAttribute('color', new THREE.BufferAttribute(colors, 4));
    g.deleteAttribute('uv');
    return g;
  });
}

/**
 * Sombra "blob" barata: disco oscuro difuminado bajo un personaje (sin shadow maps).
 * Devuelve una malla con geometría y material compartidos; escálala con `scale`.
 */
export function blobShadow(radius = 0.5, opacity = 0.55): THREE.Mesh {
  const material = mat('#000000', {
    kind: 'basic',
    vertexColors: true,
    transparent: true,
    opacity,
    depthWrite: false,
  });
  const m = new THREE.Mesh(radialDiscGeometry(18), material);
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.015;
  m.scale.setScalar(radius);
  m.renderOrder = 1;
  m.name = 'blobShadow';
  return m;
}

/** Halo aditivo (brillo suave) con el disco radial. */
export function glowDisc(color: THREE.ColorRepresentation, radius: number, opacity = 0.6): THREE.Mesh {
  const material = mat(color, {
    kind: 'basic',
    vertexColors: true,
    additive: true,
    opacity,
    fog: false,
  });
  const m = new THREE.Mesh(radialDiscGeometry(16), material);
  m.scale.setScalar(radius);
  m.renderOrder = 2;
  return m;
}

// ---------------------------------------------------------------------------
// PartBatch: fusión de piezas con color por vértice
// ---------------------------------------------------------------------------

export type V3 = readonly [number, number, number];

/** Transformación de una pieza: posición, rotación (Euler XYZ, radianes) y escala. */
export interface Xf {
  p?: V3;
  r?: V3;
  s?: number | V3;
  /** Orden de Euler (por defecto 'XYZ'; 'YXZ' = cabeceo local y luego giro). */
  o?: THREE.EulerOrder;
}

export interface TaperOptions {
  /** Escala X de la cara superior. */
  sx?: number;
  /** Escala Z de la cara superior. */
  sz?: number;
  /** Desplazamiento X de la cara superior. */
  dx?: number;
  /** Desplazamiento Z de la cara superior. */
  dz?: number;
}

const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _c = new THREE.Color();
const _va = new THREE.Vector3();
const _vb = new THREE.Vector3();
const _vc = new THREE.Vector3();
const _ab = new THREE.Vector3();
const _ac = new THREE.Vector3();
const _n = new THREE.Vector3();

function composeXf(xf: Xf | undefined, out: THREE.Matrix4): THREE.Matrix4 {
  const p = xf?.p;
  const r = xf?.r;
  const s = xf?.s;
  _p.set(p ? p[0] : 0, p ? p[1] : 0, p ? p[2] : 0);
  _e.set(r ? r[0] : 0, r ? r[1] : 0, r ? r[2] : 0, xf?.o ?? 'XYZ');
  _q.setFromEuler(_e);
  if (typeof s === 'number') _s.setScalar(s);
  else if (s) _s.set(s[0], s[1], s[2]);
  else _s.set(1, 1, 1);
  return out.compose(_p, _q, _s);
}

/**
 * Acumula piezas low-poly (cada una con su color y transformación) y las fusiona en
 * una sola geometría no indexada con normales por cara y colores por vértice.
 * Cada cara recibe una leve variación de brillo (`jitter`) para el look facetado.
 */
export class PartBatch {
  private pos: number[] = [];
  private nor: number[] = [];
  private col: number[] = [];
  private readonly rand: () => number;
  jitter: number;

  constructor(seed = 1, jitter = 0.07) {
    this.rand = rng(seed);
    this.jitter = jitter;
  }

  get isEmpty(): boolean {
    return this.pos.length === 0;
  }

  get triangles(): number {
    return this.pos.length / 9;
  }

  /** Añade una geometría (no se modifica ni se libera la original). */
  add(geometry: THREE.BufferGeometry, color: THREE.ColorRepresentation, xf?: Xf, jitter = this.jitter): this {
    const g = geometry.index ? geometry.toNonIndexed() : geometry;
    const attr = g.getAttribute('position');
    composeXf(xf, _m4);
    const flip = _m4.determinant() < 0;
    _c.set(color);
    const { pos, nor, col } = this;
    for (let i = 0; i + 2 < attr.count; i += 3) {
      _va.fromBufferAttribute(attr, i).applyMatrix4(_m4);
      if (flip) {
        _vb.fromBufferAttribute(attr, i + 2).applyMatrix4(_m4);
        _vc.fromBufferAttribute(attr, i + 1).applyMatrix4(_m4);
      } else {
        _vb.fromBufferAttribute(attr, i + 1).applyMatrix4(_m4);
        _vc.fromBufferAttribute(attr, i + 2).applyMatrix4(_m4);
      }
      _ab.subVectors(_vb, _va);
      _ac.subVectors(_vc, _va);
      _n.crossVectors(_ab, _ac);
      if (_n.lengthSq() < 1e-14) continue; // triángulo degenerado
      _n.normalize();
      const f = 1 + (this.rand() - 0.5) * 2 * jitter;
      const r = _c.r * f;
      const gg = _c.g * f;
      const b = _c.b * f;
      pos.push(_va.x, _va.y, _va.z, _vb.x, _vb.y, _vb.z, _vc.x, _vc.y, _vc.z);
      nor.push(_n.x, _n.y, _n.z, _n.x, _n.y, _n.z, _n.x, _n.y, _n.z);
      col.push(r, gg, b, r, gg, b, r, gg, b);
    }
    if (g !== geometry) g.dispose();
    return this;
  }

  private addTemp(geometry: THREE.BufferGeometry, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    this.add(geometry, color, xf, jitter);
    geometry.dispose();
    return this;
  }

  box(w: number, h: number, d: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.BoxGeometry(w, h, d), color, xf, jitter);
  }

  /** Caja con la cara superior escalada/desplazada (troncos, cabinas, torsos). */
  tbox(
    w: number,
    h: number,
    d: number,
    top: TaperOptions,
    color: THREE.ColorRepresentation,
    xf?: Xf,
    jitter?: number,
  ): this {
    const g = new THREE.BoxGeometry(w, h, d);
    const a = g.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < a.count; i++) {
      if (a.getY(i) > 0) {
        a.setX(i, a.getX(i) * (top.sx ?? 1) + (top.dx ?? 0));
        a.setZ(i, a.getZ(i) * (top.sz ?? 1) + (top.dz ?? 0));
      }
    }
    return this.addTemp(g, color, xf, jitter);
  }

  cyl(rTop: number, rBottom: number, h: number, seg: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.CylinderGeometry(rTop, rBottom, h, seg, 1), color, xf, jitter);
  }

  cone(r: number, h: number, seg: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.ConeGeometry(r, h, seg, 1), color, xf, jitter);
  }

  ico(r: number, color: THREE.ColorRepresentation, xf?: Xf, detail = 0, jitter?: number): this {
    return this.addTemp(new THREE.IcosahedronGeometry(r, detail), color, xf, jitter);
  }

  dodeca(r: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.DodecahedronGeometry(r, 0), color, xf, jitter);
  }

  oct(r: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.OctahedronGeometry(r, 0), color, xf, jitter);
  }

  /** Triángulo suelto (orden antihorario = cara visible). */
  tri(a: V3, b: V3, c: V3, color: THREE.ColorRepresentation, doubleSided = false): this {
    const g = new THREE.BufferGeometry();
    const v = doubleSided ? [...a, ...b, ...c, ...a, ...c, ...b] : [...a, ...b, ...c];
    g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
    return this.addTemp(g, color, undefined, 0);
  }

  /** Plano vertical de w x h mirando +Z (2 triángulos): ventanas, carteles. */
  plane(w: number, h: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    return this.addTemp(new THREE.PlaneGeometry(w, h), color, xf, jitter);
  }

  /** Plano horizontal (mirando +Y) de w x d, útil para manchas y marcas en el suelo. */
  flat(w: number, d: number, color: THREE.ColorRepresentation, xf?: Xf, jitter?: number): this {
    const g = new THREE.PlaneGeometry(w, d);
    g.rotateX(-Math.PI / 2);
    return this.addTemp(g, color, xf, jitter);
  }

  /** Copia otra batch (ya construida en coordenadas locales) con una transformación extra. */
  merge(other: PartBatch, xf?: Xf): this {
    if (other.isEmpty) return this;
    composeXf(xf, _m4);
    const nm = new THREE.Matrix3().getNormalMatrix(_m4);
    const flip = _m4.determinant() < 0;
    const { pos: op, nor: on, col: oc } = other;
    for (let i = 0; i < op.length; i += 9) {
      for (let k = 0; k < 3; k++) {
        const src = flip ? (k === 0 ? 0 : k === 1 ? 2 : 1) : k;
        const j = i + src * 3;
        _va.set(op[j], op[j + 1], op[j + 2]).applyMatrix4(_m4);
        _n.set(on[j], on[j + 1], on[j + 2]).applyMatrix3(nm).normalize();
        this.pos.push(_va.x, _va.y, _va.z);
        this.nor.push(_n.x, _n.y, _n.z);
        this.col.push(oc[j], oc[j + 1], oc[j + 2]);
      }
    }
    return this;
  }

  build(): THREE.BufferGeometry {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.computeBoundingBox();
    g.computeBoundingSphere();
    return g;
  }

  /** Construye una malla (por defecto con `vcLambert`) marcada como fusionable. */
  mesh(material: THREE.Material = vcLambert(), name = ''): THREE.Mesh {
    const m = new THREE.Mesh(this.build(), material);
    m.userData.mergeable = true;
    m.name = name;
    return m;
  }

  /** Añade la malla a `parent` sólo si la batch tiene contenido. */
  attachTo(parent: THREE.Object3D, material?: THREE.Material, name = ''): THREE.Mesh | null {
    if (this.isEmpty) return null;
    const m = this.mesh(material, name);
    parent.add(m);
    return m;
  }
}

/**
 * Fusiona las mallas estáticas (`userData.mergeable`) de `root` agrupándolas por material:
 * un único draw call por material. Las mallas no fusionables (animadas, transparentes,
 * con otra estructura de atributos) se dejan intactas.
 */
export function mergeStatic(root: THREE.Object3D): void {
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const buckets = new Map<THREE.Material, THREE.Mesh[]>();
  root.traverse((obj) => {
    const m = obj as THREE.Mesh;
    if (!m.isMesh || !m.userData.mergeable || Array.isArray(m.material)) return;
    const g = m.geometry;
    if (g.index || !g.getAttribute('color') || !g.getAttribute('normal')) return;
    const list = buckets.get(m.material);
    if (list) list.push(m);
    else buckets.set(m.material, [m]);
  });
  const local = new THREE.Matrix4();
  const nm = new THREE.Matrix3();
  for (const [material, meshes] of buckets) {
    if (meshes.length < 2) continue;
    let total = 0;
    for (const m of meshes) total += m.geometry.getAttribute('position').count;
    const pos = new Float32Array(total * 3);
    const nor = new Float32Array(total * 3);
    const col = new Float32Array(total * 3);
    let o = 0;
    for (const m of meshes) {
      local.multiplyMatrices(inv, m.matrixWorld);
      nm.getNormalMatrix(local);
      const pa = m.geometry.getAttribute('position');
      const na = m.geometry.getAttribute('normal');
      const ca = m.geometry.getAttribute('color');
      for (let i = 0; i < pa.count; i++) {
        _va.fromBufferAttribute(pa, i).applyMatrix4(local);
        _n.fromBufferAttribute(na, i).applyMatrix3(nm).normalize();
        pos[o * 3] = _va.x;
        pos[o * 3 + 1] = _va.y;
        pos[o * 3 + 2] = _va.z;
        nor[o * 3] = _n.x;
        nor[o * 3 + 1] = _n.y;
        nor[o * 3 + 2] = _n.z;
        col[o * 3] = ca.getX(i);
        col[o * 3 + 1] = ca.getY(i);
        col[o * 3 + 2] = ca.getZ(i);
        o++;
      }
      m.removeFromParent();
      if (!m.geometry.userData.shared) m.geometry.dispose();
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    g.computeBoundingBox();
    g.computeBoundingSphere();
    const merged = new THREE.Mesh(g, material);
    merged.name = 'merged';
    merged.userData.mergeable = true;
    merged.matrixAutoUpdate = false;
    root.add(merged);
  }
}
