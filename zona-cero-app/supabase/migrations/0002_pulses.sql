-- =============================================================================
-- Zona Cero — pulsos de la red (versión Flutter)
-- =============================================================================
--
-- Requiere 0001_init.sql. Igual que esa migración, es idempotente en lo
-- razonable (if not exists / create or replace / drop policy if exists).
--
-- Un pulso es el "me gusta" de la red: un jugador se lo manda a un nodo
-- (refugio) AJENO. No lleva ubicación ni exige estar cerca (igual que
-- LocalRepository), así que no toca el modelo de privacidad.
--
--   * `shelter_pulses` es un registro de envíos (shelter_id, player_id, count,
--     created_at). Cada cliente ve solo sus propias filas (RLS); los totales por
--     nodo salen de la RPC `shelter_pulse_totals` y `send_pulse` devuelve el
--     total actualizado del nodo.
--   * Límites de frecuencia en el servidor (anti-spam), por jugador:
--       - de 1 a 10 pulsos por llamada (fuera de rango: `invalid_count`),
--       - como mucho una llamada por segundo (`rate_limited`),
--       - como mucho 30 pulsos por hora al mismo nodo y 300 por hora en total.
--         Se acepta hasta el tope; si no queda cupo: `rate_limited`.
--   * No se puede pulsar el nodo propio (`own_shelter`) ni uno inexistente
--     (`shelter_not_found`).
--   * `compact_shelter_pulses()` (mantenimiento, no expuesta) junta las filas de
--     más de 2 días en una por (nodo, jugador): los totales no cambian y la
--     tabla no crece sin límite. Programarla con pg_cron (ver README).
-- =============================================================================

create table if not exists public.shelter_pulses (
  id         bigint generated always as identity primary key,
  shelter_id uuid not null references public.shelters (id) on delete cascade,
  player_id  uuid not null references public.profiles (id) on delete cascade,
  count      int  not null check (count > 0),
  created_at timestamptz not null default now()
);

-- Totales por nodo (index-only scan con `include`) y ventana de frecuencia por jugador.
create index if not exists shelter_pulses_shelter_idx on public.shelter_pulses (shelter_id) include (count);
create index if not exists shelter_pulses_player_idx on public.shelter_pulses (player_id, created_at desc);

-- =============================================================================
-- Row Level Security + permisos de tabla
-- =============================================================================

alter table public.shelter_pulses enable row level security;

revoke all on table public.shelter_pulses from anon, authenticated;

-- Cada uno ve solo sus envíos; los totales ajenos, vía RPC. Escritura: solo RPC.
grant select on table public.shelter_pulses to authenticated;

drop policy if exists shelter_pulses_select_own on public.shelter_pulses;
create policy shelter_pulses_select_own on public.shelter_pulses
  for select to authenticated using (player_id = (select auth.uid()));

-- =============================================================================
-- RPC: pulsos
-- =============================================================================

create or replace function public.send_pulse(p_shelter_id uuid, p_count int default 1)
returns bigint
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_max_per_call      constant int      := 10;
  c_min_interval      constant interval := interval '1 second';
  c_window            constant interval := interval '1 hour';
  c_max_per_shelter_w constant int      := 30;   -- por jugador y nodo, en la ventana
  c_max_per_player_w  constant int      := 300;  -- por jugador (todos los nodos), en la ventana
  v_uid       uuid := auth.uid();
  v_now       timestamptz := now();
  v_owner     uuid;
  v_last_at   timestamptz;
  v_sent_node bigint;
  v_sent_all  bigint;
  v_take      int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_count is null or p_count not between 1 and c_max_per_call then
    raise exception 'invalid_count';
  end if;

  select s.owner_id into v_owner from public.shelters s where s.id = p_shelter_id;
  if not found then
    raise exception 'shelter_not_found';
  end if;
  if v_owner = v_uid then
    raise exception 'own_shelter';
  end if;

  -- La fila del perfil hace de candado: los envíos del mismo jugador se aplican
  -- en serie y el control de frecuencia no se saltea con llamadas simultáneas.
  perform public.zc_ensure_profile(v_uid);
  perform 1 from public.profiles p where p.id = v_uid for update;

  select max(sp.created_at),
         coalesce(sum(sp.count) filter (where sp.shelter_id = p_shelter_id), 0),
         coalesce(sum(sp.count), 0)
    into v_last_at, v_sent_node, v_sent_all
  from public.shelter_pulses sp
  where sp.player_id = v_uid
    and sp.created_at > v_now - c_window;

  if v_last_at is not null and v_last_at > v_now - c_min_interval then
    raise exception 'rate_limited';
  end if;

  v_take := least(p_count::bigint, c_max_per_shelter_w - v_sent_node, c_max_per_player_w - v_sent_all)::int;
  if v_take <= 0 then
    raise exception 'rate_limited';
  end if;

  insert into public.shelter_pulses (shelter_id, player_id, count, created_at)
  values (p_shelter_id, v_uid, v_take, v_now);

  return (
    select coalesce(sum(sp.count), 0)::bigint
    from public.shelter_pulses sp
    where sp.shelter_id = p_shelter_id
  );
end;
$$;

-- Totales de varios nodos de una vez (máx. 200 ids; los inexistentes se omiten).
create or replace function public.shelter_pulse_totals(p_shelter_ids uuid[])
returns table (
  shelter_id uuid,
  total      bigint
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select s.id as shelter_id,
         coalesce((select sum(sp.count) from public.shelter_pulses sp where sp.shelter_id = s.id), 0)::bigint as total
  from (
    select distinct u.id
    from unnest(coalesce(p_shelter_ids, '{}'::uuid[])) as u (id)
    where u.id is not null
    limit 200
  ) ids
  join public.shelters s on s.id = ids.id;
$$;

-- =============================================================================
-- Mantenimiento (programar con pg_cron; ver README). No expuesta a clientes.
-- =============================================================================

create or replace function public.compact_shelter_pulses()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_cutoff  timestamptz := now() - interval '2 days';
  v_removed int;
  v_merged  int;
begin
  -- Solo los pares (nodo, jugador) con 2 o más filas viejas: la ventana de
  -- frecuencia (1 h) nunca mira tan atrás, así que no cambia nada para los límites.
  with old as (
    delete from public.shelter_pulses sp
     where sp.created_at < v_cutoff
       and (sp.shelter_id, sp.player_id) in (
         select o.shelter_id, o.player_id
         from public.shelter_pulses o
         where o.created_at < v_cutoff
         group by o.shelter_id, o.player_id
         having count(*) > 1)
    returning sp.shelter_id, sp.player_id, sp.count, sp.created_at
  ), merged as (
    insert into public.shelter_pulses (shelter_id, player_id, count, created_at)
    select o.shelter_id, o.player_id, sum(o.count)::int, min(o.created_at)
    from old o
    group by o.shelter_id, o.player_id
    returning 1
  )
  select (select count(*) from old), (select count(*) from merged)
    into v_removed, v_merged;

  return jsonb_build_object('removed', v_removed, 'merged', v_merged);
end;
$$;

-- =============================================================================
-- Permisos de ejecución
-- (PostgreSQL da EXECUTE a PUBLIC y Supabase además a anon/authenticated)
-- =============================================================================

revoke all on function public.compact_shelter_pulses()            from public, anon, authenticated;

revoke all on function public.send_pulse(uuid, int)               from public, anon;
revoke all on function public.shelter_pulse_totals(uuid[])        from public, anon;

grant execute on function public.send_pulse(uuid, int)            to authenticated;
grant execute on function public.shelter_pulse_totals(uuid[])     to authenticated;
