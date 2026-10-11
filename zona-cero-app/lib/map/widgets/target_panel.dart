import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../../state/signals.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/chamfer_button.dart';
import '../../ui/widgets/grit.dart';
import '../../ui/widgets/holo_in.dart';
import '../map_icons.dart';
import '../map_math.dart';

const threatLabels = ['Fácil', 'Parejo', 'Peligroso', 'Mortal'];
const threatColors = [Sutura.fine, Sutura.caution, Sutura.caution2, Sutura.danger];

const rarityLabels = {
  Rarity.common: 'Común',
  Rarity.uncommon: 'Poco común',
  Rarity.rare: 'Raro',
  Rarity.epic: 'Épico',
  Rarity.legendary: 'Legendario',
};

/// ¿Hay algo seleccionado que tenga ficha (contacto, suministro, nodo o señal)?
bool hasTargetSelection() {
  final w = app.world;
  final id = w.selectedId;
  return id != null && (w.spawnById(id) != null || w.shelterById(id) != null || w.signalById(id) != null);
}

/// Ficha del objetivo seleccionado en el mapa (contacto, suministro, nodo o
/// señal de auxilio). Devuelve un widget vacío si no hay selección.
class TargetPanel extends StatefulWidget {
  const TargetPanel({super.key, required this.onOpenEncounter, required this.onOpenNode, required this.onTransmission});

  final void Function() onOpenEncounter;
  final void Function(String shelterId) onOpenNode;

  /// Se respondió una señal: mostrar el texto de la transmisión.
  final void Function(String text) onTransmission;

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
        final w = app.world;
        final id = w.selectedId;
        final spawn = w.spawnById(id);
        final shelter = spawn == null ? w.shelterById(id) : null;
        final signal = spawn == null && shelter == null ? w.signalById(id) : null;
        final Widget? body = switch ((spawn, shelter, signal)) {
          (ZombieSpawn z, _, _) => _zombie(z),
          (SupplySpawn s, _, _) => _supply(s),
          (_, Shelter n, _) => _node(n),
          (_, _, DistressSignal s) => _signal(s),
          _ => null,
        };
        if (id == null || body == null) return const SizedBox.shrink();
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

  /// Igual que [_reach] pero con la posición actual del spawn (los infectados
  /// deambulan por su calle).
  ({double distance, double reachM, bool near, bool locked}) _reachSpawn(Spawn s) {
    final d = app.distanceToSpawn(s) ?? double.infinity;
    final r = effectiveRadius(gameConfig.interactionRules, app.location.accuracyM);
    return (distance: d, reachM: r, near: app.isNearSpawn(s), locked: app.location.speedLocked);
  }

  bool get _demo => app.location.mode == LocationMode.demo && app.location.demo != null;

  Widget _approachButtons(LatLng target, ({double distance, double reachM, bool near, bool locked}) r) {
    final left = (r.distance - r.reachM).ceil().clamp(1, 99999);
    return Row(
      children: [
        Expanded(
          // Fuera de alcance: el botón está apagado; tocarlo avisa con un error.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Sfx.play(SfxId.error, volume: 0.7),
            child: ChamferButton(
              label: 'Acercate ${distanceLabel(left.toDouble())}',
              sublabel: 'FUERA DE ALCANCE',
              expand: true,
              dense: true,
            ),
          ),
        ),
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
    final r = _reachSpawn(z);
    return _Frame(
      accent: Sutura.accent,
      kicker: 'CONTACTO HOSTIL',
      title: def.name,
      portrait: _Portrait(MapIcons.avatarAsset(z.zombieType)),
      chips: [
        _Chip(threatLabels[rating], threatColors[rating]),
        _Chip('Grado rec. ${def.recommendedLevel}', Sutura.textMid),
        _Chip(distanceLabel(r.distance), Sutura.textHi),
      ],
      description: def.description,
      actions: r.locked
          ? const _Locked()
          : r.near
          ? ChamferButton(
              label: 'Enfrentar',
              tone: ChamferTone.primary,
              icon: Icons.gps_fixed,
              expand: true,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      if (await app.engage(z)) {
                        widget.onOpenEncounter();
                      } else {
                        Sfx.play(SfxId.error);
                      }
                    }),
            )
          : _approachButtons(app.world.positionAt(z, DateTime.now().millisecondsSinceEpoch), r),
    );
  }

  Widget _supply(SupplySpawn s) {
    final def = supplyDefs[s.supplyType]!;
    final color = rarityColor(def.rarity.key);
    final r = _reachSpawn(s);
    final stamina = app.player?.stamina ?? 0;
    final enough = stamina >= def.staminaCost;
    return _Frame(
      accent: Sutura.amber,
      kicker: 'SAQUEO',
      title: def.name,
      chips: [
        _Chip(rarityLabels[def.rarity]!, color),
        _Chip('−${def.staminaCost} resistencia', enough ? Sutura.textMid : Sutura.caution2),
        _Chip(distanceLabel(r.distance), Sutura.textHi),
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
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      if (!enough) Sfx.play(SfxId.error);
                      await app.scavenge(s);
                    }),
            )
          : _approachButtons(s.position, r),
    );
  }

  Widget _node(Shelter n) {
    final own = n.ownerId == app.player?.id;
    final color = own ? Sutura.amber : Sutura.signal;
    final lv = shelterLevelDef(n.level);
    final r = _reach(n.position);
    final faction = n.factionId == null ? null : factionDefs[n.factionId]!.name;
    return _Frame(
      accent: color,
      kicker: own ? 'TU REFUGIO · RED DE RELEVO' : 'REFUGIO · NODO DE RELEVO',
      title: n.name,
      chips: [
        _Chip('Antena nv ${n.level}', color),
        _Chip(own ? 'Operador: vos' : 'Operador: ${n.ownerName}', Sutura.textMid),
        _Chip(distanceLabel(r.distance), Sutura.textHi),
      ],
      description: '${lv.name}${faction != null ? ' · $faction' : ''}',
      extra: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: BlockBar(ratio: n.level / maxShelterLevel, segments: maxShelterLevel * 3, color: color, height: 5, gap: 2),
      ),
      actions: Row(
        children: [
          Expanded(
            child: ChamferButton(
              label: 'Abrir nodo',
              tone: ChamferTone.neutral,
              icon: Icons.home_outlined,
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

  Widget _signal(DistressSignal s) {
    final r = _reach(s.position);
    final mins = ((s.expiresAt - DateTime.now().millisecondsSinceEpoch) / 60000).ceil().clamp(0, 999);
    return _Frame(
      accent: Sutura.amber,
      kicker: 'TRANSMISIÓN · CANAL ABIERTO',
      title: 'Señal de auxilio',
      chips: [_Chip('Se apaga en $mins min', Sutura.amber), _Chip(distanceLabel(r.distance), Sutura.textHi)],
      description: 'Alguien está transmitiendo desde acá. Respondé en el lugar para recuperar lo que dejaron.',
      actions: r.locked
          ? const _Locked()
          : r.near
          ? ChamferButton(
              label: 'Responder',
              tone: ChamferTone.amber,
              icon: Icons.settings_input_antenna,
              expand: true,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final text = await app.answerSignal(s);
                      if (text != null) {
                        widget.onTransmission(text);
                      } else {
                        Sfx.play(SfxId.error);
                      }
                    }),
            )
          : _approachButtons(s.position, r),
    );
  }
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
    this.portrait,
  });

  /// Retrato a la derecha del título (criaturas).
  final Widget? portrait;

  final Color accent;
  final String kicker;
  final String title;
  final List<Widget> chips;
  final String description;
  final Widget actions;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return GritPanel(
      accent: accent,
      background: const Color(0xF2111314),
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeader(kicker: kicker, color: accent),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(child: GrungeTitle(title, size: 28, maxLines: 1)),
                if (portrait != null) ...[const SizedBox(width: 10), portrait!],
              ],
            ),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: chips),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: SuturaText.bodyMid.copyWith(fontSize: 14.5)),
          ),
          ?extra,
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(right: 8), child: actions),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.kicker, required this.color, this.onClose});

  final String kicker;
  final Color color;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 7, height: 7, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            kicker,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SuturaText.label.copyWith(color: color, fontSize: 11, letterSpacing: 2.8),
          ),
        ),
        Semantics(
          button: true,
          label: 'Cerrar',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Sfx.play(SfxId.tap, volume: 0.6);
              (onClose ?? () => app.world.select(null))();
            },
            child: const SizedBox.square(dimension: 36, child: Icon(Icons.close, size: 19, color: Sutura.textMid)),
          ),
        ),
      ],
    );
  }
}

/// Retrato circular de la criatura con anillo rojo (como su marcador en el mapa).
class _Portrait extends StatelessWidget {
  const _Portrait(this.asset);
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: MapIcons.hostile, width: 1.6),
        boxShadow: const [BoxShadow(color: Color(0x80C8322B), blurRadius: 10)],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 7, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 11.5, color: color, letterSpacing: 1.6, height: 1.15)),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Sfx.play(SfxId.error, volume: 0.7),
    child: const ChamferButton(label: 'Interacciones en pausa', sublabel: 'VELOCIDAD EXCESIVA', icon: Icons.speed, expand: true),
  );
}

// -----------------------------------------------------------------------------
// Transmisión recibida (después de responder una señal)
// -----------------------------------------------------------------------------

/// El texto de la transmisión, tipeado sobre un papel.
class TransmissionPanel extends StatefulWidget {
  const TransmissionPanel({super.key, required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  State<TransmissionPanel> createState() => _TransmissionPanelState();
}

class _TransmissionPanelState extends State<TransmissionPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _type = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.text.length * 26).clamp(600, 4000)),
  )..forward();

  @override
  void dispose() {
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HoloIn(
      child: GritPanel(
        accent: Sutura.amber,
        background: const Color(0xF2111314),
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PanelHeader(kicker: 'TRANSMISIÓN RECIBIDA', color: Sutura.amber, onClose: widget.onClose),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: GestureDetector(
                onTap: () => _type.value = 1,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDCD5C2), Color(0xFFCBC2AA)],
                    ),
                    boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: AnimatedBuilder(
                    animation: _type,
                    builder: (context, _) {
                      final n = (widget.text.length * _type.value).round();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'FREC. 7.3 MHZ  ·  REGISTRO VITA-7',
                            style: SuturaText.paper.copyWith(
                              fontSize: 10.5,
                              letterSpacing: 1.4,
                              color: const Color(0xFF6B6250),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // El texto completo reserva el alto; el visible se tipea encima.
                          Stack(
                            children: [
                              Opacity(opacity: 0, child: Text(widget.text, style: _paperStyle)),
                              Text(widget.text.substring(0, n), style: _paperStyle),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SEÑAL RESPONDIDA  ·  +$signalXp XP',
                      style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 2, color: Sutura.amber),
                    ),
                  ),
                  ChamferButton(label: 'Cerrar', tone: ChamferTone.ghost, dense: true, height: 40, onPressed: widget.onClose),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _paperStyle = TextStyle(fontFamily: Sutura.fPaper, fontSize: 15, height: 1.5, color: Color(0xFF2A251D));
}
