import type { ReactElement } from 'react';
import type { ItemId } from '../../core/types';

// Íconos propios de objetos (SVG 24x24, silueta sólida en currentColor).
// Los detalles oscuros usan negro con transparencia para leerse sobre cualquier color.

const shade = { fill: '#000', fillOpacity: 0.38 } as const;

const ICONS: Record<ItemId, ReactElement> = {
  food: (
    <>
      <rect x="5.5" y="6" width="13" height="14.5" rx="1.6" />
      <ellipse cx="12" cy="6" rx="6.5" ry="2" />
      <rect x="5.5" y="10.5" width="13" height="5" {...shade} />
    </>
  ),
  water: (
    <>
      <path d="M10 2h4v3l1.8 2.4V20a2 2 0 0 1-2 2h-3.6a2 2 0 0 1-2-2V7.4L10 5z" />
      <rect x="8.2" y="11" width="7.6" height="5" {...shade} />
    </>
  ),
  medicine: (
    <g transform="rotate(-45 12 12)">
      <rect x="3.5" y="8.3" width="17" height="7.4" rx="3.7" />
      <path d="M12 8.3h4.8a3.7 3.7 0 0 1 0 7.4H12z" {...shade} />
    </g>
  ),
  wood: (
    <>
      <rect x="2.5" y="5.5" width="19" height="4.6" rx="1" transform="rotate(-10 12 8)" />
      <rect x="2.5" y="13.5" width="19" height="4.6" rx="1" transform="rotate(7 12 16)" />
      <circle cx="6" cy="8.4" r="0.9" {...shade} />
      <circle cx="18" cy="16.6" r="0.9" {...shade} />
    </>
  ),
  metal: (
    <>
      <path d="M12 2.5l8.2 4.75v9.5L12 21.5l-8.2-4.75v-9.5z" />
      <circle cx="12" cy="12" r="3.6" {...shade} />
    </>
  ),
  ammo: (
    <>
      <path d="M4 21v-8.5C4 9.5 6 6.5 6 6.5s2 3 2 6V21z" />
      <path d="M10 21v-9.5C10 8.5 12 5 12 5s2 3.5 2 6.5V21z" />
      <path d="M16 21v-8.5c0-3 2-6 2-6s2 3 2 6V21z" />
      <rect x="3.5" y="17.5" width="17" height="1.6" {...shade} />
    </>
  ),
  medkit: (
    <>
      <rect x="9" y="3.5" width="6" height="3.5" rx="1" />
      <rect x="3" y="6.5" width="18" height="14" rx="2" />
      <path d="M10.8 9.8h2.4v2.6h2.6v2.4h-2.6v2.6h-2.4v-2.6H8.2v-2.4h2.6z" {...shade} />
    </>
  ),
  ration: (
    <>
      <path d="M3 7.5l9-4 9 4v9.5l-9 4-9-4z" />
      <path d="M3 7.5l9 4 9-4M12 11.5v9.5" fill="none" stroke="#000" strokeOpacity="0.4" strokeWidth="1.5" />
    </>
  ),
  adrenaline: (
    <g transform="rotate(45 12 12)">
      <rect x="10" y="4" width="4" height="11" rx="1" />
      <rect x="8" y="3" width="8" height="1.6" />
      <rect x="11" y="0.6" width="2" height="2.4" />
      <rect x="11.5" y="15" width="1" height="7" />
      <rect x="10.6" y="9" width="2.8" height="5" {...shade} />
    </g>
  ),
  pipe: (
    <g transform="rotate(-45 12 12)">
      <rect x="10.4" y="2" width="3.2" height="20" rx="1" />
      <rect x="9.2" y="2" width="5.6" height="3.2" rx="1" />
      <rect x="9.2" y="18.8" width="5.6" height="3.2" rx="1" />
    </g>
  ),
  nail_bat: (
    <g transform="rotate(-45 12 12)">
      <path d="M11 22.5h2l.9-11.5c.3-2.8.6-5.6.6-8.5H9.5c0 2.9.3 5.7.6 8.5z" />
      <path d="M9.6 5H7.4M14.4 6.5h2.2M9.8 8.4H7.6M14.2 9.6h2.2" stroke="currentColor" strokeWidth="1.3" />
    </g>
  ),
  machete: (
    <g transform="rotate(-40 12 12)">
      <path d="M10.2 1.5h3.2c.8 4.5 1.4 9 1.6 13.5l-3 1.5-2.6-1.5c.1-4.5.3-9 .8-13.5z" />
      <rect x="10" y="16.5" width="4" height="6" rx="1" {...shade} />
    </g>
  ),
  fire_axe: (
    <g transform="rotate(-30 12 12)">
      <rect x="11" y="3" width="2.2" height="19.5" rx="1" />
      <path d="M13.2 3h2.8c3 1 4.5 4 4.5 7h-7.3z" />
      <path d="M11 3.5H9.2L7.6 7H11z" />
      <rect x="11" y="16" width="2.2" height="6.5" {...shade} />
    </g>
  ),
  pistol: (
    <>
      <path d="M2.5 6.5h17v4.5h-7.2l-.8 2h-2.2L7.8 20H3.7l1.6-7.5H2.5z" />
      <path d="M9.6 11.6v2.6H8" fill="none" stroke="currentColor" strokeWidth="1.4" />
      <rect x="2.5" y="6.5" width="17" height="1.6" {...shade} />
    </>
  ),
  shotgun: (
    <>
      <path d="M1.5 8.5h14l1.2-1h5.8v3.4H12.3l-1.1 2H9.2L7 17.6l-4.4-1.3 2.1-4.4H1.5z" />
      <rect x="15.5" y="7.5" width="7" height="1.4" {...shade} />
    </>
  ),
  leather_jacket: (
    <>
      <path d="M8 3l4 2.2L16 3l5.2 4-2 4.2-2.2-1.2V21H7V10l-2.2 1.2-2-4.2z" />
      <path d="M12 5.2V21" fill="none" stroke="#000" strokeOpacity="0.45" strokeWidth="1.4" />
    </>
  ),
  scrap_vest: (
    <>
      <path d="M7 3h3l2 2 2-2h3l2.5 4v14H4.5V7z" />
      <rect x="6.8" y="9" width="4.6" height="4.2" {...shade} />
      <rect x="12.6" y="9" width="4.6" height="4.2" {...shade} />
      <rect x="6.8" y="14.4" width="10.4" height="4.2" fill="#000" fillOpacity="0.25" />
    </>
  ),
  riot_armor: (
    <>
      <path d="M12 2l8.5 3.2v6.3c0 5.2-3.6 9.2-8.5 11-4.9-1.8-8.5-5.8-8.5-11V5.2z" />
      <path d="M7.5 9h9M7.5 12.5h9" fill="none" stroke="#000" strokeOpacity="0.4" strokeWidth="1.6" />
    </>
  ),
};

export function ItemIcon({ id, size = 24, className }: { id: ItemId; size?: number; className?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="currentColor"
      className={className}
      aria-hidden="true"
      focusable="false"
    >
      {ICONS[id]}
    </svg>
  );
}
