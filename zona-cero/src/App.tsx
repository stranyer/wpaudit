import { useEffect, useState } from 'react';
import { bootstrap } from './game/session';
import { GameMap } from './map/GameMap';
import { useGameStore } from './store/gameStore';
import { useLocationStore } from './store/locationStore';
import { useUiStore } from './store/uiStore';
import { BottomNav } from './ui/components/BottomNav';
import { Celebration } from './ui/components/Celebration';
import { Toasts } from './ui/components/Toasts';
import { CombatScreen } from './ui/screens/CombatScreen';
import { CommunityScreen } from './ui/screens/CommunityScreen';
import { InventoryScreen } from './ui/screens/InventoryScreen';
import { MapScreen } from './ui/screens/MapScreen';
import { ProfileScreen } from './ui/screens/ProfileScreen';
import { ShelterScreen } from './ui/screens/ShelterScreen';
import { StartScreen } from './ui/screens/StartScreen';

export function App() {
  const ready = useGameStore((s) => s.ready);
  const inCombat = useGameStore((s) => s.combat !== null);
  const mode = useLocationStore((s) => s.mode);
  const hasPosition = useLocationStore((s) => s.position !== null);
  const screen = useUiStore((s) => s.screen);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    bootstrap().catch((err: unknown) => setError(err instanceof Error ? err.message : String(err)));
  }, []);

  if (error) {
    return (
      <div className="app">
        <div className="loading" style={{ padding: 24, textAlign: 'center' }}>
          No se pudo iniciar el juego: {error}
        </div>
      </div>
    );
  }
  if (!ready) {
    return (
      <div className="app">
        <div className="loading">Cargando Zona Cero…</div>
      </div>
    );
  }

  const started = mode !== null && hasPosition;

  return (
    <div className="app">
      {/* El mapa queda montado detrás de las demás pantallas para no recargar tiles. */}
      {started && <GameMap active={screen === 'map'} />}
      {started && screen === 'map' && <MapScreen />}
      {started && screen === 'inventory' && <InventoryScreen />}
      {started && screen === 'shelter' && <ShelterScreen />}
      {started && screen === 'profile' && <ProfileScreen />}
      {started && screen === 'community' && <CommunityScreen />}
      {started && !inCombat && <BottomNav />}
      {started && inCombat && <CombatScreen />}
      {!started && <StartScreen />}
      {!started && mode === 'gps' && <GpsWaiting />}
      <Toasts />
      <Celebration />
    </div>
  );
}

function GpsWaiting() {
  const status = useLocationStore((s) => s.status);
  if (status !== 'requesting') return null;
  return (
    <div className="celebration" style={{ zIndex: 95 }}>
      <div className="celebration-box">
        <h2 className="display" style={{ color: 'var(--orange-bright)' }}>Buscando señal GPS…</h2>
        <p className="dim">Aceptá el permiso de ubicación. Si tarda, probá al aire libre o usá el modo demo.</p>
      </div>
    </div>
  );
}
