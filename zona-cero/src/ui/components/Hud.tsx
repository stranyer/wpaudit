import { Heart, Satellite, Zap, Gamepad2, Ban } from 'lucide-react';
import { maxHealth, maxStamina } from '../../core/player';
import { rankTitle, xpToNext } from '../../core/progression';
import { useGameStore } from '../../store/gameStore';
import { useLocationStore } from '../../store/locationStore';
import { useUiStore } from '../../store/uiStore';
import { StatBar } from './StatBar';

export function Hud() {
  const player = useGameStore((s) => s.player);
  const mode = useLocationStore((s) => s.mode);
  const accuracy = useLocationStore((s) => s.accuracyM);
  const status = useLocationStore((s) => s.status);
  const lockedUntil = useLocationStore((s) => s.speedLockedUntil);
  const go = useUiStore((s) => s.go);
  if (!player) return null;
  const mh = maxHealth(player);
  const ms = maxStamina(player);
  const locked = lockedUntil > Date.now();

  return (
    <div className="hud">
      <div className="hud-card" onClick={() => go('profile')}>
        <div className="level-badge" title="Nivel">{player.level}</div>
        <div className="hud-bars">
          <div className="hud-name">
            <span>{player.name}</span>
            <span className="rank">{rankTitle(player.level)}</span>
          </div>
          <div className="hud-row">
            <Heart color="#e2513f" />
            <StatBar value={player.health} max={mh} kind="health" />
            <span className="val">{Math.round(player.health)}</span>
          </div>
          <div className="hud-row">
            <Zap color="#b8c94a" />
            <StatBar value={player.stamina} max={ms} kind="stamina" />
            <span className="val">{Math.round(player.stamina)}</span>
          </div>
          <StatBar value={player.xp} max={xpToNext(player.level)} kind="xp" />
        </div>
      </div>
      <div className={`gps-chip ${mode === 'demo' ? 'demo' : ''} ${locked ? 'locked' : ''}`}>
        {locked ? <Ban size={20} /> : mode === 'demo' ? <Gamepad2 size={20} /> : <Satellite size={20} />}
        {locked ? 'Bloqueo' : mode === 'demo' ? 'Demo' : status === 'active' ? `±${Math.round(accuracy)} m` : 'GPS…'}
      </div>
    </div>
  );
}
