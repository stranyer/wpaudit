-- =============================================================================
-- Zona Cero — esquema inicial (Supabase + PostgreSQL 15+ + PostGIS)
-- =============================================================================
--
-- Modelo de privacidad (ver supabase/README.md):
--   * La ubicación REAL del jugador nunca se guarda en una tabla legible por
--     clientes. Solo llega como argumento de RPC para validar distancias y, como
--     mucho, se conserva la última posición validada en `player_private_state`
--     (RLS activo y SIN políticas: solo la tocan funciones SECURITY DEFINER).
--   * Toda posición pública (refugios, presencia) se vuelve a "engrosar" en el
--     servidor (ajuste a grilla) aunque el cliente ya la haya difuminado.
--
-- Anti-trampas (preparación): distancia con ST_DWithin sobre geography, tope de
-- precisión GPS, control de velocidad contra la última posición validada, un
-- reclamo por spawn y jugador, y vencimiento de spawns.
--
-- Las constantes de juego replican src/config/gameConfig.ts y src/core/shelter.ts.
-- Si se cambian allí, hay que cambiarlas también acá.
--
-- La migración es idempotente en lo razonable (if not exists / create or replace
-- / drop policy if exists), así que puede re-ejecutarse en el editor SQL.
-- =============================================================================

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

-- -----------------------------------------------------------------------------
-- Facciones (datos de referencia: se cargan acá porque otras tablas las referencian)
-- -----------------------------------------------------------------------------

create table if not exists public.factions (
  id                text primary key check (id ~ '^[a-z][a-z0-9_]{1,31}$'),
  name              text not null,
  motto             text not null default '',
  color             text not null default '#888888' check (color ~ '^#[0-9a-fA-F]{6}$'),
  bonus_description text not null default '',
  sort_order        int  not null default 0,
  created_at        timestamptz not null default now()
);

-- Igual que src/core/factions.ts (FACTION_DEFS).
insert into public.factions (id, name, motto, color, bonus_description, sort_order) values
  ('resistencia', 'La Resistencia',  'Recuperamos la ciudad, cuadra por cuadra.', '#c8742c', '+10% de experiencia en combate',     1),
  ('guardia',     'Guardia del Río', 'Lo que se guarda, se sobrevive.',           '#6f8a4a', '+15% de botín en suministros',       2),
  ('nomades',     'Nómades del Sur', 'Quien se queda quieto, se convierte.',      '#7b8c99', '+25% de regeneración de resistencia', 3)
on conflict (id) do update set
  name              = excluded.name,
  motto             = excluded.motto,
  color             = excluded.color,
  bonus_description = excluded.bonus_description,
  sort_order        = excluded.sort_order;

-- -----------------------------------------------------------------------------
-- Perfiles públicos (nombre, nivel, facción). Sin ubicación.
-- -----------------------------------------------------------------------------

create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  name       text not null default 'Superviviente' check (char_length(name) between 1 and 40),
  level      int  not null default 1 check (level between 1 and 1000),
  xp         bigint not null default 0 check (xp >= 0),
  faction_id text references public.factions (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_faction_idx on public.profiles (faction_id);

-- -----------------------------------------------------------------------------
-- Partida guardada (PlayerState completo). Solo el dueño la lee/escribe.
-- MVP: el inventario vive acá y es confiado por el cliente (ver README).
-- -----------------------------------------------------------------------------

create table if not exists public.player_saves (
  player_id  uuid primary key references auth.users (id) on delete cascade,
  save       jsonb not null check (jsonb_typeof(save) = 'object' and octet_length(save::text) <= 262144),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Estado PRIVADO del jugador: última posición validada (para el control de
-- velocidad). RLS activo y SIN políticas: ningún cliente puede leerla.
-- `purge_stale_data()` la borra tras 12 h sin actividad.
-- -----------------------------------------------------------------------------

create table if not exists public.player_private_state (
  player_id          uuid primary key references auth.users (id) on delete cascade,
  last_position      extensions.geography(Point, 4326),
  last_position_at   timestamptz,
  last_accuracy_m    float8,
  speed_locked_until timestamptz,
  updated_at         timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Refugios. Posición PÚBLICA (engrosada por el servidor). Lectura para todos;
-- escritura solo vía RPC. owner_id NULL = refugio comunitario/sistema (seed).
-- -----------------------------------------------------------------------------

create table if not exists public.shelters (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  owner_id   uuid references public.profiles (id) on delete set null,
  owner_name text not null default 'Comunidad' check (char_length(owner_name) between 1 and 40),
  faction_id text references public.factions (id) on delete set null,
  level      int  not null default 1 check (level between 1 and 5),
  position   extensions.geography(Point, 4326) not null,
  progress   jsonb not null default '{}'::jsonb check (jsonb_typeof(progress) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shelters_position_gix on public.shelters using gist (position);
-- Máximo un refugio por dueño (los NULL de sistema no cuentan).
create unique index if not exists shelters_one_per_owner on public.shelters (owner_id) where owner_id is not null;

create table if not exists public.shelter_contributions (
  shelter_id  uuid not null references public.shelters (id) on delete cascade,
  player_id   uuid not null references public.profiles (id) on delete cascade,
  player_name text not null check (char_length(player_name) between 1 and 40),
  amount      int  not null default 0 check (amount >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (shelter_id, player_id)
);

create index if not exists shelter_contributions_player_idx on public.shelter_contributions (player_id);

-- Requisitos para ALCANZAR cada nivel (igual que SHELTER_LEVELS en src/core/shelter.ts).
create table if not exists public.shelter_level_requirements (
  level        int primary key check (level between 2 and 5),
  name         text not null,
  requirements jsonb not null check (jsonb_typeof(requirements) = 'object')
);

insert into public.shelter_level_requirements (level, name, requirements) values
  (2, 'Barricadas',          '{"wood": 20, "metal": 6}'::jsonb),
  (3, 'Taller',              '{"wood": 30, "metal": 25, "food": 10}'::jsonb),
  (4, 'Torre de vigilancia', '{"wood": 40, "metal": 40, "food": 20, "water": 20}'::jsonb),
  (5, 'Fortaleza',           '{"wood": 60, "metal": 80, "food": 30, "water": 30, "medicine": 15, "ammo": 20}'::jsonb)
on conflict (level) do update set
  name         = excluded.name,
  requirements = excluded.requirements;

-- -----------------------------------------------------------------------------
-- Presencia pública APROXIMADA (grilla de ~0.002°). Solo se lee vía RPC
-- `nearby_survivors` (radio acotado, últimos 30 min); la tabla solo expone la
-- fila propia.
-- -----------------------------------------------------------------------------

create table if not exists public.public_presence (
  player_id       uuid primary key references public.profiles (id) on delete cascade,
  name            text not null,
  level           int  not null default 1,
  faction_id      text references public.factions (id) on delete set null,
  approx_position extensions.geography(Point, 4326) not null,
  updated_at      timestamptz not null default now()
);

create index if not exists public_presence_position_gix on public.public_presence using gist (approx_position);
create index if not exists public_presence_updated_idx on public.public_presence (updated_at);

-- -----------------------------------------------------------------------------
-- Reclamos de spawns: un reclamo por (jugador, spawn). Los ids de spawn incluyen
-- la ventana de tiempo (`z:<celda>:<ventana>:<i>`), así que no se repiten.
-- -----------------------------------------------------------------------------

create table if not exists public.spawn_claims (
  player_id  uuid not null references auth.users (id) on delete cascade,
  spawn_id   text not null check (char_length(spawn_id) between 1 and 128),
  claimed_at timestamptz not null default now(),
  primary key (player_id, spawn_id)
);

create index if not exists spawn_claims_claimed_at_idx on public.spawn_claims (claimed_at);

-- -----------------------------------------------------------------------------
-- Zonas de exclusión (seguridad): áreas militares, autopistas, vías, agua,
-- propiedad privada, etc. Se cargan más adelante desde OpenStreetMap. Las
-- líneas (autopistas, vías) deben cargarse ya con buffer como polígonos.
-- kind sugeridos: military | highway | railway | water | private | industrial |
--                 airport | construction | other
-- -----------------------------------------------------------------------------

create table if not exists public.exclusion_zones (
  id         bigint generated always as identity primary key,
  kind       text not null,
  name       text,
  geom       extensions.geography(MultiPolygon, 4326) not null,
  source     text,
  created_at timestamptz not null default now()
);

create index if not exists exclusion_zones_geom_gix on public.exclusion_zones using gist (geom);

-- -----------------------------------------------------------------------------
-- Eventos cooperativos (arquitectura): ataques de hordas a refugios. Los crea y
-- resuelve un cron / edge function (ver README). Lectura para todos.
-- -----------------------------------------------------------------------------

create table if not exists public.shelter_events (
  id          uuid primary key default gen_random_uuid(),
  shelter_id  uuid not null references public.shelters (id) on delete cascade,
  kind        text not null default 'horde_attack' check (kind in ('horde_attack')),
  strength    int  not null check (strength >= 0),
  starts_at   timestamptz not null,
  resolved_at timestamptz,
  outcome     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists shelter_events_shelter_idx on public.shelter_events (shelter_id, starts_at desc);

-- =============================================================================
-- Triggers
-- =============================================================================

create or replace function public.zc_touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Normaliza el nombre del perfil (sin caracteres de control, 1..40) y la fecha.
create or replace function public.zc_profiles_before_write()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.name := left(btrim(regexp_replace(coalesce(new.name, ''), '[[:cntrl:]]', '', 'g')), 40);
  if new.name = '' then
    new.name := 'Superviviente';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_before_write on public.profiles;
create trigger profiles_before_write
  before insert or update on public.profiles
  for each row execute function public.zc_profiles_before_write();

drop trigger if exists player_saves_touch on public.player_saves;
create trigger player_saves_touch
  before insert or update on public.player_saves
  for each row execute function public.zc_touch_updated_at();

drop trigger if exists shelters_touch on public.shelters;
create trigger shelters_touch
  before update on public.shelters
  for each row execute function public.zc_touch_updated_at();

-- =============================================================================
-- Row Level Security + permisos de tabla
-- (Supabase otorga ALL a anon/authenticated por defecto: lo acotamos explícitamente)
-- =============================================================================

alter table public.factions                   enable row level security;
alter table public.profiles                   enable row level security;
alter table public.player_saves               enable row level security;
alter table public.player_private_state       enable row level security;
alter table public.shelters                   enable row level security;
alter table public.shelter_contributions      enable row level security;
alter table public.shelter_level_requirements enable row level security;
alter table public.public_presence            enable row level security;
alter table public.spawn_claims               enable row level security;
alter table public.exclusion_zones            enable row level security;
alter table public.shelter_events             enable row level security;

revoke all on table
  public.factions, public.profiles, public.player_saves, public.player_private_state,
  public.shelters, public.shelter_contributions, public.shelter_level_requirements,
  public.public_presence, public.spawn_claims, public.exclusion_zones, public.shelter_events
from anon, authenticated;

-- Datos públicos de solo lectura.
grant select on table
  public.factions, public.shelters, public.shelter_contributions,
  public.shelter_level_requirements, public.exclusion_zones, public.shelter_events
to anon, authenticated;

drop policy if exists factions_read on public.factions;
create policy factions_read on public.factions
  for select to anon, authenticated using (true);

drop policy if exists shelters_read on public.shelters;
create policy shelters_read on public.shelters
  for select to anon, authenticated using (true);

drop policy if exists shelter_contributions_read on public.shelter_contributions;
create policy shelter_contributions_read on public.shelter_contributions
  for select to anon, authenticated using (true);

drop policy if exists shelter_level_requirements_read on public.shelter_level_requirements;
create policy shelter_level_requirements_read on public.shelter_level_requirements
  for select to anon, authenticated using (true);

drop policy if exists exclusion_zones_read on public.exclusion_zones;
create policy exclusion_zones_read on public.exclusion_zones
  for select to anon, authenticated using (true);

drop policy if exists shelter_events_read on public.shelter_events;
create policy shelter_events_read on public.shelter_events
  for select to anon, authenticated using (true);

-- Perfiles: lectura para usuarios autenticados; alta y edición solo del propio,
-- y solo de columnas seguras (id/created_at/updated_at no son editables).
grant select on table public.profiles to authenticated;
grant insert (id, name, level, xp, faction_id) on table public.profiles to authenticated;
grant update (name, level, xp, faction_id) on table public.profiles to authenticated;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Partidas: solo el dueño.
grant select, insert, update, delete on table public.player_saves to authenticated;

drop policy if exists player_saves_select_own on public.player_saves;
create policy player_saves_select_own on public.player_saves
  for select to authenticated using (player_id = (select auth.uid()));

drop policy if exists player_saves_insert_own on public.player_saves;
create policy player_saves_insert_own on public.player_saves
  for insert to authenticated with check (player_id = (select auth.uid()));

drop policy if exists player_saves_update_own on public.player_saves;
create policy player_saves_update_own on public.player_saves
  for update to authenticated
  using (player_id = (select auth.uid()))
  with check (player_id = (select auth.uid()));

drop policy if exists player_saves_delete_own on public.player_saves;
create policy player_saves_delete_own on public.player_saves
  for delete to authenticated using (player_id = (select auth.uid()));

-- Presencia y reclamos: cada uno ve solo lo propio (lo ajeno, vía RPC).
grant select on table public.public_presence, public.spawn_claims to authenticated;

drop policy if exists public_presence_select_own on public.public_presence;
create policy public_presence_select_own on public.public_presence
  for select to authenticated using (player_id = (select auth.uid()));

drop policy if exists spawn_claims_select_own on public.spawn_claims;
create policy spawn_claims_select_own on public.spawn_claims
  for select to authenticated using (player_id = (select auth.uid()));

-- player_private_state: RLS activo, sin políticas y sin permisos. Intencional.

-- =============================================================================
-- Funciones auxiliares internas (no expuestas a clientes)
-- =============================================================================

create or replace function public.zc_valid_coords(p_lat float8, p_lng float8)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  -- NaN e ±Infinity quedan fuera (NaN es mayor que todo en PostgreSQL).
  select coalesce(p_lat between -90 and 90 and p_lng between -180 and 180, false);
$$;

-- Punto geography (lng, lat). Acota los valores para no fallar nunca: quien llama
-- debe validar antes con zc_valid_coords.
create or replace function public.zc_point(p_lat float8, p_lng float8)
returns extensions.geography
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select st_setsrid(
           st_makepoint(
             greatest(-180::float8, least(180::float8, coalesce(p_lng, 0))),
             greatest(-90::float8,  least(90::float8,  coalesce(p_lat, 0)))),
           4326)::geography;
$$;

-- Engrosa una posición a una grilla de `p_grid_deg` grados (defensa en profundidad:
-- se aplica aunque el cliente ya la haya difuminado).
create or replace function public.zc_coarsen_point(p_lat float8, p_lng float8, p_grid_deg float8)
returns extensions.geography
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select public.zc_point(
    (round((p_lat / p_grid_deg)::numeric) * p_grid_deg::numeric)::float8,
    (round((p_lng / p_grid_deg)::numeric) * p_grid_deg::numeric)::float8);
$$;

create or replace function public.zc_ensure_profile(p_uid uuid)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_profile public.profiles;
begin
  insert into public.profiles (id) values (p_uid) on conflict (id) do nothing;
  select * into v_profile from public.profiles where id = p_uid;
  return v_profile;
end;
$$;

-- Aportes de un refugio como arreglo jsonb ordenado de mayor a menor.
create or replace function public.zc_shelter_contributions(p_shelter_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('player_id', c.player_id, 'player_name', c.player_name, 'amount', c.amount)
      order by c.amount desc, c.created_at asc),
    '[]'::jsonb)
  from public.shelter_contributions c
  where c.shelter_id = p_shelter_id;
$$;

-- Refugio como jsonb (mismas claves que las filas de nearby_shelters). NULL si no existe.
create or replace function public.zc_shelter_json(p_shelter_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'id',            s.id,
    'name',          s.name,
    'owner_id',      s.owner_id,
    'owner_name',    s.owner_name,
    'faction_id',    s.faction_id,
    'level',         s.level,
    'lat',           st_y(s.position::geometry),
    'lng',           st_x(s.position::geometry),
    'progress',      s.progress,
    'contributions', public.zc_shelter_contributions(s.id),
    'created_at',    s.created_at)
  from public.shelters s
  where s.id = p_shelter_id;
$$;

-- =============================================================================
-- Seguridad de ubicaciones
-- =============================================================================

-- true si el punto es válido y no cae (ni a menos de p_buffer_m metros) dentro
-- de una zona de exclusión.
create or replace function public.is_public_safe_point(p_lat float8, p_lng float8, p_buffer_m float8 default 0)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if not public.zc_valid_coords(p_lat, p_lng) then
    return false;
  end if;
  return not exists (
    select 1
    from public.exclusion_zones z
    where st_dwithin(z.geom, public.zc_point(p_lat, p_lng), greatest(coalesce(p_buffer_m, 0), 0))
  );
end;
$$;

-- =============================================================================
-- RPC: validación de interacciones (anti-trampas)
-- =============================================================================

-- Firma previa (sin p_action), por si se aplicó un borrador anterior.
drop function if exists public.validate_interaction(text, float8, float8, float8, float8, float8, timestamptz);

create or replace function public.validate_interaction(
  p_spawn_id   text,
  p_target_lat float8,
  p_target_lng float8,
  p_lat        float8,
  p_lng        float8,
  p_accuracy   float8,
  p_expires_at timestamptz default null,
  p_action     text default 'scavenge'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  -- Igual que src/config/gameConfig.ts
  c_radius_m           constant float8   := 40;   -- interactionRadiusM
  c_accuracy_bonus_m   constant float8   := 15;   -- maxAccuracyBonusM
  c_max_accuracy_m     constant float8   := 80;   -- maxAccuracyForInteractionM
  c_max_speed_mps      constant float8   := 12;   -- maxInteractionSpeedMps
  c_speed_lock         constant interval := interval '30 seconds'; -- speedLockMs
  c_min_speed_dt_s     constant float8   := 2;    -- intervalo mínimo para medir velocidad
  c_zombie_window_ms   constant bigint   := 600000;   -- zombieWindowMs
  c_supply_window_ms   constant bigint   := 1800000;  -- supplyWindowMs
  c_expiry_grace       constant interval := interval '60 seconds'; -- desfase de relojes
  v_uid          uuid := auth.uid();
  v_now          timestamptz := now();
  v_action       text := lower(coalesce(p_action, 'scavenge'));
  v_player       extensions.geography;
  v_target       extensions.geography;
  v_distance     float8;
  v_accuracy_ok  boolean;
  v_match        text[];
  v_window       bigint;
  v_window_ms    bigint;
  v_window_start timestamptz;
  v_expires      timestamptz;
  v_shelter_pos  extensions.geography;
  v_state        public.player_private_state;
  v_dt           float8;
  v_moved        float8;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_action not in ('scavenge', 'encounter', 'shelter') then
    raise exception 'invalid_action';
  end if;
  if p_spawn_id is null or char_length(p_spawn_id) not between 1 and 128 then
    raise exception 'invalid_spawn_id';
  end if;

  if not public.zc_valid_coords(p_lat, p_lng) or not public.zc_valid_coords(p_target_lat, p_target_lng) then
    return jsonb_build_object('ok', false, 'reason', 'out_of_range', 'distance_m', null);
  end if;

  v_player := public.zc_point(p_lat, p_lng);
  v_target := public.zc_point(p_target_lat, p_target_lng);

  -- Para refugios reales usamos la posición guardada, no la que manda el cliente.
  if v_action = 'shelter'
     and p_spawn_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select s.position into v_shelter_pos from public.shelters s where s.id = p_spawn_id::uuid;
    if v_shelter_pos is not null then
      v_target := v_shelter_pos;
    end if;
  end if;

  -- Distancia sobre esfera (igual que haversineM del cliente).
  v_distance := st_distance(v_player, v_target, false);
  v_accuracy_ok := p_accuracy is not null and p_accuracy >= 0 and p_accuracy <= c_max_accuracy_m;

  -- 1. Agotado (solo 'scavenge' reclama el punto).
  if v_action = 'scavenge' and exists (
       select 1 from public.spawn_claims sc where sc.player_id = v_uid and sc.spawn_id = p_spawn_id) then
    return jsonb_build_object('ok', false, 'reason', 'depleted', 'distance_m', round(v_distance::numeric, 1));
  end if;

  -- 2. Vencido. Si el id sigue el formato de src/core/spawns.ts
  --    (`z|s:<cx>_<cy>:<ventana>:<i>`), la ventana la calcula el servidor y no
  --    depende del reloj del cliente.
  v_match := regexp_match(p_spawn_id, '^([zs]):-?[0-9]+_-?[0-9]+:([0-9]{1,9}):[0-9]{1,6}$');
  if v_match is not null then
    v_window := v_match[2]::bigint;
    v_window_ms := case v_match[1] when 'z' then c_zombie_window_ms else c_supply_window_ms end;
    v_window_start := to_timestamp((v_window::numeric * v_window_ms / 1000)::float8);
    v_expires := least(p_expires_at, to_timestamp(((v_window + 1)::numeric * v_window_ms / 1000)::float8));
  else
    v_expires := p_expires_at;
  end if;
  if (v_expires is not null and v_now >= v_expires + c_expiry_grace)
     or (v_window_start is not null and v_window_start > v_now + c_expiry_grace) then
    return jsonb_build_object('ok', false, 'reason', 'expired', 'distance_m', round(v_distance::numeric, 1));
  end if;

  -- 3. Velocidad contra la última posición validada (privada).
  select * into v_state from public.player_private_state ps where ps.player_id = v_uid for update;
  if found then
    if v_state.speed_locked_until is not null and v_state.speed_locked_until > v_now then
      return jsonb_build_object('ok', false, 'reason', 'too_fast', 'distance_m', round(v_distance::numeric, 1));
    end if;
    if v_accuracy_ok and v_state.last_position is not null and v_state.last_position_at is not null then
      -- Intervalo mínimo de 2 s (no se saltea: evita teletransportes en ráfaga).
      v_dt := greatest(extract(epoch from (v_now - v_state.last_position_at))::float8, c_min_speed_dt_s);
      -- Se descuenta la imprecisión de ambas muestras para no castigar el ruido del GPS.
      v_moved := greatest(
        st_distance(v_state.last_position, v_player, false) - p_accuracy - coalesce(v_state.last_accuracy_m, 0),
        0);
      if v_moved / v_dt > c_max_speed_mps then
        update public.player_private_state
           set last_position      = v_player,
               last_position_at   = v_now,
               last_accuracy_m    = p_accuracy,
               speed_locked_until = v_now + c_speed_lock,
               updated_at         = v_now
         where player_id = v_uid;
        return jsonb_build_object('ok', false, 'reason', 'too_fast', 'distance_m', round(v_distance::numeric, 1));
      end if;
    end if;
  end if;

  -- 4. Precisión GPS.
  if not v_accuracy_ok then
    return jsonb_build_object('ok', false, 'reason', 'low_accuracy', 'distance_m', round(v_distance::numeric, 1));
  end if;

  -- 5. Alcance: radio + tolerancia por precisión (con tope).
  if not st_dwithin(v_player, v_target, c_radius_m + least(p_accuracy, c_accuracy_bonus_m), false) then
    return jsonb_build_object('ok', false, 'reason', 'out_of_range', 'distance_m', round(v_distance::numeric, 1));
  end if;

  -- 6. Reclamo (único por jugador y spawn; la PK resuelve carreras).
  if v_action = 'scavenge' then
    insert into public.spawn_claims (player_id, spawn_id, claimed_at)
    values (v_uid, p_spawn_id, v_now)
    on conflict (player_id, spawn_id) do nothing;
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'depleted', 'distance_m', round(v_distance::numeric, 1));
    end if;
  end if;

  -- 7. Guarda la última posición validada (privada).
  insert into public.player_private_state as ps
    (player_id, last_position, last_position_at, last_accuracy_m, speed_locked_until, updated_at)
  values (v_uid, v_player, v_now, p_accuracy, null, v_now)
  on conflict (player_id) do update set
    last_position      = excluded.last_position,
    last_position_at   = excluded.last_position_at,
    last_accuracy_m    = excluded.last_accuracy_m,
    speed_locked_until = null,
    updated_at         = excluded.updated_at;

  return jsonb_build_object('ok', true, 'reason', null, 'distance_m', round(v_distance::numeric, 1));
end;
$$;

-- =============================================================================
-- RPC: refugios
-- =============================================================================

create or replace function public.create_shelter(p_name text, p_lat float8, p_lng float8)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_grid_deg constant float8 := 0.001; -- ~110 m N-S x ~90 m E-O en Buenos Aires
  v_uid      uuid := auth.uid();
  v_name     text := left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', '', 'g')), 40);
  v_profile  public.profiles;
  v_existing uuid;
  v_pos      extensions.geography;
  v_id       uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) < 2 then
    raise exception 'invalid_name';
  end if;
  if not public.zc_valid_coords(p_lat, p_lng) then
    raise exception 'invalid_position';
  end if;

  select * into v_profile from public.zc_ensure_profile(v_uid);

  -- Uno por dueño: si ya tiene, se devuelve el existente (igual que LocalRepository).
  select s.id into v_existing from public.shelters s where s.owner_id = v_uid;
  if v_existing is not null then
    return public.zc_shelter_json(v_existing);
  end if;

  -- El servidor engrosa la posición aunque el cliente ya la haya ajustado.
  v_pos := public.zc_coarsen_point(p_lat, p_lng, c_grid_deg);
  if not public.is_public_safe_point(st_y(v_pos::geometry), st_x(v_pos::geometry)) then
    raise exception 'unsafe_location'
      using detail = 'La posición cae dentro de una zona de exclusión (no es un lugar público seguro).';
  end if;

  begin
    insert into public.shelters (name, owner_id, owner_name, faction_id, level, position, progress)
    values (v_name, v_uid, v_profile.name, v_profile.faction_id, 1, v_pos, '{}'::jsonb)
    returning id into v_id;
  exception when unique_violation then
    -- Carrera con otra llamada del mismo jugador.
    select s.id into v_id from public.shelters s where s.owner_id = v_uid;
  end;

  return public.zc_shelter_json(v_id);
end;
$$;

create or replace function public.get_shelter(p_shelter_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select public.zc_shelter_json(p_shelter_id);
$$;

-- Replica applyDonation (src/core/shelter.ts): solo se acepta lo que el próximo
-- nivel todavía necesita (el excedente se rechaza) y sube de nivel solo al
-- completar todos los requisitos.
create or replace function public.donate_to_shelter(
  p_shelter_id uuid,
  p_resources  jsonb,
  p_lat        float8,
  p_lng        float8,
  p_accuracy   float8
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_radius_m         constant float8 := 40;
  c_accuracy_bonus_m constant float8 := 15;
  c_max_accuracy_m   constant float8 := 80;
  c_max_level        constant int    := 5;
  c_resources        constant text[] := array['food', 'water', 'medicine', 'wood', 'metal', 'ammo'];
  v_uid       uuid := auth.uid();
  v_profile   public.profiles;
  v_shelter   public.shelters;
  v_player    extensions.geography;
  v_distance  float8;
  v_req       jsonb;
  v_progress  jsonb;
  v_accepted  jsonb := '{}'::jsonb;
  v_total     int := 0;
  v_key       text;
  v_val       jsonb;
  v_amount    numeric;
  v_remaining numeric;
  v_take      int;
  v_complete  boolean := false;
  v_new_level int;
  v_leveled   boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Bloquea la fila: donaciones simultáneas se aplican en serie.
  select * into v_shelter from public.shelters s where s.id = p_shelter_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found', 'accepted', '{}'::jsonb,
                              'leveled_up', false, 'shelter', null);
  end if;

  -- Alcance (una precisión inválida o peor que el tope cuenta como fuera de alcance).
  if not public.zc_valid_coords(p_lat, p_lng)
     or p_accuracy is null or not (p_accuracy >= 0 and p_accuracy <= c_max_accuracy_m) then
    return jsonb_build_object('ok', false, 'reason', 'out_of_range', 'accepted', '{}'::jsonb,
                              'leveled_up', false, 'shelter', null);
  end if;
  v_player := public.zc_point(p_lat, p_lng);
  v_distance := st_distance(v_player, v_shelter.position, false);
  if not st_dwithin(v_player, v_shelter.position, c_radius_m + least(p_accuracy, c_accuracy_bonus_m), false) then
    return jsonb_build_object('ok', false, 'reason', 'out_of_range', 'accepted', '{}'::jsonb,
                              'leveled_up', false, 'shelter', null,
                              'distance_m', round(v_distance::numeric, 1));
  end if;

  -- Requisitos del próximo nivel ({} si ya está al máximo).
  v_req := '{}'::jsonb;
  if v_shelter.level < c_max_level then
    select r.requirements into v_req
    from public.shelter_level_requirements r
    where r.level = v_shelter.level + 1;
    v_req := coalesce(v_req, '{}'::jsonb);
  end if;

  v_progress := coalesce(v_shelter.progress, '{}'::jsonb);
  v_new_level := v_shelter.level;

  if p_resources is not null and jsonb_typeof(p_resources) = 'object' then
    for v_key, v_val in select e.key, e.value from jsonb_each(p_resources) e loop
      continue when not (v_key = any (c_resources)) or jsonb_typeof(v_val) <> 'number';
      v_amount := floor((v_val #>> '{}')::numeric);
      continue when v_amount <= 0 or not (v_req ? v_key);
      v_remaining := (v_req ->> v_key)::numeric - coalesce((v_progress ->> v_key)::numeric, 0);
      continue when v_remaining <= 0;
      v_take := least(v_amount, v_remaining)::int;
      v_accepted := v_accepted || jsonb_build_object(v_key, v_take);
      v_progress := v_progress || jsonb_build_object(v_key, coalesce((v_progress ->> v_key)::numeric, 0)::int + v_take);
      v_total := v_total + v_take;
    end loop;
  end if;

  -- Nada aceptado (vacío, inválido, o el refugio no necesita eso): igual que LocalRepository.
  if v_total = 0 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_amount', 'accepted', '{}'::jsonb,
                              'leveled_up', false, 'shelter', public.zc_shelter_json(v_shelter.id),
                              'distance_m', round(v_distance::numeric, 1));
  end if;

  select * into v_profile from public.zc_ensure_profile(v_uid);

  insert into public.shelter_contributions as c (shelter_id, player_id, player_name, amount)
  values (v_shelter.id, v_uid, v_profile.name, v_total)
  on conflict (shelter_id, player_id) do update set
    amount      = c.amount + excluded.amount,
    player_name = excluded.player_name,
    updated_at  = now();

  select coalesce(bool_and(coalesce((v_progress ->> r.key)::numeric, 0) >= (r.value #>> '{}')::numeric), false)
    into v_complete
  from jsonb_each(v_req) r;

  if v_complete and v_shelter.level < c_max_level then
    v_new_level := v_shelter.level + 1;
    v_progress := '{}'::jsonb;
    v_leveled := true;
  end if;

  update public.shelters
     set level = v_new_level,
         progress = v_progress
   where id = v_shelter.id;

  return jsonb_build_object(
    'ok',         true,
    'reason',     null,
    'accepted',   v_accepted,
    'leveled_up', v_leveled,
    'shelter',    public.zc_shelter_json(v_shelter.id),
    'distance_m', round(v_distance::numeric, 1));
end;
$$;

create or replace function public.nearby_shelters(p_lat float8, p_lng float8, p_radius_m float8 default 2000)
returns table (
  id            uuid,
  name          text,
  owner_id      uuid,
  owner_name    text,
  faction_id    text,
  level         int,
  lat           float8,
  lng           float8,
  progress      jsonb,
  contributions jsonb,
  created_at    timestamptz,
  distance_m    float8
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select s.id,
         s.name,
         s.owner_id,
         s.owner_name,
         s.faction_id,
         s.level,
         st_y(s.position::geometry) as lat,
         st_x(s.position::geometry) as lng,
         s.progress,
         public.zc_shelter_contributions(s.id) as contributions,
         s.created_at,
         st_distance(s.position, public.zc_point(p_lat, p_lng), false) as distance_m
  from public.shelters s
  where public.zc_valid_coords(p_lat, p_lng)
    and st_dwithin(s.position, public.zc_point(p_lat, p_lng),
                   least(greatest(coalesce(p_radius_m, 0), 0), 20000))
  order by 12
  limit 200;
$$;

-- =============================================================================
-- RPC: presencia y supervivientes cercanos
-- =============================================================================

create or replace function public.publish_presence(p_lat float8, p_lng float8)
returns void
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_grid_deg constant float8 := 0.002; -- ~220 m N-S x ~180 m E-O en Buenos Aires
  v_uid     uuid := auth.uid();
  v_profile public.profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.zc_valid_coords(p_lat, p_lng) then
    raise exception 'invalid_position';
  end if;

  select * into v_profile from public.zc_ensure_profile(v_uid);

  insert into public.public_presence as pp (player_id, name, level, faction_id, approx_position, updated_at)
  values (v_uid, v_profile.name, v_profile.level, v_profile.faction_id,
          public.zc_coarsen_point(p_lat, p_lng, c_grid_deg), now())
  on conflict (player_id) do update set
    name            = excluded.name,
    level           = excluded.level,
    faction_id      = excluded.faction_id,
    approx_position = excluded.approx_position,
    updated_at      = excluded.updated_at
  where pp.updated_at < now() - interval '5 seconds'; -- limita la frecuencia de escritura
end;
$$;

create or replace function public.nearby_survivors(p_lat float8, p_lng float8, p_radius_m float8 default 1500)
returns table (
  player_id    uuid,
  name         text,
  level        int,
  faction_id   text,
  lat          float8,
  lng          float8,
  last_seen_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select pp.player_id,
         pp.name,
         pp.level,
         pp.faction_id,
         st_y(pp.approx_position::geometry) as lat,
         st_x(pp.approx_position::geometry) as lng,
         pp.updated_at as last_seen_at
  from public.public_presence pp
  where public.zc_valid_coords(p_lat, p_lng)
    and pp.updated_at > now() - interval '30 minutes'
    and pp.player_id is distinct from auth.uid()
    and st_dwithin(pp.approx_position, public.zc_point(p_lat, p_lng),
                   least(greatest(coalesce(p_radius_m, 0), 0), 5000))
  order by pp.updated_at desc
  limit 100;
$$;

-- =============================================================================
-- RPC: facciones y ranking
-- =============================================================================

create or replace function public.join_faction(p_faction_id text)
returns void
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_faction_id is null or not exists (select 1 from public.factions f where f.id = p_faction_id) then
    raise exception 'invalid_faction';
  end if;

  perform public.zc_ensure_profile(v_uid);
  update public.profiles set faction_id = p_faction_id where id = v_uid;
  update public.public_presence set faction_id = p_faction_id where player_id = v_uid;
  -- El refugio propio representa a la facción de su dueño.
  update public.shelters set faction_id = p_faction_id where owner_id = v_uid;
end;
$$;

create or replace function public.factions_overview()
returns table (
  id                 text,
  name               text,
  motto              text,
  color              text,
  bonus_description  text,
  members            bigint,
  total_contribution bigint
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select f.id,
         f.name,
         f.motto,
         f.color,
         f.bonus_description,
         (select count(*) from public.profiles p where p.faction_id = f.id) as members,
         (select coalesce(sum(c.amount), 0)::bigint
            from public.shelter_contributions c
            join public.profiles p on p.id = c.player_id
           where p.faction_id = f.id) as total_contribution
  from public.factions f
  order by f.sort_order, f.id;
$$;

create or replace function public.leaderboard(p_limit int default 20)
returns table (
  player_id    uuid,
  player_name  text,
  faction_id   text,
  level        int,
  contribution bigint
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with totals as (
    select c.player_id, sum(c.amount)::bigint as contribution, max(c.player_name) as last_name
    from public.shelter_contributions c
    group by c.player_id
  )
  select t.player_id,
         coalesce(p.name, t.last_name) as player_name,
         p.faction_id,
         coalesce(p.level, 1) as level,
         t.contribution
  from totals t
  left join public.profiles p on p.id = t.player_id
  where t.contribution > 0
  order by t.contribution desc, t.player_id
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

-- =============================================================================
-- Mantenimiento (programar con pg_cron; ver README). No expuesta a clientes.
-- =============================================================================

create or replace function public.purge_stale_data()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_claims   int;
  v_presence int;
  v_private  int;
begin
  -- Los spawns duran como mucho 30 min: los reclamos viejos ya no sirven.
  delete from public.spawn_claims where claimed_at < now() - interval '2 days';
  get diagnostics v_claims = row_count;
  delete from public.public_presence where updated_at < now() - interval '1 day';
  get diagnostics v_presence = row_count;
  -- Retención mínima de la última posición real validada.
  delete from public.player_private_state
   where coalesce(last_position_at, updated_at) < now() - interval '12 hours';
  get diagnostics v_private = row_count;
  return jsonb_build_object('spawn_claims', v_claims, 'public_presence', v_presence,
                            'player_private_state', v_private);
end;
$$;

-- =============================================================================
-- Permisos de ejecución
-- (PostgreSQL da EXECUTE a PUBLIC y Supabase además a anon/authenticated)
-- =============================================================================

-- Internas: nadie desde el cliente.
revoke all on function public.zc_touch_updated_at()                       from public, anon, authenticated;
revoke all on function public.zc_profiles_before_write()                  from public, anon, authenticated;
revoke all on function public.zc_valid_coords(float8, float8)             from public, anon, authenticated;
revoke all on function public.zc_point(float8, float8)                    from public, anon, authenticated;
revoke all on function public.zc_coarsen_point(float8, float8, float8)    from public, anon, authenticated;
revoke all on function public.zc_ensure_profile(uuid)                     from public, anon, authenticated;
revoke all on function public.zc_shelter_contributions(uuid)              from public, anon, authenticated;
revoke all on function public.zc_shelter_json(uuid)                       from public, anon, authenticated;
revoke all on function public.purge_stale_data()                          from public, anon, authenticated;

-- RPC del juego: solo usuarios autenticados (incluye sesiones anónimas de Supabase).
revoke all on function public.is_public_safe_point(float8, float8, float8) from public, anon;
revoke all on function public.validate_interaction(text, float8, float8, float8, float8, float8, timestamptz, text) from public, anon;
revoke all on function public.create_shelter(text, float8, float8)         from public, anon;
revoke all on function public.get_shelter(uuid)                            from public, anon;
revoke all on function public.donate_to_shelter(uuid, jsonb, float8, float8, float8) from public, anon;
revoke all on function public.nearby_shelters(float8, float8, float8)      from public, anon;
revoke all on function public.publish_presence(float8, float8)             from public, anon;
revoke all on function public.nearby_survivors(float8, float8, float8)     from public, anon;
revoke all on function public.join_faction(text)                           from public, anon;
revoke all on function public.factions_overview()                          from public, anon;
revoke all on function public.leaderboard(int)                             from public, anon;

grant execute on function public.is_public_safe_point(float8, float8, float8) to authenticated;
grant execute on function public.validate_interaction(text, float8, float8, float8, float8, float8, timestamptz, text) to authenticated;
grant execute on function public.create_shelter(text, float8, float8)         to authenticated;
grant execute on function public.get_shelter(uuid)                            to authenticated;
grant execute on function public.donate_to_shelter(uuid, jsonb, float8, float8, float8) to authenticated;
grant execute on function public.nearby_shelters(float8, float8, float8)      to authenticated;
grant execute on function public.publish_presence(float8, float8)             to authenticated;
grant execute on function public.nearby_survivors(float8, float8, float8)     to authenticated;
grant execute on function public.join_faction(text)                           to authenticated;
grant execute on function public.factions_overview()                          to authenticated;
grant execute on function public.leaderboard(int)                             to authenticated;
