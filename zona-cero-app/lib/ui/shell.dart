import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../services/location/location_types.dart';
import '../state/location_controller.dart';
import '../state/ui_controller.dart';
import 'screens/archive_screen.dart';
import 'screens/case_screen.dart';
import 'screens/encounter_screen.dart';
import 'screens/map_screen.dart';
import 'screens/network_screen.dart';
import 'screens/node_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/tokens.dart';
import 'widgets/chamfer_button.dart';
import 'widgets/hexagon.dart';
import 'widgets/holo_in.dart';
import 'widgets/screen_frame.dart';
import 'widgets/seg_bar.dart';

/// Transición de pantallas: aparición holográfica rápida (sin deslizamientos).
Route<T> holoRoute<T>(Widget page, {bool opaque = true}) => PageRouteBuilder<T>(
      opaque: opaque,
      transitionDuration: Sutura.heavy,
      reverseTransitionDuration: Sutura.base,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final t = CurvedAnimation(parent: a, curve: Sutura.easeIn);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(scale: Tween(begin: 1.02, end: 1.0).animate(t), child: child),
        );
      },
    );

/// Estructura principal: cinco pestañas con el mapa siempre vivo (IndexedStack).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool _inEncounter = false;

  Future<void> _openEncounter() async {
    if (_inEncounter) return;
    _inEncounter = true;
    await Navigator.of(context).push(holoRoute<void>(const EncounterScreen()));
    _inEncounter = false;
    // Si la pantalla se cerró sin pasar por "volver al mapa", limpiar el combate.
    if (app.combat != null && app.outcome != null) app.leaveCombat();
  }

  void _openNode(String id) => Navigator.of(context).push(holoRoute<void>(NodeScreen(shelterId: id)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sutura.void_,
      resizeToAvoidBottomInset: false,
      body: ListenableBuilder(
        listenable: app.ui,
        builder: (context, _) {
          final tab = app.ui.tab;
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: tab,
                      children: [
                        MapScreen(onOpenEncounter: _openEncounter, onOpenNode: _openNode),
                        const CaseScreen(),
                        NetworkScreen(onOpenNode: _openNode),
                        const ArchiveScreen(),
                        const ProfileScreen(),
                      ],
                    ),
                  ),
                  _NavBar(index: tab, onTap: app.ui.goTab),
                ],
              ),
              if (tab == 0) const _GpsProblemBanner(),
              const _CelebrationLayer(),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de navegación
// ---------------------------------------------------------------------------

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _items = [
  _NavItem('Mapa', Icons.explore_outlined),
  _NavItem('Maletín', Icons.work_outline),
  _NavItem('Red', Icons.hub_outlined),
  _NavItem('Archivo', Icons.folder_open_outlined),
  _NavItem('Perfil', Icons.badge_outlined),
];

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final unread = app.ready ? app.unreadLore : 0;
        return Container(
          padding: EdgeInsets.only(bottom: bottom),
          decoration: const BoxDecoration(
            color: Color(0xF205070A),
            border: Border(top: BorderSide(color: Sutura.lineHair)),
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (final (i, it) in _items.indexed)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: it.label,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onTap(i);
                        },
                        child: _NavButton(item: it, active: i == index, badge: i == 3 ? unread : 0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.badge});

  final _NavItem item;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? Sutura.signal : Sutura.textLow;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Marca superior de la pestaña activa.
        Positioned(
          top: 0,
          child: AnimatedContainer(
            duration: Sutura.fast,
            curve: Sutura.easeIn,
            width: active ? 26 : 0,
            height: 2,
            color: Sutura.signal,
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon, size: 21, color: color),
                if (badge > 0)
                  Positioned(
                    right: -9,
                    top: -5,
                    child: CountDot(badge),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.label.toUpperCase(),
              style: SuturaText.mono.copyWith(fontSize: 9.5, letterSpacing: 1.4, color: color),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// GPS sin permiso / apagado
// ---------------------------------------------------------------------------

class _GpsProblemBanner extends StatelessWidget {
  const _GpsProblemBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        final loc = app.location;
        final err = loc.error;
        if (loc.mode != LocationMode.gps || loc.status != LocationStatus.error || err == null) return const SizedBox.shrink();
        return Positioned(
          left: 12,
          right: 12,
          bottom: 60 + MediaQuery.paddingOf(context).bottom + 96,
          child: HoloIn(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Sutura.surface1Solid,
                border: Border.all(color: Sutura.danger.withValues(alpha: 0.7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SIN SEÑAL GNSS', style: SuturaText.mono.copyWith(color: Sutura.danger, letterSpacing: 3)),
                  const SizedBox(height: 6),
                  Text(locationErrorMessages[err]!, style: SuturaText.bodyMid),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChamferButton(label: 'Reintentar', dense: true, expand: true, onPressed: () => app.start(LocationMode.gps)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChamferButton(
                          label: 'Simulación',
                          tone: ChamferTone.amber,
                          dense: true,
                          expand: true,
                          onPressed: () => app.start(LocationMode.demo),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Celebraciones (subida de grado, antena nueva)
// ---------------------------------------------------------------------------

class _CelebrationLayer extends StatefulWidget {
  const _CelebrationLayer();

  @override
  State<_CelebrationLayer> createState() => _CelebrationLayerState();
}

class _CelebrationLayerState extends State<_CelebrationLayer> {
  Celebration? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    app.ui.addListener(_onUi);
  }

  @override
  void dispose() {
    app.ui.removeListener(_onUi);
    _timer?.cancel();
    super.dispose();
  }

  void _onUi() {
    final c = app.ui.celebration;
    if (c == _shown) return;
    // En combate la pantalla de resultado ya muestra la subida de grado.
    if (c != null && app.combat != null) {
      scheduleMicrotask(() => app.ui.celebrate(null));
      return;
    }
    setState(() => _shown = c);
    _timer?.cancel();
    if (c != null) _timer = Timer(const Duration(milliseconds: 3200), _dismiss);
  }

  void _dismiss() {
    if (app.ui.celebration != null) app.ui.celebrate(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = _shown;
    if (c == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: GestureDetector(
        onTap: _dismiss,
        child: ColoredBox(
          color: const Color(0xC005070A),
          child: Center(
            child: HoloIn(
              key: ValueKey(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HexBadge(size: 86, glow: true, line: Sutura.signal, child: Icon(Icons.keyboard_double_arrow_up, color: Sutura.signal, size: 38)),
                    const SizedBox(height: 18),
                    Text(c.title, textAlign: TextAlign.center, style: SuturaText.display.copyWith(fontSize: 30, color: Sutura.signal, letterSpacing: 5)),
                    const SizedBox(height: 8),
                    Text(c.subtitle, textAlign: TextAlign.center, style: SuturaText.bodyMid),
                    const SizedBox(height: 18),
                    const MicroText('tocá para continuar'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
