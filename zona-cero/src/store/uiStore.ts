import { create } from 'zustand';

export type Screen = 'map' | 'combat' | 'inventory' | 'shelter' | 'profile' | 'community';

export type ToastTone = 'info' | 'good' | 'warn' | 'bad' | 'loot';

export interface Toast {
  id: number;
  text: string;
  tone: ToastTone;
}

export interface Celebration {
  title: string;
  subtitle: string;
}

interface UiState {
  screen: Screen;
  /** Refugio abierto en la pantalla de refugio (null = el propio o la lista). */
  shelterViewId: string | null;
  toasts: Toast[];
  celebration: Celebration | null;
  go(screen: Screen): void;
  openShelter(id: string | null): void;
  toast(text: string, tone?: ToastTone): void;
  dismissToast(id: number): void;
  celebrate(c: Celebration | null): void;
}

let toastSeq = 1;

export const useUiStore = create<UiState>((set, get) => ({
  screen: 'map',
  shelterViewId: null,
  toasts: [],
  celebration: null,
  go: (screen) => set({ screen }),
  openShelter: (id) => set({ screen: 'shelter', shelterViewId: id }),
  toast: (text, tone = 'info') => {
    const id = toastSeq++;
    // Máximo 4 a la vez para no tapar el mapa.
    set({ toasts: [...get().toasts.slice(-3), { id, text, tone }] });
    setTimeout(() => get().dismissToast(id), tone === 'bad' || tone === 'warn' ? 3800 : 2800);
  },
  dismissToast: (id) => set({ toasts: get().toasts.filter((t) => t.id !== id) }),
  celebrate: (celebration) => set({ celebration }),
}));
