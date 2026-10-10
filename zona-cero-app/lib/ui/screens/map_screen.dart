import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../map/game_map.dart';
import '../../map/widgets/hud.dart';
import '../../map/widgets/joystick.dart';
import '../../map/widgets/pointer_shield.dart';
import '../../map/widgets/scan_button.dart';
import '../../map/widgets/target_panel.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../theme/tokens.dart';
import '../widgets/toast_feed.dart';
import '../widgets/weapon_panel.dart';

/// Pantalla principal: mapa de exploración con el HUD de la terminal VITA-7.
///
/// - Arriba: logo, tarjeta de estado (modo, hora, clima y ciudad), objetivo
///   actual (tocar = ir al objetivo), brújula y feed de avisos.
/// - Derecha: escáner (mantener y soltar), zoom y volver a mi posición.
/// - Abajo: región y escala; paneles ESTADO y ARMA EQUIPADA.
/// - Al seleccionar un marcador, su ficha reemplaza la fila inferior.
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
  static const _panelH = 96.0;
  static const _bottomGap = 10.0;

  /// Distancia desde abajo hasta el pie del mapa (región y escala).
  static const _captionBottom = _bottomGap + _panelH + 14;

  final _camera = GameMapController();
  late final _hud = MapHudModel(_camera);

  /// Texto de la última señal respondida (se muestra hasta cerrarlo).
  final _transmission = ValueNotifier<String?>(null);

  // El mapa se construye una sola vez: el resto del HUD se reconstruye solo.
  late final Widget _map = GameMap(controller: _camera);

  @override
  void dispose() {
    _hud.dispose();
    _camera.dispose();
    _transmission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: Sutura.map,
      child: Stack(
        children: [
          Positioned.fill(child: _map),
          // Degradés para leer el HUD sobre el mapa.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: pad.top + 210,
            child: const IgnorePointer(child: _Scrim(top: true)),
          ),
          const Positioned(bottom: 0, left: 0, right: 0, height: 300, child: IgnorePointer(child: _Scrim(top: false))),
          // Arriba: encabezado, objetivo, brújula y avisos.
          Positioned(
            top: pad.top + 12,
            left: 16,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MapHeader(model: _hud),
                const SizedBox(height: 10),
                SizedBox(
                  width: (width - 16 - 118).clamp(200.0, 420.0),
                  child: PointerShield(child: ObjectiveCard(camera: _camera)),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PointerShield(child: CompassButton(camera: _camera)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: IgnorePointer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SpeedLockBanner(),
                            const SizedBox(height: 4),
                            ToastFeed(ui: app.ui),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Controles del mapa (se ocultan con una ficha abierta).
          Positioned.fill(
            child: _MapControls(camera: _camera, hud: _hud, transmission: _transmission, captionBottom: _captionBottom),
          ),
          // Abajo: paneles, ficha del objetivo o transmisión recibida.
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
                  child = const _BottomHud(key: ValueKey('hud'), height: _panelH);
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
          const Positioned.fill(child: GnssSearchOverlay()),
        ],
      ),
    );
  }
}

/// Columna derecha (escáner, zoom, ubicar), pie del mapa y joystick. Solo se
/// reconstruye cuando cambia si hay ficha abierta o el modo simulación (no en
/// cada lectura de GPS).
class _MapControls extends StatefulWidget {
  const _MapControls({required this.camera, required this.hud, required this.transmission, required this.captionBottom});

  final GameMapController camera;
  final MapHudModel hud;
  final ValueNotifier<String?> transmission;
  final double captionBottom;

  @override
  State<_MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<_MapControls> {
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
    return AnimatedOpacity(
      opacity: _panel ? 0 : 1,
      duration: Sutura.fast,
      child: IgnorePointer(
        ignoring: _panel,
        child: Stack(
          children: [
            // Línea que separa el mapa de los paneles.
            Positioned(
              left: 0,
              right: 0,
              bottom: b - 7,
              height: 1,
              child: const IgnorePointer(child: ColoredBox(color: Color(0xFF2C2F32))),
            ),
            Positioned(
              left: 16,
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
                right: 14,
                bottom: b + 26 + 12,
                // Un solo escudo para toda la columna: en web cada escudo es una
                // vista de plataforma y CanvasKit admite pocas superficies.
                child: PointerShield(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ScanButton(),
                      const SizedBox(height: 12),
                      ZoomButtons(camera: widget.camera),
                      const SizedBox(height: 12),
                      LocateButton(camera: widget.camera),
                    ],
                  ),
                ),
              ),
            if (_demo && !_panel)
              Positioned(
                left: 14,
                bottom: b + 48,
                child: PointerShield(child: DemoJoystick(bearingOf: () => widget.camera.bearing)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomHud extends StatelessWidget {
  const _BottomHud({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return PointerShield(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: StatusPanel(height: height)),
          const SizedBox(width: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: app,
              builder: (context, _) {
                final p = app.player;
                return WeaponPanel(
                  weapon: p == null ? null : displayedWeapon(p.equipment),
                  ammo: p == null ? 0 : countOf(p.inventory, ItemId.ammo),
                  height: height,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: top
              ? [Sutura.void_.withValues(alpha: 0.88), Sutura.void_.withValues(alpha: 0.55), Sutura.void_.withValues(alpha: 0)]
              : [Sutura.void_.withValues(alpha: 0.94), Sutura.void_.withValues(alpha: 0.78), Sutura.void_.withValues(alpha: 0)],
          stops: top ? const [0, 0.45, 1] : const [0, 0.42, 1],
        ),
      ),
    );
  }
}
