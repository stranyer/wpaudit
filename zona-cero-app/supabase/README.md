# Zona Cero (Flutter) — backend en Supabase (opcional)

La app funciona **completa sin backend**: si se compila sin `SUPABASE_URL` y
`SUPABASE_ANON_KEY`, `createRepository()` (`lib/data/repository_factory.dart`) devuelve
`LocalRepository` (SharedPreferences + comunidad simulada). Con esas dos variables
(`--dart-define`), inicializa `supabase_flutter`, abre una sesión anónima y el juego pasa
a usar `SupabaseRepository` (`lib/data/supabase_repository.dart`) contra Supabase + PostGIS:

- sesión **anónima** de Supabase (sin registro; el id del jugador es `auth.uid()`, y la
  sesión se guarda en el dispositivo para conservar el mismo jugador),
- partida guardada en la nube,
- refugios (nodos), donaciones, facciones, ranking, supervivientes cercanos y **pulsos** reales,
- validación de interacciones en el servidor (alcance, velocidad, reclamos, vencimiento).

Si la conexión falla al arrancar (sin red, credenciales mal puestas, proveedor anónimo
deshabilitado…), la fábrica escribe un `debugPrint` y **cae a `LocalRepository`**: el juego
nunca queda trabado en la pantalla de carga.

**Mismo backend que la web.** `migrations/0001_init.sql` y `seed.sql` son copias exactas de
los de la versión web (`zona-cero/supabase/`), así que ambas apps pueden compartir el mismo
proyecto de Supabase (mismas tablas, RPC y jugadores). Los comentarios de esa migración
nombran archivos de la web (`src/config/gameConfig.ts`, `src/core/shelter.ts`…); sus
equivalentes en Flutter son `lib/core/game_config.dart`, `lib/core/shelter.dart`, etc.
`0002_pulses.sql` es nuevo de la versión Flutter (la web lo ignora sin problemas).

Archivos:

| Archivo | Contenido |
| --- | --- |
| `migrations/0001_init.sql` | Esquema, RLS, funciones RPC, datos de referencia (facciones y requisitos por nivel). Idempotente. Idéntico al de la web. |
| `migrations/0002_pulses.sql` | Pulsos de la red: tabla `shelter_pulses`, RLS, RPC `send_pulse` (con límites de frecuencia) y `shelter_pulse_totals`, mantenimiento `compact_shelter_pulses`. Idempotente. |
| `seed.sql` | Refugios comunitarios de demostración en plazas y parques públicos de Buenos Aires. |

---

## 1. Puesta en marcha

### 1.1 Crear el proyecto

1. Entrar a <https://supabase.com/dashboard> → **New project**. Elegir la región más
   cercana a los jugadores (para Argentina: `South America (São Paulo)`).
2. Guardar la contraseña de la base (la pide la CLI).

(Si ya existe el proyecto de la versión web, se reutiliza: saltear a §1.4 y aplicar solo
`0002_pulses.sql`.)

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
exactamente este paso (y la app arranca en modo local).

Recomendado en producción: activar **CAPTCHA** (Authentication → Attack Protection)
y revisar los límites de **Rate Limits** para sesiones anónimas, porque cualquiera
puede crear usuarios anónimos.

### 1.4 Aplicar las migraciones (en orden)

**Opción A — Editor SQL del Dashboard:** abrir **SQL Editor**, pegar y ejecutar
`supabase/migrations/0001_init.sql` y después `supabase/migrations/0002_pulses.sql`.
Se pueden re-ejecutar sin romper nada.

**Opción B — Supabase CLI** (desde `zona-cero-app/`):

```bash
npx supabase login
npx supabase init            # solo si no existe supabase/config.toml (no toca migrations/)
npx supabase link --project-ref <REF_DEL_PROYECTO>
npx supabase db push         # aplica supabase/migrations/*.sql en orden
```

> Si la base ya tiene aplicada la migración de la web con la CLI, `db push` reconoce
> `0001_init` por su nombre y solo aplica `0002_pulses`.

Sin `0002_pulses.sql` el juego funciona igual: `sendPulse` detecta que la RPC no existe y
cuenta los pulsos en el dispositivo (con un aviso en el log).

### 1.5 Cargar los datos de demostración

- Editor SQL: pegar y ejecutar `supabase/seed.sql`, o
- CLI: `npx supabase db push --include-seed`, o
- en local (`npx supabase start`): `npx supabase db reset` aplica migraciones + seed.

El seed es idempotente (ids fijos + `on conflict do nothing`).

### 1.6 Configurar la app (Flutter)

En **Project Settings → API** copiar la URL y la clave **anon / publishable** (nunca
la `service_role`, que saltea RLS). Las credenciales se pasan en tiempo de compilación:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<REF_DEL_PROYECTO>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<clave anon>
```

Lo mismo para compilar (`flutter build apk …`, `flutter build ios …`). Para no repetirlas,
se pueden poner en un JSON fuera del control de versiones:

```bash
# supabase.local.json → {"SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_ANON_KEY": "<clave anon>"}
flutter run --dart-define-from-file=supabase.local.json
```

Sin esas variables (un `flutter run` normal) se juega en modo local. `hasSupabaseConfig`
indica si la build las trae.

Supabase local (`npx supabase start`): la URL es `http://127.0.0.1:54321` (en el emulador
de Android, `http://10.0.2.2:54321`) y la clave anon la imprime `npx supabase status`.

Cableado en la app (lo hace el arranque, no este directorio):

```dart
final store = await KeyValueStore.open();
final repo = await createRepository(store); // Supabase o LocalRepository
await AppState.instance.bootstrap(repository: repo);
```

### 1.7 Problemas frecuentes

- **En el log: `[Zona Cero] Supabase no disponible, usando datos locales. …`**: la app
  cayó a modo local; el resto del mensaje dice por qué (red, URL, clave, proveedor anónimo).
- **"Could not find the function … in the schema cache"**: la API todavía no vio las
  funciones nuevas. Ejecutar `notify pgrst, 'reload schema';` en el editor SQL.
- **"el inicio de sesión anónimo está deshabilitado"**: ver §1.3.
- **`type "extensions.geography" does not exist`**: PostGIS está en otro esquema (§1.2).
- **`[SupabaseRepository] El servidor no tiene pulsos…`**: falta `0002_pulses.sql` (§1.4).

---

## 2. Esquema

| Tabla | Para qué | Quién lee | Quién escribe |
| --- | --- | --- | --- |
| `factions` | Las 3 facciones (`resistencia`, `guardia`, `nomades`). | todos | migración |
| `profiles` | Nombre, nivel, xp y facción públicos (sin ubicación). | autenticados | el dueño (solo `name`, `level`, `xp`, `faction_id`) |
| `player_saves` | `PlayerState` completo en jsonb (≤ 256 KB), mismo formato que la web. | el dueño | el dueño |
| `player_private_state` | Última posición **real** validada + hora + bloqueo de velocidad. | **nadie** | solo RPC (`SECURITY DEFINER`) |
| `shelters` | Refugios con posición **pública engrosada**, nivel 1..5 y progreso. Máx. 1 por dueño. `owner_id` NULL = refugio comunitario. | todos | solo RPC |
| `shelter_contributions` | Aporte acumulado por (refugio, jugador). | todos | solo RPC |
| `shelter_level_requirements` | Requisitos para alcanzar los niveles 2..5 (= `shelterLevels`). | todos | migración |
| `public_presence` | Presencia **aproximada** (grilla de ~0,002°). | el dueño (lo ajeno, vía RPC) | solo RPC |
| `spawn_claims` | Un reclamo por (jugador, spawn). | el dueño | solo RPC |
| `exclusion_zones` | Polígonos donde no puede haber refugios (militar, autopistas, vías, agua, privado…). | todos | administradores |
| `shelter_events` | Eventos cooperativos (ataques de hordas). Solo arquitectura. | todos | cron / edge function |
| `shelter_pulses` | Registro de pulsos (`shelter_id`, `player_id`, `count`, `created_at`). Sin ubicación. | el dueño (totales, vía RPC) | solo RPC |

Todas las tablas tienen RLS activo. Además, las migraciones revocan los permisos que
Supabase da por defecto a `anon`/`authenticated` y otorgan solo lo necesario (incluidos
permisos **por columna** en `profiles`).

## 3. Funciones RPC

Todas son `SECURITY DEFINER` con `search_path = public, extensions, pg_temp`, usan
`auth.uid()` como identidad y solo las puede ejecutar el rol `authenticated` (las
sesiones anónimas lo son). Las auxiliares `zc_*`, `purge_stale_data` y
`compact_shelter_pulses` no están expuestas.

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
| `send_pulse(p_shelter_id uuid, p_count int default 1)` *(0002)* | `bigint`: total de pulsos del nodo después del envío |
| `shelter_pulse_totals(p_shelter_ids uuid[])` *(0002)* | filas `shelter_id, total` (máx. 200 ids; los inexistentes se omiten) |

Errores que pueden lanzar (el cliente los traduce a mensajes en español en
`SupabaseMapping.serverErrors`): `not_authenticated`, `invalid_name`, `invalid_position`,
`unsafe_location`, `invalid_faction`, `invalid_action`, `invalid_spawn_id` y, de los pulsos,
`invalid_count`, `shelter_not_found`, `own_shelter`, `rate_limited`.

---

## 4. Modelo de privacidad

Regla del juego: **la ubicación real del jugador nunca es visible para otros**.

1. **Ninguna tabla legible por clientes guarda coordenadas reales.** Las posiciones
   públicas (`shelters.position`, `public_presence.approx_position`) son siempre
   aproximadas. Los pulsos no llevan ubicación.
2. **La posición real solo viaja como argumento** de `validate_interaction` y
   `donate_to_shelter`, para medir la distancia. El único lugar donde se conserva es
   `player_private_state` (última posición validada + hora + precisión), que tiene
   RLS activo **sin ninguna política** y sin permisos para `anon`/`authenticated`: solo
   la leen y escriben las funciones `SECURITY DEFINER`. Sirve exclusivamente para el
   control de velocidad y se borra tras 12 h de inactividad (`purge_stale_data`).
3. **Defensa en profundidad:** el cliente difumina antes de enviar
   (`lib/core/privacy.dart` → `fuzzPosition`: grilla de 250 m + desplazamiento estable por
   jugador). `AppState` difumina la presencia y `SupabaseRepository.publishPresence` la
   vuelve a pasar por `fuzzPosition` con el id del jugador (igual que la web; aplicarla dos
   veces no la mueve). Los nodos se crean con la posición pública que arma el juego
   (difuminada + ajustada a la calle). Y el servidor **vuelve a engrosar** cualquier
   posición pública aunque el cliente esté modificado:
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
`lib/core/interaction.dart`):

| Chequeo | Detalle | Rechazo |
| --- | --- | --- |
| Reclamo único | Solo `p_action = 'scavenge'` reclama el spawn. PK `(player_id, spawn_id)` en `spawn_claims`; las carreras las resuelve la PK. `encounter` y `shelter` no reclaman. | `depleted` |
| Vencimiento | Si el id sigue el formato de `lib/core/spawns.dart` (`z|s:<cx>_<cy>:<ventana>:<i>`), el servidor **calcula la ventana** (10 min zombies / 30 min suministros) y no depende del reloj del cliente; también rechaza ventanas futuras. Si no, usa `p_expires_at`. Tolerancia de 60 s por desfase de relojes. | `expired` |
| Velocidad | Compara con la última posición validada (privada): distancia menos la precisión de ambas muestras, dividida por el tiempo (mínimo 2 s, para que no sirvan ráfagas). Más de **12 m/s** → bloqueo de **30 s**. | `too_fast` |
| Precisión GPS | Más de **80 m**, negativa, NaN o nula. | `low_accuracy` |
| Alcance | `ST_DWithin` sobre `geography` (esfera, igual que `haversineM`): **40 m + min(precisión, 15 m)**. Para `p_action = 'shelter'` con id de un refugio real, se usa la posición guardada del refugio, no la que manda el cliente. | `out_of_range` |

`donate_to_shelter` bloquea la fila del refugio (`for update`), valida el alcance
contra la posición guardada y replica exactamente `applyDonation`: solo acepta lo que
el próximo nivel todavía necesita (el excedente se rechaza), redondea hacia abajo,
ignora recursos desconocidos o no positivos, sube de nivel automáticamente al
completar todos los requisitos y acumula el aporte por jugador. Si no se acepta nada,
responde `invalid_amount` (igual que `LocalRepository`).

`send_pulse` (0002) valida, por jugador y en serie (bloquea la fila del perfil, así las
llamadas simultáneas no se saltean los límites):

| Chequeo | Detalle | Rechazo |
| --- | --- | --- |
| Cantidad | De 1 a 10 pulsos por llamada (el cliente acota a 10). | `invalid_count` |
| Nodo | Tiene que existir y no ser propio. | `shelter_not_found` / `own_shelter` |
| Frecuencia | Como mucho una llamada por segundo. | `rate_limited` |
| Cupo | Máx. **30 pulsos por hora** al mismo nodo y **300 por hora** en total. Se acepta hasta el tope; sin cupo, se rechaza. | `rate_limited` |

Las constantes replican `lib/core/game_config.dart` y `lib/core/shelter.dart` (en la web,
`src/config/gameConfig.ts` y `src/core/shelter.ts`): `interactionRadiusM`, `maxAccuracyBonusM`, `maxAccuracyForInteractionM`,
`maxInteractionSpeedMps`, `speedLockMs`, `zombieWindowMs`, `supplyWindowMs`,
`shelterLevels`. **Si se cambian en el cliente, hay que cambiarlas también en la
migración** (y en la versión web, que comparte el backend).

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

1. **Spawns en el servidor:** una Edge Function (Deno) que porte la lógica pura de
   `lib/core` (`spawns`, `rng`, `geo`, `supplies`, `loot`; la web tiene la misma lógica en
   TypeScript lista para importar) y regenere de forma determinística los spawns de la
   celda con la misma `worldSeed`. Así `validate_interaction` puede verificar que el spawn
   existe y tomar su posición real.
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
   integridad del dispositivo (Play Integrity en Android, App Attest en iOS).
6. **Límites de frecuencia** por jugador en el resto de las RPC (como ya hace
   `send_pulse`).

---

## 6. Mantenimiento

`purge_stale_data()` borra reclamos de más de 2 días, presencia de más de 1 día y la
posición privada tras 12 h sin actividad. `compact_shelter_pulses()` junta los pulsos de
más de 2 días en una fila por (nodo, jugador), sin cambiar los totales. Programarlas con
**pg_cron** (Database → Extensions → `pg_cron`):

```sql
select cron.schedule('zona-cero-purge', '17 * * * *', $$select public.purge_stale_data()$$);
select cron.schedule('zona-cero-pulses', '43 4 * * *', $$select public.compact_shelter_pulses()$$);
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

## 7. Cliente Flutter: comportamiento

- **Errores:** toda falla se lanza como `SupabaseRepositoryException`, cuyo `toString()` es
  un mensaje en español listo para un toast y cuyo `code` es estable: el de la RPC
  (`rate_limited`, `unsafe_location`…) o uno del cliente (`network`, `timeout`,
  `invalid_response`, `missing_rpc`, `session_expired`, `permission_denied`,
  `server_unavailable`, `anonymous_disabled`). `isNetwork` distingue la falta de conexión.
  Cada llamada tiene un tiempo límite (15 s por defecto).
- **Sesión:** si hay una sesión guardada pero no hay red para refrescarla, `init()` falla
  con `network` en vez de crear otro usuario anónimo (que perdería la partida).
- **Igual que la web:** ids que no son uuid (nodos simulados) → `getShelter` = null y
  `donateToShelter` = `not_found` sin tocar la red; `factions_overview` vacío → facciones
  del cliente sin estadísticas; si falla el espejo del perfil público al guardar, la
  partida igual queda guardada.
- **Pulsos:** `sendPulse` devuelve el total del servidor. Si el servidor no tiene la RPC
  (falta 0002), cuenta en el dispositivo (`zc:sb-pulses`) y no vuelve a intentar en esa
  sesión. `pulsesOf(id)` devuelve el último total conocido (sin red);
  `getNearbyShelters` precarga los totales en segundo plano y `fetchPulseTotals(ids)` los
  pide explícitamente.
- **Facción:** `joinFaction(id, null)` (dejar la facción) limpia `profiles.faction_id`
  directamente, porque `join_faction` no acepta `null`; el refugio propio conserva su
  facción hasta que se una a otra.

## 8. Próximos pasos

- **Inventario autoritativo + Edge Function de spawns/botín** (ver §5).
- **Ataques de hordas (cron):** un job cada N minutos que, para refugios activos,
  inserte en `shelter_events` un `horde_attack` con fuerza según `planHordeAttack`;
  al vencer `starts_at`, otra pasada lo resuelve con `resolveHordeAttack` (defensa del
  nivel + poder de defensores conectados cerca, vía `public_presence`) y guarda
  `outcome`/`resolved_at`; si falla, descuenta progreso del refugio. Notificar con
  **Realtime** (suscripción a `shelter_events` filtrada por refugio).
- **Realtime** para refugios (progreso compartido en vivo), presencia y pulsos.
- **Fusionar cuentas anónimas** con email/OAuth (`linkIdentity`) para no perder la
  partida al cambiar de dispositivo.
- **Cargar `exclusion_zones`** reales y sumar un chequeo de cercanía entre refugios
  (hoy dos refugios pueden caer en el mismo punto de la grilla).
- `join_faction` que acepte `null` (dejar la facción) y actualice también el refugio propio.

## 9. Verificación realizada

- **Web (0001 + seed):** la migración se aplicó (dos veces, para comprobar que es
  idempotente) junto con el seed sobre **PostgreSQL 16.15 + PostGIS 3.4.2** con un esquema
  `auth` de prueba (`auth.users`, `auth.uid()` leyendo `request.jwt.claim.sub`) y roles
  `anon`/`authenticated`. Como `authenticated` se probaron RLS y permisos por columna, la
  tabla privada inaccesible, todos los motivos de rechazo de `validate_interaction`
  (incluido el bloqueo por velocidad), el engrosado de posiciones y las zonas de exclusión,
  donaciones con excedente y subida de nivel, ranking, facciones, presencia, y el rechazo de
  RPC a `anon`.
- **Flutter (0002):** `0001_init.sql` + `seed.sql` + `0002_pulses.sql` aplicadas dos veces
  sobre el mismo entorno (PostgreSQL 16.15 + PostGIS 3.4.2, `auth` de prueba). Como
  `authenticated` se probaron: `not_authenticated`, `invalid_count` (0 y 11),
  `shelter_not_found`, `own_shelter`, `rate_limited` por ráfaga (< 1 s) y por cupo (acepta 4
  de 10 cuando quedaban 4 del tope de 30/h), dos llamadas simultáneas del mismo jugador
  (una sola pasa), RLS de `shelter_pulses` (solo filas propias, sin INSERT directo), totales
  de otro jugador vía `shelter_pulse_totals` (ids inexistentes y `null` ignorados),
  `compact_shelter_pulses` (conserva la suma, idempotente, no expuesta) y el rechazo de
  ambas RPC a `anon`.
- **Cliente:** `flutter test test/data` prueba el mapeo fila ↔ modelo y el repositorio de
  punta a punta contra un GoTrue/PostgREST falso en loopback (sin red externa).
