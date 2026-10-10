# Zona Cero · Protocolo Sutura

Juego de supervivencia zombie con GPS para Android, hecho en **Flutter**. Caminás tu ciudad real
como un **Enlace** del Protocolo Sutura: escaneás la zona, recuperás suministros, enfrentás
infectados y reconstruís una red de nodos (refugios) junto a otros sobrevivientes.

Escenario inicial: **Buenos Aires** (simulación desde el Obelisco), pero funciona en cualquier
ciudad: el mundo se genera de forma determinística a partir de la ubicación.

> Estado: **v0.4 jugable**. Funciona completo sin backend (datos locales + comunidad simulada) y
> se conecta a **Supabase/PostGIS** si le pasás credenciales.

Esta app reemplaza a la versión web de `../zona-cero` (React + Three.js) con la misma lógica de
juego, portada a Dart y verificada contra la versión original con tests de paridad.

---

## Dirección de arte (v0.4): survival horror de calle

Panel de metal gastado, títulos condensados con desgaste y la ciudad real bajo la lluvia. IP propia
(sin marcas de terceros).

| Elemento | Decisión |
| --- | --- |
| Paleta | Fondo `#0A0B0C`; **rojo de emergencia** `#C8322B` para lo activo y lo hostil; **ámbar** `#D9A233` para recursos y entregas; **azul acero** `#8DB4C9` para la red, los refugios y la resistencia; verde ECG para la salud |
| Tipografía | Oswald (títulos, con textura de desgaste en dos capas: manchas + rayones), Barlow Condensed (interfaz, rótulos espaciados), Share Tech Mono (registros), Courier Prime (documentos), Special Elite (sellos). Todas OFL e incluidas |
| Paneles | Metal oscuro con textura, borde fino, marcas en las esquinas y esquinas cortadas a 45° |
| Encabezado | Logo ZONA CERO con el subtítulo de cada pestaña y una nota escrita a mano en un papelito |
| Maletín | Una valija de metal abierta: el equipo va en la tapa y el inventario en compartimentos de la base (la valija se estira según las filas) |
| Nodo | Foto del campamento a sangre, nivel en verde, antena, recursos con barras finas, botón ámbar pintado y bitácora con íconos |
| Mapa | Estilo "foto aérea" nocturna (texturas de techos y copas de árboles sobre teselas vectoriales), marcadores con tallo y rótulo (SAQUEO, REFUGIO, SEÑAL DE AUXILIO, infectados), zonas infectadas como resplandor rojo, clima real |
| Combate | Criaturas en alta definición animadas en tiempo real (ver abajo) sobre una calle de Buenos Aires con el Obelisco |

### Arte HD y cómo se animan los monstruos

El arte (5 criaturas, 18 objetos, fondos, retrato y texturas) se generó con modelos de imagen y se
recortó con BiRefNet; está en `assets/art/` (≈3 MB en WebP).

Cada criatura es **una sola imagen HD** que se anima como una marioneta: se dibuja sobre una malla
de 11×17 vértices (`Canvas.drawVertices`) que se deforma cada cuadro. Así respira, se balancea,
gira la cabeza, embiste hacia la cámara (con estelas de movimiento), acusa los golpes (abolladura +
destello), grita (Chillón), se agacha para cargar (Bruto), suelta gas (Hinchado) y cae al morir
(se disuelve en ceniza). La zona de la cabeza se detecta sola a partir del recorte, para la
puntería. Se eligió este enfoque frente a 3D en tiempo real porque da calidad de ilustración con
un costo bajo en celulares de gama media (ver `lib/combat/puppet.dart` y `cutout_rig.dart`).

**Relieve (v0.4).** Para que no se vean "de papel", cada criatura tiene un mapa de profundidad
(Depth Anything V2) del que salen sus normales: la luz de borde roja de la baliza, la luz fría del
otro lado y el fogonazo de los disparos siguen la forma del cuerpo, y la malla gira con paralaje
(las manos y la cabeza se desplazan más que el torso). Los mapas están en
`assets/art/zombies/relief/` y se regeneran con `tool/art/relief.py`.

## Cómo se juega

1. **Arranque**: elegí *Conectar GPS* (jugás caminando) o *Simulación · Buenos Aires*.
2. **Mapa**: mantené el botón hexagonal para **escanear** (cada 45 s). Aparecen infectados
   (rombos rojos), suministros (cuadros ámbar) y nodos (hexágonos).
3. Acercate a menos de **40 m** (más tolerancia por la precisión del GPS) y tocá el objetivo:
   - **Recuperar** un suministro (cuesta resistencia, llena el maletín).
   - **Responder** una **señal de auxilio** (siempre visible en el mapa): botín y transmisiones
     nuevas en el Archivo.
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

- `assets/art/zombies/`: las cinco criaturas recortadas (WebP con transparencia).
- `assets/art/items/`: fotos de los 18 objetos (256×256).
- `assets/art/bg/`: calles del combate (Obelisco, Teatro Colón), campamentos de nodo, valija del maletín, retrato del enlace.
- `assets/art/fp/`: manos en primera persona para el combate.
- `assets/art/avatars/`: retratos de las criaturas para el mapa.
- `assets/art/zombies/relief/`: luz por forma y profundidad de cada criatura.
- `assets/art/tex/`: texturas de paneles, desgaste de títulos y del mapa (techos y árboles).
- `assets/fonts/`: tipografías con licencia OFL.
- Mapa: teselas vectoriales de [OpenFreeMap](https://openfreemap.org) (datos © OpenStreetMap).
- Clima: [Open-Meteo](https://open-meteo.com) con coordenadas redondeadas a 0,1° (privacidad).
