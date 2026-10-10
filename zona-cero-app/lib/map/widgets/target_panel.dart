import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/brackets.dart';
import '../../ui/widgets/caps_title.dart';
import '../../ui/widgets/chamfer_button.dart';
import '../../ui/widgets/holo_in.dart';
import '../../ui/widgets/seg_bar.dart';

const threatLabels = ['Fácil', 'Parejo', 'Peligroso', 'Mortal'];
const threatColors = [Sutura.fine, Sutura.caution, Sutura.caution2, Sutura.danger];

const rarityLabels = {
  Rarity.common: 'Común',
  Rarity.uncommon: 'Poco común',
  Rarity.rare: 'Raro',
  Rarity.epic: 'Épico',
  Rarity.legendary: 'Legendario',
};

/// Ficha del objetivo seleccionado en el mapa (contacto, suministro o nodo).
/// Devuelve un widget vacío si no hay selección.
class TargetPanel extends StatefulWidget {
  const TargetPanel({super.key, required this.onOpenEncounter, required this.onOpenNode});

  final void Function() onOpenEncounter;
  final void Function(String shelterId) onOpenNode;

  @override
  State<TargetPanel> createState() => _TargetPanelState();
}

class _TargetPanelState extends State<TargetPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.world, app.location, app]),
      builder: (context, _) {
        final id = app.world.selectedId;
        final spawn = app.world.spawnById(id);
        final shelter = spawn == null ? app.world.shelterById(id) : null;
        final Widget body = switch ((spawn, shelter)) {
          (ZombieSpawn z, _) => _zombie(z),
          (SupplySpawn s, _) => _supply(s),
          (_, Shelter n) => _node(n),
          _ => const SizedBox.shrink(),
        };
        if (id == null || (spawn == null && shelter == null)) return const SizedBox.shrink();
        return HoloIn(key: ValueKey(id), child: body);
      },
    );
  }

  // ---------------------------------------------------------------------------

  ({double distance, double reachM, bool near, bool locked}) _reach(LatLng target) {
    final d = app.distanceTo(target) ?? double.infinity;
    final r = effectiveRadius(gameConfig.interactionRules, app.location.accuracyM);
    return (distance: d, reachM: r, near: app.isNear(target), locked: app.location.speedLocked);
  }

  bool get _demo => app.location.mode == LocationMode.demo && app.location.demo != null;

  Widget _approachButtons(LatLng target, ({double distance, double reachM, bool near, bool locked}) r) {
    final left = (r.distance - r.reachM).ceil().clamp(1, 99999);
    return Row(
      children: [
        Expanded(child: ChamferButton(label: 'Acercate ${_fmtM(left.toDouble())}', sublabel: 'FUERA DE ALCANCE', expand: true, dense: true)),
        if (_demo) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ChamferButton(
              label: 'Caminar',
              sublabel: 'HASTA ACÁ',
              tone: ChamferTone.ghost,
              icon: Icons.directions_walk,
              expand: true,
              dense: true,
              onPressed: () => app.location.demo?.walkTo(target, stopAtM: 25),
            ),
          ),
        ],
      ],
    );
  }

  Widget _zombie(ZombieSpawn z) {
    final def = zombieDefs[z.zombieType]!;
    final level = app.player?.level ?? 1;
    final rating = threatRating(def, level);
    final r = _reach(z.position);
    return _Frame(
      accent: Sutura.danger,
      kicker: 'CONTACTO HOSTIL',
      title: def.name,
      chips: [
        _Chip(threatLabels[rating].toUpperCase(), threatColors[rating]),
        _Chip('GRADO REC. ${def.recommendedLevel}', Sutura.textMid),
        _Chip(_fmtM(r.distance), Sutura.textHi, mono: true),
      ],
      description: def.description,
      actions: r.locked
          ? const _Locked()
          : r.near
              ? ChamferButton(
                  label: 'Enfrentar',
                  tone: ChamferTone.danger,
                  icon: Icons.gps_fixed,
                  expand: true,
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            if (await app.engage(z)) widget.onOpenEncounter();
                          }),
                )
              : _approachButtons(z.position, r),
    );
  }

  Widget _supply(SupplySpawn s) {
    final def = supplyDefs[s.supplyType]!;
    final color = rarityColor(def.rarity.key);
    final r = _reach(s.position);
    final stamina = app.player?.stamina ?? 0;
    final enough = stamina >= def.staminaCost;
    return _Frame(
      accent: def.rarity.index >= Rarity.epic.index ? color : Sutura.amber,
      kicker: 'SUMINISTRO',
      title: def.name,
      chips: [
        _Chip(rarityLabels[def.rarity]!.toUpperCase(), color),
        _Chip('−${def.staminaCost} RES', enough ? Sutura.textMid : Sutura.caution2),
        _Chip(_fmtM(r.distance), Sutura.textHi, mono: true),
      ],
      description: def.description,
      actions: r.locked
          ? const _Locked()
          : r.near
              ? ChamferButton(
                  label: 'Recuperar',
                  sublabel: enough ? null : 'RESISTENCIA INSUFICIENTE',
                  tone: ChamferTone.amber,
                  icon: Icons.inventory_2_outlined,
                  expand: true,
                  onPressed: _busy ? null : () => _run(() => app.scavenge(s)),
                )
              : _approachButtons(s.position, r),
    );
  }

  Widget _node(Shelter n) {
    final own = n.ownerId == app.player?.id;
    final lv = shelterLevelDef(n.level);
    final r = _reach(n.position);
    final faction = n.factionId == null ? null : factionDefs[n.factionId]!.name;
    return _Frame(
      accent: own ? Sutura.amber : Sutura.signal,
      kicker: own ? 'TU NODO · RED DE RELEVO' : 'NODO DE RELEVO',
      title: n.name,
      chips: [
        _Chip('ANTENA NV ${n.level}', own ? Sutura.amber : Sutura.signal),
        _Chip(own ? 'OPERADOR: VOS' : 'OPERADOR: ${n.ownerName.toUpperCase()}', Sutura.textMid),
        _Chip(_fmtM(r.distance), Sutura.textHi, mono: true),
      ],
      description: '${lv.name}${faction != null ? ' · $faction' : ''}',
      extra: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegBar(value: n.level.toDouble(), max: maxShelterLevel.toDouble(), segments: maxShelterLevel, color: own ? Sutura.amber : Sutura.signal, height: 4),
      ),
      actions: Row(
        children: [
          Expanded(
            child: ChamferButton(
              label: 'Abrir nodo',
              tone: ChamferTone.primary,
              icon: Icons.hexagon_outlined,
              expand: true,
              dense: true,
              onPressed: () => widget.onOpenNode(n.id),
            ),
          ),
          if (_demo && !r.near) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ChamferButton(
                label: 'Viajar',
                sublabel: '(SIMULACIÓN)',
                tone: ChamferTone.ghost,
                expand: true,
                dense: true,
                onPressed: () => app.demoTravel(n.position),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _fmtM(double m) {
  if (!m.isFinite) return '— M';
  if (m < 1000) return '${m.round()} M';
  return '${(m / 1000).toStringAsFixed(1).replaceFirst('.', ',')} KM';
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.accent,
    required this.kicker,
    required this.title,
    required this.chips,
    required this.description,
    required this.actions,
    this.extra,
  });

  final Color accent;
  final String kicker;
  final String title;
  final List<Widget> chips;
  final String description;
  final Widget actions;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return BracketPanel(
      color: accent,
      background: Sutura.surface1Solid.withValues(alpha: 0.94),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(kicker, style: SuturaText.micro.copyWith(color: accent, fontSize: 9.5, letterSpacing: 1.6)),
              ),
              Semantics(
                button: true,
                label: 'Cerrar',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => app.world.select(null),
                  child: const SizedBox.square(dimension: 32, child: Icon(Icons.close, size: 18, color: Sutura.textMid)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: CapsTitle(title, size: 19),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: chips),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: SuturaText.bodyMid.copyWith(fontSize: 13.5)),
          ),
          ?extra,
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(right: 6), child: actions),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color, {this.mono = false});
  final String text;
  final Color color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: mono
            ? SuturaText.mono.copyWith(fontSize: 11.5, color: color, height: 1.1)
            : SuturaText.caption.copyWith(fontSize: 11, color: color, letterSpacing: 1.2, height: 1.1),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) => const ChamferButton(
        label: 'Interacciones en pausa',
        sublabel: 'VELOCIDAD EXCESIVA',
        icon: Icons.speed,
        expand: true,
      );
}
