// Retrato 3D del superviviente sobre un pedestal de escombros, girando lentamente.
// Fondo transparente (alpha) para fundirse con una tarjeta oscura de la UI.

import * as THREE from 'three';
import { Stage } from '../engine/Stage';
import { PALETTE, PartBatch, blobShadow, vcLambert } from '../models/materials';
import { addRubble } from '../models/props';
import { createSurvivor, type SurvivorRig } from '../models/survivorModel';

export interface AvatarSceneOptions {
  accentColor?: string;
}

const PEDESTAL_H = 0.26;
/** Elevación de la cámara (rad): un poco desde arriba para ver el pedestal. */
const CAM_ELEVATION = 0.1;
/** Margen en NDC: |x|,|y| ≤ 0.8 deja ~10% libre a cada lado. */
const NDC_LIMIT = 0.8;

const _p = new THREE.Vector3();
const _target = new THREE.Vector3();

export class AvatarScene {
  private readonly stage: Stage;
  private readonly survivor: SurvivorRig;
  private readonly turntable = new THREE.Group();
  private readonly rim: THREE.DirectionalLight;
  /** Puntos de control (espacio del mundo, invariantes al giro) para encuadrar. */
  private readonly fitPoints: THREE.Vector3[] = [];
  private disposed = false;

  constructor(container: HTMLElement, opts: AvatarSceneOptions = {}) {
    const stage = new Stage(container, { alpha: true, fog: null, fov: 30, near: 0.1, far: 40 });
    this.stage = stage;
    const scene = stage.scene;

    // Luces: ambiente frío + clave cálida + contraluz (rim) frío intenso
    scene.add(new THREE.HemisphereLight('#6a7d92', '#241a10', 1.5));
    const key = new THREE.DirectionalLight('#f0b070', 2.2);
    key.position.set(-2.5, 2.6, 3.5);
    scene.add(key);
    this.rim = new THREE.DirectionalLight('#a8c8ff', 3.2);
    this.rim.position.set(2.2, 2.8, -3.5);
    scene.add(this.rim);

    // Pedestal de escombros
    const b = new PartBatch(17, 0.09);
    b.cyl(0.62, 0.7, PEDESTAL_H, 9, '#4a4f52', { p: [0, PEDESTAL_H / 2, 0] });
    b.cyl(0.5, 0.58, 0.05, 9, '#5a5f60', { p: [0.04, PEDESTAL_H + 0.01, -0.02], r: [0.03, 0.4, -0.02] });
    b.box(0.5, 0.06, 0.3, '#3e4244', { p: [0.38, PEDESTAL_H + 0.02, 0.3], r: [0.1, 0.6, 0.12] });
    addRubble(b, { seed: 5, count: 16, radius: 0.9, height: 0.18, mixed: false }, 0, 0);
    b.box(0.03, 0.55, 0.03, '#6e3f1f', { p: [-0.45, PEDESTAL_H + 0.18, -0.25], r: [0.3, 0, 0.5] }, 0); // varilla
    b.box(0.03, 0.4, 0.03, '#5a3420', { p: [-0.5, PEDESTAL_H + 0.12, -0.15], r: [-0.2, 0, 0.7] }, 0);
    b.box(0.22, 0.07, 0.1, '#5a3a2e', { p: [0.55, 0.035, 0.45], r: [0, 0.4, 0] });
    b.box(0.22, 0.07, 0.1, '#6a4434', { p: [0.62, 0.105, 0.4], r: [0, 0.9, 0] });
    b.cyl(0.035, 0.035, 0.12, 6, PALETTE.rust, { p: [-0.3, PEDESTAL_H + 0.06, 0.4], r: [0, 0, 1.2] }); // lata
    this.turntable.add(b.mesh(vcLambert(), 'pedestal'));
    const shadow = blobShadow(0.95, 0.5);
    shadow.position.y = 0.005;
    this.turntable.add(shadow);

    this.survivor = createSurvivor({ accentColor: opts.accentColor });
    this.survivor.root.position.y = PEDESTAL_H + 0.02;
    this.turntable.add(this.survivor.root);
    this.turntable.rotation.y = -0.5;
    scene.add(this.turntable);

    // Puntos de encuadre: anillos (simétricos al girar) en la base, el pedestal, los hombros y
    // la cabeza, con la altura real del personaje medida con su caja envolvente.
    const figure = new THREE.Box3().setFromObject(this.survivor.root);
    const top = figure.max.y + 0.03;
    const rings: [number, number][] = [
      [0.0, 0.98],
      [PEDESTAL_H, 0.72],
      [top * 0.55, 0.42],
      [top * 0.8, 0.4],
      [top, 0.18],
    ];
    for (const [y, r] of rings) {
      for (let k = 0; k < 12; k++) {
        const a = (k / 12) * Math.PI * 2;
        this.fitPoints.push(new THREE.Vector3(Math.sin(a) * r, y, Math.cos(a) * r));
      }
    }

    stage.onResize(this.onResize);
    stage.onUpdate(this.update);
    stage.renderOnce();
  }

  setAccentColor(color: string): void {
    this.survivor.setAccentColor(color);
    if (!this.stage.isRunning) this.stage.renderOnce();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.stage.dispose();
  }

  private update = (dt: number, elapsed: number): void => {
    this.turntable.rotation.y += dt * 0.35;
    this.survivor.update(dt);
    this.rim.intensity = 3.2 + Math.sin(elapsed * 0.7) * 0.25;
  };

  /**
   * Encuadre según el aspecto: busca la distancia mínima a la que todos los puntos de control
   * entran con ~10% de margen y luego centra verticalmente la figura.
   */
  private onResize = (w: number, h: number): void => {
    const cam = this.stage.camera;
    cam.aspect = w / h;
    cam.updateProjectionMatrix();
    let ty = 1.0;
    let dist = 5;
    for (let pass = 0; pass < 3; pass++) {
      let lo = 1;
      let hi = 40;
      for (let i = 0; i < 22; i++) {
        const mid = (lo + hi) / 2;
        if (this.extent(mid, ty).fits) hi = mid;
        else lo = mid;
      }
      dist = hi;
      const e = this.extent(dist, ty);
      // recentra: desplaza el objetivo para que el centro proyectado quede en y = 0
      const T = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2);
      ty += ((e.minY + e.maxY) / 2) * dist * T;
    }
    this.placeCamera(dist, ty);
  };

  private placeCamera(dist: number, ty: number): void {
    const cam = this.stage.camera;
    _target.set(0, ty, 0);
    cam.position.set(0, ty + Math.sin(CAM_ELEVATION) * dist, Math.cos(CAM_ELEVATION) * dist);
    cam.lookAt(_target);
    cam.updateMatrixWorld(true);
  }

  private extent(dist: number, ty: number): { fits: boolean; minY: number; maxY: number } {
    this.placeCamera(dist, ty);
    const cam = this.stage.camera;
    let minY = Infinity;
    let maxY = -Infinity;
    let fits = true;
    for (const p of this.fitPoints) {
      _p.copy(p).project(cam);
      if (_p.z > 1 || _p.z < -1) fits = false;
      if (Math.abs(_p.x) > NDC_LIMIT + 0.05) fits = false;
      minY = Math.min(minY, _p.y);
      maxY = Math.max(maxY, _p.y);
    }
    if (maxY - minY > NDC_LIMIT * 2) fits = false;
    return { fits, minY, maxY };
  }
}
