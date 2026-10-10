// Superviviente low-poly: chaqueta militar con capucha, mochila con saco de dormir,
// pañuelo/bandana con color de acento, pantalón cargo, botas y un machete.
//
// Convenciones: metros, pies en y = 0, mira hacia +Z, altura ~1.75 m.

import * as THREE from 'three';
import { PALETTE, PartBatch, blobShadow, cloneMat, lambert, vcLambert } from './materials';

export interface SurvivorOptions {
  /** Color del pañuelo/bandana (p. ej. el color de la facción). */
  accentColor?: string;
}

export interface SurvivorRig {
  root: THREE.Group;
  update(dt: number): void;
  /** Cambia el color de acento sin reconstruir el modelo. */
  setAccentColor(color: string): void;
}

const HIP_Y = 0.9;
const THIGH = 0.42;
const SHIN = 0.42;
const SPINE = 0.5;
const UPPER = 0.29;
const FORE = 0.27;

export function createSurvivor(opts: SurvivorOptions = {}): SurvivorRig {
  const jacket = PALETTE.army;
  const jacketDark = PALETTE.olive;
  const jacketDeep = '#2f3818';
  const pants = PALETTE.charcoal;
  const pantsDark = '#222628';
  const boot = '#1d1a16';
  const glove = '#141516';
  const skin = '#a07e62';
  const skinShadow = '#6e5442';
  const pack = '#3a3528';
  const packDark = '#2a261d';

  const mk = (seed: number) => new PartBatch(seed, 0.06);
  const hipsB = mk(1);
  const spineB = mk(2);
  const headB = mk(3);
  const accentB = new PartBatch(4, 0.1);
  const accentHeadB = new PartBatch(5, 0.1);
  const armLB = mk(6);
  const foreLB = mk(7);
  const armRB = mk(8);
  const foreRB = mk(9);
  const legLB = mk(10);
  const shinLB = mk(11);
  const legRB = mk(12);
  const shinRB = mk(13);
  const white = '#ffffff';

  // Cadera: faldón de la chaqueta + cinturón con bolsillos
  hipsB.box(0.34, 0.2, 0.22, pants, { p: [0, 0, 0] });
  hipsB.tbox(0.4, 0.16, 0.27, { sx: 0.94, sz: 0.94 }, jacket, { p: [0, 0.06, 0] });
  hipsB.box(0.41, 0.045, 0.28, '#211d16', { p: [0, 0.0, 0] });
  hipsB.box(0.09, 0.1, 0.06, jacketDark, { p: [0.15, -0.02, 0.13] });
  hipsB.box(0.09, 0.1, 0.06, jacketDark, { p: [-0.13, -0.02, 0.13] });

  // Torso
  spineB.tbox(0.36, 0.52, 0.24, { sx: 1.18, sz: 1.05 }, jacket, { p: [0, 0.26, 0] });
  spineB.box(0.012, 0.48, 0.01, jacketDeep, { p: [0.02, 0.26, 0.128] }); // cremallera
  spineB.box(0.12, 0.11, 0.03, jacketDark, { p: [0.1, 0.33, 0.13] }); // bolsillos de pecho
  spineB.box(0.12, 0.11, 0.03, jacketDark, { p: [-0.1, 0.33, 0.13] });
  spineB.box(0.12, 0.025, 0.035, jacketDeep, { p: [0.1, 0.39, 0.132] });
  spineB.box(0.12, 0.025, 0.035, jacketDeep, { p: [-0.1, 0.39, 0.132] });
  spineB.box(0.08, 0.04, 0.012, PALETTE.rust, { p: [-0.13, 0.46, 0.13] }); // parche
  // Correas de la mochila
  for (const sd of [1, -1]) {
    spineB.box(0.05, 0.5, 0.02, packDark, { p: [sd * 0.12, 0.3, 0.135], r: [0.05, 0, 0] });
    spineB.box(0.05, 0.03, 0.26, packDark, { p: [sd * 0.13, 0.53, 0.0] });
  }
  // Mochila con saco de dormir
  spineB.tbox(0.34, 0.44, 0.17, { sx: 0.92, sz: 0.85 }, pack, { p: [0, 0.3, -0.21] });
  spineB.box(0.36, 0.13, 0.19, packDark, { p: [0, 0.48, -0.215] });
  spineB.box(0.24, 0.16, 0.06, packDark, { p: [0, 0.2, -0.315] });
  spineB.box(0.07, 0.24, 0.13, packDark, { p: [0.2, 0.25, -0.2] });
  spineB.box(0.07, 0.24, 0.13, packDark, { p: [-0.2, 0.25, -0.2] });
  spineB.cyl(0.085, 0.085, 0.46, 8, '#5a4a3a', { p: [0, 0.6, -0.2], r: [0, 0, Math.PI / 2] });
  spineB.box(0.03, 0.18, 0.18, '#2a241e', { p: [0.12, 0.6, -0.2] });
  spineB.box(0.03, 0.18, 0.18, '#2a241e', { p: [-0.12, 0.6, -0.2] });
  spineB.box(0.04, 0.2, 0.04, PALETTE.metal, { p: [0.22, 0.42, -0.23], r: [0, 0, 0.1] }); // linterna

  // Cabeza bajo capucha
  headB.cyl(0.05, 0.055, 0.1, 6, skinShadow, { p: [0, 0.04, 0] });
  headB.box(0.18, 0.22, 0.2, skin, { p: [0, 0.2, 0.0] });
  headB.box(0.16, 0.05, 0.06, skinShadow, { p: [0, 0.26, 0.08] }); // sombra de la capucha sobre los ojos
  headB.box(0.04, 0.018, 0.012, '#141210', { p: [0.042, 0.235, 0.104] });
  headB.box(0.04, 0.018, 0.012, '#141210', { p: [-0.042, 0.235, 0.104] });
  headB.box(0.17, 0.025, 0.04, '#2a2018', { p: [0, 0.262, 0.095] }); // cejas/flequillo
  // Capucha abierta por delante
  headB.box(0.27, 0.06, 0.28, jacketDark, { p: [0, 0.345, -0.015] });
  headB.box(0.05, 0.3, 0.27, jacketDark, { p: [0.12, 0.2, -0.015], r: [0, 0, -0.04] });
  headB.box(0.05, 0.3, 0.27, jacketDark, { p: [-0.12, 0.2, -0.015], r: [0, 0, 0.04] });
  headB.box(0.27, 0.32, 0.05, jacketDark, { p: [0, 0.2, -0.13] });
  headB.box(0.26, 0.04, 0.05, jacketDeep, { p: [0, 0.33, 0.11] }); // ribete
  headB.box(0.04, 0.24, 0.05, jacketDeep, { p: [0.125, 0.21, 0.11] });
  headB.box(0.04, 0.24, 0.05, jacketDeep, { p: [-0.125, 0.21, 0.11] });
  headB.tbox(0.24, 0.12, 0.2, { sx: 0.6, sz: 0.6 }, jacketDark, { p: [0, 0.36, -0.13], r: [-0.4, 0, 0] });

  // Pañuelo (acento): tapa boca y cuello, con una punta colgando
  accentHeadB.box(0.2, 0.1, 0.06, white, { p: [0, 0.135, 0.09] });
  accentHeadB.tbox(0.19, 0.06, 0.05, { sx: 0.3 }, white, { p: [0, 0.08, 0.09], r: [Math.PI, 0, 0] });
  accentB.cyl(0.12, 0.14, 0.1, 8, white, { p: [0, 0.53, 0.01] });
  accentB.tbox(0.12, 0.2, 0.03, { sx: 0.4 }, white, { p: [0.06, 0.43, 0.13], r: [Math.PI + 0.1, 0, 0.15] });

  // Brazos
  const addArm = (up: PartBatch, fo: PartBatch, sd: 1 | -1) => {
    up.ico(0.075, jacket, { s: [1, 0.9, 1] });
    up.cyl(0.058, 0.065, UPPER, 6, jacket, { p: [0, -UPPER / 2, 0] });
    up.box(0.07, 0.07, 0.02, jacketDark, { p: [sd * 0.04, -0.08, 0.04], r: [0, sd * 0.6, 0] }); // parche hombro
    fo.ico(0.06, jacket);
    fo.cyl(0.055, 0.058, FORE, 6, jacket, { p: [0, -FORE / 2, 0] });
    fo.cyl(0.06, 0.06, 0.05, 6, jacketDeep, { p: [0, -FORE + 0.03, 0] }); // puño
    fo.box(0.075, 0.1, 0.045, glove, { p: [0, -FORE - 0.06, 0.005] });
    fo.box(0.03, 0.06, 0.03, glove, { p: [sd * -0.04, -FORE - 0.04, 0.03], r: [-0.3, 0, 0] });
  };
  addArm(armLB, foreLB, 1);
  addArm(armRB, foreRB, -1);
  // Machete en la mano derecha
  foreRB.box(0.035, 0.13, 0.035, '#2a1d14', { p: [0, -FORE - 0.08, 0.04], r: [1.25, 0, 0] });
  foreRB.box(0.012, 0.06, 0.48, '#7d8589', { p: [0, -FORE - 0.115, 0.32], r: [-0.12, 0, 0] });
  foreRB.box(0.012, 0.045, 0.12, '#6e3f1f', { p: [0, -FORE - 0.14, 0.5], r: [-0.12, 0, 0] });

  // Piernas
  const addLeg = (th: PartBatch, sh: PartBatch, sd: 1 | -1) => {
    th.cyl(0.072, 0.082, THIGH, 6, pants, { p: [0, -THIGH / 2, 0] });
    th.box(0.04, 0.13, 0.1, pantsDark, { p: [sd * 0.08, -0.22, 0.01] }); // bolsillo cargo
    sh.ico(0.068, pants);
    sh.cyl(0.058, 0.068, SHIN, 6, pants, { p: [0, -SHIN / 2, 0] });
    const ankle = HIP_Y - THIGH - SHIN;
    sh.cyl(0.07, 0.075, 0.16, 6, boot, { p: [0, -SHIN + 0.02, 0] });
    sh.box(0.115, 0.1, 0.25, boot, { p: [0, -SHIN - ankle + 0.05, 0.05] });
    sh.box(0.12, 0.03, 0.26, '#0f0e0c', { p: [0, -SHIN - ankle + 0.015, 0.05] });
    sh.box(0.06, 0.012, 0.1, '#3a3228', { p: [0, -SHIN - ankle + 0.1, 0.12] });
  };
  addLeg(legLB, shinLB, 1);
  addLeg(legRB, shinRB, -1);
  shinLB.box(0.12, 0.12, 0.05, jacketDark, { p: [0, -0.06, 0.06] }); // rodillera

  // ---- Jerarquía ----
  const m = vcLambert();
  const accentMat = cloneMat(lambert('#ffffff', { vertexColors: true }));
  accentMat.color.set(opts.accentColor ?? PALETTE.rust);

  const root = new THREE.Group();
  root.name = 'survivor';
  const body = new THREE.Group();
  const hips = new THREE.Group();
  const spine = new THREE.Group();
  const head = new THREE.Group();
  const armL = new THREE.Group();
  const elbowL = new THREE.Group();
  const armR = new THREE.Group();
  const elbowR = new THREE.Group();
  const legL = new THREE.Group();
  const kneeL = new THREE.Group();
  const legR = new THREE.Group();
  const kneeR = new THREE.Group();

  root.add(body);
  body.add(hips);
  hips.position.y = HIP_Y;
  hipsB.attachTo(hips, m);
  for (const [leg, knee, tb, sb, sx] of [
    [legL, kneeL, legLB, shinLB, 1],
    [legR, kneeR, legRB, shinRB, -1],
  ] as const) {
    leg.position.set(sx * 0.1, -0.02, 0);
    hips.add(leg);
    tb.attachTo(leg, m);
    knee.position.y = -THIGH;
    leg.add(knee);
    sb.attachTo(knee, m);
  }
  spine.position.y = 0.06;
  hips.add(spine);
  spineB.attachTo(spine, m);
  accentB.attachTo(spine, accentMat);
  head.position.y = SPINE;
  spine.add(head);
  headB.attachTo(head, m);
  accentHeadB.attachTo(head, accentMat);
  for (const [arm, elbow, ub, fb, sx] of [
    [armL, elbowL, armLB, foreLB, 1],
    [armR, elbowR, armRB, foreRB, -1],
  ] as const) {
    arm.position.set(sx * 0.225, 0.45, 0);
    spine.add(arm);
    ub.attachTo(arm, m);
    elbow.position.y = -UPPER;
    arm.add(elbow);
    fb.attachTo(elbow, m);
  }
  root.add(blobShadow(0.5, 0.55));

  let t = Math.random() * 10;
  const pose = () => {
    const b = Math.sin(t * 1.6);
    const w = Math.sin(t * 0.5);
    body.rotation.z = w * 0.015;
    hips.position.x = w * 0.012;
    hips.position.y = HIP_Y - 0.01 + b * 0.003;
    spine.rotation.x = 0.05 + b * 0.015;
    spine.rotation.z = -w * 0.02;
    spine.scale.set(1 + b * 0.008, 1 + b * 0.01, 1 + b * 0.012);
    head.rotation.y = Math.sin(t * 0.35) * 0.4 + Math.sin(t * 0.9) * 0.04;
    head.rotation.x = -0.03 + Math.sin(t * 0.5 + 1) * 0.05;
    armL.rotation.set(0.05 + b * 0.02, 0, 0.13 + b * 0.015);
    elbowL.rotation.x = -0.2;
    armR.rotation.set(-0.12 + b * 0.02, 0, -0.16 - b * 0.015);
    elbowR.rotation.x = -0.35;
    legL.rotation.set(-0.02, 0, 0.03);
    legR.rotation.set(0.03, 0, -0.05);
    kneeL.rotation.x = 0.04;
    kneeR.rotation.x = 0.02;
  };
  pose();

  return {
    root,
    update(dt: number) {
      t += dt;
      pose();
    },
    setAccentColor(color: string) {
      accentMat.color.set(color);
    },
  };
}
