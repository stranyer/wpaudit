// Retrato 3D del superviviente con fondo transparente (ponlo sobre una tarjeta oscura).

import { useEffect, useRef, useState } from 'react';
import { AvatarScene } from '../scenes/AvatarScene';
import { ViewportFallback, viewportStyle } from './ViewportFallback';

export interface AvatarViewportProps {
  accentColor?: string;
  className?: string;
}

export function AvatarViewport({ accentColor, className }: AvatarViewportProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<AvatarScene | null>(null);
  const accentRef = useRef(accentColor);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let scene: AvatarScene;
    try {
      scene = new AvatarScene(host, { accentColor: accentRef.current });
    } catch (err) {
      console.warn('[AvatarViewport] No se pudo iniciar WebGL:', err);
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
    accentRef.current = accentColor;
    if (accentColor) sceneRef.current?.setAccentColor(accentColor);
  }, [accentColor]);

  if (failed) return <ViewportFallback className={className} />;
  return <div ref={hostRef} className={className} style={viewportStyle} />;
}

export default AvatarViewport;
