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
const LOOK_Y = 1.08;

export class AvatarScene {
  private readonly stage: Stage;
  private readonly survivor: SurvivorRig;
  private readonly turntable = new THREE.Group();
  private readonly rim: THREE.DirectionalLight;
  private disposed = false;

  constructor(container: HTMLElement, opts: AvatarSceneOptions = {}) {
    const stage = new Stage(container, { alpha: true, fog: null, fov: 30, near: 0.1, far: 40 });
    this.stage = stage;
    const scene = stage.scene;

    // Luces: ambiente frío + clave cálida + contraluz (rim) frío intenso
    scene.add(new THREE.HemisphereLight('#5d6f82', '#1e1710', 1.0));
    const key = new THREE.DirectionalLight('#f0b070', 1.5);
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
    addRubble(b, { seed: 5, count: 16, radius: 0.95, height: 0.18 }, 0, 0);
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

  private onResize = (w: number, h: number): void => {
    const cam = this.stage.camera;
    const aspect = w / h;
    const vTan = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2);
    // Encuadre: ~2.25 m de alto (pedestal + personaje) y ~1.7 m de ancho
    const dist = Math.max(1.18 / vTan, 0.85 / (vTan * aspect));
    cam.position.set(0, LOOK_Y + 0.15, dist);
    cam.lookAt(0, LOOK_Y, 0);
  };
}
