// Stage: envoltorio reutilizable de renderer + escena + cámara dentro de un contenedor DOM.
//
// - Ajusta el tamaño con ResizeObserver (el canvas ocupa el 100% del contenedor).
// - Bucle con `renderer.setAnimationLoop`; los suscriptores reciben (dt, elapsed) en segundos.
// - Se pausa cuando la pestaña/app está oculta (`visibilitychange`) o el contenedor sale de
//   pantalla (IntersectionObserver), y al volver no hay saltos de tiempo.
// - `dispose()` libera TODO: geometrías, materiales, renderer, contexto WebGL, canvas y listeners.
//
// Si WebGL no está disponible el constructor lanza `WebGLUnavailableError`.

import * as THREE from 'three';
import { disposeTree, PALETTE } from '../models/materials';

export type UpdateCallback = (dt: number, elapsed: number) => void;
export type ResizeCallback = (width: number, height: number) => void;

export interface StageOptions {
  /** Canvas transparente (clear alpha 0) para fundirse con la UI. */
  alpha?: boolean;
  /** Color de fondo (ignorado si `alpha`). */
  background?: THREE.ColorRepresentation;
  /** Niebla de la escena; `null` para desactivarla. */
  fog?: THREE.Fog | THREE.FogExp2 | null;
  fov?: number;
  near?: number;
  far?: number;
  /** Tope del devicePixelRatio (por defecto 1.75). */
  maxPixelRatio?: number;
  /** Pausar el render cuando el contenedor no es visible en pantalla (por defecto true). */
  pauseWhenOffscreen?: boolean;
}

export class WebGLUnavailableError extends Error {
  constructor(cause?: unknown) {
    super('WebGL no está disponible en este dispositivo');
    this.name = 'WebGLUnavailableError';
    if (cause !== undefined) (this as { cause?: unknown }).cause = cause;
  }
}

const MAX_DT = 0.1;

export class Stage {
  readonly container: HTMLElement;
  readonly renderer: THREE.WebGLRenderer;
  readonly scene: THREE.Scene;
  readonly camera: THREE.PerspectiveCamera;
  readonly canvas: HTMLCanvasElement;

  /** Tamaño actual en píxeles CSS. */
  width = 1;
  height = 1;
  /** Segundos acumulados mientras el bucle estuvo activo. */
  elapsed = 0;

  private updaters: UpdateCallback[] = [];
  private resizers: ResizeCallback[] = [];
  private lastTime = -1;
  private running = false;
  private onscreen = true;
  private contextLost = false;
  private disposed = false;
  private resizeObserver: ResizeObserver | null = null;
  private intersectionObserver: IntersectionObserver | null = null;

  constructor(container: HTMLElement, options: StageOptions = {}) {
    this.container = container;
    const alpha = options.alpha ?? false;

    const canvas = document.createElement('canvas');
    canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block;outline:none;';
    canvas.setAttribute('aria-hidden', 'true');
    this.canvas = canvas;

    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        canvas,
        antialias: dpr < 2,
        alpha,
        powerPreference: 'high-performance',
        preserveDrawingBuffer: false,
        stencil: false,
      });
      if (!renderer.getContext()) throw new Error('Contexto WebGL nulo');
    } catch (err) {
      throw new WebGLUnavailableError(err);
    }
    this.renderer = renderer;
    renderer.setPixelRatio(Math.min(dpr, options.maxPixelRatio ?? 1.75));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.shadowMap.enabled = false;

    this.scene = new THREE.Scene();
    if (alpha) {
      renderer.setClearColor(0x000000, 0);
      this.scene.background = null;
    } else {
      const bg = new THREE.Color(options.background ?? PALETTE.fog);
      renderer.setClearColor(bg, 1);
      this.scene.background = bg;
    }
    if (options.fog !== undefined) this.scene.fog = options.fog;

    this.camera = new THREE.PerspectiveCamera(options.fov ?? 50, 1, options.near ?? 0.1, options.far ?? 200);
    // La cámara forma parte de la escena para poder colgarle hijos (overlays, fogonazos).
    this.scene.add(this.camera);

    if (getComputedStyle(container).position === 'static') container.style.position = 'relative';
    container.appendChild(canvas);

    canvas.addEventListener('webglcontextlost', this.onContextLost, false);
    canvas.addEventListener('webglcontextrestored', this.onContextRestored, false);
    document.addEventListener('visibilitychange', this.onVisibility);

    this.applySize(container.clientWidth, container.clientHeight);

    if (typeof ResizeObserver !== 'undefined') {
      this.resizeObserver = new ResizeObserver((entries) => {
        const entry = entries[entries.length - 1];
        if (!entry) return;
        const box = entry.contentRect;
        this.applySize(box.width, box.height);
      });
      this.resizeObserver.observe(container);
    } else {
      window.addEventListener('resize', this.onWindowResize);
    }

    if ((options.pauseWhenOffscreen ?? true) && typeof IntersectionObserver !== 'undefined') {
      this.intersectionObserver = new IntersectionObserver((entries) => {
        const entry = entries[entries.length - 1];
        if (!entry) return;
        this.onscreen = entry.isIntersecting;
        this.syncLoop();
      });
      this.intersectionObserver.observe(container);
    }

    this.syncLoop();
  }

  /** Suscribe una función al bucle. Devuelve la función para desuscribirse. */
  onUpdate(fn: UpdateCallback): () => void {
    this.updaters.push(fn);
    return () => {
      const i = this.updaters.indexOf(fn);
      if (i >= 0) this.updaters.splice(i, 1);
    };
  }

  /** Suscribe una función a los cambios de tamaño (se llama también al suscribirse). */
  onResize(fn: ResizeCallback): () => void {
    this.resizers.push(fn);
    fn(this.width, this.height);
    return () => {
      const i = this.resizers.indexOf(fn);
      if (i >= 0) this.resizers.splice(i, 1);
    };
  }

  /** Renderiza un fotograma inmediatamente (p. ej. tras reconstruir algo estando en pausa). */
  renderOnce(): void {
    if (this.disposed || this.contextLost) return;
    this.renderer.render(this.scene, this.camera);
  }

  get isRunning(): boolean {
    return this.running;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.running = false;
    this.renderer.setAnimationLoop(null);
    this.resizeObserver?.disconnect();
    this.intersectionObserver?.disconnect();
    this.resizeObserver = null;
    this.intersectionObserver = null;
    window.removeEventListener('resize', this.onWindowResize);
    document.removeEventListener('visibilitychange', this.onVisibility);
    this.canvas.removeEventListener('webglcontextlost', this.onContextLost, false);
    this.canvas.removeEventListener('webglcontextrestored', this.onContextRestored, false);
    this.updaters.length = 0;
    this.resizers.length = 0;

    disposeTree(this.scene);
    this.scene.clear();
    this.scene.background = null;
    this.scene.fog = null;
    this.renderer.renderLists.dispose();
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    this.canvas.remove();
  }

  // -------------------------------------------------------------------------

  private applySize(w: number, h: number): void {
    if (this.disposed) return;
    const width = Math.max(1, Math.floor(w));
    const height = Math.max(1, Math.floor(h));
    this.width = width;
    this.height = height;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    for (let i = 0; i < this.resizers.length; i++) this.resizers[i](width, height);
    if (!this.running) this.renderOnce();
  }

  private loop = (time: number): void => {
    if (this.lastTime < 0) this.lastTime = time;
    let dt = (time - this.lastTime) / 1000;
    this.lastTime = time;
    if (!(dt > 0)) dt = 0;
    if (dt > MAX_DT) dt = MAX_DT;
    this.elapsed += dt;
    const list = this.updaters;
    for (let i = 0; i < list.length; i++) list[i](dt, this.elapsed);
    this.renderer.render(this.scene, this.camera);
  };

  private syncLoop(): void {
    const shouldRun = !this.disposed && !this.contextLost && this.onscreen && !document.hidden;
    if (shouldRun === this.running) return;
    this.running = shouldRun;
    if (shouldRun) {
      this.lastTime = -1; // evita un dt enorme al reanudar
      this.renderer.setAnimationLoop(this.loop);
    } else {
      this.renderer.setAnimationLoop(null);
    }
  }

  private onVisibility = (): void => {
    this.syncLoop();
  };

  private onWindowResize = (): void => {
    this.applySize(this.container.clientWidth, this.container.clientHeight);
  };

  private onContextLost = (event: Event): void => {
    event.preventDefault();
    this.contextLost = true;
    this.syncLoop();
  };

  private onContextRestored = (): void => {
    this.contextLost = false;
    this.syncLoop();
  };
}
