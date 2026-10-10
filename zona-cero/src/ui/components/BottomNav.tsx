import { Backpack, Map as MapIcon, Tent, User, Users } from 'lucide-react';
import { useUiStore, type Screen } from '../../store/uiStore';

const ITEMS: { screen: Screen; label: string; Icon: typeof MapIcon }[] = [
  { screen: 'map', label: 'Mapa', Icon: MapIcon },
  { screen: 'inventory', label: 'Mochila', Icon: Backpack },
  { screen: 'shelter', label: 'Refugio', Icon: Tent },
  { screen: 'community', label: 'Comunidad', Icon: Users },
  { screen: 'profile', label: 'Perfil', Icon: User },
];

export function BottomNav() {
  const screen = useUiStore((s) => s.screen);
  const go = useUiStore((s) => s.go);
  const openShelter = useUiStore((s) => s.openShelter);
  return (
    <nav className="bottom-nav" aria-label="Navegación principal">
      {ITEMS.map(({ screen: target, label, Icon }) => (
        <button
          key={target}
          className={`nav-item ${screen === target ? 'active' : ''}`}
          onClick={() => (target === 'shelter' ? openShelter(null) : go(target))}
        >
          <Icon size={22} strokeWidth={screen === target ? 2.4 : 1.8} />
          {label}
        </button>
      ))}
    </nav>
  );
}
