# Zona Cero

Juego de supervivencia zombie con GPS para Android (y navegador). El mundo real sufrió un
apocalipsis: explorá tu ciudad, saqueá suministros, enfrentá infectados en combate por turnos
y mejorá refugios junto a otros sobrevivientes.

Escenario inicial: **Buenos Aires** (modo demo desde el Obelisco), pero funciona en cualquier
ciudad del mundo: el mundo se genera de forma determinística a partir de la ubicación.

> Estado: **vertical slice jugable (v0.1)**. Funciona completo sin backend (datos locales +
> comunidad simulada) y está preparado para Supabase/PostGIS.

---

## Inicio rápido

Requisitos: **Node.js 22+** y npm 10+.

```bash
cd zona-cero
npm install
npm run dev
```

Abrí <http://localhost:5173> y elegí **Modo demo · Buenos Aires** (o "Usar mi ubicación" para GPS real;
en el navegador el GPS requiere `localhost` o HTTPS).

### Controles del modo demo

| Acción | Cómo |
| --- | --- |
| Caminar | Joystick en pantalla, o **WASD / flechas** |
| Correr | Llevar el joystick al borde, o mantener **Shift** |
| Ir a un objetivo | Tocar un marcador → **Caminar hasta acá** |
| Teletransportarse | **Clic derecho** en el mapa (o mantener presionado en pantallas táctiles) |
| Visitar un refugio lejano | Pantalla del refugio → **Viajar (demo)** |

### Ciclo de juego

1. El mapa real se centra en el jugador; alrededor aparecen **zombies** (hexágonos rojos) y
   **suministros** (cajas con borde según rareza). Las **zonas infestadas** se marcan en rojo:
   más zombies y mejor botín (cajas militares).
2. Acercate a menos de **40 m** (+ tolerancia por precisión del GPS) e interactuá.
3. **Saquear** cuesta resistencia y llena la mochila (capacidad limitada por nivel).
4. **Enfrentar** abre la escena 3D de combate por turnos: atacar, golpe fuerte, disparar
   (gasta munición), cubrirse, usar objetos o huir. Cada tipo de zombie tiene una mecánica:
   - **Corredor**: a veces ataca dos veces. **Hinchado**: explota al morir (rematalo a distancia).
   - **Chillón**: grita y llegan refuerzos. **Bruto**: prepara embestidas — cubrite en el momento justo
     y queda aturdido (el siguiente golpe es crítico).
5. Ganás XP, objetos y subís de nivel (más salud, resistencia y mochila). Si caés, perdés parte de los recursos.
6. **Mochila → Fabricar**: raciones, bate con clavos, munición, chaleco, botiquín, machete, pistola
   (las recetas avanzadas requieren el taller de tu refugio).
7. **Refugio**: montá tu campamento (5 madera + 3 metal) y doná recursos para subirlo de nivel
   (Barricadas → Taller → Torre de vigilancia → Fortaleza). Descansar junto al fuego recupera salud.
   Los refugios comunitarios (plazas de Buenos Aires) también aceptan donaciones.
8. **Comunidad**: refugios cercanos, facciones (con bonus), ranking de aportes y sobrevivientes cercanos
   con distancia aproximada.

El progreso se guarda solo (localStorage o Supabase).

---

## Scripts

| Comando | Qué hace |
| --- | --- |
| `npm run dev` | Servidor de desarrollo (Vite) |
| `npm run build` | Chequeo de TypeScript + build de producción en `dist/` |
| `npm run typecheck` | Solo TypeScript |
| `npm test` | Tests (Vitest) |
| `npm run preview` | Sirve el build de producción |
| `npm run android:sync` | Build + copia al proyecto Android |
| `npm run android:open` | Abre el proyecto en Android Studio |
| `npm run android:run` | Build + sync + ejecuta en dispositivo/emulador |

## Variables de entorno

Copiá `.env.example` a `.env.local`. **Todas son opcionales.**

| Variable | Uso |
| --- | --- |
| `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` | Activan el backend real. Sin ellas se usa el repositorio local con datos simulados. |
| `VITE_MAP_STYLE_URL` | Estilo MapLibre alternativo. Por defecto: estilo propio sobre tiles gratuitos de OpenFreeMap (sin API key). |
| `VITE_INTERACTION_RADIUS_M` | Radio de interacción (default 40 m). |
| `VITE_WORLD_SEED` | Semilla del mundo: misma semilla = mismos spawns para todos los clientes. |

---

## Arquitectura

```
src/
├── core/        Motor de juego puro (sin React/DOM): tipos, geo, RNG determinístico,
│                objetos, botín, inventario, fabricación, progresión, jugador,
│                combate por turnos, zombies, spawns, refugios, facciones,
│                validación de interacciones y ubicación segura de spawns.
├── config/      Balance y parámetros (radios, GPS, ventanas de spawn, regeneración...).
├── game/        Capa de sesión: conecta ubicación ↔ mundo ↔ jugador ↔ persistencia
│                (session.ts) y las acciones del jugador (actions.ts).
├── store/       Estado global con Zustand (jugador, mundo, ubicación, UI).
├── services/
│   ├── location/  GPS real (Capacitor nativo o navigator.geolocation) con filtro de
│   │              Kalman + throttling, y proveedor demo (joystick/teclado/auto-caminata).
│   ├── data/      GameRepository (interfaz) + LocalRepository (localStorage + mocks)
│   │              + SupabaseRepository (carga diferida).
│   └── privacy.ts Difuminado de ubicaciones públicas.
├── map/         MapLibre: estilo propio oscuro, marcadores, zonas, extracción de calles
│                de los tiles para ubicar spawns.
├── three/       Three.js: motor de escena, modelos low-poly procedurales (zombies,
│                sobreviviente, refugio, props) y escenas de combate/refugio/avatar.
└── ui/          Pantallas y componentes React + estilos (CSS puro).
supabase/        Migración PostgreSQL/PostGIS, seed y guía (ver supabase/README.md).
tests/           Tests de mecánicas (Vitest).
android/         Proyecto nativo generado por Capacitor.
```

Principios:

- **El core es puro y determinístico.** Combate, botín y spawns reciben un RNG; con la misma semilla
  dan el mismo resultado. Eso permite testearlos y, más adelante, ejecutarlos en el servidor.
- **Mundo compartido sin servidor.** Cada celda de ~200 m genera sus spawns a partir de
  `(semilla, celda, ventana de tiempo)`: zombies cada 10 min, suministros cada 30 min, zonas infestadas
  cada 6 h. Todos los jugadores ven lo mismo y el backend puede regenerarlo para validar.
- **Repositorio intercambiable.** La UI no sabe si hay backend: `getRepository()` elige Supabase si hay
  credenciales (y si falla, cae al modo local).
- **Three.js se carga bajo demanda** (combate, refugio y perfil) para que el mapa arranque rápido.

## Seguridad, privacidad y anti-trampas

- **Ubicación real nunca pública.** La presencia y los refugios se difuminan en el cliente (grilla de
  250 m + desplazamiento estable) y el servidor vuelve a engrosarlos. Los demás ven distancias
  aproximadas ("~300 m").
- **El refugio no se crea en tu casa:** se ubica en una calle pública cercana a una posición difuminada.
- **Lugares seguros:** los spawns se ajustan a calles y senderos públicos extraídos de los tiles
  (OpenStreetMap). Se descartan los que caen en agua, vías de tren, autopistas, zonas militares,
  industriales, cementerios, aeropuertos o accesos privados. No aparecen zombies junto a refugios.
- **Validación de interacciones** (`core/interaction.ts`), replicada en el servidor
  (`validate_interaction`): alcance con tolerancia por precisión, precisión mínima, bloqueo por
  velocidad de vehículo (>43 km/h), puntos agotados y vencidos.
- **Aviso de seguridad** al iniciar: atención al entorno, no entrar a propiedades privadas, no jugar manejando.

## Rendimiento y batería

- GPS con `watchPosition`, filtro de Kalman, descarte de lecturas imprecisas y de movimientos < 3 m;
  se **detiene en segundo plano** (visibilitychange) y se reanuda al volver.
- Mapa: `pixelRatio` máx. 2, sin antialias, sin fades, caché de tiles acotada; solo se dibujan
  marcadores a < 520 m; recálculo de spawns solo al cambiar de celda o de ventana de tiempo.
- Three.js: low-poly con materiales compartidos, sin sombras dinámicas, pocas luces, `pixelRatio` acotado,
  render en pausa con la app oculta y liberación completa de memoria al salir de cada escena.
- Guardado con antirrebote y al ocultar la app.

---

## Android (Capacitor)

Requisitos: Android Studio (Ladybug o superior), JDK 21 y SDK de Android.

```bash
npm run android:sync   # build web + copia a android/
npm run android:open   # abre Android Studio → Run
# o directamente:
npm run android:run
```

- Permisos declarados: ubicación fina/aproximada, internet y vibración.
- Orientación vertical fija; el WebView sirve el juego desde `https://localhost`.
- El GPS usa el plugin nativo `@capacitor/geolocation` (pide permisos del sistema).

## Supabase (opcional)

Ver [`supabase/README.md`](supabase/README.md): esquema PostGIS, RLS, funciones RPC con validación de
distancia/velocidad, modelo de privacidad y pasos de despliegue. Con `VITE_SUPABASE_URL` y
`VITE_SUPABASE_ANON_KEY` el juego usa autenticación anónima y sincroniza progreso, refugios, donaciones,
facciones, ranking y presencia.

## Tests

```bash
npm test
```

Cubren: geometría y grilla, ajuste de spawns a calles y zonas excluidas, determinismo del mundo,
validación de interacciones y velocidad, privacidad, inventario/capacidad, fabricación, botín,
combate (golpes, críticos, embestida del Bruto, explosión del Hinchado, munición, objetos, derrota),
progresión, regeneración, penalización por caer, descanso, donaciones y subida de nivel de refugios,
hordas, repositorio local y suavizado GPS.

## Próximos pasos sugeridos

- Inventario y botín autoritativos en el servidor (Edge Function que regenere spawns con la semilla).
- Ataques de hordas a refugios en tiempo real (la lógica y las tablas ya existen: `planHordeAttack`,
  `resolveHordeAttack`, `shelter_events`).
- Eventos cooperativos y combate en grupo (Supabase Realtime).
- Sonido ambiente y efectos; modelos 3D de props sobre el mapa.
- Puntos de interés reales (farmacias, almacenes) para tematizar suministros.

## Créditos

- Mapas: © [OpenStreetMap](https://www.openstreetmap.org/copyright), tiles de [OpenFreeMap](https://openfreemap.org).
- Tipografías: Black Ops One y Oswald (SIL Open Font License), vía Fontsource.
- Íconos de interfaz: [Lucide](https://lucide.dev) (ISC). Íconos de objetos y modelos 3D: propios (procedurales).
