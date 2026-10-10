// Visor 3D de combate. Llena su contenedor padre (dale tamaño al padre).
// Expone `play(animation)` vía ref (React 19: `ref` es una prop normal).

import { useEffect, useImperativeHandle, useRef, useState } from 'react';
import type { Ref } from 'react';
import type { ZombieTypeId } from '../../core/types';
import type { CombatAnimation, CombatViewportHandle } from '../types';
import { CombatScene } from '../scenes/CombatScene';
import { ViewportFallback, viewportStyle } from './ViewportFallback';

export interface CombatViewportProps {
  zombieType: ZombieTypeId;
  className?: string;
  ref?: Ref<CombatViewportHandle>;
}

export function CombatViewport({ zombieType, className, ref }: CombatViewportProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<CombatScene | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let scene: CombatScene;
    try {
      scene = new CombatScene(host, zombieType);
    } catch (err) {
      console.warn('[CombatViewport] No se pudo iniciar WebGL:', err);
      setFailed(true);
      return;
    }
    sceneRef.current = scene;
    return () => {
      if (sceneRef.current === scene) sceneRef.current = null;
      scene.dispose();
    };
  }, [zombieType]);

  useImperativeHandle(
    ref,
    () => ({
      play(animation: CombatAnimation) {
        sceneRef.current?.play(animation);
      },
    }),
    [],
  );

  if (failed) return <ViewportFallback className={className} />;
  return <div ref={hostRef} className={className} style={viewportStyle} />;
}

export default CombatViewport;
