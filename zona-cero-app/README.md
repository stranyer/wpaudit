# Zona Cero · Protocolo Sutura

Juego de supervivencia zombie con GPS para Android, hecho en **Flutter**. Caminás tu ciudad real
como un **Enlace** del Protocolo Sutura: escaneás la zona, recuperás suministros, enfrentás
infectados y reconstruís una red de nodos (refugios) junto a otros sobrevivientes.

Escenario inicial: **Buenos Aires** (simulación desde el Obelisco), pero funciona en cualquier
ciudad: el mundo se genera de forma determinística a partir de la ubicación.

> Estado: **v0.2 jugable**. Funciona completo sin backend (datos locales + comunidad simulada) y
> se conecta a **Supabase/PostGIS** si le pasás credenciales.

Esta app reemplaza a la versión web de `../zona-cero` (React + Three.js) con la misma lógica de
juego, portada a Dart y verificada contra la versión original con tests de paridad.

---

## Dirección de arte: "Protocolo Sutura"

Survival horror clínico (Resident Evil) × red holográfica fría (Death Stranding), con IP propia.

| Elemento | Decisión |
| --- | --- |
| Paleta | Fondo `#05070A`, señal cian `#6ADBEA` (red, escáner), ámbar `#E2B53E` (recompensas, nodos), estados ECG verde/amarillo/naranja/rojo |
| Tipografía | Jost (títulos), Barlow Semi Condensed (UI), Share Tech Mono (datos), Courier Prime (documentos), Special Elite (sellos), Syncopate (logo). Todas incluidas como TTF |
| Formas | Esquinas en L, chaflán a 45°, hexágonos = nodos, rombos = amenazas |
| Salud | Monitor ECG que cambia de ritmo y color (ESTABLE / PRECAUCIÓN / PELIGRO) |
| Mapa | Topográfico oscuro; zonas infestadas como curvas de nivel rojas |
| Escáner | Pulso de 250 m tipo sonar: los contactos aparecen cuando los alcanza la onda y quedan como eco |
| Combate | Escena 2D con sprites pre-renderizados de los modelos 3D low-poly (Flame) |

Lore original: la cepa AMB-0 ("la Ámbar"), Laboratorios Ferrán-Kessler, la DESAM y las
terminales VITA-7. Todo el texto del juego está en español rioplatense.

---

## Cómo se juega

1. **Arranque**: elegí *Conectar GPS* (jugás caminando) o *Simulación · Buenos Aires*.
2. **Mapa**: mantené el botón hexagonal para **escanear** (cada 45 s). Aparecen infectados
   (rombos rojos), suministros (cuadros ámbar) y nodos (hexágonos).
3. Acercate a menos de **40 m** (más tolerancia por la precisión del GPS) y tocá el objetivo:
   - **Recuperar** un suministro (cuesta resistencia, llena el maletín).
   - **Enfrentar** un infectado: combate por turnos con puntería. Mantené apretado para que la
     mira se cierre y soltá para atacar. Con la mira cerrada sobre la cabeza el golpe es crítico
     garantizado; si seguís manteniendo con un arma cuerpo a cuerpo, la mira se pone ámbar
     (*CARGADO*) y sale un golpe fuerte. *Cubrirse*, *Objetos* (botiquín, raciones) y *Huir*
     completan el turno. Cada infectado tiene su mecánica: el Corredor puede atacar dos veces,
     el Chillón grita y se recupera, el Hinchado explota al morir y el Bruto prepara
     embestidas (cubrite en el momento justo).
4. **Maletín**: inventario en grilla (cada objeto ocupa su huella), equipo y **taller**.
5. **Red**: instalá tu **nodo** (madera + metal), sumate a una facción, mirá el ranking y los
   enlaces cercanos (siempre con posición aproximada).
6. **Nodo**: entregá recursos para subir la antena (5 niveles), escribí en la **bitácora** para
   guardar y descansar, y dejá **pulsos** a otros enlaces.
7. **Archivo**: documentos que se desbloquean jugando (informes, diarios, transmisiones).

### Controles de la simulación

| Acción | Cómo |
| --- | --- |
| Caminar / correr | Joystick en pantalla (al borde = correr) |
| Ir a un objetivo | Tocar un marcador → **Caminar hasta acá** |
| Teletransportarse | Mantener presionado en el mapa |
| Visitar un nodo lejano | Panel del nodo → **Viajar (simulación)** |

---

## Inicio rápido

Requisitos: **Flutter 3.47+** (Dart 3.13+), Android SDK 36 y JDK 21.

```bash
cd zona-cero-app
flutter pub get
flutter run                 # celular Android conectado por USB (depuración activada)
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (celulares actuales, ~35 MB)
```

Para probar la interfaz en el navegador (el GPS real necesita `localhost` o HTTPS):

```bash
flutter run -d chrome
```

### Backend opcional (Supabase)

Sin credenciales, la app usa `LocalRepository`: guarda todo en el teléfono y simula la comunidad
(nodos en plazas de Buenos Aires, ranking y enlaces cercanos). Para jugar en red:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu-anon-key
```

El esquema (tablas, RLS y funciones RPC con validación del lado del servidor) está en
[`supabase/`](supabase/README.md). Si la conexión falla, la app vuelve sola al modo local.

---

## Seguridad y privacidad

- **Tu ubicación exacta nunca sale del teléfono.** A la red solo llega una posición difuminada a
  una grilla de ~250 m.
- Los **nodos** se ubican en un punto público cercano (grilla + ajuste a una calle), nunca en la
  ubicación real de quien lo instala.
- Los spawns se ajustan a calles públicas transitables con los datos del mapa y se descartan en
  agua, vías, zonas militares, industriales, cementerios, cárceles o aeropuertos.
- **Control de velocidad**: a más de 12 m/s (vehículo) las interacciones se pausan 30 s.
- Las validaciones de distancia y velocidad corren en el cliente y están replicadas en el
  servidor (RPC de Supabase).
- Aviso de seguridad al iniciar: mirar la calle, no entrar a propiedades privadas, no jugar
  manejando.

## Rendimiento y batería

- GPS con `distanceFilter`, intervalos adaptados y suavizado Kalman; se pausa en segundo plano.
- El mapa vive en un `IndexedStack` (no se recrea al cambiar de pestaña) y las capas se
  actualizan como fuentes GeoJSON con límite de frecuencia.
- Íconos del mapa generados una sola vez en tiempo de ejecución.
- Combate en Flame con imágenes precargadas y sprites optimizados (~9 MB en total).
- Guardado con *debounce* (no se escribe en disco en cada paso).

---

## Arquitectura

```
lib/
├── core/        Lógica pura del juego (sin Flutter): RNG, mundo, combate, loot, progresión,
│                refugios, facciones, privacidad, interacción. Paridad bit a bit con la web.
├── data/        GameRepository + LocalRepository (offline) + SupabaseRepository + fábrica.
├── services/    Ubicación: GPS real (geolocator) y simulación.
├── state/       AppState (motor: conecta ubicación, mundo, jugador y persistencia),
│                WorldController (spawns + escáner), LocationController, UiController.
├── map/         Mapa MapLibre: estilo oscuro, capas, íconos, ubicación sobre calles.
├── combat/      Escena Flame, manifiesto de sprites, puntería y secuencia de turnos.
├── content/     Lore del Archivo.
└── ui/          Tema SUTURA, widgets (paneles con esquinas en L, botones con chaflán, ECG,
                 hexágonos), pantallas y navegación.
```

- **Estado**: `ChangeNotifier` + `ListenableBuilder` sobre un `AppState` global; cada pantalla
  escucha solo los controladores que necesita.
- **Mundo determinístico**: la misma celda y ventana de tiempo generan los mismos spawns en todos
  los dispositivos (mulberry32 + FNV-1a), lo que permite validarlos en el servidor.

## Tests

```bash
flutter analyze
flutter test
```

Incluye la lógica del núcleo (con fixtures generados desde la versión TypeScript para comprobar
paridad), balance de combate por Monte Carlo, el repositorio local, el mapeo de Supabase, la
puntería del combate y la grilla del maletín.

## Assets

- `assets/combat/`: sprites de los cinco tipos de infectado (idle, ataque, impacto, muerte y
  especiales), fondos y retrato, renderizados desde los modelos low-poly de la versión web.
  `manifest.json` describe cuadros, fps y ubicación sobre el fondo.
- `assets/fonts/`: tipografías con licencia OFL.
- Mapa: teselas vectoriales de [OpenFreeMap](https://openfreemap.org) (datos © OpenStreetMap).
