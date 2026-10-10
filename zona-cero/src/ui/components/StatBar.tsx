interface StatBarProps {
  value: number;
  max: number;
  kind: 'health' | 'stamina' | 'xp' | 'enemy' | 'progress';
  className?: string;
}

export function StatBar({ value, max, kind, className = '' }: StatBarProps) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  const low = (kind === 'health' || kind === 'stamina') && pct < 25;
  return (
    <div className={`bar ${kind} ${low ? 'low' : ''} ${className}`} role="progressbar" aria-valuenow={Math.round(value)} aria-valuemax={max}>
      <div className="bar-fill" style={{ width: `${pct}%` }} />
    </div>
  );
}
