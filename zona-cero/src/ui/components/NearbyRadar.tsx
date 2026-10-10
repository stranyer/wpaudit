import { useMemo } from 'react';
import { Package, Skull } from 'lucide-react';
import { formatDistance, haversineM } from '../../core/geo';
import type { Spawn } from '../../core/types';
import { useLocationStore } from '../../store/locationStore';
import { useWorldStore, visibleSpawns } from '../../store/worldStore';

/** Accesos rápidos al zombie y al suministro más cercanos. */
export function NearbyRadar() {
  const spawns = useWorldStore((s) => s.spawns);
  const placementAvailable = useWorldStore((s) => s.placementAvailable);
  const selectedId = useWorldStore((s) => s.selectedId);
  const select = useWorldStore((s) => s.select);
  const position = useLocationStore((s) => s.position);
  const coarse = position ? `${position.lat.toFixed(4)},${position.lng.toFixed(4)}` : '';

  const nearest = useMemo(() => {
    if (!position) return { zombie: null, supply: null };
    let zombie: { s: Spawn; d: number } | null = null;
    let supply: { s: Spawn; d: number } | null = null;
    for (const s of visibleSpawns(spawns, placementAvailable)) {
      const d = haversineM(position, s.position);
      if (s.kind === 'zombie' && (!zombie || d < zombie.d)) zombie = { s, d };
      if (s.kind === 'supply' && (!supply || d < supply.d)) supply = { s, d };
    }
    return { zombie, supply };
    // `coarse` agrupa los movimientos pequeños para no recalcular en cada paso.
  }, [spawns, placementAvailable, coarse]);

  if (selectedId || !position) return null;
  return (
    <div
      style={{
        position: 'absolute',
        right: 10,
        bottom: 'calc(var(--nav-h) + var(--safe-bottom) + 16px)',
        zIndex: 11,
        display: 'grid',
        gap: 6,
      }}
    >
      {nearest.zombie && (
        <button className="btn btn-sm" style={{ justifyContent: 'flex-start' }} onClick={() => select(nearest.zombie!.s.id)}>
          <Skull size={15} color="#ff6a4d" /> {formatDistance(nearest.zombie.d)}
        </button>
      )}
      {nearest.supply && (
        <button className="btn btn-sm" style={{ justifyContent: 'flex-start' }} onClick={() => select(nearest.supply!.s.id)}>
          <Package size={15} color="#ec9442" /> {formatDistance(nearest.supply.d)}
        </button>
      )}
    </div>
  );
}
