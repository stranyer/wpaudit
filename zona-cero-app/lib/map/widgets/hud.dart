import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../services/location/location_types.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../../state/world_controller.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/brackets.dart';
import '../../ui/widgets/chamfer_button.dart';
import '../../ui/widgets/ecg_monitor.dart';
import '../../ui/widgets/hexagon.dart';
import '../../ui/widgets/holo_in.dart';
import '../../ui/widgets/seg_bar.dart';
import '../game_map.dart';

// -----------------------------------------------------------------------------
// Objetivo contextual
// -----------------------------------------------------------------------------

/// "OBJETIVO · Escaneá la zona", según lo que pasa en el mapa.
class ObjectiveLine extends StatelessWidget {
  const ObjectiveLine({super.key});

  static (String, Color) objective() {
    final pos = app.location.position;
    if (pos == null) return ('Buscando señal GNSS', Sutura.textMid);
    if (app.location.speedLocked) return ('Bajá la velocidad', Sutura.danger);
    final p = app.player;
    if (p != null && p.health / maxHealth(p) < 0.25) return ('Curate: signos vitales críticos', Sutura.caution2);
    final w = app.world;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sel = w.spawnById(w.selectedId);
    if (sel != null) {
      final d = app.distanceTo(sel.position) ?? 0;
      final near = app.isNear(sel.position);
      return switch (sel) {
        ZombieSpawn() => near ? ('Enfrentá al infectado', Sutura.danger) : ('Acercate al contacto · ${d.round()} m', Sutura.textHi),
        SupplySpawn() => near ? ('Recuperá el suministro', Sutura.amber) : ('Acercate al suministro · ${d.round()} m', Sutura.textHi),
      };
    }
    final node = w.shelterById(w.selectedId);
    if (node != null) {
      return app.isNear(node.position)
          ? ('Abrí el nodo de relevo', Sutura.signal)
          : ('Llegá al nodo · ${formatDistance(app.distanceTo(node.position) ?? 0)}', Sutura.textHi);
    }
    var visible = 0;
    var inReach = 0;
    for (final s in w.drawable) {
      if (w.visibilityOf(s, pos, now) == SpawnVisibility.hidden) continue;
      visible++;
      if (app.isNear(s.position)) inReach++;
    }
    if (inReach > 0) return ('Contacto al alcance · tocá el marcador', Sutura.signal);
    if (w.scanCooldownLeft(now) == 0) return ('Escaneá la zona', Sutura.signal);
    if (visible > 0) return ('Acercate a un contacto', Sutura.textHi);
    return ('Explorá: caminá para encontrar contactos', Sutura.textHi);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.world, app.location, app]),
      builder: (context, _) {
        final (text, color) = objective();
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          decoration: const BoxDecoration(
            color: Sutura.surface1,
            border: Border(left: BorderSide(color: Sutura.signal, width: 2)),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'OBJETIVO · ', style: SuturaText.mono.copyWith(fontSize: 10, letterSpacing: 1.4, color: Sutura.signal)),
              TextSpan(text: text, style: SuturaText.caption.copyWith(fontSize: 13, color: color, letterSpacing: 0.4)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Estado de red, hora y precisión
// -----------------------------------------------------------------------------

class StatusCluster extends StatefulWidget {
  const StatusCluster({super.key});

  @override
  State<StatusCluster> createState() => _StatusClusterState();
}

class _StatusClusterState extends State<StatusCluster> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        final loc = app.location;
        final (label, color, spacing) = switch (loc.mode) {
          LocationMode.demo => ('SIMULACIÓN', Sutura.amber, 1.6),
          _ when loc.position != null && loc.status != LocationStatus.error => ('EN LÍNEA', Sutura.signal, 1.6),
          _ => ('S I N  S E Ñ A L', Sutura.offline, 1.0),
        };
        final acc = loc.position == null ? '±— m' : '±${loc.accuracyM.round()} m';
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          color: Sutura.surface1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Blink(color: color, active: label != 'SIMULACIÓN'),
                  const SizedBox(width: 6),
                  Text(label, style: SuturaText.mono.copyWith(fontSize: 10.5, color: color, letterSpacing: spacing)),
                ],
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: hhmm, style: SuturaText.mono.copyWith(fontSize: 15, color: Sutura.textHi)),
                  TextSpan(text: '  $acc', style: SuturaText.mono.copyWith(fontSize: 10.5, color: Sutura.textMid)),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Blink extends StatefulWidget {
  const _Blink({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final on = !widget.active || _c.value < 0.6;
        return Container(width: 6, height: 6, color: widget.color.withValues(alpha: on ? 1 : 0.25));
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Signos vitales (abajo a la izquierda)
// -----------------------------------------------------------------------------

class VitalsPanel extends StatelessWidget {
  const VitalsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        if (p == null) return const SizedBox.shrink();
        final maxH = maxHealth(p);
        final ratio = (p.health / maxH).clamp(0.0, 1.0);
        final vital = vitalFor(ratio);
        final carried = carriedWeight(p.inventory) * 0.5;
        final cap = capacityOf(p) * 0.5;
        final heavy = carried >= cap * 0.9;
        return BracketPanel(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              EcgMonitor(ratio: ratio, width: 104, height: 24, showLabel: false),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(vitalLabel(vital), style: SuturaText.mono.copyWith(fontSize: 10, color: vitalColor(vital), letterSpacing: 1.2)),
                  const Spacer(),
                  Text('${p.health.round()}', style: SuturaText.mono.copyWith(fontSize: 12, color: Sutura.textHi)),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text('RES', style: SuturaText.micro.copyWith(fontSize: 8.5, color: Sutura.textMid)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SegBar(value: p.stamina, max: maxStamina(p).toDouble(), segments: 10, color: Sutura.signal, height: 4),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${carried.toStringAsFixed(1).replaceFirst('.', ',')} / ${cap.toStringAsFixed(1).replaceFirst('.', ',')} KG',
                style: SuturaText.mono.copyWith(fontSize: 10.5, color: heavy ? Sutura.caution2 : Sutura.textMid),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Arma y munición (abajo a la derecha)
// -----------------------------------------------------------------------------

class WeaponPanel extends StatelessWidget {
  const WeaponPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        if (p == null) return const SizedBox.shrink();
        final melee = p.equipment.melee;
        final firearm = p.equipment.firearm;
        final ammo = countOf(p.inventory, ItemId.ammo);
        return BracketPanel(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (melee != null ? itemDefs[melee]!.name : 'Puños').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SuturaText.caption.copyWith(fontSize: 11.5, color: Sutura.textHi, letterSpacing: 0.8),
              ),
              Text(
                (firearm != null ? itemDefs[firearm]!.name : 'Sin arma de fuego').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SuturaText.caption.copyWith(fontSize: 10.5, color: firearm != null ? Sutura.textMid : Sutura.textLow, letterSpacing: 0.8),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('MUNICIÓN', style: SuturaText.micro.copyWith(fontSize: 8.5, color: Sutura.textMid)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ammo.toString().padLeft(2, '0'),
                    style: SuturaText.mono.copyWith(
                      fontSize: 30,
                      height: 1,
                      color: ammo == 0 ? Sutura.danger : Sutura.textHi,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Botones de cámara
// -----------------------------------------------------------------------------

class MapSquareButton extends StatelessWidget {
  const MapSquareButton({super.key, required this.icon, required this.onTap, required this.label, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Sutura.signal : Sutura.textMid;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: CustomPaint(
            painter: ChamferPainter(
              fill: active ? Sutura.signal.withValues(alpha: 0.12) : Sutura.surface1,
              line: active ? Sutura.signal : Sutura.lineStrong,
              cut: 5,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

class MapCameraButtons extends StatelessWidget {
  const MapCameraButtons({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MapSquareButton(
            icon: Icons.my_location,
            label: 'Centrar en mi posición',
            active: camera.follow,
            onTap: camera.recenter,
          ),
          const SizedBox(height: 8),
          MapSquareButton(
            icon: Icons.threed_rotation,
            label: 'Alternar vista inclinada',
            active: camera.pitched,
            onTap: camera.togglePitch,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Bloqueo por velocidad
// -----------------------------------------------------------------------------

class SpeedLockBanner extends StatelessWidget {
  const SpeedLockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        if (!app.location.speedLocked) return const SizedBox.shrink();
        return HoloIn(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Sutura.danger.withValues(alpha: 0.16),
              border: Border.all(color: Sutura.danger.withValues(alpha: 0.8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.speed, size: 16, color: Sutura.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VELOCIDAD EXCESIVA · INTERACCIONES EN PAUSA',
                    style: SuturaText.mono.copyWith(fontSize: 10.5, color: Sutura.danger, letterSpacing: 1.2),
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

// -----------------------------------------------------------------------------
// Antes del primer fix
// -----------------------------------------------------------------------------

class GnssSearchOverlay extends StatefulWidget {
  const GnssSearchOverlay({super.key});

  @override
  State<GnssSearchOverlay> createState() => _GnssSearchOverlayState();
}

class _GnssSearchOverlayState extends State<GnssSearchOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    app.location.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    app.location.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  void _sync() {
    final searching = app.location.position == null;
    if (searching && !_c.isAnimating) _c.repeat();
    if (!searching && _c.isAnimating) _c.stop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        final loc = app.location;
        final searching = loc.position == null;
        return IgnorePointer(
          ignoring: !searching,
          child: AnimatedOpacity(
            opacity: searching ? 1 : 0,
            duration: Sutura.heavy,
            child: ColoredBox(
              color: Sutura.void_.withValues(alpha: 0.78),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 120,
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) => CustomPaint(painter: _SearchPainter(_c.value)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('BUSCANDO SEÑAL GNSS…', style: SuturaText.mono.copyWith(fontSize: 13, color: Sutura.signal, letterSpacing: 3)),
                    const SizedBox(height: 8),
                    if (loc.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          locationErrorMessages[loc.error]!,
                          textAlign: TextAlign.center,
                          style: SuturaText.bodyMid.copyWith(fontSize: 13),
                        ),
                      )
                    else
                      const MicroText('VITA-7 // TRIANGULANDO SATÉLITES'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchPainter extends CustomPainter {
  _SearchPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1.0;
      canvas.drawCircle(c, r * (0.25 + 0.75 * Sutura.scanCurve.transform(k)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Sutura.signal.withValues(alpha: (1 - k) * 0.7));
    }
    final hex = hexPath(c, 16);
    canvas.drawPath(hex, Paint()..color = Sutura.surface2);
    canvas.drawPath(hex, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Sutura.signal);
    final a = t * 2 * math.pi;
    canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r - 4), Paint()
      ..color = Sutura.signal.withValues(alpha: 0.5)
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_SearchPainter old) => old.t != t;
}
