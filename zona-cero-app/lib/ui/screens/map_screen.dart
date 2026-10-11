import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../../map/game_map.dart';
import '../../map/widgets/event_feed.dart';
import '../../map/widgets/hud.dart';
import '../../map/widgets/joystick.dart';
import '../../map/widgets/pointer_shield.dart';
import '../../map/widgets/scan_button.dart';
import '../../map/widgets/scan_wave.dart';
import '../../map/widgets/target_panel.dart';
import '../../map/widgets/vitals_panel.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../theme/tokens.dart';
import '../widgets/toast_feed.dart';

/// Pantalla principal: mapa satelital de exploración con el HUD de la
/// terminal VITA-7.
///
/// - Arriba: logo, tarjeta de estado (ciudad, modo, hora, día y clima),
///   objetivo actual a todo el ancho (tocar = ir al objetivo), indicador de
///   norte y feeds de avisos (juego y ambiente).
/// - Derecha: ubicar, zoom y escáner (mantener y soltar).
/// - Abajo: emblema y región, escala y créditos; panel SIGNOS VITALES | ARMA
///   EQUIPADA. Al seleccionar un marcador, su ficha reemplaza el panel.
/// - El pulso del escáner es una onda de choque que distorsiona el mapa.
/// - Modo simulación: joystick chico y mantener presionado el mapa para saltar.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.onOpenEncounter, required this.onOpenNode});

  /// Se llama cuando `app.engage` aceptó el encuentro (abrir la pantalla de combate).
  final void Function() onOpenEncounter;

  /// Abrir la pantalla del nodo (refugio) con ese id.
  final void Function(String shelterId) onOpenNode;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _panelH = 78.0;
  static const _bottomGap = 10.0;

  /// Distancia desde abajo hasta el pie del mapa (emblema, escala y créditos).
  static const _captionBottom = _bottomGap + _panelH + 18;

  final _camera = GameMapController();
  late final _hud = MapHudModel(_camera);

  /// Texto de la última señal respondida (se muestra hasta cerrarlo).
  final _transmission = ValueNotifier<String?>(null);

  /// Sacudón de la vista al disparar el escáner.
  final _shake = ValueNotifier<Offset>(Offset.zero);

  // El mapa se construye una sola vez: el resto del HUD se reconstruye solo.
  late final Widget _map = GameMap(controller: _camera);

  ValueListenable<TickerModeData>? _tickerMode;
  bool? _visible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_syncAmbience);
      _tickerMode = mode..addListener(_syncAmbience);
      _syncAmbience();
    }
  }

  /// Ambiente de ciudad mientras el mapa está a la vista. Al pasar a otra
  /// pestaña se apaga; si lo tapa una pantalla (combate, nodo) no se toca: esa
  /// pantalla pone el suyo.
  void _syncAmbience() {
    final visible = _tickerMode?.value.enabled ?? true;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      Sfx.ambience(Ambience.map);
    } else if (app.ui.tab != 0 && app.combat == null) {
      Sfx.ambience(null);
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_syncAmbience);
    _hud.dispose();
    _camera.dispose();
    _transmission.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Sutura.map,
      child: Stack(
        children: [
          // Mapa y onda del escáner (los dos se sacuden con el pulso).
          Positioned.fill(
            child: ValueListenableBuilder<Offset>(
              valueListenable: _shake,
              builder: (context, o, child) => Transform.translate(offset: o, child: child),
              child: Stack(
                children: [
                  Positioned.fill(child: _map),
                  Positioned.fill(
                    child: ScanWave(camera: _camera, shake: _shake),
                  ),
                ],
              ),
            ),
          ),
          // Viñeta y polvo sobre la imagen (como una foto vieja de la terminal).
          const Positioned.fill(child: IgnorePointer(child: _MapGrain())),
          // Degradés: el encabezado y el panel inferior quedan sobre fondo oscuro.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: pad.top + 150,
            child: IgnorePointer(child: _Scrim(top: true, solidUntil: (pad.top + 66) / (pad.top + 150))),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _captionBottom + 70,
            child: IgnorePointer(child: _Scrim(top: false, solidUntil: (_captionBottom - 16) / (_captionBottom + 70))),
          ),
          // Arriba: encabezado y línea.
          Positioned(
            top: pad.top + 10,
            left: 16,
            right: 6,
            child: MapHeader(model: _hud),
          ),
          Positioned(
            top: pad.top + 68,
            left: 0,
            right: 0,
            height: 1,
            child: const IgnorePointer(child: ColoredBox(color: Color(0xFF26292C))),
          ),
          // Objetivo actual, a todo el ancho.
          Positioned(
            top: pad.top + 76,
            left: 14,
            right: 12,
            child: PointerShield(child: ObjectiveCard(camera: _camera)),
          ),
          // Norte y avisos.
          Positioned(
            top: pad.top + 132,
            left: 10,
            right: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PointerShield(child: NorthIndicator(camera: _camera)),
                const SizedBox(width: 6),
                Expanded(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SpeedLockBanner(),
                          ToastFeed(ui: app.ui),
                          MapEventFeed(camera: _camera),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Controles del mapa (se ocultan con una ficha abierta).
          Positioned.fill(
            child: _MapControls(camera: _camera, hud: _hud, transmission: _transmission, captionBottom: _captionBottom, top: pad.top),
          ),
          // Abajo: panel, ficha del objetivo o transmisión recibida.
          Positioned(
            left: 12,
            right: 12,
            bottom: _bottomGap,
            child: ListenableBuilder(
              listenable: Listenable.merge([app.world, _transmission]),
              builder: (context, _) {
                final text = _transmission.value;
                final Widget child;
                if (text != null) {
                  child = PointerShield(
                    key: const ValueKey('transmission'),
                    child: TransmissionPanel(text: text, onClose: () => _transmission.value = null),
                  );
                } else if (hasTargetSelection()) {
                  child = PointerShield(
                    key: const ValueKey('target'),
                    child: TargetPanel(
                      onOpenEncounter: widget.onOpenEncounter,
                      onOpenNode: widget.onOpenNode,
                      onTransmission: (t) => _transmission.value = t,
                    ),
                  );
                } else {
                  child = const PointerShield(
                    key: ValueKey('hud'),
                    child: MapVitalsPanel(height: _panelH),
                  );
                }
                return AnimatedSwitcher(
                  duration: Sutura.base,
                  switchInCurve: Sutura.easeIn,
                  switchOutCurve: Sutura.easeOut,
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomCenter, children: [...previous, ?current]),
                  child: child,
                );
              },
            ),
          ),
          Positioned.fill(child: IntroCaption(camera: _camera)),
          const Positioned.fill(child: GnssSearchOverlay()),
        ],
      ),
    );
  }
}

/// Columna derecha (ubicar, zoom, escáner), pie del mapa y joystick. Solo se
/// reconstruye cuando cambia si hay ficha abierta o el modo simulación (no en
/// cada lectura de GPS).
class _MapControls extends StatefulWidget {
  const _MapControls({required this.camera, required this.hud, required this.transmission, required this.captionBottom, required this.top});

  final GameMapController camera;
  final MapHudModel hud;
  final ValueNotifier<String?> transmission;
  final double captionBottom;

  /// Margen superior del sistema.
  final double top;

  @override
  State<_MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<_MapControls> {
  static const _columnH = 42 + 10 + 89 + 12 + 60.0;

  bool _panel = false;
  bool _demo = false;

  @override
  void initState() {
    super.initState();
    app.world.addListener(_sync);
    app.location.addListener(_sync);
    widget.transmission.addListener(_sync);
    _read();
  }

  @override
  void dispose() {
    app.world.removeListener(_sync);
    app.location.removeListener(_sync);
    widget.transmission.removeListener(_sync);
    super.dispose();
  }

  bool _read() {
    final panel = widget.transmission.value != null || hasTargetSelection();
    final demo = app.location.mode == LocationMode.demo && app.location.demo != null;
    final changed = panel != _panel || demo != _demo;
    _panel = panel;
    _demo = demo;
    return changed;
  }

  void _sync() {
    if (mounted && _read()) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.captionBottom;
    return LayoutBuilder(
      builder: (context, c) {
        // Columna a la altura de la referencia (un tercio de la pantalla),
        // sin pisar el pie del mapa en pantallas bajas.
        final colTop = math.min(widget.top + 226, c.maxHeight - b - 56 - _columnH);
        return AnimatedOpacity(
          opacity: _panel ? 0 : 1,
          duration: Sutura.fast,
          child: IgnorePointer(
            ignoring: _panel,
            child: Stack(
              children: [
                // Línea que separa el mapa del panel inferior.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: b - 9,
                  height: 1,
                  child: const IgnorePointer(child: ColoredBox(color: Color(0xFF2A2D30))),
                ),
                Positioned(
                  left: 14,
                  bottom: b,
                  child: IgnorePointer(child: MapCaption(model: widget.hud)),
                ),
                Positioned(
                  right: 14,
                  bottom: b,
                  child: IgnorePointer(child: ScaleBar(camera: widget.camera)),
                ),
                // Sin ficha abierta: en web los escudos (aunque invisibles) taparían el mapa.
                if (!_panel)
                  Positioned(
                    right: 12,
                    top: colTop,
                    // Un solo escudo para toda la columna: en web cada escudo es una
                    // vista de plataforma y CanvasKit admite pocas superficies.
                    child: PointerShield(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LocateButton(camera: widget.camera),
                          const SizedBox(height: 10),
                          ZoomButtons(camera: widget.camera),
                          const SizedBox(height: 12),
                          const ScanButton(),
                        ],
                      ),
                    ),
                  ),
                if (_demo && !_panel)
                  Positioned(
                    left: 12,
                    bottom: b + 52,
                    child: PointerShield(child: DemoJoystick(bearingOf: () => widget.camera.bearing, size: 78)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Viñeta oscura en los bordes y una textura de manchas muy tenue: el mapa
/// se lee como una toma satelital gastada. Estática (se rasteriza una vez).
class _MapGrain extends StatelessWidget {
  const _MapGrain();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(image: AssetImage(Sutura.texMottle), repeat: ImageRepeat.repeat, opacity: 0.07, scale: 1.4),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(radius: 0.95, colors: [Color(0x00000000), Color(0x00000000), Color(0x8C050606)], stops: [0, 0.55, 1]),
          ),
        ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top, required this.solidUntil});
  final bool top;

  /// Fracción (desde el borde) que queda casi opaca.
  final double solidUntil;

  @override
  Widget build(BuildContext context) {
    final s = solidUntil.clamp(0.0, 0.95);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [const Color(0xFF0A0B0C), const Color(0xF20A0B0C), const Color(0x8C0A0B0C), const Color(0x000A0B0C)],
          stops: [0, s, s + (1 - s) * 0.4, 1],
        ),
      ),
    );
  }
}
