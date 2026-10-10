// Escena de combate en primera persona: calle nocturna con un zombie de frente.
//
// - Zombie en el origen mirando a +Z. Cámara a la altura de los ojos (1.6 m) en +Z, mirando
//   hacia -Z, a 4–5 m según el tipo.
// - Encuadre pensado para pantalla VERTICAL con la UI cubriendo ~40% inferior: se usa un
//   desplazamiento de lente (setViewOffset) que sube la imagen sin inclinar las verticales.
// - Luces: hemisférica + direccional (luna) + PointLight naranja de farola que parpadea.
//   Sin shadow maps (sombras "blob").

import * as THREE from 'three';
import type { ZombieTypeId } from '../../core/types';
import type { CombatAnimation } from '../types';
import { Stage } from '../engine/Stage';
import { ParticlePool } from '../engine/Particles';
import { createZombie, type ZombieRig } from '../models/zombieModel';
import { PALETTE, PartBatch, basic, clamp01, mergeStatic, smooth01, vcLambert } from '../models/materials';
import {
  addDebris,
  addRubble,
  createBarrel,
  createBuilding,
  createCar,
  createFireBarrel,
  createGround,
  createMoon,
  createSkyDome,
  createStreetLamp,
  flicker,
} from '../models/props';

const EYE_HEIGHT = 1.6;
const FOV = 50;
const FOG_COLOR = '#1a2327';
/** Giro del zombie respecto a la cámara (vista 3/4 para que se lea la silueta). */
const ZOMBIE_YAW = 0.3;
/** Fracción de la altura del canvas que ocupa el zombie. */
const HEIGHT_FILL = 0.66;
/** Fracción máxima del ancho del canvas que puede ocupar el zombie (pantallas muy estrechas). */
const WIDTH_FILL = 0.85;
/** Centro vertical del zombie, medido desde ABAJO del canvas (0.45 ≈ 55% desde arriba). */
const CENTER_FROM_BOTTOM = 0.45;

/** Ancho aproximado (m) de cada zombie con los brazos en reposo (vista 3/4). */
const ZOMBIE_WIDTH: Record<ZombieTypeId, number> = {
  walker: 1.15,
  runner: 1.15,
  bloater: 1.3,
  screamer: 1.0,
  brute: 1.7,
};

const BLOOD = [new THREE.Color('#4a0606'), new THREE.Color('#6a0a0a'), new THREE.Color('#821212'), new THREE.Color('#3a0505')];
const TOXIC = [new THREE.Color('#7d9a2e'), new THREE.Color('#9fb63e'), new THREE.Color('#5f7a22'), new THREE.Color('#b9c860')];
const HEAL = [new THREE.Color('#5fd27a'), new THREE.Color('#a8ffb0'), new THREE.Color('#3fb060')];
const SPARK = [new THREE.Color('#ffd27a'), new THREE.Color('#ffb24a'), new THREE.Color('#fff2c0')];
const DUST = [new THREE.Color('#3a3a36'), new THREE.Color('#4a4a44'), new THREE.Color('#2e2f2c')];
const ASH = [new THREE.Color('#6a665c'), new THREE.Color('#8a8070'), new THREE.Color('#9a7a5a')];

const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _red = new THREE.Color('#8a0a06');
const _green = new THREE.Color('#2f7a2a');
const _toxicTint = new THREE.Color('#5a7a12');
const _black = new THREE.Color('#000000');
const _hemiSky = new THREE.Color('#4a5a6a');
const _hemiFlash = new THREE.Color('#ffd2a0');

interface Timer {
  at: number;
  fn: () => void;
}

interface Ring {
  mesh: THREE.Mesh;
  mat: THREE.MeshBasicMaterial;
  t: number;
  dur: number;
  maxScale: number;
  alpha: number;
}

function bump(t: number, a: number, b: number, c: number, d: number): number {
  if (t <= a || t >= d) return 0;
  if (t < b) return smooth01((t - a) / (b - a));
  if (t <= c) return 1;
  return 1 - smooth01((t - c) / (d - c));
}

export class CombatScene {
  private readonly stage: Stage;
  private readonly zombie: ZombieRig;
  private readonly zombieType: ZombieTypeId;
  private camDist = 4;
  private lensShift = 0.2;

  private readonly hemi: THREE.HemisphereLight;
  private readonly lampLight: THREE.PointLight;
  private readonly lampSet: (f: number) => void;
  private readonly fireUpdate: (t: number) => void;

  private readonly blood: ParticlePool;
  private readonly glow: ParticlePool;
  private readonly rings: Ring[] = [];
  private readonly stars: THREE.Group;
  private readonly starMeshes: THREE.Mesh[] = [];
  private readonly muzzle: THREE.Mesh;
  private readonly muzzleMat: THREE.MeshBasicMaterial;
  private readonly vignette: THREE.Mesh;
  private readonly vignetteMat: THREE.MeshBasicMaterial;
  private readonly dim: THREE.Mesh;
  private readonly dimMat: THREE.MeshBasicMaterial;

  private time = 0;
  private timers: Timer[] = [];
  private trauma = 0;
  private recoil = 0;
  private knock = 0;
  private hemiFlash = 0;
  private muzzleT = -1;
  private stunT = -1;
  private defendT = -1;
  private fleeT = -1;
  private redPulse = 0;
  private greenPulse = 0;
  private toxicPulse = 0;
  private ashTimer = 0;
  private disposed = false;

  constructor(container: HTMLElement, zombieType: ZombieTypeId) {
    this.zombieType = zombieType;
    const stage = new Stage(container, {
      background: FOG_COLOR,
      fog: new THREE.FogExp2(FOG_COLOR, 0.04),
      fov: FOV,
      near: 0.1,
      far: 140,
    });
    this.stage = stage;
    const scene = stage.scene;

    // ---------------- Luces ----------------
    this.hemi = new THREE.HemisphereLight(_hemiSky, '#1c160e', 1.3);
    scene.add(this.hemi);
    const moon = new THREE.DirectionalLight('#9db4cc', 1.6);
    moon.position.set(-4, 7, 6);
    moon.target.position.set(0, 0.8, 0);
    scene.add(moon, moon.target);

    // ---------------- Entorno ----------------
    const env = new THREE.Group();
    env.name = 'environment';
    scene.add(env);
    scene.add(createSkyDome({ radius: 110, top: '#05070a', horizon: FOG_COLOR, glow: '#36261a' }));
    const moonDisc = createMoon(1.9);
    moonDisc.position.set(-10, 19, -84);
    moonDisc.lookAt(0, 1.6, 4);
    scene.add(moonDisc);

    const ground = createGround({ width: 34, depth: 80, road: 8.5, cell: 1.6, seed: 7, cracks: 46 });
    ground.position.set(-0.9, 0, -24); // el zombie queda en el carril derecho, no sobre la línea
    env.add(ground);

    const car = createCar({ color: '#56463a', seed: 3 });
    car.position.set(-2.55, 0, -2.6);
    car.rotation.set(0, 0.62, 0.025);
    env.add(car);
    const car2 = createCar({ color: '#3d4a4a', seed: 8 });
    car2.position.set(3.2, 0, -13);
    car2.rotation.y = -0.2;
    env.add(car2);

    const b1 = createBarrel('rust', 2);
    b1.position.set(1.75, 0, -1.6);
    const b2 = createBarrel('green', 3);
    b2.position.set(2.35, 0, -2.3);
    b2.rotation.y = 0.6;
    const b3 = createBarrel('rust', 4);
    b3.position.set(1.4, 0.29, -3.0);
    b3.rotation.set(Math.PI / 2, 0.9, 0, 'YXZ');
    env.add(b1, b2, b3);

    const fire = createFireBarrel(5);
    fire.root.position.set(-1.6, 0, -9.5);
    scene.add(fire.root);
    this.fireUpdate = fire.update;

    const detail = new PartBatch(77, 0.08);
    addRubble(detail, { seed: 21, count: 22, radius: 1.6, height: 0.7 }, -4.9, -6.5);
    addRubble(detail, { seed: 22, count: 16, radius: 1.3, height: 0.5 }, 4.6, -9.5);
    addRubble(detail, { seed: 23, count: 7, radius: 0.6, height: 0.15, mixed: false }, 0.95, -0.9);
    addRubble(detail, { seed: 24, count: 10, radius: 1.0, height: 0.3 }, -0.6, -17);
    addDebris(detail, { seed: 31, count: 26, width: 7, depth: 12, oz: -3 });
    addDebris(detail, { seed: 32, count: 14, width: 8, depth: 14, oz: -16 });
    // Postes y cables cruzando la calle (siluetas contra el cielo)
    for (const z of [-7.5, -21]) {
      for (const sx of [-1, 1]) {
        detail.cyl(0.11, 0.14, 8.5, 6, '#1a1c1d', { p: [sx * 5.3, 4.25, z] });
        detail.box(1.6, 0.1, 0.1, '#1a1c1d', { p: [sx * 5.3, 7.9, z] });
      }
      for (const [y, sag] of [
        [7.85, 0.7],
        [7.4, 0.9],
      ] as const) {
        const segs = 6;
        for (let i = 0; i < segs; i++) {
          const x0 = -5.3 + (10.6 * i) / segs;
          const x1 = -5.3 + (10.6 * (i + 1)) / segs;
          const yy0 = y - sag * (1 - Math.pow((x0 / 5.3) ** 2, 1));
          const yy1 = y - sag * (1 - Math.pow((x1 / 5.3) ** 2, 1));
          const len = Math.hypot(x1 - x0, yy1 - yy0);
          detail.box(len, 0.025, 0.025, '#0d0e0e', {
            p: [(x0 + x1) / 2, (yy0 + yy1) / 2, z],
            r: [0, 0, Math.atan2(yy1 - yy0, x1 - x0)],
          }, 0);
        }
      }
    }
    // Barricada de tablas cruzando al fondo
    detail.box(3.4, 0.2, 0.08, PALETTE.woodDark, { p: [1.8, 0.7, -14.5], r: [0, 0.1, 0.2] });
    detail.box(3.0, 0.2, 0.08, PALETTE.wood, { p: [1.5, 0.45, -14.4], r: [0, 0.1, -0.15] });
    env.add(detail.mesh(vcLambert(), 'details'));

    // Edificios
    const bRand = (i: number) => {
      const h = Math.sin(i * 91.7) * 43758.5;
      return h - Math.floor(h);
    };
    let i = 0;
    for (const sx of [-1, 1]) {
      let z = 3;
      while (z > -62) {
        const d = 7 + bRand(i++) * 7;
        const w = 6 + bRand(i++) * 5;
        const h = 7 + bRand(i++) * 16;
        const b = createBuilding({ width: w, height: h, depth: d - 0.6, seed: 100 + i, lit: 0.16 });
        b.position.set(sx * (7.6 + w / 2 + bRand(i++) * 1.2), 0, z - d / 2);
        env.add(b);
        z -= d;
      }
    }
    for (let k = 0; k < 4; k++) {
      const w = 9 + bRand(i++) * 6;
      const center = k === 1 || k === 2;
      const b = createBuilding({ width: w, height: center ? 7 + bRand(i++) * 4 : 14 + bRand(i++) * 16, depth: 8, seed: 300 + k, lit: 0.16 });
      b.position.set(-16 + k * 10.5, 0, -66 - bRand(i++) * 6);
      env.add(b);
    }

    // Farola con luz naranja parpadeante
    const lamp = createStreetLamp({ height: 4.7, seed: 4 });
    lamp.root.position.set(3.2, 0, -0.6);
    lamp.root.rotation.y = Math.PI;
    scene.add(lamp.root);
    this.lampSet = lamp.setIntensity;
    lamp.root.updateMatrixWorld(true);
    const lp = lamp.root.localToWorld(lamp.lightPosition.clone());
    this.lampLight = new THREE.PointLight('#ff9a48', 32, 16, 1.5);
    this.lampLight.position.copy(lp);
    scene.add(this.lampLight);
    // Farola lejana apagada
    const lamp2 = createStreetLamp({ height: 4.7, seed: 6 });
    lamp2.root.position.set(-5.0, 0, -18);
    lamp2.setIntensity(0.25);
    env.add(lamp2.root);

    mergeStatic(env);

    // ---------------- Zombie ----------------
    this.zombie = createZombie(zombieType);
    this.zombie.setFacing(ZOMBIE_YAW);
    scene.add(this.zombie.root);

    // ---------------- Efectos ----------------
    this.blood = new ParticlePool(360, { soft: 0.55 });
    this.glow = new ParticlePool(220, { additive: true, soft: 0.2 });
    scene.add(this.blood.points, this.glow.points);

    const ringGeo = new THREE.RingGeometry(0.82, 1.0, 40, 1);
    for (let k = 0; k < 4; k++) {
      const m = new THREE.MeshBasicMaterial({
        color: '#d8d2b8',
        transparent: true,
        opacity: 0,
        side: THREE.DoubleSide,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        fog: false,
      });
      const mesh = new THREE.Mesh(k === 0 ? ringGeo : ringGeo.clone(), m);
      mesh.visible = false;
      mesh.renderOrder = 7;
      scene.add(mesh);
      this.rings.push({ mesh, mat: m, t: -1, dur: 0.7, maxScale: 4, alpha: 0.6 });
    }

    this.stars = new THREE.Group();
    const starGeo = new THREE.OctahedronGeometry(0.045, 0);
    const starMat = basic(PALETTE.flameCore, { fog: false });
    for (let k = 0; k < 5; k++) {
      const s = new THREE.Mesh(starGeo, starMat);
      s.scale.set(1, 1.8, 1);
      this.stars.add(s);
      this.starMeshes.push(s);
    }
    this.stars.visible = false;
    scene.add(this.stars);

    // Fogonazo del disparo y overlays pegados a la cámara
    const cam = stage.camera;
    this.muzzleMat = new THREE.MeshBasicMaterial({
      color: '#ffd38a',
      transparent: true,
      opacity: 0,
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      fog: false,
    });
    this.muzzle = new THREE.Mesh(starburstGeometry(10, 1, 0.35), this.muzzleMat);
    this.muzzle.visible = false;
    this.muzzle.renderOrder = 1001; // por encima de la viñeta
    cam.add(this.muzzle);

    this.vignetteMat = new THREE.MeshBasicMaterial({
      color: '#000000',
      vertexColors: true,
      transparent: true,
      opacity: 0.6,
      depthTest: false,
      depthWrite: false,
      fog: false,
    });
    this.vignette = new THREE.Mesh(vignetteGeometry(), this.vignetteMat);
    this.vignette.renderOrder = 999;
    this.vignette.frustumCulled = false;
    cam.add(this.vignette);

    this.dimMat = new THREE.MeshBasicMaterial({
      color: '#000000',
      transparent: true,
      opacity: 0,
      depthTest: false,
      depthWrite: false,
      fog: false,
    });
    this.dim = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), this.dimMat);
    this.dim.renderOrder = 1000;
    this.dim.visible = false;
    this.dim.frustumCulled = false;
    cam.add(this.dim);

    // ---------------- Cámara ----------------
    stage.onResize(this.onResize);
    this.applyCamera(0);
    stage.onUpdate(this.update);
    stage.renderOnce();
  }

  // -------------------------------------------------------------------------
  // API pública
  // -------------------------------------------------------------------------

  play(animation: CombatAnimation): void {
    if (this.disposed) return;
    const z = this.zombie;
    switch (animation) {
      case 'player_hit':
        z.hit(false);
        this.after(0.03, () => this.bloodBurst(16, 1));
        this.addTrauma(0.12);
        break;
      case 'player_crit':
        z.hit(true);
        this.after(0.03, () => {
          this.bloodBurst(38, 1.6);
          this.sparks(12);
        });
        this.addTrauma(0.42);
        break;
      case 'player_miss':
        z.dodge();
        this.after(0.12, () => this.dust(8, 0.9));
        break;
      case 'player_shoot':
        this.muzzleT = 0;
        this.hemiFlash = 1;
        this.recoil = 1;
        this.addTrauma(0.22);
        this.after(0.04, () => {
          z.hit(true);
          this.bloodBurst(28, 1.4);
        });
        break;
      case 'zombie_attack': {
        const impact = z.attack();
        this.after(impact, () => {
          this.addTrauma(0.55);
          this.redPulse = 1;
          this.knock = 1;
        });
        break;
      }
      case 'zombie_miss':
        z.lungeMiss();
        this.after(0.4, () => {
          this.addTrauma(0.12);
          this.dust(10, 1.1);
        });
        break;
      case 'zombie_charge_prepare':
        z.chargePrepare();
        this.addTrauma(0.1);
        this.after(0.25, () => this.dust(10, 1));
        break;
      case 'zombie_charge': {
        const impact = z.charge();
        this.addTrauma(0.25);
        this.dust(14, 1.2);
        this.after(impact, () => {
          this.addTrauma(1);
          this.redPulse = 1.2;
          this.knock = 1.6;
        });
        break;
      }
      case 'zombie_scream': {
        const peak = z.scream();
        this.after(peak, () => {
          this.shockwave();
          this.addTrauma(0.3);
        });
        this.after(peak + 0.25, () => this.shockwave());
        break;
      }
      case 'zombie_stunned':
        z.stun();
        this.stunT = 0;
        break;
      case 'zombie_death':
        z.die();
        this.after(0.9, () => {
          this.dust(16, 1.4);
          this.addTrauma(0.15);
        });
        break;
      case 'toxic_burst':
        this.toxicCloud();
        this.toxicPulse = 1;
        this.addTrauma(0.2);
        break;
      case 'defend':
        this.defendT = 0;
        break;
      case 'heal':
        this.greenPulse = 1;
        for (let k = 0; k < 5; k++) this.after(k * 0.16, () => this.healMotes(9));
        break;
      case 'flee':
        this.fleeT = 0;
        break;
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.timers.length = 0;
    this.stage.dispose();
  }

  // -------------------------------------------------------------------------
  // Bucle
  // -------------------------------------------------------------------------

  private update = (dt: number, elapsed: number): void => {
    this.time = elapsed;

    // temporizadores
    if (this.timers.length) {
      for (let k = this.timers.length - 1; k >= 0; k--) {
        const tm = this.timers[k];
        tm.at -= dt;
        if (tm.at <= 0) {
          this.timers.splice(k, 1);
          tm.fn();
        }
      }
    }

    this.zombie.update(dt);

    // farola y fuego
    const f = flicker(elapsed, 1.3);
    this.lampLight.intensity = 32 * f;
    this.lampSet(f);
    this.fireUpdate(elapsed);

    // fogonazo
    this.hemiFlash = Math.max(0, this.hemiFlash - dt * 12);
    this.hemi.intensity = 1.3 + this.hemiFlash * 2.4;
    this.hemi.color.lerpColors(_hemiSky, _hemiFlash, this.hemiFlash * 0.8);
    if (this.muzzleT >= 0) {
      // se evalúa ANTES de avanzar el tiempo: el primer frame siempre muestra el fogonazo
      const mt = this.muzzleT;
      this.muzzleT += dt;
      const on = mt < 0.1;
      this.muzzle.visible = on;
      if (on) {
        this.muzzleMat.opacity = 1 - (mt / 0.1) * 0.6;
        const s = 0.095 + Math.random() * 0.04;
        this.muzzle.scale.set(s, s, 1);
        this.muzzle.rotation.z = Math.random() * Math.PI;
      } else {
        this.muzzleT = -1;
      }
    }

    // anillos de onda expansiva
    for (const r of this.rings) {
      if (r.t < 0) continue;
      r.t += dt;
      const u = r.t / r.dur;
      if (u >= 1) {
        r.t = -1;
        r.mesh.visible = false;
        continue;
      }
      const e = 1 - Math.pow(1 - u, 3);
      const s = 0.25 + e * r.maxScale;
      r.mesh.scale.set(s, s, s);
      r.mat.opacity = r.alpha * (1 - u) * (1 - u);
    }

    // estrellas de aturdimiento
    if (this.stunT >= 0) {
      this.stunT += dt;
      const dur = 1.5;
      if (this.stunT > dur || this.zombie.isDead) {
        this.stunT = -1;
        this.stars.visible = false;
      } else {
        this.stars.visible = true;
        this.zombie.getHeadWorldPosition(_v);
        this.stars.position.set(_v.x, _v.y + 0.28 * (this.zombieType === 'brute' ? 1.3 : 1), _v.z);
        const k = Math.min(1, this.stunT / 0.15) * (1 - smooth01((this.stunT - dur + 0.3) / 0.3));
        for (let n = 0; n < this.starMeshes.length; n++) {
          const a = this.stunT * 5 + (n / this.starMeshes.length) * Math.PI * 2;
          const m = this.starMeshes[n];
          m.position.set(Math.cos(a) * 0.3, Math.sin(a * 2) * 0.04, Math.sin(a) * 0.3);
          m.rotation.y = a * 2;
          m.scale.set(k, 1.8 * k, k);
        }
      }
    }

    // ceniza que cae
    this.ashTimer -= dt;
    if (this.ashTimer <= 0) {
      this.ashTimer = 0.25;
      _v.set((Math.random() - 0.5) * 4, 3.2, (Math.random() - 0.5) * 4 - 1);
      this.blood.emit({
        count: 1,
        origin: _v,
        velocity: [0.12, -0.22, 0.05],
        velocityRandom: [0.08, 0.05, 0.08],
        life: [9, 12],
        size: [0.03, 0.025],
        colors: ASH,
        alpha: [0.55, 0.3],
      });
    }

    this.blood.update(dt);
    this.glow.update(dt);

    // overlays de color
    this.redPulse = Math.max(0, this.redPulse - dt * 2.2);
    this.greenPulse = Math.max(0, this.greenPulse - dt * 1.1);
    this.toxicPulse = Math.max(0, this.toxicPulse - dt * 0.7);
    const vc = this.vignetteMat.color;
    vc.copy(_black);
    let op = 0.62;
    if (this.redPulse > 0) {
      const p = Math.min(1, this.redPulse);
      vc.lerp(_red, p);
      op = Math.max(op, 0.62 + 0.38 * p);
    }
    if (this.greenPulse > 0) {
      const p = Math.min(1, this.greenPulse) * 0.8;
      vc.lerp(_green, p);
      op = Math.max(op, 0.62 + 0.25 * p);
    }
    if (this.toxicPulse > 0) {
      const p = Math.min(1, this.toxicPulse) * 0.85;
      vc.lerp(_toxicTint, p);
      op = Math.max(op, 0.62 + 0.3 * p);
    }
    this.vignetteMat.opacity = op;

    this.applyCamera(dt);
  };

  private applyCamera(dt: number): void {
    const cam = this.stage.camera;
    const t = this.time;
    this.trauma = Math.max(0, this.trauma - dt * 1.4);
    this.recoil = Math.max(0, this.recoil - dt * 7);
    this.knock = Math.max(0, this.knock - dt * 3.2);

    let x = Math.sin(t * 0.55) * 0.02;
    let y = EYE_HEIGHT + Math.sin(t * 1.15) * 0.012;
    let z = this.camDist;
    let yaw = Math.sin(t * 0.37) * 0.008;
    let pitch = Math.sin(t * 0.83) * 0.005;
    let roll = Math.sin(t * 0.61) * 0.006;

    // defenderse: retrocede y se agacha un poco
    if (this.defendT >= 0) {
      this.defendT += dt;
      const e = bump(this.defendT, 0, 0.18, 0.55, 1.0);
      z += 0.45 * e;
      y -= 0.12 * e;
      pitch += 0.04 * e;
      if (this.defendT > 1.0) this.defendT = -1;
    }

    // huir: gira, se desplaza y oscurece; vuelve si la escena sigue viva
    let dimA = 0;
    if (this.fleeT >= 0) {
      this.fleeT += dt;
      const e = bump(this.fleeT, 0, 0.55, 1.6, 2.5);
      yaw += 1.35 * e;
      x -= 0.7 * e;
      z += 0.5 * e;
      roll -= 0.05 * e;
      y -= 0.05 * Math.abs(Math.sin(this.fleeT * 11)) * e; // pasos
      dimA = 0.85 * bump(this.fleeT, 0.1, 0.7, 1.6, 2.5);
      if (this.fleeT > 2.5) this.fleeT = -1;
    }
    this.dimMat.opacity = dimA;
    this.dim.visible = dimA > 0.001;

    // golpe recibido: empujón hacia atrás
    if (this.knock > 0) {
      const k = Math.min(1, this.knock) * this.knock;
      z += 0.18 * k;
      pitch += 0.05 * k;
      roll += 0.04 * k;
    }
    pitch += this.recoil * this.recoil * 0.045;

    // temblor (trauma²)
    const s = this.trauma * this.trauma;
    if (s > 0) {
      const ts = t * 38;
      yaw += s * 0.045 * (Math.sin(ts * 1.1) + Math.sin(ts * 2.3 + 1) * 0.5);
      pitch += s * 0.045 * (Math.sin(ts * 1.7 + 2) + Math.sin(ts * 2.9) * 0.5);
      roll += s * 0.06 * Math.sin(ts * 1.3 + 4);
      x += s * 0.05 * Math.sin(ts * 0.9 + 3);
      y += s * 0.04 * Math.sin(ts * 1.5 + 5);
    }

    cam.position.set(x, y, z);
    cam.rotation.set(pitch, yaw, roll, 'YXZ');
  }

  // -------------------------------------------------------------------------
  // Efectos
  // -------------------------------------------------------------------------

  private after(seconds: number, fn: () => void): void {
    if (seconds <= 0) fn();
    else this.timers.push({ at: seconds, fn });
  }

  private addTrauma(v: number): void {
    this.trauma = Math.min(1, this.trauma + v);
  }

  private bloodBurst(count: number, power: number): void {
    this.zombie.getChestWorldPosition(_v);
    this.blood.emit({
      count,
      origin: _v,
      spread: 0.12,
      velocity: [0, 1.2 * power, 1.4 * power],
      velocityRandom: [1.6 * power, 1.3 * power, 1.1 * power],
      gravity: 9,
      drag: 0.6,
      life: [0.55, 1.1],
      size: [0.07, 0.05],
      sizeRandom: 0.5,
      colors: BLOOD,
      alpha: [1, 0.85],
      floor: true,
    });
    // neblina de sangre
    this.blood.emit({
      count: Math.round(count / 4),
      origin: _v,
      spread: 0.1,
      radial: 0.5,
      velocity: [0, 0.2, 0.4],
      drag: 2,
      life: [0.35, 0.6],
      size: [0.12, 0.35],
      colors: BLOOD,
      alpha: [0.6, 0],
    });
  }

  private sparks(count: number): void {
    this.zombie.getChestWorldPosition(_v);
    this.glow.emit({
      count,
      origin: _v,
      spread: 0.05,
      radial: 3,
      velocity: [0, 0.8, 1.2],
      gravity: 6,
      drag: 1.5,
      life: [0.15, 0.35],
      size: [0.05, 0.02],
      colors: SPARK,
      alpha: [1, 0],
    });
  }

  private dust(count: number, spreadScale: number): void {
    this.zombie.root.getWorldPosition(_v2);
    _v.set(_v2.x, 0.12, _v2.z + 0.2);
    this.blood.emit({
      count,
      origin: _v,
      spread: 0.4 * spreadScale,
      spreadScale: [1, 0.2, 0.6],
      radial: 0.9 * spreadScale,
      velocity: [0, 0.25, 0.2],
      drag: 1.8,
      life: [0.7, 1.2],
      size: [0.25, 0.7],
      colors: DUST,
      alpha: [0.4, 0],
    });
  }

  private toxicCloud(): void {
    this.zombie.getChestWorldPosition(_v);
    this.blood.emit({
      count: 36,
      origin: _v,
      spread: 0.35,
      radial: 1.4,
      velocity: [0, 0.15, 0.9],
      velocityRandom: [0.4, 0.25, 0.4],
      gravity: -0.12,
      drag: 0.9,
      life: [1.8, 2.8],
      size: [0.35, 1.5],
      sizeRandom: 0.4,
      colors: TOXIC,
      alpha: [0.42, 0],
    });
    this.glow.emit({
      count: 18,
      origin: _v,
      spread: 0.3,
      radial: 2.2,
      drag: 1.2,
      life: [0.6, 1.2],
      size: [0.08, 0.03],
      colors: TOXIC,
      alpha: [0.8, 0],
    });
    // anillo verde a ras de suelo
    const r = this.nextRing();
    if (r) {
      this.zombie.root.getWorldPosition(_v2);
      r.mesh.position.set(_v2.x, 0.06, _v2.z);
      r.mesh.rotation.set(-Math.PI / 2, 0, 0);
      r.mat.color.set('#8fa83a');
      r.dur = 1.0;
      r.maxScale = 3.2;
      r.alpha = 0.7;
      r.t = 0;
      r.mesh.visible = true;
    }
  }

  private healMotes(count: number): void {
    for (let k = 0; k < count; k++) {
      this.screenToWorld(0.12 + Math.random() * 0.76, 0.04 + Math.random() * 0.25, 1.3, _v);
      this.glow.emit({
        count: 1,
        origin: _v,
        velocity: [0, 0.38, 0],
        velocityRandom: [0.04, 0.12, 0.02],
        life: [1.1, 1.7],
        size: [0.035, 0.012],
        sizeRandom: 0.4,
        colors: HEAL,
        alpha: [0.95, 0],
      });
    }
  }

  private nextRing(): Ring | null {
    for (const r of this.rings) if (r.t < 0) return r;
    return this.rings[0] ?? null;
  }

  private shockwave(): void {
    const head = this.zombie.getHeadWorldPosition(_v);
    const r = this.nextRing();
    if (r) {
      r.mesh.position.copy(head);
      r.mesh.position.z += 0.15;
      r.mesh.rotation.set(0, 0, 0);
      r.mat.color.set('#e8dcc0');
      r.dur = 0.75;
      r.maxScale = 3.4;
      r.alpha = 0.55;
      r.t = 0;
      r.mesh.visible = true;
    }
    const g = this.nextRing();
    if (g) {
      this.zombie.root.getWorldPosition(_v2);
      g.mesh.position.set(_v2.x, 0.05, _v2.z);
      g.mesh.rotation.set(-Math.PI / 2, 0, 0);
      g.mat.color.set('#c8b890');
      g.dur = 0.9;
      g.maxScale = 5;
      g.alpha = 0.4;
      g.t = 0;
      g.mesh.visible = true;
    }
  }

  /**
   * Convierte una posición de pantalla (fx, fy en 0..1 desde abajo-izquierda) a un punto en
   * espacio de cámara a `d` metros, teniendo en cuenta el desplazamiento de lente.
   */
  private screenToCamera(fx: number, fy: number, d: number, out: THREE.Vector3): THREE.Vector3 {
    const cam = this.stage.camera;
    const T = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2);
    const aspect = this.stage.width / this.stage.height;
    const y = d * T * (2 * fy - 1 - 2 * this.lensShift);
    const x = d * T * aspect * (2 * fx - 1);
    return out.set(x, y, -d);
  }

  private screenToWorld(fx: number, fy: number, d: number, out: THREE.Vector3): THREE.Vector3 {
    this.screenToCamera(fx, fy, d, out);
    return this.stage.camera.localToWorld(out);
  }

  /**
   * Encuadre según el aspecto del canvas: la distancia hace que el zombie ocupe ~66% del alto
   * (o como mucho ~85% del ancho en pantallas estrechas) y un desplazamiento de lente lo centra
   * a ~57% desde arriba sin inclinar la cámara (las verticales siguen verticales).
   */
  private onResize = (w: number, h: number): void => {
    const cam = this.stage.camera;
    const aspect = w / h;
    cam.fov = FOV;
    const T = Math.tan(THREE.MathUtils.degToRad(FOV) / 2);
    // el corredor va encorvado: su altura visible es menor que la del rig
    const H = (this.zombieType === 'runner' ? 1.62 : this.zombie.height) + 0.08;
    const W = ZOMBIE_WIDTH[this.zombieType] ?? 1.2;
    const dH = H / (HEIGHT_FILL * 2 * T);
    const dW = W / (WIDTH_FILL * 2 * T * aspect);
    const d = Math.max(2.4, dH, dW);
    this.camDist = d;
    this.zombie.setReach(d);
    const span = 2 * d * T;
    this.lensShift = CENTER_FROM_BOTTOM - 0.5 - (H / 2 - EYE_HEIGHT) / span;
    cam.setViewOffset(w, h, 0, h * this.lensShift, w, h);

    const pr = this.stage.renderer.getPixelRatio();
    this.blood.setViewport(h * pr, cam.fov);
    this.glow.setViewport(h * pr, cam.fov);

    // overlays a 0.3 m de la cámara, centrados en el centro del canvas
    const od = 0.3;
    const halfH = od * T;
    const halfW = halfH * aspect;
    this.screenToCamera(0.5, 0.5, od, _v);
    this.vignette.position.copy(_v);
    this.vignette.scale.set(halfW, halfH, 1);
    this.dim.position.copy(_v);
    this.dim.scale.set(halfW * 2.2, halfH * 2.2, 1);
    // fogonazo: abajo a la derecha (como si el arma estuviera ahí)
    this.screenToCamera(0.76, 0.2, 0.9, _v);
    this.muzzle.position.copy(_v);
    this.applyCamera(0);
  };
}

// ---------------------------------------------------------------------------
// Geometrías de efectos
// ---------------------------------------------------------------------------

/** Estrella de N puntas (abanico de triángulos) para el fogonazo. */
function starburstGeometry(points: number, outer: number, inner: number): THREE.BufferGeometry {
  const pos: number[] = [];
  const n = points * 2;
  for (let i = 0; i < n; i++) {
    const a0 = (i / n) * Math.PI * 2;
    const a1 = ((i + 1) / n) * Math.PI * 2;
    const r0 = i % 2 === 0 ? outer : inner;
    const r1 = i % 2 === 0 ? inner : outer;
    pos.push(0, 0, 0, Math.cos(a0) * r0, Math.sin(a0) * r0, 0, Math.cos(a1) * r1, Math.sin(a1) * r1, 0);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  return g;
}

/** Anillo elíptico con alfa por vértice (transparente en el centro, opaco en los bordes). */
function vignetteGeometry(): THREE.BufferGeometry {
  const g = new THREE.RingGeometry(0.62, 1.75, 36, 4);
  const pos = g.getAttribute('position');
  const colors = new Float32Array(pos.count * 4);
  for (let i = 0; i < pos.count; i++) {
    const r = Math.hypot(pos.getX(i), pos.getY(i));
    const a = clamp01((r - 0.62) / (1.35 - 0.62));
    colors[i * 4] = 1;
    colors[i * 4 + 1] = 1;
    colors[i * 4 + 2] = 1;
    colors[i * 4 + 3] = a * a * (3 - 2 * a);
  }
  g.setAttribute('color', new THREE.BufferAttribute(colors, 4));
  g.deleteAttribute('uv');
  g.deleteAttribute('normal');
  return g;
}
