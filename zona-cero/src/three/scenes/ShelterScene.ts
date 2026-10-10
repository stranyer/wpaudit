// Vista 3D del refugio: diorama nocturno con cámara orbital (táctil), autorrotación lenta,
// fogata con luz parpadeante y reconstrucción animada al cambiar de nivel.

import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { Stage } from '../engine/Stage';
import { PALETTE, disposeTree, lerp, mergeStatic } from '../models/materials';
import { createBuilding, createSkyDome } from '../models/props';
import { createShelterModel, SHELTER_RADIUS, type ShelterModel } from '../models/shelterModel';

const TARGET = new THREE.Vector3(0, 0.9, 0);
/** Dirección por defecto de la cámara (desde el objetivo). */
const DEFAULT_DIR = new THREE.Vector3(0.62, 0.55, 0.85).normalize();
const AUTO_ROTATE_RESUME_MS = 4000;
const POP_DURATION = 0.55;

function easeOutBack(x: number): number {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
}

export class ShelterScene {
  private readonly stage: Stage;
  private readonly controls: OrbitControls;
  private readonly fireLight: THREE.PointLight;
  private model: ShelterModel;
  private level: number;
  private popT = POP_DURATION;
  private fitted = false;
  private resumeTimer: ReturnType<typeof setTimeout> | null = null;
  private disposed = false;

  constructor(container: HTMLElement, level: number) {
    this.level = clampLevel(level);
    const stage = new Stage(container, {
      background: PALETTE.fog,
      fog: new THREE.Fog(PALETTE.fog, 26, 70),
      fov: 45,
      near: 0.2,
      far: 160,
    });
    this.stage = stage;
    const scene = stage.scene;

    // Luces: hemisférica + luna + fogata
    scene.add(new THREE.HemisphereLight('#52637a', '#1c150d', 1.15));
    const moon = new THREE.DirectionalLight('#a6bcd6', 1.1);
    moon.position.set(-9, 14, 7);
    scene.add(moon);
    this.fireLight = new THREE.PointLight('#ff8a3c', 30, 13, 1.5);
    scene.add(this.fireLight);

    // Cielo y siluetas lejanas de la ciudad en ruinas
    scene.add(createSkyDome({ radius: 120, top: '#030405', horizon: PALETTE.fog, glow: '#24170d' }));
    const city = new THREE.Group();
    city.name = 'skyline';
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * Math.PI * 2 + Math.sin(i * 7.3) * 0.15;
      const r = 34 + (Math.sin(i * 3.1) * 0.5 + 0.5) * 12;
      const h = 8 + (Math.sin(i * 5.7) * 0.5 + 0.5) * 22;
      const b = createBuilding({ width: 7 + (i % 3) * 3, height: h, depth: 7, seed: 500 + i, lit: 0.07 });
      b.position.set(Math.sin(a) * r, -6, Math.cos(a) * r);
      b.rotation.y = a;
      city.add(b);
    }
    scene.add(city);
    mergeStatic(city);

    this.model = createShelterModel(this.level);
    scene.add(this.model.root);
    this.fireLight.position.copy(this.model.firePosition);

    // Controles orbitales
    const controls = new OrbitControls(stage.camera, stage.renderer.domElement);
    controls.target.copy(TARGET);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.enablePan = false;
    controls.rotateSpeed = 0.7;
    controls.zoomSpeed = 0.8;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.6;
    controls.minPolarAngle = 0.25;
    controls.maxPolarAngle = 1.32; // la cámara nunca baja del suelo
    controls.addEventListener('start', this.onInteractStart);
    controls.addEventListener('end', this.onInteractEnd);
    this.controls = controls;

    stage.onResize(this.onResize);
    stage.onUpdate(this.update);
    stage.renderOnce();
  }

  /** Reconstruye el refugio para otro nivel con una animación de "pop". */
  setLevel(level: number): void {
    if (this.disposed) return;
    const L = clampLevel(level);
    if (L === this.level) return;
    this.level = L;
    const old = this.model;
    this.stage.scene.remove(old.root);
    disposeTree(old.root, true);
    this.model = createShelterModel(L);
    this.model.root.scale.setScalar(0.001);
    this.stage.scene.add(this.model.root);
    this.fireLight.position.copy(this.model.firePosition);
    this.popT = 0;
    if (!this.stage.isRunning) {
      this.model.root.scale.setScalar(1);
      this.popT = POP_DURATION;
      this.stage.renderOnce();
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.resumeTimer) clearTimeout(this.resumeTimer);
    this.controls.removeEventListener('start', this.onInteractStart);
    this.controls.removeEventListener('end', this.onInteractEnd);
    this.controls.dispose();
    this.stage.dispose();
  }

  // -------------------------------------------------------------------------

  private update = (dt: number, elapsed: number): void => {
    if (this.popT < POP_DURATION) {
      this.popT = Math.min(POP_DURATION, this.popT + dt);
      const u = this.popT / POP_DURATION;
      const s = Math.max(0.001, easeOutBack(u));
      this.model.root.scale.set(s, lerp(0.6, 1, Math.min(1, u * 1.6)) * s, s);
    }
    this.model.update(elapsed);
    const f =
      0.82 +
      Math.sin(elapsed * 9.3) * 0.07 +
      Math.sin(elapsed * 15.1 + 1.3) * 0.05 +
      Math.sin(elapsed * 23.7 + 0.4) * 0.03;
    this.fireLight.intensity = 30 * f;
    this.controls.update(dt);
  };

  private onResize = (w: number, h: number): void => {
    const cam = this.stage.camera;
    const aspect = w / h;
    // FOV más abierto en vertical para que el diorama quepa a lo ancho
    cam.fov = aspect < 1 ? lerp(62, 45, Math.max(0, (aspect - 0.45) / 0.55)) : 45;
    cam.updateProjectionMatrix();
    const vTan = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2);
    const hTan = vTan * aspect;
    const fitR = SHELTER_RADIUS * 0.92;
    const dist = Math.min(48, Math.max(12, Math.max(fitR / hTan, (fitR * 0.62) / vTan)));
    this.controls.minDistance = dist * 0.5;
    this.controls.maxDistance = dist * 1.45;
    if (!this.fitted) {
      this.fitted = true;
      cam.position.copy(TARGET).addScaledVector(DEFAULT_DIR, dist);
      cam.lookAt(TARGET);
    } else {
      const d = cam.position.distanceTo(TARGET);
      if (d > this.controls.maxDistance || d < this.controls.minDistance) {
        const nd = Math.min(this.controls.maxDistance, Math.max(this.controls.minDistance, d));
        cam.position.sub(TARGET).setLength(nd).add(TARGET);
      }
    }
    this.controls.update();
  };

  private onInteractStart = (): void => {
    this.controls.autoRotate = false;
    if (this.resumeTimer) {
      clearTimeout(this.resumeTimer);
      this.resumeTimer = null;
    }
  };

  private onInteractEnd = (): void => {
    if (this.resumeTimer) clearTimeout(this.resumeTimer);
    this.resumeTimer = setTimeout(() => {
      this.resumeTimer = null;
      if (!this.disposed) this.controls.autoRotate = true;
    }, AUTO_ROTATE_RESUME_MS);
  };
}

function clampLevel(level: number): number {
  return Math.max(1, Math.min(5, Math.round(Number.isFinite(level) ? level : 1)));
}
