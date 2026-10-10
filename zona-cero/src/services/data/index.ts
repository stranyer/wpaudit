import type { GameRepository } from './GameRepository';
import { LocalRepository } from './LocalRepository';

let instance: GameRepository | null = null;

/**
 * Devuelve el repositorio de datos. Si hay credenciales de Supabase usa el backend
 * real (cargado de forma diferida para no sumar peso al bundle inicial); si no,
 * o si falla la conexión, usa el repositorio local con datos simulados.
 */
export async function getRepository(): Promise<GameRepository> {
  if (instance) return instance;
  const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
  if (url && key) {
    try {
      const { SupabaseRepository } = await import('./SupabaseRepository');
      const repo = new SupabaseRepository(url, key);
      await repo.init();
      instance = repo;
      return instance;
    } catch (err) {
      console.warn('[Zona Cero] Supabase no disponible, usando datos locales.', err);
    }
  }
  const local = new LocalRepository();
  await local.init();
  instance = local;
  return instance;
}

/** Acceso síncrono una vez inicializado (lanza si se usa antes de tiempo). */
export function repository(): GameRepository {
  if (!instance) throw new Error('Repositorio no inicializado');
  return instance;
}

export type { GameRepository } from './GameRepository';
