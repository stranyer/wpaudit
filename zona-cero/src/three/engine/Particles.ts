// Sistema de partículas con pool fijo (un único THREE.Points, sin asignaciones por frame).
// Cada partícula tiene posición, velocidad, gravedad, rozamiento, tamaño (m, mundo) y
// color/alfa interpolados durante su vida. El shader dibuja discos suaves.

import * as THREE from 'three';

export interface EmitOptions {
  count: number;
  /** Origen en coordenadas de mundo. */
  origin: THREE.Vector3;
  /** Radio aleatorio alrededor del origen. */
  spread?: number;
  /** Escala por eje del radio de dispersión. */
  spreadScale?: readonly [number, number, number];
  /** Velocidad base (m/s). */
  velocity?: readonly [number, number, number];
  /** Componente aleatoria de velocidad (m/s) por eje. */
  velocityRandom?: readonly [number, number, number];
  /** Velocidad radial hacia afuera desde el origen (m/s). */
  radial?: number;
  gravity?: number;
  drag?: number;
  life: readonly [number, number];
  /** Tamaño inicial y final (m). */
  size: readonly [number, number];
  /** Variación aleatoria del tamaño (0..1). */
  sizeRandom?: number;
  /** Colores posibles (se elige uno al azar por partícula). */
  colors: readonly THREE.Color[];
  /** Alfa inicial y final. */
  alpha?: readonly [number, number];
  /** Rebota/se detiene al tocar el suelo (y = 0.02). */
  floor?: boolean;
  /** Retraso aleatorio de nacimiento hasta N segundos. */
  stagger?: number;
}

const VERT = /* glsl */ `
attribute float size;
attribute vec4 pcolor;
uniform float uScale;
varying vec4 vColor;
void main() {
  vColor = pcolor;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mv;
  float s = size * uScale / max(0.05, -mv.z);
  gl_PointSize = min(s, 220.0);
  if (size <= 0.0 || pcolor.a <= 0.002) gl_PointSize = 0.0;
}
`;

const FRAG = /* glsl */ `
uniform float uSoft;
varying vec4 vColor;
void main() {
  vec2 c = gl_PointCoord - 0.5;
  float d = length(c) * 2.0;
  float a = 1.0 - smoothstep(uSoft, 1.0, d);
  a *= vColor.a;
  if (a < 0.01) discard;
  gl_FragColor = vec4(vColor.rgb, a);
  #include <colorspace_fragment>
}
`;

export class ParticlePool {
  readonly points: THREE.Points;
  readonly capacity: number;

  private readonly pos: Float32Array;
  private readonly col: Float32Array;
  private readonly siz: Float32Array;
  private readonly vel: Float32Array;
  private readonly age: Float32Array;
  private readonly life: Float32Array;
  private readonly s0: Float32Array;
  private readonly s1: Float32Array;
  private readonly a0: Float32Array;
  private readonly a1: Float32Array;
  private readonly grav: Float32Array;
  private readonly drag: Float32Array;
  private readonly floor: Uint8Array;
  private readonly rgb: Float32Array;
  private readonly posAttr: THREE.BufferAttribute;
  private readonly colAttr: THREE.BufferAttribute;
  private readonly sizAttr: THREE.BufferAttribute;
  private readonly material: THREE.ShaderMaterial;
  private cursor = 0;
  private alive = 0;
  private dirty = false;

  constructor(capacity: number, opts: { additive?: boolean; soft?: number } = {}) {
    this.capacity = capacity;
    this.pos = new Float32Array(capacity * 3);
    this.col = new Float32Array(capacity * 4);
    this.siz = new Float32Array(capacity);
    this.vel = new Float32Array(capacity * 3);
    this.age = new Float32Array(capacity);
    this.life = new Float32Array(capacity);
    this.s0 = new Float32Array(capacity);
    this.s1 = new Float32Array(capacity);
    this.a0 = new Float32Array(capacity);
    this.a1 = new Float32Array(capacity);
    this.grav = new Float32Array(capacity);
    this.drag = new Float32Array(capacity);
    this.floor = new Uint8Array(capacity);
    this.rgb = new Float32Array(capacity * 3);
    this.life.fill(0);
    this.age.fill(1);

    const g = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage);
    this.colAttr = new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage);
    this.sizAttr = new THREE.BufferAttribute(this.siz, 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.posAttr);
    g.setAttribute('pcolor', this.colAttr);
    g.setAttribute('size', this.sizAttr);
    g.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 1e4);

    this.material = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: {
        uScale: { value: 500 },
        uSoft: { value: opts.soft ?? 0.35 },
      },
      transparent: true,
      depthWrite: false,
      blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, this.material);
    this.points.frustumCulled = false;
    this.points.renderOrder = opts.additive ? 6 : 5;
    this.points.name = opts.additive ? 'particlesAdd' : 'particles';
  }

  /** Factor de escala de tamaño: alto del viewport en px de dispositivo / (2·tan(fov/2)). */
  setViewport(heightPx: number, fovDeg: number): void {
    this.material.uniforms.uScale.value = heightPx / (2 * Math.tan(THREE.MathUtils.degToRad(fovDeg) / 2));
  }

  get activeCount(): number {
    return this.alive;
  }

  emit(o: EmitOptions): void {
    const n = Math.min(o.count, this.capacity);
    const spread = o.spread ?? 0;
    const ss = o.spreadScale;
    const v = o.velocity;
    const vr = o.velocityRandom;
    const radial = o.radial ?? 0;
    const sr = o.sizeRandom ?? 0.3;
    const alpha = o.alpha ?? [1, 0];
    const stagger = o.stagger ?? 0;
    for (let k = 0; k < n; k++) {
      const i = this.cursor;
      this.cursor = (this.cursor + 1) % this.capacity;
      if (this.age[i] < this.life[i]) this.alive--; // reemplaza la más vieja
      // dirección aleatoria uniforme
      let dx = Math.random() * 2 - 1;
      let dy = Math.random() * 2 - 1;
      let dz = Math.random() * 2 - 1;
      const len = Math.hypot(dx, dy, dz) || 1;
      dx /= len;
      dy /= len;
      dz /= len;
      const rr = spread * Math.cbrt(Math.random());
      this.pos[i * 3] = o.origin.x + dx * rr * (ss ? ss[0] : 1);
      this.pos[i * 3 + 1] = o.origin.y + dy * rr * (ss ? ss[1] : 1);
      this.pos[i * 3 + 2] = o.origin.z + dz * rr * (ss ? ss[2] : 1);
      this.vel[i * 3] = (v ? v[0] : 0) + (vr ? (Math.random() * 2 - 1) * vr[0] : 0) + dx * radial;
      this.vel[i * 3 + 1] = (v ? v[1] : 0) + (vr ? (Math.random() * 2 - 1) * vr[1] : 0) + dy * radial;
      this.vel[i * 3 + 2] = (v ? v[2] : 0) + (vr ? (Math.random() * 2 - 1) * vr[2] : 0) + dz * radial;
      this.life[i] = o.life[0] + Math.random() * (o.life[1] - o.life[0]);
      this.age[i] = stagger > 0 ? -Math.random() * stagger : 0;
      const sk = 1 + (Math.random() * 2 - 1) * sr;
      this.s0[i] = o.size[0] * sk;
      this.s1[i] = o.size[1] * sk;
      this.a0[i] = alpha[0];
      this.a1[i] = alpha[1];
      this.grav[i] = o.gravity ?? 0;
      this.drag[i] = o.drag ?? 0;
      this.floor[i] = o.floor ? 1 : 0;
      const c = o.colors[Math.floor(Math.random() * o.colors.length)];
      this.rgb[i * 3] = c.r;
      this.rgb[i * 3 + 1] = c.g;
      this.rgb[i * 3 + 2] = c.b;
      this.siz[i] = 0;
      this.col[i * 4 + 3] = 0;
      this.alive++;
    }
    this.dirty = true;
  }

  update(dt: number): void {
    if (this.alive <= 0 && !this.dirty) return;
    let alive = 0;
    const { pos, vel, col, siz, age, life } = this;
    for (let i = 0; i < this.capacity; i++) {
      if (age[i] >= life[i]) {
        if (siz[i] !== 0) {
          siz[i] = 0;
          col[i * 4 + 3] = 0;
        }
        continue;
      }
      age[i] += dt;
      if (age[i] >= life[i]) {
        siz[i] = 0;
        col[i * 4 + 3] = 0;
        continue;
      }
      alive++;
      if (age[i] < 0) continue; // aún no nace (stagger)
      const i3 = i * 3;
      const dr = 1 - Math.min(1, this.drag[i] * dt);
      vel[i3] *= dr;
      vel[i3 + 1] = (vel[i3 + 1] - this.grav[i] * dt) * dr;
      vel[i3 + 2] *= dr;
      pos[i3] += vel[i3] * dt;
      pos[i3 + 1] += vel[i3 + 1] * dt;
      pos[i3 + 2] += vel[i3 + 2] * dt;
      if (this.floor[i] && pos[i3 + 1] < 0.02) {
        pos[i3 + 1] = 0.02;
        vel[i3 + 1] = 0;
        vel[i3] *= 0.3;
        vel[i3 + 2] *= 0.3;
      }
      const t = age[i] / life[i];
      siz[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * t;
      const fadeIn = Math.min(1, age[i] / 0.05);
      col[i * 4] = this.rgb[i3];
      col[i * 4 + 1] = this.rgb[i3 + 1];
      col[i * 4 + 2] = this.rgb[i3 + 2];
      col[i * 4 + 3] = (this.a0[i] + (this.a1[i] - this.a0[i]) * t) * fadeIn;
    }
    this.alive = alive;
    this.posAttr.needsUpdate = true;
    this.colAttr.needsUpdate = true;
    this.sizAttr.needsUpdate = true;
    this.dirty = alive > 0;
  }
}
