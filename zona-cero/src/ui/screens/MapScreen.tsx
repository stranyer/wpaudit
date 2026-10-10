import { useLocationStore } from '../../store/locationStore';
import { DemoJoystick } from '../components/DemoJoystick';
import { Hud } from '../components/Hud';
import { TargetSheet } from '../components/TargetSheet';
import { NearbyRadar } from '../components/NearbyRadar';

/** Capa de interfaz sobre el mapa (el mapa vive en App para no recrearse). */
export function MapScreen() {
  const mode = useLocationStore((s) => s.mode);
  const lockedUntil = useLocationStore((s) => s.speedLockedUntil);
  const status = useLocationStore((s) => s.status);
  return (
    <>
      <Hud />
      {lockedUntil > Date.now() && <div className="speed-warning">Vas demasiado rápido · interacciones en pausa</div>}
      {mode === 'gps' && status === 'requesting' && <div className="speed-warning" style={{ background: 'rgba(20,24,20,.92)', borderColor: 'var(--line-2)' }}>Buscando señal GPS…</div>}
      <NearbyRadar />
      <TargetSheet />
      {mode === 'demo' && <DemoJoystick />}
    </>
  );
}
