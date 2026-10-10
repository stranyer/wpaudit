import { useEffect, useRef, useState } from 'react';
import { demoProvider } from '../../game/session';
import { getMapBearing } from '../../map/mapInstance';
import { GAME_CONFIG } from '../../config/gameConfig';

/** Convierte un vector de pantalla (arriba = +y) a este/norte según la rotación del mapa. */
function toWorld(sx: number, sy: number): { x: number; y: number } {
  const b = (getMapBearing() * Math.PI) / 180;
  return { x: sx * Math.cos(b) + sy * Math.sin(b), y: -sx * Math.sin(b) + sy * Math.cos(b) };
}

const RADIUS = 34;

/** Joystick táctil + teclado (WASD / flechas, Shift para correr) para el modo demo. */
export function DemoJoystick() {
  const baseRef = useRef<HTMLDivElement>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const pointerId = useRef<number | null>(null);

  useEffect(() => {
    const keys = new Set<string>();
    const update = () => {
      const sx = (keys.has('d') || keys.has('arrowright') ? 1 : 0) - (keys.has('a') || keys.has('arrowleft') ? 1 : 0);
      const sy = (keys.has('w') || keys.has('arrowup') ? 1 : 0) - (keys.has('s') || keys.has('arrowdown') ? 1 : 0);
      const run = keys.has('shift') ? GAME_CONFIG.demo.runMultiplier : 1;
      const w = toWorld(sx, sy);
      demoProvider()?.setVelocity(w.x, w.y, run);
    };
    const isTyping = (e: KeyboardEvent) => e.target instanceof HTMLInputElement;
    const down = (e: KeyboardEvent) => {
      if (isTyping(e)) return;
      const k = e.key.toLowerCase();
      if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright', 'shift'].includes(k)) {
        if (k.startsWith('arrow')) e.preventDefault();
        keys.add(k);
        update();
      }
    };
    const up = (e: KeyboardEvent) => {
      keys.delete(e.key.toLowerCase());
      update();
    };
    const blur = () => {
      keys.clear();
      update();
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', blur);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', blur);
      demoProvider()?.setVelocity(0, 0);
    };
  }, []);

  const move = (clientX: number, clientY: number) => {
    const rect = baseRef.current!.getBoundingClientRect();
    let dx = clientX - (rect.left + rect.width / 2);
    let dy = clientY - (rect.top + rect.height / 2);
    const len = Math.hypot(dx, dy);
    if (len > RADIUS) {
      dx = (dx / len) * RADIUS;
      dy = (dy / len) * RADIUS;
    }
    setKnob({ x: dx, y: dy });
    const mag = Math.min(1, len / RADIUS);
    // Empujar el stick al máximo hace correr.
    const run = mag > 0.95 ? GAME_CONFIG.demo.runMultiplier : 1;
    const w = toWorld(dx / RADIUS, -dy / RADIUS);
    demoProvider()?.setVelocity(w.x, w.y, run * (mag < 0.2 ? 0 : 1));
  };

  const release = () => {
    pointerId.current = null;
    setKnob({ x: 0, y: 0 });
    demoProvider()?.setVelocity(0, 0);
  };

  return (
    <div
      ref={baseRef}
      className="joystick"
      onPointerDown={(e) => {
        pointerId.current = e.pointerId;
        e.currentTarget.setPointerCapture(e.pointerId);
        move(e.clientX, e.clientY);
      }}
      onPointerMove={(e) => {
        if (pointerId.current === e.pointerId) move(e.clientX, e.clientY);
      }}
      onPointerUp={release}
      onPointerCancel={release}
      aria-label="Joystick de movimiento (modo demo)"
    >
      <div className="joystick-knob" style={{ transform: `translate(${knob.x}px, ${knob.y}px)` }} />
    </div>
  );
}
