import { useState } from 'react';
import { Biohazard, Gamepad2, Satellite, TriangleAlert } from 'lucide-react';
import { startLocation } from '../../game/session';
import { useGameStore } from '../../store/gameStore';

export function StartScreen() {
  const lastMode = useGameStore((s) => s.lastMode);
  const player = useGameStore((s) => s.player);
  const [busy, setBusy] = useState(false);

  const begin = async (mode: 'gps' | 'demo') => {
    setBusy(true);
    try {
      await startLocation(mode);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="start grain">
      <div>
        <h1 className="logo">
          Zona
          <span>Cero</span>
        </h1>
        <div className="logo-sub">Sobreviví a tu ciudad</div>
        <div className="biohazard">
          <Biohazard size={120} strokeWidth={1} />
        </div>
      </div>

      <div style={{ display: 'grid', gap: 16 }}>
        {player && player.level > 1 && (
          <div className="chip ok" style={{ justifySelf: 'center' }}>
            {player.name} · Nivel {player.level}
          </div>
        )}
        <div className="start-warning">
          <TriangleAlert size={20} />
          <span>
            Prestá atención a tu entorno. No ingreses a propiedades privadas ni a lugares peligrosos y no juegues mientras
            manejás. Tu ubicación exacta nunca se comparte con otros jugadores.
          </span>
        </div>
        <div className="start-actions">
          <button className="btn btn-primary btn-lg btn-block" disabled={busy} onClick={() => begin('gps')}>
            <Satellite size={20} /> {lastMode === 'gps' ? 'Continuar con GPS' : 'Usar mi ubicación'}
          </button>
          <button className="btn btn-lg btn-block" disabled={busy} onClick={() => begin('demo')}>
            <Gamepad2 size={20} /> Modo demo · Buenos Aires
          </button>
        </div>
        <p className="label" style={{ textAlign: 'center', margin: 0 }}>
          v0.1 · Mapas © OpenStreetMap
        </p>
      </div>
    </div>
  );
}
