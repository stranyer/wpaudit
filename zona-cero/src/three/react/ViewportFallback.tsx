// Contenedor común de los visores 3D y mensaje de respaldo cuando WebGL no está disponible.

import type { CSSProperties } from 'react';

export const viewportStyle: CSSProperties = {
  position: 'relative',
  width: '100%',
  height: '100%',
  overflow: 'hidden',
};

const fallbackStyle: CSSProperties = {
  ...viewportStyle,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: '16px',
  boxSizing: 'border-box',
  background: 'radial-gradient(ellipse at center, #1a1e1f 0%, #0b0d0b 75%)',
  color: '#8f9a78',
  fontSize: '14px',
  lineHeight: 1.4,
  textAlign: 'center',
};

export const WEBGL_FALLBACK_MESSAGE = 'Tu dispositivo no puede mostrar gráficos 3D';

export function ViewportFallback({ className }: { className?: string }) {
  return (
    <div className={className} style={fallbackStyle} role="status">
      {WEBGL_FALLBACK_MESSAGE}
    </div>
  );
}
