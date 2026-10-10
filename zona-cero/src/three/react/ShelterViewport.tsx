// Visor 3D del refugio con cámara orbital táctil. Al cambiar `level` se reconstruye el
// modelo con una animación (no se recrea la escena ni el contexto WebGL).

import { useEffect, useRef, useState } from 'react';
import { ShelterScene } from '../scenes/ShelterScene';
import { ViewportFallback, viewportStyle } from './ViewportFallback';

export interface ShelterViewportProps {
  level: number;
  className?: string;
}

export function ShelterViewport({ level, className }: ShelterViewportProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<ShelterScene | null>(null);
  const levelRef = useRef(level);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let scene: ShelterScene;
    try {
      scene = new ShelterScene(host, levelRef.current);
    } catch (err) {
      console.warn('[ShelterViewport] No se pudo iniciar WebGL:', err);
      setFailed(true);
      return;
    }
    sceneRef.current = scene;
    return () => {
      if (sceneRef.current === scene) sceneRef.current = null;
      scene.dispose();
    };
  }, []);

  useEffect(() => {
    levelRef.current = level;
    sceneRef.current?.setLevel(level);
  }, [level]);

  if (failed) return <ViewportFallback className={className} />;
  return <div ref={hostRef} className={className} style={viewportStyle} />;
}

export default ShelterViewport;
