-- =============================================================================
-- Zona Cero — datos de demostración (refugios comunitarios)
-- =============================================================================
-- Ejecutar DESPUÉS de supabase/migrations/0001_init.sql (editor SQL del
-- Dashboard, `supabase db reset` en local, o `supabase db push --include-seed`).
--
-- Notas:
--   * Las facciones y los requisitos por nivel ya los carga la migración.
--   * Todo refugio necesita dueño, pero estos son "de la comunidad": no hay un
--     usuario real detrás, así que van con owner_id NULL (la columna es nullable
--     justamente para refugios de sistema) y owner_name 'Comunidad'. La regla de
--     "un refugio por dueño" (índice único parcial) ignora los NULL.
--   * Solo lugares PÚBLICOS (plazas y parques de Buenos Aires). Por ser públicos
--     se insertan con su posición exacta, sin engrosar: el ajuste a grilla de
--     `create_shelter` existe para proteger la ubicación de jugadores, y acá
--     moverlos podría sacarlos de la plaza.
--   * Idempotente: ids fijos + `on conflict do nothing` (no pisa progreso real).
-- =============================================================================

insert into public.shelters (id, name, owner_id, owner_name, faction_id, level, position, progress, created_at)
values
  ('5e1e7000-0000-4000-8000-000000000001', 'Plaza de Mayo', null, 'Comunidad', 'resistencia', 3,
   extensions.st_setsrid(extensions.st_makepoint(-58.3712, -34.6083), 4326)::extensions.geography,
   '{"wood": 18, "metal": 12, "food": 6}'::jsonb, '2026-09-01T12:00:00Z'),

  ('5e1e7000-0000-4000-8000-000000000002', 'Parque Centenario', null, 'Comunidad', 'guardia', 2,
   extensions.st_setsrid(extensions.st_makepoint(-58.4355, -34.6063), 4326)::extensions.geography,
   '{"wood": 22, "metal": 9}'::jsonb, '2026-09-03T15:30:00Z'),

  ('5e1e7000-0000-4000-8000-000000000003', 'Plaza Serrano', null, 'Comunidad', 'nomades', 1,
   extensions.st_setsrid(extensions.st_makepoint(-58.4302, -34.5886), 4326)::extensions.geography,
   '{"wood": 12, "metal": 2}'::jsonb, '2026-09-05T20:15:00Z'),

  ('5e1e7000-0000-4000-8000-000000000004', 'Parque Lezama', null, 'Comunidad', 'guardia', 2,
   extensions.st_setsrid(extensions.st_makepoint(-58.3696, -34.6280), 4326)::extensions.geography,
   '{"wood": 10, "food": 4}'::jsonb, '2026-09-08T10:45:00Z'),

  ('5e1e7000-0000-4000-8000-000000000005', 'Plaza Francia (Recoleta)', null, 'Comunidad', null, 1,
   extensions.st_setsrid(extensions.st_makepoint(-58.3931, -34.5838), 4326)::extensions.geography,
   '{}'::jsonb, '2026-09-10T18:00:00Z')
on conflict (id) do nothing;

-- Ejemplo (comentado) de zona de exclusión, para probar `is_public_safe_point`.
-- Las reales se cargan desde OpenStreetMap (ver README).
--
-- insert into public.exclusion_zones (kind, name, geom, source) values
--   ('water', 'Río de la Plata (muestra)',
--    extensions.st_multi(extensions.st_geomfromtext(
--      'POLYGON((-58.335 -34.60, -58.30 -34.60, -58.30 -34.56, -58.335 -34.56, -58.335 -34.60))', 4326))::extensions.geography,
--    'manual');
