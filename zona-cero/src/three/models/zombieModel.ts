// Zombies procedurales low-poly con rig de grupos pivote y animación por código.
//
// CONVENCIONES
// - Unidades en metros. Los pies están en y = 0 (espacio local de `root`).
// - El zombie MIRA HACIA +Z. En la escena de combate la cámara está en +Z mirando hacia -Z,
//   así que el zombie mira a la cámara. La izquierda del personaje es +X.
// - Altura ~1.8 m (runner encorvado ~1.6, bloater ~1.65, screamer ~2.0, brute ~2.3 con escala 1.38).
// - `root` no se anima: la escena puede moverlo/rotarlo libremente. El rig anima `root > body > …`.
//
// JERARQUÍA
//   root
//   ├─ shadow (blob)
//   └─ body (pivote en los pies: embestidas, caída hacia atrás)
//      └─ hips (cadera)
//         ├─ legL > kneeL      ├─ legR > kneeR
//         └─ spine (cintura → pecho)
//            ├─ belly (malla aparte, "respira" en el bloater)
//            ├─ head (cuello) > jaw, eyes, eyeGlow
//            ├─ armL (hombro) > elbowL
//            └─ armR (hombro) > elbowR
//
// Todas las piezas de un grupo se fusionan en UNA malla con colores por vértice y un único
// material por zombie (clonado para poder hacer el destello rojo de golpe y el fundido al morir).

import * as THREE from 'three';
import type { ZombieTypeId } from '../../core/types';
import {
  PALETTE,
  PartBatch,
  blobShadow,
  clamp01,
  cloneMat,
  glowDisc,
  rng,
  smooth01,
  vcBasic,
  vcLambert,
} from './materials';

export interface ZombieRig {
  readonly type: ZombieTypeId;
  readonly root: THREE.Group;
  /** Altura aproximada (m) en espacio de `root`, ya con la escala del tipo. */
  readonly height: number;
  readonly isDead: boolean;
  /** true cuando terminó la animación de muerte (hundido y oculto). */
  readonly isGone: boolean;
  /**
   * Gira el zombie `yaw` rad sobre Y (vista 3/4) manteniendo la cabeza mirando a +Z del mundo
   * y las embestidas/esquivas alineadas con los ejes del mundo (hacia la cámara).
   */
  setFacing(yaw: number): void;
  /**
   * Distancia (m) entre el zombie y la cámara: limita el alcance de embestidas y cargas para
   * que no atraviesen la cámara cuando el encuadre la acerca.
   */
  setReach(distance: number): void;
  update(dt: number): void;
  /** Embestida hacia la cámara. Devuelve los segundos hasta el impacto. */
  attack(): number;
  /** Embestida que falla y trastabilla hacia un lado. */
  lungeMiss(): void;
  /** Retroceso + destello rojo. */
  hit(strong: boolean): void;
  /** Esquiva lateral. */
  dodge(): void;
  /** Se agacha y le brillan los ojos; se mantiene hasta charge()/attack()/stun()/die(). */
  chargePrepare(): void;
  /** Carga brutal hacia la cámara. Devuelve los segundos hasta el impacto. */
  charge(): number;
  /** Grito: cabeza atrás, mandíbula abierta, brazos abiertos. Devuelve segundos hasta el pico. */
  scream(): number;
  /** Tambaleo de ~1.2 s. */
  stun(): void;
  /** Cae hacia atrás, se hunde y se desvanece. Después no hay idle. */
  die(): void;
  /** Posición mundial de la cabeza (para efectos). */
  getHeadWorldPosition(target: THREE.Vector3): THREE.Vector3;
  /** Posición mundial del pecho (para sangre/nubes). */
  getChestWorldPosition(target: THREE.Vector3): THREE.Vector3;
}

// ---------------------------------------------------------------------------
// Canales de pose
// ---------------------------------------------------------------------------

const BX = 0;
const BY = 1;
const BZ = 2;
const BRX = 3;
const BRY = 4;
const BRZ = 5;
const HIPS = 6;
const SX = 7;
const SY = 8;
const SZ = 9;
const HX = 10;
const HY = 11;
const HZ = 12;
const JAW = 13;
const ALX = 14;
const ALY = 15;
const ALZ = 16; // hacia afuera
const EL = 17;
const ARX = 18;
const ARY = 19;
const ARZ = 20; // hacia afuera
const ER = 21;
const LLX = 22;
const LLZ = 23; // hacia afuera
const KL = 24;
const LRX = 25;
const LRZ = 26; // hacia afuera
const KR = 27;
const EYE = 28;
const CHANNELS = 29;

// ---------------------------------------------------------------------------
// Dimensiones y vestuario por tipo
// ---------------------------------------------------------------------------

interface Dims {
  scale: number;
  hipY: number;
  thigh: number;
  shin: number;
  legGap: number;
  waist: number;
  spine: number;
  shoulderX: number;
  shoulderY: number;
  upperArm: number;
  foreArm: number;
  /** Pivote de la mandíbula en espacio de cabeza. */
  jaw: readonly [number, number, number];
  /** Centro de los ojos en espacio de cabeza (x = separación). */
  eyes: readonly [number, number, number];
  eyeSize: number;
  shadow: number;
  speed: number;
  /** Distancia (m mundo) de la embestida de ataque. */
  lunge: number;
}

const DIMS: Record<ZombieTypeId, Dims> = {
  walker: {
    scale: 1,
    hipY: 0.9,
    thigh: 0.42,
    shin: 0.42,
    legGap: 0.1,
    waist: 0.06,
    spine: 0.52,
    shoulderX: 0.225,
    shoulderY: 0.46,
    upperArm: 0.29,
    foreArm: 0.28,
    jaw: [0, 0.145, -0.04],
    eyes: [0.048, 0.225, 0.118],
    eyeSize: 1,
    shadow: 0.5,
    speed: 1,
    lunge: 1.45,
  },
  runner: {
    scale: 1,
    hipY: 0.92,
    thigh: 0.43,
    shin: 0.43,
    legGap: 0.09,
    waist: 0.05,
    spine: 0.5,
    shoulderX: 0.195,
    shoulderY: 0.44,
    upperArm: 0.29,
    foreArm: 0.29,
    jaw: [0, 0.14, -0.04],
    eyes: [0.045, 0.22, 0.112],
    eyeSize: 1,
    shadow: 0.45,
    speed: 1.4,
    lunge: 1.7,
  },
  bloater: {
    scale: 1,
    hipY: 0.79,
    thigh: 0.35,
    shin: 0.37,
    legGap: 0.16,
    waist: 0.06,
    spine: 0.55,
    shoulderX: 0.29,
    shoulderY: 0.5,
    upperArm: 0.29,
    foreArm: 0.27,
    jaw: [0, 0.115, -0.02],
    eyes: [0.04, 0.19, 0.115],
    eyeSize: 0.9,
    shadow: 0.68,
    speed: 0.8,
    lunge: 1.0,
  },
  screamer: {
    scale: 1,
    hipY: 1.02,
    thigh: 0.48,
    shin: 0.48,
    legGap: 0.085,
    waist: 0.06,
    spine: 0.58,
    shoulderX: 0.2,
    shoulderY: 0.53,
    upperArm: 0.4,
    foreArm: 0.4,
    jaw: [0, 0.15, -0.04],
    eyes: [0.045, 0.255, 0.112],
    eyeSize: 1.05,
    shadow: 0.48,
    speed: 1.1,
    lunge: 1.3,
  },
  brute: {
    scale: 1.38,
    hipY: 0.84,
    thigh: 0.39,
    shin: 0.39,
    legGap: 0.15,
    waist: 0.06,
    spine: 0.56,
    shoulderX: 0.41,
    shoulderY: 0.47,
    upperArm: 0.32,
    foreArm: 0.31,
    jaw: [0, 0.075, 0.0],
    eyes: [0.042, 0.13, 0.15],
    eyeSize: 1.1,
    shadow: 0.58,
    speed: 0.85,
    lunge: 1.6,
  },
};

interface Parts {
  hips: PartBatch;
  spine: PartBatch;
  belly: PartBatch;
  head: PartBatch;
  jaw: PartBatch;
  eyes: PartBatch;
  armL: PartBatch;
  foreL: PartBatch;
  armR: PartBatch;
  foreR: PartBatch;
  legL: PartBatch;
  shinL: PartBatch;
  legR: PartBatch;
  shinR: PartBatch;
}

function makeParts(seed: number): Parts {
  let s = seed;
  const b = () => new PartBatch(s++, 0.07);
  return {
    hips: b(),
    spine: b(),
    belly: b(),
    head: b(),
    jaw: b(),
    eyes: new PartBatch(1, 0),
    armL: b(),
    foreL: b(),
    armR: b(),
    foreR: b(),
    legL: b(),
    shinL: b(),
    legR: b(),
    shinR: b(),
  };
}

type Side = 1 | -1;

function side<T>(sd: Side, l: T, r: T): T {
  return sd === 1 ? l : r;
}

interface LimbStyle {
  upperR: number;
  foreR: number;
  upperColor: string;
  foreColor: string;
  /** Manga corta: color de la manga sobre el brazo (0..1 de la longitud del brazo). */
  sleeve?: { color: string; len: number; r: number };
  skin: string;
  hand: number;
  fingerLen: number;
}

function addArm(p: Parts, d: Dims, sd: Side, st: LimbStyle): void {
  const up = side(sd, p.armL, p.armR);
  const fo = side(sd, p.foreL, p.foreR);
  up.ico(st.upperR * 1.15, st.sleeve?.color ?? st.upperColor, { p: [0, -0.01, 0], s: [1, 0.9, 1] });
  up.cyl(st.upperR * 0.9, st.upperR, d.upperArm, 6, st.upperColor, { p: [0, -d.upperArm / 2, 0] });
  if (st.sleeve) {
    const l = d.upperArm * st.sleeve.len;
    up.cyl(st.sleeve.r * 0.95, st.sleeve.r, l, 6, st.sleeve.color, { p: [0, -l / 2, 0], r: [0, 0.3, 0] });
  }
  fo.ico(st.foreR * 1.05, st.upperColor, { p: [0, 0, 0] });
  fo.cyl(st.foreR * 0.8, st.foreR, d.foreArm, 6, st.foreColor, { p: [0, -d.foreArm / 2, 0] });
  const h = st.hand;
  const hy = -d.foreArm - h * 0.45;
  fo.box(h * 0.75, h, h * 0.38, st.skin, { p: [0, hy, 0.005] });
  const fl = st.fingerLen;
  for (let i = -1; i <= 1; i++) {
    fo.box(h * 0.16, fl, h * 0.16, st.skin, {
      p: [i * h * 0.24, hy - h * 0.5 - fl * 0.4, 0.02],
      r: [-0.35, 0, i * 0.08],
    });
  }
  // pulgar
  fo.box(h * 0.16, fl * 0.7, h * 0.16, st.skin, { p: [sd * -h * 0.42, hy - h * 0.1, 0.03], r: [-0.4, 0, sd * 0.5] });
}

interface LegStyle {
  thighR: number;
  shinR: number;
  thighColor: string;
  shinColor: string;
  foot: string;
  footW: number;
  footL: number;
  footH: number;
  bare?: boolean;
}

function addLeg(p: Parts, d: Dims, sd: Side, st: LegStyle): void {
  const th = side(sd, p.legL, p.legR);
  const sh = side(sd, p.shinL, p.shinR);
  th.cyl(st.thighR * 0.85, st.thighR, d.thigh, 6, st.thighColor, { p: [0, -d.thigh / 2, 0] });
  sh.ico(st.shinR * 1.1, st.thighColor, { p: [0, 0, 0.005] });
  sh.cyl(st.shinR * 0.75, st.shinR, d.shin, 6, st.shinColor, { p: [0, -d.shin / 2, 0] });
  const ankle = d.hipY - d.thigh - d.shin;
  const fy = -d.shin - ankle + st.footH / 2;
  sh.box(st.footW, st.footH, st.footL, st.foot, { p: [0, fy, st.footL * 0.22] });
  if (st.bare) {
    for (let i = -1; i <= 1; i++) {
      sh.box(st.footW * 0.22, st.footH * 0.5, 0.04, st.foot, {
        p: [i * st.footW * 0.3, fy - st.footH * 0.22, st.footL * 0.72],
      });
    }
  } else {
    // suela
    sh.box(st.footW * 1.04, st.footH * 0.28, st.footL * 1.02, '#121212', {
      p: [0, fy - st.footH * 0.4, st.footL * 0.22],
    });
  }
}

/** Tiras de ropa colgando (harapos). */
function rags(
  b: PartBatch,
  r: () => number,
  count: number,
  color: string,
  y: number,
  radiusX: number,
  radiusZ: number,
  len: number,
  front = true,
): void {
  for (let i = 0; i < count; i++) {
    const a = front ? -1.2 + (2.4 * i) / Math.max(1, count - 1) : (Math.PI * 2 * i) / count;
    const x = Math.sin(a) * radiusX;
    const z = Math.cos(a) * radiusZ;
    const l = len * (0.6 + r() * 0.7);
    b.box(0.045 + r() * 0.03, l, 0.014, color, {
      p: [x, y - l / 2, z],
      r: [0.08 + (r() - 0.5) * 0.2, a, (r() - 0.5) * 0.35],
    });
  }
}

function dressWalker(p: Parts, d: Dims): void {
  const r = rng(11);
  const skin = PALETTE.skinWalker;
  const skinDark = '#5d6a4c';
  const shirt = '#6a5c48';
  const shirtDark = '#4a4034';
  const pants = PALETTE.denim;
  // Cadera
  p.hips.box(0.33, 0.2, 0.2, pants, { p: [0, 0.0, 0] });
  p.hips.box(0.34, 0.04, 0.21, '#241a12', { p: [0, 0.09, 0] });
  // Torso con camisa rota
  p.spine.tbox(0.34, 0.52, 0.2, { sx: 1.2, sz: 1.05 }, shirt, { p: [0, 0.26, 0] });
  p.spine.box(0.13, 0.11, 0.03, skin, { p: [0.06, 0.13, 0.1] }); // piel expuesta
  p.spine.box(0.06, 0.05, 0.02, PALETTE.blood, { p: [0.08, 0.14, 0.115] }); // herida
  p.spine.box(0.1, 0.16, 0.012, '#3a2418', { p: [-0.08, 0.36, 0.112] }); // mancha de sangre seca
  p.spine.box(0.07, 0.07, 0.012, '#3a2418', { p: [0.1, 0.42, -0.112] });
  p.spine.tbox(0.18, 0.05, 0.12, { sx: 0.8 }, shirtDark, { p: [0, 0.52, 0.0] }); // cuello camisa
  rags(p.spine, r, 6, shirtDark, 0.02, 0.16, 0.1, 0.13);
  rags(p.spine, r, 3, shirt, 0.02, 0.17, -0.1, 0.1);
  // Cabeza
  const h = p.head;
  h.cyl(0.045, 0.05, 0.12, 5, skin, { p: [0, 0.05, -0.01] });
  h.box(0.2, 0.17, 0.21, skin, { p: [0, 0.225, 0.005] });
  h.box(0.17, 0.05, 0.17, skinDark, { p: [0, 0.135, 0.0] }); // pómulos hundidos
  h.box(0.205, 0.035, 0.05, skinDark, { p: [0, 0.255, 0.095] }); // ceja
  h.box(0.06, 0.035, 0.02, '#141410', { p: [-0.048, 0.225, 0.108] }); // cuencas
  h.box(0.06, 0.035, 0.02, '#141410', { p: [0.048, 0.225, 0.108] });
  h.tbox(0.035, 0.05, 0.03, { sx: 0.6 }, skinDark, { p: [0, 0.19, 0.118] }); // nariz
  h.box(0.13, 0.055, 0.07, '#1c0606', { p: [0, 0.135, 0.065] }); // boca interior
  h.box(0.12, 0.022, 0.02, PALETTE.bone, { p: [0, 0.155, 0.1] }); // dientes sup.
  h.box(0.022, 0.055, 0.045, skin, { p: [0.106, 0.205, 0.0] });
  h.box(0.022, 0.055, 0.045, skin, { p: [-0.106, 0.205, 0.0] });
  h.box(0.21, 0.04, 0.16, '#211d18', { p: [-0.01, 0.31, -0.03] }); // pelo ralo
  h.box(0.07, 0.12, 0.17, '#211d18', { p: [-0.085, 0.25, -0.03] });
  h.box(0.08, 0.05, 0.02, PALETTE.blood, { p: [0.06, 0.29, 0.1] });
  // Mandíbula
  p.jaw.box(0.165, 0.065, 0.15, skin, { p: [0, -0.03, 0.085] });
  p.jaw.box(0.11, 0.02, 0.02, PALETTE.bone, { p: [0, 0.008, 0.145] });
  p.jaw.box(0.05, 0.03, 0.02, PALETTE.blood, { p: [0.03, -0.04, 0.16] });
  // Brazos
  for (const sd of [1, -1] as const) {
    addArm(p, d, sd, {
      upperR: 0.052,
      foreR: 0.046,
      upperColor: skin,
      foreColor: skin,
      sleeve: { color: shirt, len: 0.45, r: 0.067 },
      skin,
      hand: 0.09,
      fingerLen: 0.07,
    });
    addLeg(p, d, sd, {
      thighR: 0.08,
      shinR: 0.066,
      thighColor: pants,
      shinColor: pants,
      foot: sd === 1 ? '#1d1b18' : skinDark,
      footW: 0.1,
      footL: 0.24,
      footH: 0.08,
      bare: sd === -1,
    });
  }
  p.shinL.box(0.085, 0.08, 0.02, skin, { p: [0, -0.06, 0.055] }); // rodilla rota
  p.legR.box(0.07, 0.1, 0.02, '#1e2830', { p: [0, -0.25, 0.066] });
}

function dressRunner(p: Parts, d: Dims): void {
  const r = rng(23);
  const skin = '#9aa088';
  const skinDark = '#6f765f';
  const hoodie = '#4c2623';
  const hoodieDark = '#33191a';
  const pants = '#25292c';
  p.hips.box(0.29, 0.19, 0.19, pants, { p: [0, 0, 0] });
  p.spine.tbox(0.3, 0.5, 0.19, { sx: 1.15, sz: 1.05 }, hoodie, { p: [0, 0.25, 0] });
  p.spine.box(0.32, 0.06, 0.2, hoodieDark, { p: [0, 0.02, 0] }); // elástico
  p.spine.box(0.19, 0.1, 0.02, hoodieDark, { p: [0, 0.13, 0.102] }); // bolsillo
  p.spine.box(0.012, 0.1, 0.01, '#b0a890', { p: [0.035, 0.42, 0.11] }); // cordones
  p.spine.box(0.012, 0.13, 0.01, '#b0a890', { p: [-0.035, 0.4, 0.11] });
  p.spine.tbox(0.26, 0.15, 0.13, { sx: 0.7, sz: 0.6 }, hoodieDark, { p: [0, 0.49, -0.1], r: [-0.5, 0, 0] }); // capucha
  p.spine.box(0.1, 0.08, 0.02, skin, { p: [-0.08, 0.3, 0.105] }); // desgarro
  p.spine.box(0.06, 0.05, 0.015, PALETTE.blood, { p: [-0.075, 0.3, 0.112] });
  p.spine.box(0.14, 0.12, 0.012, '#2a1010', { p: [0.06, 0.34, 0.108] });
  rags(p.spine, r, 4, hoodieDark, 0.0, 0.14, 0.1, 0.08);
  const h = p.head;
  h.cyl(0.04, 0.045, 0.12, 5, skin, { p: [0, 0.05, -0.01] });
  h.box(0.19, 0.17, 0.2, skin, { p: [0, 0.22, 0.0] });
  h.box(0.16, 0.05, 0.16, skinDark, { p: [0, 0.135, 0.0] });
  h.box(0.195, 0.03, 0.05, skinDark, { p: [0, 0.25, 0.09] });
  h.box(0.055, 0.03, 0.02, '#121210', { p: [-0.045, 0.22, 0.102] });
  h.box(0.055, 0.03, 0.02, '#121210', { p: [0.045, 0.22, 0.102] });
  h.tbox(0.03, 0.045, 0.03, { sx: 0.6 }, skinDark, { p: [0, 0.185, 0.112] });
  h.box(0.12, 0.05, 0.07, '#1c0606', { p: [0, 0.13, 0.06] });
  h.box(0.11, 0.02, 0.02, PALETTE.bone, { p: [0, 0.148, 0.095] });
  h.box(0.2, 0.05, 0.21, '#17140f', { p: [0, 0.31, -0.01] }); // pelo corto
  h.box(0.2, 0.15, 0.06, '#17140f', { p: [0, 0.25, -0.085] });
  h.box(0.02, 0.05, 0.04, skin, { p: [0.1, 0.2, 0] });
  h.box(0.02, 0.05, 0.04, skin, { p: [-0.1, 0.2, 0] });
  p.jaw.box(0.15, 0.06, 0.14, skin, { p: [0, -0.028, 0.08] });
  p.jaw.box(0.1, 0.02, 0.02, PALETTE.bone, { p: [0, 0.005, 0.14] });
  p.jaw.box(0.12, 0.04, 0.03, PALETTE.bloodBright, { p: [0, -0.045, 0.14] }); // sangre en la barbilla
  for (const sd of [1, -1] as const) {
    addArm(p, d, sd, {
      upperR: 0.058,
      foreR: 0.052,
      upperColor: hoodie,
      foreColor: hoodie,
      skin,
      hand: 0.085,
      fingerLen: 0.085,
    });
    addLeg(p, d, sd, {
      thighR: 0.065,
      shinR: 0.055,
      thighColor: pants,
      shinColor: pants,
      foot: '#8a887c',
      footW: 0.1,
      footL: 0.25,
      footH: 0.085,
    });
  }
  // muñeca a la vista y un desgarro en la manga
  p.foreL.box(0.07, 0.06, 0.02, skin, { p: [0, -0.15, 0.04] });
  p.foreR.box(0.06, 0.05, 0.015, PALETTE.blood, { p: [0, -0.12, 0.045] });
}

function dressBloater(p: Parts, d: Dims): void {
  const r = rng(37);
  const skin = PALETTE.skinBloater;
  const skinDark = '#717a3e';
  const vein = '#4d5a2a';
  const shorts = '#3b3428';
  p.hips.box(0.46, 0.24, 0.32, shorts, { p: [0, -0.01, 0] });
  p.hips.box(0.47, 0.045, 0.33, '#1f1812', { p: [0, 0.1, 0] });
  // Pecho
  p.spine.tbox(0.46, 0.52, 0.3, { sx: 0.95, sz: 0.85 }, skin, { p: [0, 0.28, -0.03] });
  p.spine.tbox(0.48, 0.16, 0.31, { sx: 0.93, sz: 0.88 }, '#827c62', { p: [0, 0.44, -0.03] }); // camiseta rota
  p.spine.box(0.05, 0.1, 0.02, '#827c62', { p: [0.12, 0.54, 0.1] });
  p.spine.box(0.05, 0.1, 0.02, '#827c62', { p: [-0.12, 0.54, 0.1] });
  p.spine.ico(0.2, skin, { p: [0, 0.42, -0.14], s: [1.4, 0.9, 0.8] }); // espalda gorda
  // Panza enorme (malla aparte para "respirar")
  const bc: readonly [number, number, number] = [0, 0.17, 0.1];
  const br = 0.4;
  p.belly.ico(br, skin, { p: bc, s: [1.06, 0.95, 1.0] }, 1);
  p.belly.ico(0.035, '#3a3a1c', { p: [bc[0], bc[1] - 0.04, bc[2] + br * 0.99] }); // ombligo
  const dir = new THREE.Vector3();
  for (let i = 0; i < 14; i++) {
    const a = (r() - 0.5) * 2.4;
    const e = (r() - 0.45) * 1.5;
    dir.set(Math.sin(a) * Math.cos(e), Math.sin(e), Math.cos(a) * Math.cos(e)).normalize();
    const rr = 0.028 + r() * 0.035;
    const col = r() < 0.25 ? '#8a5a2a' : r() < 0.5 ? '#c4b04e' : '#b39a3c';
    p.belly.ico(rr, col, {
      p: [bc[0] + dir.x * br * 1.04, bc[1] + dir.y * br * 0.95, bc[2] + dir.z * br * 0.98],
    });
  }
  for (let i = 0; i < 6; i++) {
    const a = (r() - 0.5) * 1.8;
    const y = bc[1] + (r() - 0.5) * 0.4;
    p.belly.box(0.012, 0.16 + r() * 0.1, 0.012, vein, {
      p: [Math.sin(a) * br * 0.98, y, bc[2] + Math.cos(a) * br * 0.93],
      r: [0, a, (r() - 0.5) * 1.2],
    });
  }
  // Cabeza pequeña y calva con bultos
  const h = p.head;
  h.cyl(0.1, 0.13, 0.1, 6, skin, { p: [0, 0.03, 0.0] }); // cuello gordo
  h.box(0.16, 0.14, 0.17, skin, { p: [0, 0.175, 0.03] });
  h.box(0.13, 0.04, 0.14, skinDark, { p: [0, 0.1, 0.03] });
  h.box(0.165, 0.03, 0.04, skinDark, { p: [0, 0.21, 0.105] });
  h.box(0.045, 0.028, 0.02, '#121210', { p: [-0.04, 0.19, 0.11] });
  h.box(0.045, 0.028, 0.02, '#121210', { p: [0.04, 0.19, 0.11] });
  h.box(0.1, 0.04, 0.06, '#1c0606', { p: [0, 0.115, 0.08] });
  h.ico(0.035, '#b39a3c', { p: [0.05, 0.25, 0.04] });
  h.ico(0.028, '#c4b04e', { p: [-0.06, 0.24, -0.02] });
  h.ico(0.03, skinDark, { p: [0.02, 0.255, -0.05] });
  p.jaw.box(0.13, 0.05, 0.13, skin, { p: [0, -0.02, 0.07] });
  p.jaw.box(0.08, 0.018, 0.02, PALETTE.bone, { p: [0, 0.005, 0.125] });
  p.jaw.box(0.03, 0.06, 0.015, '#7d8a30', { p: [0.02, -0.06, 0.13] }); // baba tóxica
  for (const sd of [1, -1] as const) {
    addArm(p, d, sd, {
      upperR: 0.08,
      foreR: 0.07,
      upperColor: skin,
      foreColor: skin,
      skin,
      hand: 0.1,
      fingerLen: 0.06,
    });
    addLeg(p, d, sd, {
      thighR: 0.11,
      shinR: 0.09,
      thighColor: shorts,
      shinColor: skin,
      foot: '#2a2420',
      footW: 0.13,
      footL: 0.24,
      footH: 0.09,
    });
  }
  p.foreL.ico(0.035, '#c4b04e', { p: [0.05, -0.12, 0.04] });
  p.armR.ico(0.04, '#b39a3c', { p: [-0.06, -0.15, 0.05] });
}

function dressScreamer(p: Parts, d: Dims): void {
  const r = rng(51);
  const skin = PALETTE.skinPale;
  const skinDark = '#66705a';
  const rib = '#55604a';
  const gown = '#6c7975';
  const gownDark = '#4d5856';
  const pants = '#202427';
  p.hips.box(0.26, 0.18, 0.17, pants, { p: [0, 0, 0] });
  // Torso esquelético con costillas
  p.spine.tbox(0.24, 0.58, 0.15, { sx: 1.3, sz: 1.12 }, skin, { p: [0, 0.29, 0] });
  for (let i = 0; i < 4; i++) {
    const y = 0.25 + i * 0.065;
    const w = 0.07 + i * 0.008;
    p.spine.box(w, 0.012, 0.01, rib, { p: [0.06, y, 0.082], r: [0, 0, -0.25] });
    p.spine.box(w, 0.012, 0.01, rib, { p: [-0.06, y, 0.082], r: [0, 0, 0.25] });
  }
  p.spine.box(0.04, 0.2, 0.012, skinDark, { p: [0, 0.14, 0.08] });
  // Bata hospitalaria abierta y hecha jirones
  p.spine.tbox(0.12, 0.6, 0.17, { sx: 1.2, sz: 1.1 }, gown, { p: [0.13, 0.29, -0.005] });
  p.spine.tbox(0.12, 0.6, 0.17, { sx: 1.2, sz: 1.1 }, gown, { p: [-0.13, 0.29, -0.005] });
  p.spine.box(0.32, 0.6, 0.04, gown, { p: [0, 0.29, -0.075] });
  rags(p.hips, r, 7, gownDark, 0.02, 0.17, 0.11, 0.45, false);
  rags(p.hips, r, 4, gown, 0.04, 0.16, 0.1, 0.32);
  // Cabeza alargada, mandíbula enorme, pelo largo y fibroso
  const h = p.head;
  h.cyl(0.032, 0.04, 0.16, 5, skin, { p: [0, 0.07, 0] });
  h.tbox(0.18, 0.2, 0.2, { sx: 1.05, sz: 1.0 }, skin, { p: [0, 0.255, 0.0] });
  h.box(0.15, 0.06, 0.17, skinDark, { p: [0, 0.15, -0.005] });
  h.box(0.185, 0.03, 0.05, skinDark, { p: [0, 0.29, 0.09] });
  h.box(0.06, 0.045, 0.02, '#0c0c0a', { p: [-0.045, 0.255, 0.1] });
  h.box(0.06, 0.045, 0.02, '#0c0c0a', { p: [0.045, 0.255, 0.1] });
  h.box(0.13, 0.08, 0.1, '#140404', { p: [0, 0.15, 0.055] }); // garganta oscura
  h.box(0.12, 0.03, 0.02, PALETTE.bone, { p: [0, 0.165, 0.095] });
  for (let i = -2; i <= 2; i++) {
    h.cone(0.008, 0.03, 3, PALETTE.bone, { p: [i * 0.024, 0.142, 0.095], r: [Math.PI, 0, 0] });
  }
  h.box(0.195, 0.05, 0.21, '#141412', { p: [0, 0.37, -0.005] }); // cuero cabelludo
  const hair = '#121210';
  for (let i = 0; i < 16; i++) {
    const a = -2.3 + (4.6 * i) / 15 + (r() - 0.5) * 0.12;
    const len = 0.3 + r() * 0.22;
    const x = Math.sin(a) * 0.105;
    const z = Math.cos(a) * 0.11 - 0.005;
    if (Math.abs(a) < 0.55) continue; // deja la cara visible
    h.box(0.022, len, 0.016, hair, {
      p: [x * 1.05, 0.37 - len / 2, z * 1.03],
      r: [(r() - 0.5) * 0.15 - (z > 0 ? 0.12 : -0.1), a, (r() - 0.5) * 0.25 + (x > 0 ? 0.08 : -0.08)],
    });
  }
  // flequillo fibroso
  h.box(0.02, 0.2, 0.014, hair, { p: [0.06, 0.29, 0.108], r: [0.1, 0, 0.15] });
  h.box(0.018, 0.16, 0.014, hair, { p: [-0.075, 0.3, 0.106], r: [0.08, 0, -0.2] });
  p.jaw.tbox(0.15, 0.13, 0.16, { sx: 1.1, sz: 1.0 }, skin, { p: [0, -0.065, 0.085] });
  p.jaw.box(0.11, 0.05, 0.1, '#140404', { p: [0, -0.005, 0.09] });
  for (let i = -2; i <= 2; i++) {
    p.jaw.cone(0.008, 0.03, 3, PALETTE.bone, { p: [i * 0.022, 0.015, 0.14] });
  }
  for (const sd of [1, -1] as const) {
    addArm(p, d, sd, {
      upperR: 0.035,
      foreR: 0.03,
      upperColor: skin,
      foreColor: skin,
      sleeve: { color: gown, len: 0.35, r: 0.05 },
      skin,
      hand: 0.1,
      fingerLen: 0.11,
    });
    addLeg(p, d, sd, {
      thighR: 0.055,
      shinR: 0.045,
      thighColor: pants,
      shinColor: skin,
      foot: skinDark,
      footW: 0.09,
      footL: 0.24,
      footH: 0.07,
      bare: true,
    });
  }
}

function dressBrute(p: Parts, d: Dims): void {
  const r = rng(71);
  const skin = PALETTE.skinBrute;
  const skinDark = '#566146';
  const overall = PALETTE.olive;
  const overallDark = '#2c3520';
  const armor = '#1b1e20';
  const armorEdge = '#3a3f42';
  p.hips.box(0.52, 0.24, 0.34, overall, { p: [0, 0, 0] });
  p.hips.box(0.53, 0.05, 0.35, '#1a1612', { p: [0, 0.1, 0] });
  // Torso enorme en V (barril facetado)
  p.spine.cyl(0.42, 0.27, 0.56, 7, skin, { p: [0, 0.28, 0], s: [1, 1, 0.7] });
  p.spine.ico(0.26, skin, { p: [0, 0.52, -0.08], s: [1.5, 0.62, 1.0] }); // trapecios
  p.spine.ico(0.15, skin, { p: [0.13, 0.4, 0.17], s: [1.25, 0.8, 0.6] }); // pectorales
  p.spine.ico(0.15, skin, { p: [-0.13, 0.4, 0.17], s: [1.25, 0.8, 0.6] });
  p.spine.box(0.1, 0.12, 0.02, PALETTE.blood, { p: [0.14, 0.42, 0.262] });
  p.spine.box(0.02, 0.18, 0.02, '#4a5338', { p: [-0.04, 0.4, 0.275], r: [0, 0, 0.5] }); // cicatriz
  // Overol: pantalón alto + peto + tirantes
  p.spine.tbox(0.64, 0.32, 0.46, { sx: 1.08, sz: 1.05 }, overall, { p: [0, 0.15, 0.0] });
  p.spine.box(0.3, 0.2, 0.04, overall, { p: [0, 0.36, 0.25] });
  p.spine.box(0.1, 0.06, 0.02, overallDark, { p: [0, 0.38, 0.272] }); // bolsillo
  p.spine.box(0.06, 0.34, 0.03, overallDark, { p: [0.15, 0.5, 0.2], r: [0.35, 0, 0.12] }); // tirantes
  p.spine.box(0.06, 0.34, 0.03, overallDark, { p: [-0.15, 0.5, 0.2], r: [0.35, 0, -0.12] });
  // Restos del equipo antidisturbios
  p.spine.box(0.17, 0.13, 0.03, armor, { p: [-0.16, 0.44, 0.255], r: [0, -0.25, 0] });
  p.spine.box(0.15, 0.02, 0.035, armorEdge, { p: [-0.16, 0.5, 0.258], r: [0, -0.25, 0] });
  rags(p.spine, r, 5, overallDark, 0.0, 0.25, 0.17, 0.1);
  // Cabeza pequeña con casco roto, metida entre los hombros
  const h = p.head;
  h.cyl(0.12, 0.15, 0.12, 6, skin, { p: [0, 0.0, 0.02] });
  h.box(0.17, 0.15, 0.18, skin, { p: [0, 0.13, 0.06] });
  h.box(0.175, 0.035, 0.05, skinDark, { p: [0, 0.155, 0.135] });
  h.box(0.05, 0.03, 0.02, '#0c0c0a', { p: [-0.042, 0.13, 0.142] });
  h.box(0.05, 0.03, 0.02, '#0c0c0a', { p: [0.042, 0.13, 0.142] });
  h.box(0.1, 0.04, 0.06, '#1c0606', { p: [0, 0.075, 0.12] });
  h.box(0.1, 0.018, 0.02, PALETTE.bone, { p: [0, 0.09, 0.15] });
  h.tbox(0.21, 0.09, 0.23, { sx: 0.78, sz: 0.8 }, armor, { p: [0, 0.225, 0.05] }); // casco
  h.box(0.21, 0.025, 0.04, armorEdge, { p: [0, 0.185, 0.17] }); // visera rota
  h.box(0.06, 0.04, 0.01, '#6a7378', { p: [0.06, 0.205, 0.17], r: [0, 0, 0.4] });
  p.jaw.box(0.15, 0.06, 0.15, skin, { p: [0, -0.02, 0.1] });
  p.jaw.box(0.1, 0.018, 0.02, PALETTE.bone, { p: [0, 0.01, 0.17] });
  for (const sd of [1, -1] as const) {
    addArm(p, d, sd, {
      upperR: 0.11,
      foreR: 0.1,
      upperColor: skin,
      foreColor: skin,
      skin,
      hand: 0.15,
      fingerLen: 0.06,
    });
    addLeg(p, d, sd, {
      thighR: 0.12,
      shinR: 0.1,
      thighColor: overall,
      shinColor: overall,
      foot: '#1a1816',
      footW: 0.16,
      footL: 0.3,
      footH: 0.11,
    });
    const sh = side(sd, p.shinL, p.shinR);
    sh.tbox(0.15, 0.16, 0.08, { sx: 0.8 }, armor, { p: [0, -0.08, 0.07] }); // rodillera
  }
  // Hombrera sólo en el derecho; el izquierdo lleva la herida a la vista
  p.armR.ico(0.17, armor, { p: [-0.02, 0.02, 0], s: [1.05, 0.75, 1.0] });
  p.armR.box(0.2, 0.02, 0.05, armorEdge, { p: [-0.02, 0.0, 0.14] });
  p.armL.box(0.08, 0.1, 0.02, PALETTE.blood, { p: [0.03, -0.12, 0.105] });
  p.foreR.tbox(0.15, 0.2, 0.15, { sx: 0.9, sz: 0.9 }, armor, { p: [0, -0.17, 0] }); // brazal
  p.foreL.box(0.13, 0.05, 0.12, overallDark, { p: [0, -0.04, 0] }); // trapo atado
}

const DRESS: Record<ZombieTypeId, (p: Parts, d: Dims) => void> = {
  walker: dressWalker,
  runner: dressRunner,
  bloater: dressBloater,
  screamer: dressScreamer,
  brute: dressBrute,
};

// ---------------------------------------------------------------------------
// Curvas de animación
// ---------------------------------------------------------------------------

/** Sube suavemente de a→b y baja de b→c (0 fuera de [a, c]). */
function bump(u: number, a: number, b: number, c: number): number {
  if (u <= a || u >= c) return 0;
  if (u < b) return smooth01((u - a) / (b - a));
  return 1 - smooth01((u - b) / (c - b));
}

/** Impulso: subida rápida en `rise` segundos y caída exponencial. */
function impulse(t: number, rise: number, decay: number): number {
  if (t < 0) return 0;
  if (t < rise) return t / rise;
  return Math.exp(-(t - rise) * decay);
}

type MainAction = 'none' | 'attack' | 'lungeMiss' | 'dodge' | 'charge' | 'scream' | 'stun';

const BASE_DUR: Record<Exclude<MainAction, 'none'>, number> = {
  attack: 0.85,
  lungeMiss: 1.05,
  dodge: 0.6,
  charge: 1.15,
  scream: 1.55,
  stun: 1.3,
};

const SMOOTH = 20;
const DEATH_SINK_START = 1.9;
const DEATH_END = 3.6;

const _eyeBase = new THREE.Color(PALETTE.eye);
const _eyeHot = new THREE.Color(PALETTE.eyeHot);
const _chestLocal = new THREE.Vector3();

class ZombieRigImpl implements ZombieRig {
  readonly type: ZombieTypeId;
  readonly root = new THREE.Group();
  readonly height: number;

  private readonly d: Dims;
  private readonly body = new THREE.Group();
  private readonly hips = new THREE.Group();
  private readonly spine = new THREE.Group();
  private readonly head = new THREE.Group();
  private readonly jaw = new THREE.Group();
  private readonly armL = new THREE.Group();
  private readonly elbowL = new THREE.Group();
  private readonly armR = new THREE.Group();
  private readonly elbowR = new THREE.Group();
  private readonly legL = new THREE.Group();
  private readonly kneeL = new THREE.Group();
  private readonly legR = new THREE.Group();
  private readonly kneeR = new THREE.Group();
  private belly: THREE.Mesh | null = null;
  private readonly eyes: THREE.Mesh;
  private readonly eyeGlow: THREE.Mesh;
  private readonly shadow: THREE.Mesh;

  private readonly bodyMat: THREE.MeshLambertMaterial;
  private readonly eyeMat: THREE.MeshBasicMaterial;
  private readonly glowMat: THREE.MeshBasicMaterial;
  private readonly shadowMat: THREE.MeshBasicMaterial;
  private readonly shadowOpacity: number;

  private readonly target = new Float32Array(CHANNELS);
  private readonly cur = new Float32Array(CHANNELS);
  private readonly deathBase = new Float32Array(CHANNELS);

  private t = 0;
  private crouch = 0;
  private readonly rand = rng(Math.floor(Math.random() * 1e9));

  private main: MainAction = 'none';
  private mainT = 0;
  private mainDur = 1;
  private mainDir = 1;

  private hitT = -1;
  private hitStrong = false;
  private hitDir = 1;
  private flash = 0;

  private stanceTarget = 0;
  private stance = 0;

  private twitchT = 0.6;
  private twitchAge = 10;
  private twX = 0;
  private twY = 0;
  private twZ = 0;

  private dead = false;
  private deathT = 0;
  private gone = false;
  private dodgeSide = 1;
  private facing = 0;
  private reach = 4.5;

  constructor(type: ZombieTypeId) {
    this.type = type;
    const d = DIMS[type];
    this.d = d;
    this.root.name = `zombie:${type}`;

    const parts = makeParts(type.length * 97 + 13);
    DRESS[type](parts, d);

    this.bodyMat = cloneMat(vcLambert());
    this.eyeMat = cloneMat(vcBasic());
    this.eyeMat.color.copy(_eyeBase);
    const glow = glowDisc(PALETTE.ember, 1, 0.4);
    this.glowMat = cloneMat(glow.material as THREE.MeshBasicMaterial);
    glow.material = this.glowMat;
    this.eyeGlow = glow;

    // Jerarquía
    const m = this.bodyMat;
    this.root.add(this.body);
    this.body.add(this.hips);
    this.hips.position.y = d.hipY;
    parts.hips.attachTo(this.hips, m, 'hips');

    for (const [leg, knee, pb, sb, sx] of [
      [this.legL, this.kneeL, parts.legL, parts.shinL, 1],
      [this.legR, this.kneeR, parts.legR, parts.shinR, -1],
    ] as const) {
      leg.position.set(sx * d.legGap, -0.02, 0);
      this.hips.add(leg);
      pb.attachTo(leg, m, 'thigh');
      knee.position.y = -d.thigh;
      leg.add(knee);
      sb.attachTo(knee, m, 'shin');
    }

    this.spine.position.y = d.waist;
    this.hips.add(this.spine);
    parts.spine.attachTo(this.spine, m, 'torso');
    this.belly = parts.belly.attachTo(this.spine, m, 'belly');
    if (this.belly) {
      // escalar desde el centro de la panza
      const bb = this.belly.geometry.boundingSphere;
      if (bb) {
        this.belly.geometry.translate(-bb.center.x, -bb.center.y, -bb.center.z);
        this.belly.position.copy(bb.center);
      }
    }

    this.head.position.y = d.spine;
    this.spine.add(this.head);
    parts.head.attachTo(this.head, m, 'head');
    this.jaw.position.set(d.jaw[0], d.jaw[1], d.jaw[2]);
    this.head.add(this.jaw);
    parts.jaw.attachTo(this.jaw, m, 'jaw');

    // Ojos brillantes
    const es = 0.04 * d.eyeSize;
    const ey: [number, number, number] = [d.eyes[0], d.eyes[1], d.eyes[2]];
    parts.eyes.box(es, es * 0.6, 0.012, '#ffffff', { p: [ey[0], ey[1], ey[2]] });
    parts.eyes.box(es, es * 0.6, 0.012, '#ffffff', { p: [-ey[0], ey[1], ey[2]] });
    this.eyes = parts.eyes.mesh(this.eyeMat, 'eyes');
    this.eyes.userData.mergeable = false;
    this.head.add(this.eyes);
    this.eyeGlow.position.set(0, ey[1], ey[2] + 0.02);
    this.eyeGlow.scale.set(ey[0] * 2.6, 0.06, 1);
    this.head.add(this.eyeGlow);

    for (const [arm, elbow, ub, fb, sx] of [
      [this.armL, this.elbowL, parts.armL, parts.foreL, 1],
      [this.armR, this.elbowR, parts.armR, parts.foreR, -1],
    ] as const) {
      arm.position.set(sx * d.shoulderX, d.shoulderY, 0);
      this.spine.add(arm);
      ub.attachTo(arm, m, 'upperArm');
      elbow.position.y = -d.upperArm;
      arm.add(elbow);
      fb.attachTo(elbow, m, 'foreArm');
    }

    // Sombra (material propio para poder desvanecerla)
    this.shadow = blobShadow(d.shadow, 0.6);
    this.shadowMat = cloneMat(this.shadow.material as THREE.MeshBasicMaterial);
    this.shadow.material = this.shadowMat;
    this.shadowOpacity = this.shadowMat.opacity;
    this.root.add(this.shadow);

    this.root.scale.setScalar(d.scale);
    const headTop = type === 'screamer' ? 0.42 : type === 'brute' ? 0.28 : 0.33;
    this.height = (d.hipY + d.waist + d.spine + headTop) * d.scale;

    // Pose inicial sin interpolar
    this.computeTarget(0);
    this.cur.set(this.target);
    this.applyPose();
  }

  get isDead(): boolean {
    return this.dead;
  }

  get isGone(): boolean {
    return this.gone;
  }

  // -------------------------------------------------------------------------
  // Disparadores
  // -------------------------------------------------------------------------

  private startMain(kind: Exclude<MainAction, 'none'>, dir = this.rand() < 0.5 ? -1 : 1): number {
    if (this.dead) return 0;
    this.main = kind;
    this.mainT = 0;
    this.mainDur = BASE_DUR[kind] / this.d.speed;
    this.mainDir = dir;
    return this.mainDur;
  }

  attack(): number {
    if (this.dead) return 0;
    this.stanceTarget = 0;
    const dur = this.startMain('attack');
    return dur * 0.4;
  }

  lungeMiss(): void {
    if (this.dead) return;
    this.stanceTarget = 0;
    this.startMain('lungeMiss');
  }

  hit(strong: boolean): void {
    if (this.dead) return;
    this.hitT = 0;
    this.hitStrong = strong;
    this.hitDir = this.rand() < 0.5 ? -1 : 1;
    this.flash = strong ? 1.25 : 0.9;
  }

  dodge(): void {
    if (this.dead) return;
    this.dodgeSide = -this.dodgeSide;
    this.startMain('dodge', this.dodgeSide);
  }

  chargePrepare(): void {
    if (this.dead) return;
    this.stanceTarget = 1;
  }

  charge(): number {
    if (this.dead) return 0;
    this.stanceTarget = 0;
    this.stance = Math.min(this.stance, 0.6);
    const dur = this.startMain('charge');
    return dur * 0.2;
  }

  scream(): number {
    if (this.dead) return 0;
    this.stanceTarget = 0;
    const dur = this.startMain('scream');
    return dur * 0.26;
  }

  stun(): void {
    if (this.dead) return;
    this.stanceTarget = 0;
    this.startMain('stun');
  }

  die(): void {
    if (this.dead) return;
    this.dead = true;
    this.deathT = 0;
    this.deathBase.set(this.cur);
    this.main = 'none';
    this.stanceTarget = 0;
    this.flash = Math.max(this.flash, 0.6);
  }

  setReach(distance: number): void {
    this.reach = Math.max(1, distance);
  }

  private lunge(): number {
    return Math.min(this.d.lunge, this.reach * 0.42);
  }

  setFacing(yaw: number): void {
    this.facing = yaw;
    this.root.rotation.y = yaw;
  }

  getHeadWorldPosition(target: THREE.Vector3): THREE.Vector3 {
    return this.head.localToWorld(target.set(0, this.d.eyes[1], 0.02));
  }

  getChestWorldPosition(target: THREE.Vector3): THREE.Vector3 {
    _chestLocal.set(0, this.d.spine * 0.6, 0.12);
    return this.spine.localToWorld(target.copy(_chestLocal));
  }

  // -------------------------------------------------------------------------
  // Bucle
  // -------------------------------------------------------------------------

  update(dt: number): void {
    if (this.gone) return;
    this.t += dt;
    if (this.main !== 'none') {
      this.mainT += dt;
      if (this.mainT >= this.mainDur) this.main = 'none';
    }
    if (this.hitT >= 0) {
      this.hitT += dt;
      if (this.hitT > 1.2) this.hitT = -1;
    }
    this.stance += (this.stanceTarget - this.stance) * (1 - Math.exp(-(this.stanceTarget > this.stance ? 5 : 3) * dt));
    this.flash = Math.max(0, this.flash - dt * (this.hitStrong ? 3.2 : 4.5));
    this.updateTwitch(dt);

    if (this.dead) {
      this.deathT += dt;
      this.computeDeath(this.deathT);
    } else {
      this.computeTarget(this.t);
    }

    const k = 1 - Math.exp(-(this.dead ? 28 : SMOOTH) * dt);
    const cur = this.cur;
    const tgt = this.target;
    for (let i = 0; i < CHANNELS; i++) cur[i] += (tgt[i] - cur[i]) * k;
    this.applyPose();
    this.applyMaterials();
  }

  private updateTwitch(dt: number): void {
    this.twitchAge += dt;
    const twitchy = this.type === 'runner' || this.type === 'screamer';
    if (!twitchy || this.dead) return;
    this.twitchT -= dt;
    if (this.twitchT <= 0) {
      const r = this.rand;
      this.twitchT = (this.type === 'runner' ? 0.35 : 0.8) + r() * 1.3;
      this.twitchAge = 0;
      const amp = this.type === 'runner' ? 1 : 0.7;
      this.twX = (r() - 0.5) * 0.5 * amp;
      this.twY = (r() - 0.5) * 1.0 * amp;
      this.twZ = (r() - 0.5) * 0.8 * amp;
    }
  }

  private computeTarget(t: number): void {
    const T = this.target;
    T.fill(0);
    this.crouch = 0;
    this.idle(T, t);

    // Postura de preparación de carga (se mantiene)
    const s = this.stance;
    if (s > 0.001) {
      this.crouch += 0.42 * s;
      T[SX] += 0.38 * s;
      T[HX] -= 0.4 * s;
      T[ALX] += 0.55 * s;
      T[ARX] += 0.55 * s;
      T[ALZ] += 0.25 * s;
      T[ARZ] += 0.25 * s;
      T[EL] -= 0.45 * s;
      T[ER] -= 0.45 * s;
      T[BRY] += 0.3 * s;
      T[BX] += Math.sin(t * 41) * 0.012 * s;
      T[HY] += Math.sin(t * 33) * 0.03 * s;
      T[JAW] += 0.3 * s;
      T[EYE] += 1.1 * s;
    }

    if (this.main !== 'none') this.applyMain(T, this.main, this.mainT, this.mainT / this.mainDur, this.mainDir);
    if (this.hitT >= 0) this.applyHit(T, this.hitT);
    this.applyCrouch(T, this.crouch);
  }

  private applyCrouch(T: Float32Array, a: number): void {
    if (a === 0) return;
    const d = this.d;
    T[LLX] -= a;
    T[LRX] -= a;
    T[KL] += 2 * a;
    T[KR] += 2 * a;
    T[HIPS] -= (d.thigh + d.shin) * (1 - Math.cos(a));
    T[SX] += a * 0.35;
  }

  private idle(T: Float32Array, t: number): void {
    const tw = Math.exp(-this.twitchAge * 9);
    switch (this.type) {
      case 'walker': {
        const w = Math.sin(t * 0.9);
        T[BRZ] = w * 0.05;
        T[BRY] = Math.sin(t * 0.43) * 0.1;
        T[BX] = w * 0.025;
        T[SX] = 0.16 + Math.sin(t * 1.8) * 0.02;
        T[SZ] = Math.sin(t * 0.9 + 0.6) * 0.05;
        T[SY] = Math.sin(t * 0.45) * 0.06;
        T[HX] = -0.14 + Math.sin(t * 1.1) * 0.05;
        T[HY] = Math.sin(t * 0.5 + 1) * 0.15;
        T[HZ] = 0.26 + Math.sin(t * 0.7) * 0.07;
        T[JAW] = 0.14 + Math.max(0, Math.sin(t * 2.6)) * 0.14;
        T[ALX] = -1.28 + Math.sin(t * 1.3) * 0.08;
        T[ALZ] = 0.12;
        T[EL] = -0.22 + Math.sin(t * 1.3 + 0.5) * 0.08;
        T[ARX] = -1.02 + Math.sin(t * 1.2 + 2) * 0.08;
        T[ARZ] = 0.05;
        T[ER] = -0.4;
        T[LLX] = w * 0.07;
        T[LRX] = -w * 0.07 - 0.08;
        T[KL] = 0.06 + Math.max(0, w) * 0.12;
        T[KR] = 0.14 + Math.max(0, -w) * 0.12;
        T[LLZ] = 0.03;
        T[LRZ] = 0.03;
        T[EYE] = 0.15 + Math.sin(t * 2.1) * 0.05;
        break;
      }
      case 'runner': {
        const b = Math.abs(Math.sin(t * 3.8));
        this.crouch = 0.4 + b * 0.05;
        T[LLX] = -0.25;
        T[KL] = 0.15;
        T[LRX] = 0.15;
        T[LLZ] = 0.1;
        T[LRZ] = 0.08;
        T[SX] = 0.62 + Math.sin(t * 3.8) * 0.03;
        T[SZ] = 0.1 + this.twZ * 0.25 * tw;
        T[HX] = -0.95 + Math.sin(t * 7.1) * 0.025 + this.twX * tw;
        T[HY] = Math.sin(t * 13) * 0.03 + Math.sin(t * 7.7) * 0.04 + this.twY * tw;
        T[HZ] = 0.1 + Math.sin(t * 11.3) * 0.02 + this.twZ * tw;
        T[JAW] = 0.28 + Math.sin(t * 9) * 0.06;
        T[ALX] = -1.55 + Math.sin(t * 3.8) * 0.06;
        T[ALZ] = 0.38 + this.twY * 0.1 * tw;
        T[EL] = -0.95;
        T[ARX] = -1.25 + Math.sin(t * 3.8 + 1) * 0.06;
        T[ARZ] = 0.45;
        T[ER] = -1.1 + this.twX * 0.3 * tw;
        T[BRY] = this.twY * 0.12 * tw + Math.sin(t * 0.8) * 0.06;
        T[EYE] = 0.3 + Math.sin(t * 5) * 0.08;
        break;
      }
      case 'bloater': {
        const w = Math.sin(t * 0.6);
        this.crouch = 0.08;
        T[BRZ] = w * 0.06;
        T[BX] = w * 0.03;
        T[BRY] = Math.sin(t * 0.31) * 0.08;
        T[SX] = -0.08 + Math.sin(t * 1.2) * 0.02;
        T[SZ] = Math.sin(t * 0.6 + 0.4) * 0.05;
        T[HX] = 0.02 + Math.sin(t * 0.9) * 0.06;
        T[HZ] = Math.sin(t * 0.5) * 0.12;
        T[HY] = Math.sin(t * 0.37) * 0.2;
        T[JAW] = 0.22 + Math.sin(t * 1.2) * 0.08;
        T[ALX] = -0.62 + Math.sin(t * 1.2) * 0.05;
        T[ALZ] = 0.44;
        T[EL] = -0.8;
        T[ARX] = -0.55 + Math.sin(t * 1.2 + 0.8) * 0.05;
        T[ARZ] = 0.46;
        T[ER] = -0.7;
        T[LLZ] = 0.1;
        T[LRZ] = 0.1;
        T[EYE] = 0.15;
        break;
      }
      case 'screamer': {
        T[BRZ] = Math.sin(t * 0.7) * 0.06;
        T[BRY] = Math.sin(t * 0.35) * 0.12;
        T[SX] = 0.26 + Math.sin(t * 1.4) * 0.03;
        T[SZ] = Math.sin(t * 0.7 + 1) * 0.08;
        T[HX] = -0.32 + Math.sin(t * 1.7) * 0.05 + this.twX * tw;
        T[HY] = Math.sin(t * 0.6) * 0.1 + this.twY * tw;
        T[HZ] = -0.18 + Math.sin(t * 0.8) * 0.06 + this.twZ * tw;
        T[JAW] = 0.68 + Math.sin(t * 2.7) * 0.08;
        T[ALX] = -0.42 + Math.sin(t * 0.7) * 0.08;
        T[ALZ] = 0.13 + Math.sin(t * 0.9) * 0.04;
        T[EL] = -0.18;
        T[ARX] = -0.36 + Math.sin(t * 0.7 + 1.5) * 0.08;
        T[ARZ] = 0.15;
        T[ER] = -0.28;
        T[LLZ] = 0.02;
        T[KL] = 0.12;
        T[KR] = 0.06;
        T[LRX] = -0.08;
        T[EYE] = 0.25;
        break;
      }
      case 'brute': {
        const b = Math.sin(t * 1.5);
        const w = Math.sin(t * 0.75);
        this.crouch = 0.17;
        T[SX] = 0.26 + b * 0.035;
        T[ALX] = -0.42 + b * 0.04;
        T[ALZ] = 0.2;
        T[EL] = -0.75;
        T[ARX] = -0.5 + b * 0.04;
        T[ARZ] = 0.18;
        T[ER] = -0.7;
        T[HX] = -0.32 + b * 0.03;
        T[HY] = Math.sin(t * 0.4) * 0.12;
        T[HZ] = Math.sin(t * 0.53) * 0.05;
        T[BRZ] = w * 0.04;
        T[BX] = w * 0.03;
        T[LLZ] = 0.1;
        T[LRZ] = 0.1;
        T[JAW] = 0.16 + Math.max(0, b) * 0.1;
        T[EYE] = 0.2;
        break;
      }
    }
  }

  private applyMain(T: Float32Array, kind: MainAction, time: number, u: number, dir: number): void {
    const inv = 1 / this.d.scale;
    switch (kind) {
      case 'attack': {
        const w = bump(u, 0, 0.28, 0.42);
        const s = bump(u, 0.28, 0.4, 0.95);
        T[BZ] += (-0.15 * w + this.lunge() * s) * inv;
        T[SX] += -0.35 * w + 0.5 * s;
        T[HX] += -0.25 * w - 0.2 * s;
        T[ALX] += -1.0 * w + 0.35 * s;
        T[ARX] += -1.15 * w + 0.15 * s;
        T[EL] += -0.3 * w + 0.25 * s;
        T[ER] += -0.35 * w + 0.3 * s;
        T[ALZ] += 0.25 * w;
        T[ARZ] += 0.3 * w;
        T[JAW] += 0.35 * w + 0.6 * s;
        T[BRY] += 0.22 * s * dir;
        T[LLX] -= 0.45 * s;
        T[KL] += 0.25 * s;
        T[LRX] += 0.25 * s;
        T[EYE] += 0.6 * s;
        break;
      }
      case 'lungeMiss': {
        const w = bump(u, 0, 0.2, 0.34);
        const s = bump(u, 0.2, 0.4, 0.78);
        const st = bump(u, 0.38, 0.6, 1.0);
        T[BZ] += (-0.1 * w + this.lunge() * 0.65 * s) * inv;
        T[BX] += (dir * 0.75 * s + dir * 0.25 * st) * inv;
        T[BRY] += dir * 0.65 * s;
        T[SX] += 0.45 * s + 0.3 * st;
        T[BRZ] -= dir * 0.18 * st;
        T[SZ] -= dir * 0.3 * s;
        T[ALX] += -0.7 * w + 0.4 * s;
        T[ARX] += -0.7 * w + 0.4 * s;
        T[HX] += 0.25 * st;
        T[HZ] += dir * 0.3 * st;
        T[JAW] += 0.5 * s;
        T[LLX] -= 0.45 * s;
        T[KR] += 0.4 * st;
        this.crouch += 0.18 * st;
        break;
      }
      case 'dodge': {
        const e = bump(u, 0, 0.3, 1.0);
        T[BX] += dir * 0.55 * e * inv;
        T[BRZ] -= dir * 0.1 * e;
        T[SZ] -= dir * 0.28 * e;
        T[BRY] += dir * 0.3 * e;
        T[HX] += 0.1 * e;
        T[HZ] += dir * 0.2 * e;
        T[ALZ] += 0.35 * e;
        T[ARZ] += 0.35 * e;
        T[ALX] += 0.3 * e;
        T[ARX] += 0.3 * e;
        this.crouch += 0.18 * e;
        break;
      }
      case 'charge': {
        const pc = u < 0.2 ? smooth01(u / 0.2) : 1 - smooth01((u - 0.3) / 0.6);
        T[BZ] += Math.min(2.4, this.reach * 0.46) * pc * inv;
        T[SX] += 0.55 * pc;
        T[HX] -= 0.45 * pc;
        T[BRY] += 0.45 * pc * dir;
        T[ALX] += 0.5 * pc;
        T[ARX] += -1.2 * pc;
        const run = Math.sin(time * 26) * 0.7 * pc;
        T[LLX] += run;
        T[LRX] -= run;
        T[KL] += 0.5 * pc;
        T[KR] += 0.5 * pc;
        T[JAW] += 0.6 * pc;
        T[EYE] += 1.0 * pc;
        this.crouch += 0.15 * pc;
        break;
      }
      case 'scream': {
        const inh = bump(u, 0, 0.17, 0.3);
        const sc = bump(u, 0.2, 0.3, 0.92);
        T[SX] += -0.32 * inh + 0.3 * sc;
        T[HX] += -0.6 * inh - 0.3 * sc;
        T[JAW] += 0.25 * inh + 0.95 * sc;
        T[ALZ] += 0.95 * sc;
        T[ARZ] += 0.95 * sc;
        T[ALX] += -0.35 * sc - 0.2 * inh;
        T[ARX] += -0.35 * sc - 0.2 * inh;
        T[EL] += 0.15 * sc;
        T[ER] += 0.15 * sc;
        T[HY] += Math.sin(time * 47) * 0.05 * sc;
        T[BX] += Math.sin(time * 31) * 0.012 * sc;
        T[BY] += 0.04 * sc;
        T[EYE] += 0.9 * sc;
        break;
      }
      case 'stun': {
        const a = bump(u, 0, 0.08, 1.0);
        T[BRZ] += Math.sin(time * 7.5) * 0.15 * a;
        T[BRX] += Math.sin(time * 5.1) * 0.06 * a;
        T[HZ] += Math.sin(time * 5.5) * 0.45 * a;
        T[HX] += (0.35 + Math.sin(time * 4.4) * 0.15) * a;
        T[JAW] += 0.3 * a;
        const limp = 1 - 0.75 * a;
        T[ALX] *= limp;
        T[ARX] *= limp;
        T[EL] *= limp;
        T[ER] *= limp;
        T[ALZ] += Math.sin(time * 7.5) * 0.2 * a;
        T[ARZ] -= Math.sin(time * 7.5) * 0.2 * a;
        T[EYE] -= 0.5 * a;
        this.crouch += 0.22 * a;
        break;
      }
      case 'none':
        break;
    }
  }

  private applyHit(T: Float32Array, time: number): void {
    const strong = this.hitStrong;
    const e = impulse(time, 0.05, strong ? 4.5 : 6.5);
    const dir = this.hitDir;
    const inv = 1 / this.d.scale;
    T[BZ] -= (strong ? 0.38 : 0.16) * e * inv;
    T[SX] -= (strong ? 0.6 : 0.32) * e;
    T[HX] -= (strong ? 0.6 : 0.4) * e;
    T[HZ] += dir * 0.3 * e;
    T[HY] += dir * 0.25 * e;
    T[ALX] -= 0.55 * e;
    T[ARX] -= 0.45 * e;
    T[ALZ] += 0.35 * e;
    T[ARZ] += 0.35 * e;
    T[BRY] += dir * 0.18 * e;
    T[BRZ] += dir * 0.06 * e;
    T[JAW] += 0.45 * e;
    if (strong) this.crouch += 0.12 * e;
  }

  private computeDeath(t: number): void {
    const T = this.target;
    T.set(this.deathBase);
    const e1 = smooth01(t / 0.25);
    const f = clamp01((t - 0.12) / 0.72);
    const fe = f * f;
    // Rodillas ceden, cabeza hacia atrás, brazos arriba
    T[HIPS] -= 0.1 * e1 * (1 - fe);
    T[KL] = T[KL] * (1 - e1) + 0.6 * e1 * (1 - fe * 0.7);
    T[KR] = T[KR] * (1 - e1) + 0.5 * e1 * (1 - fe * 0.7);
    T[LLX] = T[LLX] * (1 - e1) - 0.3 * e1 * (1 - fe);
    T[LRX] = T[LRX] * (1 - e1) - 0.2 * e1 * (1 - fe);
    T[HX] = T[HX] * (1 - e1) - 0.55 * e1;
    T[SX] = T[SX] * (1 - e1) - 0.2 * e1;
    T[JAW] = 0.75;
    const armUp = e1 * (1 - smooth01((t - 0.9) / 0.5));
    T[ALX] = T[ALX] * (1 - e1) - 2.2 * armUp - 0.4 * e1;
    T[ARX] = T[ARX] * (1 - e1) - 2.0 * armUp - 0.5 * e1;
    T[ALZ] = T[ALZ] * (1 - e1) + 0.5 * e1 + 0.5 * smooth01((t - 0.9) / 0.5);
    T[ARZ] = T[ARZ] * (1 - e1) + 0.6 * e1 + 0.4 * smooth01((t - 0.9) / 0.5);
    T[EL] = -0.3 * e1;
    T[ER] = -0.2 * e1;
    // Caída hacia atrás pivotando en los pies
    T[BRX] = -1.5 * fe;
    T[BRY] = T[BRY] * (1 - e1);
    T[BRZ] = T[BRZ] * (1 - e1);
    T[BZ] = T[BZ] - 0.3 * fe;
    T[BY] = T[BY] + 0.1 * fe;
    if (t > 0.84) {
      const k = t - 0.84;
      T[BRX] += Math.sin(k * 16) * 0.07 * Math.exp(-k * 6);
    }
    // Hundimiento
    const sink = smooth01((t - DEATH_SINK_START) / (DEATH_END - DEATH_SINK_START - 0.2));
    T[BY] -= 0.55 * sink;
    T[EYE] = -1 * smooth01(t / 0.7);
  }

  private applyPose(): void {
    const c = this.cur;
    // Desplazamientos del cuerpo en ejes del mundo (compensa el giro de `root`)
    const fc = Math.cos(-this.facing);
    const fs = Math.sin(-this.facing);
    const bx = c[BX] * fc + c[BZ] * fs;
    const bz = -c[BX] * fs + c[BZ] * fc;
    const look = this.dead ? 1 - smooth01(this.deathT / 0.4) : 1;
    this.body.position.set(bx, c[BY], bz);
    this.body.rotation.set(c[BRX], c[BRY], c[BRZ]);
    this.hips.position.y = this.d.hipY + c[HIPS];
    this.spine.rotation.set(c[SX], c[SY] - this.facing * 0.3 * look, c[SZ]);
    this.head.rotation.set(c[HX], c[HY] - this.facing * 0.6 * look, c[HZ]);
    this.jaw.rotation.x = Math.max(0, c[JAW]);
    this.armL.rotation.set(c[ALX], c[ALY], c[ALZ]);
    this.elbowL.rotation.x = Math.min(0, c[EL]);
    this.armR.rotation.set(c[ARX], -c[ARY], -c[ARZ]);
    this.elbowR.rotation.x = Math.min(0, c[ER]);
    this.legL.rotation.set(c[LLX], 0, c[LLZ]);
    this.kneeL.rotation.x = Math.max(0, c[KL]);
    this.legR.rotation.set(c[LRX], 0, -c[LRZ]);
    this.kneeR.rotation.x = Math.max(0, c[KR]);

    // Sombra: sigue al cuerpo en el suelo
    this.shadow.position.x = bx;
    this.shadow.position.z = bz - Math.sin(-c[BRX]) * 0.6;
    const stretch = 1 + Math.abs(Math.sin(c[BRX])) * 1.4;
    this.shadow.scale.set(this.d.shadow, this.d.shadow * stretch, 1);

    if (this.belly) {
      let s = 1 + Math.sin(this.t * 1.25) * 0.035;
      if (this.dead) s += 0.22 * smooth01(this.deathT / 0.35) * (1 - smooth01((this.deathT - 0.6) / 0.6));
      this.belly.scale.setScalar(s);
    }
  }

  private applyMaterials(): void {
    // Destello de golpe (emisivo rojo)
    const f = Math.min(1, this.flash);
    this.bodyMat.emissive.setRGB(0.3 * f, 0.012 * f, 0.004 * f);

    // Ojos
    const g = this.cur[EYE];
    const glow = clamp01(g);
    this.eyeMat.color.lerpColors(_eyeBase, _eyeHot, glow);
    if (g < 0) this.eyeMat.color.multiplyScalar(clamp01(1 + g));
    const es = 1 + glow * 0.6;
    this.eyes.scale.set(es, es, 1);
    this.glowMat.opacity = clamp01(0.25 + glow * 0.75) * clamp01(1 + g);
    this.eyeGlow.scale.y = 0.06 + glow * 0.05;

    // Fundido al morir
    if (this.dead) {
      const fade = 1 - smooth01((this.deathT - DEATH_SINK_START - 0.3) / (DEATH_END - DEATH_SINK_START - 0.3));
      if (fade < 1 && !this.bodyMat.transparent) {
        this.bodyMat.transparent = true;
        this.bodyMat.needsUpdate = true;
      }
      this.bodyMat.opacity = fade;
      this.shadowMat.opacity = this.shadowOpacity * fade;
      if (this.deathT >= DEATH_END) {
        this.gone = true;
        this.body.visible = false;
        this.shadow.visible = false;
      }
    }
  }
}

/** Crea un zombie procedural del tipo indicado. */
export function createZombie(type: ZombieTypeId): ZombieRig {
  return new ZombieRigImpl(type);
}
