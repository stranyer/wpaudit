import { useEffect } from 'react';
import { useUiStore } from '../../store/uiStore';

export function Celebration() {
  const celebration = useUiStore((s) => s.celebration);
  const celebrate = useUiStore((s) => s.celebrate);
  useEffect(() => {
    if (!celebration) return;
    const t = setTimeout(() => celebrate(null), 3500);
    return () => clearTimeout(t);
  }, [celebration, celebrate]);
  if (!celebration) return null;
  return (
    <div className="celebration" onClick={() => celebrate(null)} role="dialog" aria-live="assertive">
      <div className="celebration-box">
        <h2 className="celebration-title">{celebration.title}</h2>
        <p className="dim">{celebration.subtitle}</p>
        <p className="label" style={{ marginTop: 24 }}>Tocá para continuar</p>
      </div>
    </div>
  );
}
