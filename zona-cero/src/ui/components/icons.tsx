import {
  Backpack,
  BriefcaseMedical,
  Car,
  Construction,
  Hammer,
  ShoppingCart,
  Skull,
  Tent,
  Castle,
  House,
  Package,
  type LucideIcon,
} from 'lucide-react';
import type { SupplyTypeId } from '../../core/types';

export const SUPPLY_ICONS: Record<SupplyTypeId, LucideIcon> = {
  backpack: Backpack,
  car: Car,
  debris: Construction,
  grocery: ShoppingCart,
  pharmacy: BriefcaseMedical,
  hardware: Hammer,
  military: Package,
};

export const ZombieIcon = Skull;

/** Ícono del refugio según su nivel. */
export function shelterIcon(level: number): LucideIcon {
  if (level >= 5) return Castle;
  if (level >= 3) return House;
  return Tent;
}

/** Silueta de sobreviviente para el marcador del jugador (SVG propio). */
export function SurvivorFigure({ color = '#ec9442' }: { color?: string }) {
  return (
    <svg viewBox="0 0 44 56" width="44" height="56" aria-hidden="true">
      <ellipse cx="22" cy="53" rx="10" ry="3" fill="rgba(0,0,0,0.5)" />
      {/* Mochila */}
      <rect x="11" y="18" width="22" height="18" rx="3" fill="#2d3420" />
      {/* Piernas */}
      <path d="M15 36h6l-1 15h-5zM23 36h6l0 15h-5z" fill="#1d211a" />
      {/* Torso / campera */}
      <path d="M13 20c0-4 4-6 9-6s9 2 9 6l1 17H12z" fill="#4b5320" stroke="#0b0d0b" strokeWidth="1.2" />
      {/* Pañuelo */}
      <path d="M16 18h12l-2 4h-8z" fill={color} />
      {/* Capucha y cabeza */}
      <path d="M14 11a8 8 0 0 1 16 0v5H14z" fill="#3b4228" stroke="#0b0d0b" strokeWidth="1.2" />
      <rect x="17" y="9" width="10" height="7" rx="2" fill="#c9a183" />
      <rect x="18" y="11" width="8" height="2" fill="#1a1a1a" opacity="0.7" />
    </svg>
  );
}
