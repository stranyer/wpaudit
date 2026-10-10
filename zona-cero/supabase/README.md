# Zona Cero — backend en Supabase (opcional)

El juego funciona **completo sin backend**: si faltan `VITE_SUPABASE_URL` y
`VITE_SUPABASE_ANON_KEY`, se usa `LocalRepository` (localStorage + comunidad simulada).
Con esas dos variables, la fábrica carga `src/services/data/SupabaseRepository.ts`
(import dinámico) y el juego pasa a usar Supabase + PostGIS:

- sesión **anónima** de Supabase (sin registro; el id del jugador es `auth.uid()`),
- partida guardada en la nube,
- refugios, donaciones, facciones, ranking y supervivientes cercanos **reales**,
- validación de interacciones en el servidor (alcance, velocidad, reclamos, vencimiento).

Archivos:

| Archivo | Contenido |
| --- | --- |
| `migrations/0001_init.sql` | Esquema, RLS, funciones RPC, datos de referencia (facciones y requisitos por nivel). Idempotente. |
| `seed.sql` | Refugios comunitarios de demostración en plazas y parques públicos de Buenos Aires. |

---

## 1. Puesta en marcha

### 1.1 Crear el proyecto

1. Entrar a <https://supabase.com/dashboard> → **New project**. Elegir la región más
   cercana a los jugadores (para Argentina: `South America (São Paulo)`).
2. Guardar la contraseña de la base (la pide la CLI).

### 1.2 Habilitar PostGIS

**Database → Extensions → `postgis` → Enable**, en el esquema **`extensions`** (el
valor por defecto). La migración también ejecuta
`create extension if not exists postgis with schema extensions;`, así que este paso
es opcional, pero conviene verificarlo.

> ⚠️ Si PostGIS ya estaba instalado en otro esquema (por ejemplo `public`), la
> migración falla porque referencia `extensions.geography`. En ese caso, moverlo:
> `alter extension postgis set schema extensions;` (o recrear el proyecto).

### 1.3 Habilitar el inicio de sesión anónimo

**Authentication → Providers → Anonymous** (en el Dashboard nuevo: **Authentication →
Sign In / Providers → "Allow anonymous sign-ins"**) → activar y guardar.

Si está desactivado, `SupabaseRepository.init()` lanza un error en español que indica
exactamente este paso.

Recomendado en producción: activar **CAPTCHA** (Authentication → Attack Protection)
y revisar los límites de **Rate Limits** para sesiones anónimas, porque cualquiera
puede crear usuarios anónimos.

### 1.4 Aplicar la migración

**Opción A — Editor SQL del Dashboard:** abrir **SQL Editor**, pegar el contenido de
`supabase/migrations/0001_init.sql` y ejecutar. Se puede re-ejecutar sin romper nada.

**Opción B — Supabase CLI:**

```bash
npx supabase login
npx supabase init            # solo si no existe supabase/config.toml (no toca migrations/)
npx supabase link --project-ref <REF_DEL_PROYECTO>
npx supabase db push         # aplica supabase/migrations/*.sql
```

### 1.5 Cargar los datos de demostración

- Editor SQL: pegar y ejecutar `supabase/seed.sql`, o
- CLI: `npx supabase db push --include-seed`, o
- en local (`npx supabase start`): `npx supabase db reset` aplica migraciones + seed.

El seed es idempotente (ids fijos + `on conflict do nothing`).

### 1.6 Configurar el cliente

En **Project Settings → API** copiar la URL y la clave **anon / publishable** (nunca
la `service_role`, que saltea RLS). Crear `.env.local` en la raíz del proyecto:

```bash
VITE_SUPABASE_URL=https://<REF_DEL_PROYECTO>.supabase.co
VITE_SUPABASE_ANON_KEY=<clave anon>
```

Reiniciar `npm run dev`. Para volver al modo local, borrar (o dejar vacías) esas variables.

### 1.7 Problemas frecuentes

- **"Could not find the function … in the schema cache"**: la API todavía no vio las
  funciones nuevas. Ejecutar `notify pgrst, 'reload schema';` en el editor SQL.
- **"el inicio de sesión anónimo está deshabilitado"**: ver §1.3.
- **`type "extensions.geography" does not exist`**: PostGIS está en otro esquema (§1.2).

---

## 2. Esquema

| Tabla | Para qué | Quién lee | Quién escribe |
| --- | --- | --- | --- |
| `factions` | Las 3 facciones (`resistencia`, `guardia`, `nomades`). | todos | migración |
| `profiles` | Nombre, nivel, xp y facción públicos (sin ubicación). | autenticados | el dueño (solo `name`, `level`, `xp`, `faction_id`) |
| `player_saves` | `PlayerState` completo en jsonb (≤ 256 KB). | el dueño | el dueño |
| `player_private_state` | Última posición **real** validada + hora + bloqueo de velocidad. | **nadie** | solo RPC (`SECURITY DEFINER`) |
| `shelters` | Refugios con posición **pública engrosada**, nivel 1..5 y progreso. Máx. 1 por dueño. `owner_id` NULL = refugio comunitario. | todos | solo RPC |
| `shelter_contributions` | Aporte acumulado por (refugio, jugador). | todos | solo RPC |
| `shelter_level_requirements` | Requisitos para alcanzar los niveles 2..5 (= `SHELTER_LEVELS`). | todos | migración |
| `public_presence` | Presencia **aproximada** (grilla de ~0,002°). | el dueño (lo ajeno, vía RPC) | solo RPC |
| `spawn_claims` | Un reclamo por (jugador, spawn). | el dueño | solo RPC |
| `exclusion_zones` | Polígonos donde no puede haber refugios (militar, autopistas, vías, agua, privado…). | todos | administradores |
| `shelter_events` | Eventos cooperativos (ataques de hordas). Solo arquitectura. | todos | cron / edge function |

Todas las tablas tienen RLS activo. Además, la migración revoca los permisos que
Supabase da por defecto a `anon`/`authenticated` y otorga solo lo necesario (incluidos
permisos **por columna** en `profiles`).

## 3. Funciones RPC

Todas son `SECURITY DEFINER` con `search_path = public, extensions, pg_temp`, usan
`auth.uid()` como identidad y solo las puede ejecutar el rol `authenticated` (las
sesiones anónimas lo son). Las auxiliares `zc_*` y `purge_stale_data` no están
expuestas.

| Función | Devuelve |
| --- | --- |
| `validate_interaction(p_spawn_id text, p_target_lat float8, p_target_lng float8, p_lat float8, p_lng float8, p_accuracy float8, p_expires_at timestamptz default null, p_action text default 'scavenge')` | `{ok, reason, distance_m}`; `reason` ∈ `out_of_range`, `too_fast`, `depleted`, `expired`, `low_accuracy` |
| `create_shelter(p_name text, p_lat float8, p_lng float8)` | refugio en jsonb (si el jugador ya tiene uno, devuelve el existente) |
| `get_shelter(p_shelter_id uuid)` | refugio en jsonb o `null` |
| `donate_to_shelter(p_shelter_id uuid, p_resources jsonb, p_lat float8, p_lng float8, p_accuracy float8)` | `{ok, reason, accepted, leveled_up, shelter, distance_m}`; `reason` ∈ `out_of_range`, `not_found`, `invalid_amount` |
| `nearby_shelters(p_lat float8, p_lng float8, p_radius_m float8 default 2000)` | filas `id, name, owner_id, owner_name, faction_id, level, lat, lng, progress, contributions (jsonb, mayor a menor), created_at, distance_m` (radio ≤ 20 km, máx. 200) |
| `publish_presence(p_lat float8, p_lng float8)` | `void` (el servidor engrosa a grilla; máx. una escritura cada 5 s) |
| `nearby_survivors(p_lat float8, p_lng float8, p_radius_m float8 default 1500)` | filas `player_id, name, level, faction_id, lat, lng, last_seen_at` (últimos 30 min, sin el propio jugador, radio ≤ 5 km, máx. 100) |
| `leaderboard(p_limit int default 20)` | filas `player_id, player_name, faction_id, level, contribution` (1..100) |
| `join_faction(p_faction_id text)` | `void` (actualiza perfil, presencia y el refugio propio) |
| `factions_overview()` | filas `id, name, motto, color, bonus_description, members, total_contribution` |
| `is_public_safe_point(p_lat float8, p_lng float8, p_buffer_m float8 default 0)` | `boolean` |

Errores que pueden lanzar (el cliente los traduce a mensajes en español):
`not_authenticated`, `invalid_name`, `invalid_position`, `unsafe_location`,
`invalid_faction`, `invalid_action`, `invalid_spawn_id`.

---

## 4. Modelo de privacidad

Regla del juego: **la ubicación real del jugador nunca es visible para otros**.

1. **Ninguna tabla legible por clientes guarda coordenadas reales.** Las posiciones
   públicas (`shelters.position`, `public_presence.approx_position`) son siempre
   aproximadas.
2. **La posición real solo viaja como argumento** de `validate_interaction` y
   `donate_to_shelter`, para medir la distancia. El único lugar donde se conserva es
   `player_private_state` (última posición validada + hora + precisión), que tiene
   RLS activo **sin ninguna política** y sin permisos para `anon`/`authenticated`: solo
   la leen y escriben las funciones `SECURITY DEFINER`. Sirve exclusivamente para el
   control de velocidad y se borra tras 12 h de inactividad (`purge_stale_data`).
3. **Defensa en profundidad:** el cliente difumina antes de enviar
   (`services/privacy.ts`: grilla de 250 m + desplazamiento estable por jugador) y el
   servidor **vuelve a engrosar** cualquier posición pública aunque el cliente esté
   modificado:
   - presencia → grilla de **0,002°** (~220 m N-S × ~180 m E-O en Buenos Aires);
   - refugios → grilla de **0,001°** (~110 m × ~90 m), para que sigan siendo
     alcanzables (radio de interacción 40 m + hasta 15 m de tolerancia).
4. **La presencia ajena no se puede leer en bloque:** la tabla solo expone la fila
   propia; lo ajeno sale de `nearby_survivors`, con radio máximo de 5 km, solo
   actividad de los últimos 30 min y sin distancias exactas.
5. **Lugares seguros:** `create_shelter` rechaza posiciones dentro de
   `exclusion_zones` (`is_public_safe_point`). Los refugios del seed están en plazas
   y parques públicos.
6. Las búsquedas por cercanía (`nearby_*`) reciben un centro, pero no lo guardan.

## 5. Anti-trampas

Lo que valida el servidor (en `validate_interaction`, en este orden, igual que
`src/core/interaction.ts`):

| Chequeo | Detalle | Rechazo |
| --- | --- | --- |
| Reclamo único | Solo `p_action = 'scavenge'` reclama el spawn. PK `(player_id, spawn_id)` en `spawn_claims`; las carreras las resuelve la PK. `encounter` y `shelter` no reclaman. | `depleted` |
| Vencimiento | Si el id sigue el formato de `src/core/spawns.ts` (`z|s:<cx>_<cy>:<ventana>:<i>`), el servidor **calcula la ventana** (10 min zombies / 30 min suministros) y no depende del reloj del cliente; también rechaza ventanas futuras. Si no, usa `p_expires_at`. Tolerancia de 60 s por desfase de relojes. | `expired` |
| Velocidad | Compara con la última posición validada (privada): distancia menos la precisión de ambas muestras, dividida por el tiempo (mínimo 2 s, para que no sirvan ráfagas). Más de **12 m/s** → bloqueo de **30 s**. | `too_fast` |
| Precisión GPS | Más de **80 m**, negativa, NaN o nula. | `low_accuracy` |
| Alcance | `ST_DWithin` sobre `geography` (esfera, igual que `haversineM`): **40 m + min(precisión, 15 m)**. Para `p_action = 'shelter'` con id de un refugio real, se usa la posición guardada del refugio, no la que manda el cliente. | `out_of_range` |

`donate_to_shelter` bloquea la fila del refugio (`for update`), valida el alcance
contra la posición guardada y replica exactamente `applyDonation`: solo acepta lo que
el próximo nivel todavía necesita (el excedente se rechaza), redondea hacia abajo,
ignora recursos desconocidos o no positivos, sube de nivel automáticamente al
completar todos los requisitos y acumula el aporte por jugador. Si no se acepta nada,
responde `invalid_amount` (igual que `LocalRepository`).

Las constantes replican `src/config/gameConfig.ts` y `src/core/shelter.ts`
(`interactionRadiusM`, `maxAccuracyBonusM`, `maxAccuracyForInteractionM`,
`maxInteractionSpeedMps`, `speedLockMs`, `zombieWindowMs`, `supplyWindowMs`,
`SHELTER_LEVELS`). **Si se cambian allí, hay que cambiarlas también en la
migración.**

### Lo que todavía confía en el cliente (MVP)

- **Inventario, XP, nivel, salud y estadísticas** viven en `player_saves.save` (jsonb)
  y los escribe el cliente. El servidor no puede impedir que alguien edite su partida
  y se regale recursos; sí impide donar desde lejos, donar más de lo que el refugio
  necesita, reclamar dos veces el mismo spawn o reclamar fuera de su ventana.
- **Que el spawn exista en esa posición:** los spawns se generan en el cliente con la
  semilla compartida del mundo; el servidor valida la distancia al objetivo que
  informa el cliente, no que haya un spawn ahí.
- **El botín y el resultado de los combates** se sortean en el cliente.
- **La posición GPS en sí** (un GPS simulado no se detecta; el control de velocidad
  solo limita los "teletransportes").
- `profiles.level`/`xp` son un espejo del guardado (pueden falsearse en el ranking por
  nivel; el ranking principal es por aportes, que sí valida el servidor).

### Camino a servidor autoritativo

1. **Spawns en el servidor:** una Edge Function (Deno) que importe la lógica pura de
   `src/core` (`spawns.ts`, `rng.ts`, `geo.ts`, `supplies.ts`, `loot.ts`) y regenere de
   forma determinística los spawns de la celda con la misma `worldSeed`. Así
   `validate_interaction` puede verificar que el spawn existe y tomar su posición
   real.
2. **Botín en el servidor:** la misma función sortea el botín (`rng` sembrado con
   `worldSeed + spawnId + playerId`) y lo suma a un inventario autoritativo.
3. **Inventario autoritativo:** mover el inventario a una tabla
   `player_inventory (player_id, item_id, qty)` escribible solo por RPC; donar,
   fabricar y consumir pasan a ser RPC que descuentan del inventario real, y
   `player_saves` queda solo para preferencias y estado no crítico.
4. **Combate:** resolver turnos en una RPC/Edge Function con semilla del servidor, o al
   menos validar el resultado (XP y botín máximos posibles por tipo de zombie).
5. **Señales de GPS falso:** guardar en `player_private_state` un historial corto y
   detectar patrones (saltos repetidos, precisión constante, velocidad imposible);
   integridad del dispositivo (Play Integrity) en Android.
6. **Límites de frecuencia** por jugador en las RPC (p. ej. tabla de contadores o
   `pg_net` + edge middleware).

---

## 6. Mantenimiento

`purge_stale_data()` borra reclamos de más de 2 días, presencia de más de 1 día y la
posición privada tras 12 h sin actividad. Programarla con **pg_cron**
(Database → Extensions → `pg_cron`):

```sql
select cron.schedule('zona-cero-purge', '17 * * * *', $$select public.purge_stale_data()$$);
```

### Cargar zonas de exclusión desde OpenStreetMap

Importar un extracto (p. ej. Geofabrik, `argentina-latest.osm.pbf` recortado al área)
con `osm2pgsql` a tablas temporales y copiar a `exclusion_zones`. Las líneas
(autopistas, vías) se cargan con un buffer en metros:

```sql
-- Áreas (militares, agua, privadas…)
insert into public.exclusion_zones (kind, name, geom, source)
select 'military', name,
       extensions.st_multi(extensions.st_transform(way, 4326))::extensions.geography, 'osm'
from planet_osm_polygon
where landuse = 'military' or military is not null;

-- Autopistas y vías férreas: buffer de 25 m
insert into public.exclusion_zones (kind, name, geom, source)
select case when railway is not null then 'railway' else 'highway' end, name,
       extensions.st_multi(
         extensions.st_buffer(extensions.st_transform(way, 4326)::extensions.geography, 25)::extensions.geometry
       )::extensions.geography,
       'osm'
from planet_osm_line
where highway in ('motorway', 'motorway_link', 'trunk', 'trunk_link') or railway in ('rail', 'subway', 'light_rail');
```

## 7. Próximos pasos

- **Inventario autoritativo + Edge Function de spawns/botín** (ver §5).
- **Ataques de hordas (cron):** un job cada N minutos que, para refugios activos,
  inserte en `shelter_events` un `horde_attack` con fuerza según `planHordeAttack`;
  al vencer `starts_at`, otra pasada lo resuelve con `resolveHordeAttack` (defensa del
  nivel + poder de defensores conectados cerca, vía `public_presence`) y guarda
  `outcome`/`resolved_at`; si falla, descuenta progreso del refugio. Notificar con
  **Realtime** (suscripción a `shelter_events` filtrada por refugio).
- **Realtime** para refugios (progreso compartido en vivo) y presencia.
- **Fusionar cuentas anónimas** con email/OAuth (`linkIdentity`) para no perder la
  partida al cambiar de dispositivo.
- **Cargar `exclusion_zones`** reales y sumar un chequeo de cercanía entre refugios
  (hoy dos refugios pueden caer en el mismo punto de la grilla).
- **Tipos generados** (`npx supabase gen types typescript`) para tipar el cliente.

## 8. Verificación realizada

La migración se aplicó (dos veces, para comprobar que es idempotente) junto con el
seed sobre **PostgreSQL 16.15 + PostGIS 3.4.2** con un esquema `auth` de prueba
(`auth.users`, `auth.uid()` leyendo `request.jwt.claim.sub`) y roles
`anon`/`authenticated`. Como `authenticated` se probaron:
- RLS y permisos por columna;
- la tabla privada inaccesible;
- todos los motivos de rechazo de `validate_interaction`, incluido el bloqueo por velocidad;
- el engrosado de posiciones y las zonas de exclusión;
- donaciones con excedente y subida de nivel;
- ranking, facciones, presencia, y el rechazo de RPC a `anon`.
