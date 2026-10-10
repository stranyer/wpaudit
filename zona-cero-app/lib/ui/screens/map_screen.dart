import 'package:flutter/material.dart';

import '../../map/game_map.dart';
import '../../map/widgets/hud.dart';
import '../../map/widgets/joystick.dart';
import '../../map/widgets/scan_button.dart';
import '../../map/widgets/target_panel.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../theme/tokens.dart';
import '../widgets/seg_bar.dart';
import '../widgets/toast_feed.dart';

/// Pantalla principal: el mapa de la ciudad con el HUD de la terminal VITA-7.
///
/// - Arriba a la izquierda: objetivo contextual y feed de avisos.
/// - Arriba a la derecha: estado de red, hora local y precisión GPS.
/// - Abajo: signos vitales, botón hexagonal del escáner y arma/munición.
/// - Al seleccionar un marcador, la ficha del objetivo reemplaza la fila inferior.
/// - Modo simulación: joystick y mantener presionado el mapa para saltar.
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
  final _camera = GameMapController();

  // El mapa se construye una sola vez: el resto del HUD se reconstruye solo.
  late final Widget _map = GameMap(controller: _camera);

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Sutura.map,
      child: Stack(
        children: [
          Positioned.fill(child: _map),
          // Viñetas para leer el HUD sobre el mapa.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: IgnorePointer(child: _Vignette(top: true)),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 230,
            child: IgnorePointer(child: _Vignette(top: false)),
          ),
          // Arriba a la izquierda: objetivo + avisos.
          Positioned(
            top: pad.top + 10,
            left: 14,
            right: 128,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const ObjectiveLine(),
                const SizedBox(height: 6),
                IgnorePointer(child: ToastFeed(ui: app.ui)),
              ],
            ),
          ),
          // Arriba a la derecha: red, hora y precisión.
          Positioned(top: pad.top + 10, right: 14, child: const StatusCluster()),
          // Bloqueo por velocidad.
          Positioned(top: pad.top + 62, left: 14, right: 14, child: const IgnorePointer(child: SpeedLockBanner())),
          // Abajo: HUD o ficha del objetivo.
          Positioned(
            left: 14,
            right: 14,
            bottom: pad.bottom + 12,
            child: ListenableBuilder(
              listenable: app.world,
              builder: (context, _) {
                final selected = app.world.selectedId != null &&
                    (app.world.spawnById(app.world.selectedId) != null || app.world.shelterById(app.world.selectedId) != null);
                return AnimatedSwitcher(
                  duration: Sutura.base,
                  switchInCurve: Sutura.easeIn,
                  switchOutCurve: Sutura.easeOut,
                  child: selected
                      ? TargetPanel(
                          key: const ValueKey('target'),
                          onOpenEncounter: widget.onOpenEncounter,
                          onOpenNode: widget.onOpenNode,
                        )
                      : const _BottomHud(key: ValueKey('hud')),
                );
              },
            ),
          ),
          // Controles de cámara y joystick (se ocultan con la ficha abierta).
          Positioned.fill(
            child: ListenableBuilder(
              listenable: Listenable.merge([app.world, app.location]),
              builder: (context, _) {
                final panel = app.world.selectedId != null;
                final demo = app.location.mode == LocationMode.demo && app.location.demo != null;
                return Stack(
                  children: [
                    if (!panel)
                      Positioned(right: 14, bottom: pad.bottom + 150, child: MapCameraButtons(camera: _camera)),
                    if (demo && !panel)
                      Positioned(
                        left: 14,
                        bottom: pad.bottom + 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const IgnorePointer(child: MicroText('SIM · MANTENÉ PRESIONADO EL MAPA PARA SALTAR')),
                            const SizedBox(height: 6),
                            DemoJoystick(bearingOf: () => _camera.bearing),
                          ],
                        ),
                      ),
                  ],
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

class _BottomHud extends StatelessWidget {
  const _BottomHud({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Align(alignment: Alignment.bottomLeft, child: VitalsPanel())),
        SizedBox(width: 6),
        ScanButton(),
        SizedBox(width: 6),
        Expanded(child: Align(alignment: Alignment.bottomRight, child: WeaponPanel())),
      ],
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [Sutura.void_.withValues(alpha: 0.72), Sutura.void_.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
