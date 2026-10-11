import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/grit.dart';
import '../widgets/holo_in.dart';
import '../widgets/item_glyph.dart';
import '../widgets/screen_frame.dart';

Color factionColor(FactionId? id) {
  if (id == null) return Sutura.textLow;
  final hex = factionDefs[id]!.color.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// Tipo de evento de la bitácora (define el ícono).
enum NodeLogKind { people, supply, signal, alert, note }

/// Entrada de la bitácora de un nodo.
class NodeLogEntry {
  const NodeLogEntry(this.at, this.text, {this.mine = false, this.kind = NodeLogKind.note});
  final int at;
  final String text;
  final bool mine;
  final NodeLogKind kind;

  Map<String, dynamic> toJson() => {'a': at, 't': text, 'm': mine, 'k': kind.name};
  static NodeLogEntry fromJson(Map j) =>
      NodeLogEntry((j['a'] as num).toInt(), j['t'] as String, mine: j['m'] == true, kind: NodeLogKind.values.asNameMap()[j['k']] ?? NodeLogKind.note);
}

const _zonesOf = ['Oeste', 'Sur', 'Norte', 'Este'];
const _streets = ['Av. Corrientes', 'Av. de Mayo', 'Tucumán', 'Av. Callao', 'Viamonte', 'Av. 9 de Julio'];

/// Eventos de otros enlaces derivados de los aportes del nodo (deterministas
/// por nodo y día), para que la bitácora de los nodos de la red no esté vacía.
List<NodeLogEntry> communityLog(Shelter s, int now) {
  final today = DateTime.fromMillisecondsSinceEpoch(now);
  // Ayer y hoy: los horarios son fijos para cada día y se muestran los que ya
  // pasaron (así la bitácora no queda vacía apenas pasada la medianoche).
  final out = <NodeLogEntry>[
    for (final d in [today.subtract(const Duration(days: 1)), today]) ..._dayLog(s, DateTime(d.year, d.month, d.day)),
  ];
  return out.where((e) => e.at <= now).toList();
}

List<NodeLogEntry> _dayLog(Shelter s, DateTime day) {
  final midnight = day.millisecondsSinceEpoch;
  final rng = createRng('nodelog:${s.id}:${day.year}-${day.month}-${day.day}');
  int at() => midnight + rng.intRange(20, 1430) * 60000;
  final out = <NodeLogEntry>[];
  final mats = [ItemId.wood, ItemId.metal, ItemId.food, ItemId.water];
  for (final c in s.contributions.take(4)) {
    final what = mats[rng.intRange(0, mats.length - 1)];
    if (rng.chance(0.3)) {
      out.add(NodeLogEntry(at(), '${c.playerName} reforzó la seguridad del nodo.', kind: NodeLogKind.people));
    } else {
      out.add(
        NodeLogEntry(at(), '${c.playerName} ${rng.chance(0.5) ? 'entregó' : 'dejó'} ${rng.intRange(1, 8)} de ${itemName(what)}.', kind: NodeLogKind.supply),
      );
    }
  }
  if (rng.chance(0.55)) out.add(NodeLogEntry(at(), 'Llega una donación de ${itemName(mats[rng.intRange(0, 3)]).toLowerCase()}.', kind: NodeLogKind.supply));
  if (rng.chance(0.6)) out.add(NodeLogEntry(at(), 'Se restableció la señal. Zona ${_zonesOf[rng.intRange(0, 3)]} conectada.', kind: NodeLogKind.signal));
  if (rng.chance(0.6)) out.add(NodeLogEntry(at(), 'Se reportan movimientos en ${_streets[rng.intRange(0, _streets.length - 1)]}.', kind: NodeLogKind.alert));
  if (rng.chance(0.7)) out.add(NodeLogEntry(at(), 'Se registraron ${rng.intRange(2, 9)} pulsos en el nodo.', kind: NodeLogKind.people));
  return out;
}

const _mottos = [
  'Acá la gente se cuida entre gente.',
  'Nadie se queda afuera.',
  'La radio no se apaga.',
  'Si llegaste hasta acá, ya sos parte.',
  'La fogata no se apaga.',
];

/// Pantalla de un NODO (refugio comunitario): antena, recursos, pulsos y bitácora.
class NodeScreen extends StatefulWidget {
  const NodeScreen({super.key, required this.shelterId, this.onShowOnMap});

  final String shelterId;

  /// Muestra el nodo en el mapa (cierra esta pantalla).
  final void Function(String shelterId)? onShowOnMap;

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  final _line = TextEditingController();
  List<NodeLogEntry> _log = [];
  bool _busy = false;
  bool _writing = false;
  bool _allLog = false;

  String get _logKey => 'zc:log:${widget.shelterId}';

  @override
  void initState() {
    super.initState();
    _log = app.store.readJson(_logKey, (j) => [for (final e in (j as List).cast<Map>()) NodeLogEntry.fromJson(e)]) ?? [];
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  void _addLog(String text, NodeLogKind kind) {
    _log = [NodeLogEntry(app.now, text, mine: true, kind: kind), ..._log].take(20).toList();
    unawaited(app.store.writeJson(_logKey, [for (final e in _log) e.toJson()]));
    if (mounted) setState(() {});
  }

  String get _me => app.player?.name ?? 'Vos';

  Future<void> _donate(Shelter s, Inventory offer) async {
    final before = Map<ItemId, int>.from(app.player!.inventory);
    setState(() => _busy = true);
    await app.donate(s, offer);
    if (!mounted) return;
    setState(() => _busy = false);
    final after = app.player!.inventory;
    final given = [
      for (final id in offer.keys)
        if ((before[id] ?? 0) - (after[id] ?? 0) > 0) '${(before[id] ?? 0) - (after[id] ?? 0)} de ${itemName(id)}',
    ];
    if (given.isNotEmpty) _addLog('$_me entregó ${given.join(', ')}.', NodeLogKind.supply);
  }

  Future<void> _pulse(Shelter s) async {
    await app.sendPulse(s);
    _addLog('$_me dejó un pulso.', NodeLogKind.people);
  }

  Future<void> _write(Shelter s) async {
    final text = _line.text.trim().isEmpty ? 'Sin novedades. La antena sigue en pie.' : _line.text.trim();
    setState(() => _busy = true);
    final ok = await app.logAndRest(s, text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _writing = false;
    });
    if (!ok) return;
    _line.clear();
    FocusScope.of(context).unfocus();
    _addLog('$_me: “${text.substring(0, math.min(90, text.length))}”', NodeLogKind.note);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sutura.void_,
      body: ListenableBuilder(
        listenable: Listenable.merge([app, app.world, app.location]),
        builder: (context, _) {
          final s = app.world.shelterById(widget.shelterId);
          if (s == null) return _Missing(onBack: () => Navigator.of(context).pop());
          return GritBackground(child: _body(context, s));
        },
      ),
    );
  }

  Widget _body(BuildContext context, Shelter s) {
    final pad = MediaQuery.paddingOf(context);
    final p = app.player!;
    final def = shelterLevelDef(s.level);
    final near = app.isNear(s.position);
    final dist = app.distanceTo(s.position);
    final own = s.ownerId == p.id;
    final remaining = remainingRequirements(s);
    final next = nextLevelRequirements(s.level);
    final pulses = app.pulsesOf(s);
    final events = [..._log, ...communityLog(s, app.now)]..sort((a, b) => b.at.compareTo(a.at));
    final canGiveAll = near && !_busy && remaining.keys.any((k) => countOf(p.inventory, k) > 0);
    final motto = _mottos[createRng('motto:${s.id}').intRange(0, _mottos.length - 1)];
    final heroH = 540 + pad.top;
    final topH = 382 + pad.top; // donde arrancan los pulsos, sobre el final de la foto
    final where = own
        ? 'TU REFUGIO'
        : near
        ? 'REFUGIO  ·  ESTÁS ACÁ'
        : dist == null
        ? 'REFUGIO'
        : 'REFUGIO  ·  A ${distanceLabel(dist).toUpperCase()}';

    return Stack(
      children: [
        // Foto del campamento a sangre, fundida al negro hacia abajo.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroH,
          child: Image.asset(
            'assets/art/bg/node_lavalle.webp',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.9),
            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1A140C)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroH + 1,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.14, 0.34, 0.6, 0.84, 1],
                colors: [Color(0xE60A0B0C), Color(0x800A0B0C), Color(0x260A0B0C), Color(0x1A0A0B0C), Color(0xCC0A0B0C), Sutura.void_],
              ),
            ),
          ),
        ),
        // Viñeta lateral para que el texto se lea sobre la foto.
        Positioned(
          left: 0,
          top: 0,
          width: 260,
          height: heroH * 0.5,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x990A0B0C), Color(0x000A0B0C)])),
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: topH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(6, pad.top + 6, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Volver',
                            icon: const Icon(Icons.chevron_left, size: 28, color: Sutura.textHi),
                          ),
                          Container(width: 1, height: 22, color: Sutura.lineStrong),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ZONA CERO  /  NODO · ${s.id.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 1.6, color: Sutura.textMid),
                            ),
                          ),
                          if (widget.onShowOnMap != null)
                            _OutlineAction(
                              icon: Icons.map_outlined,
                              label: 'Ver en el mapa',
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onShowOnMap!(s.id);
                              },
                            ),
                        ],
                      ),
                    ),
                    HoloIn(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _LevelBadge(level: s.level),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        where,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: SuturaText.label.copyWith(
                                          fontSize: 12.5,
                                          letterSpacing: 3.2,
                                          color: near || own ? Sutura.refuge : Sutura.textMid,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: GrungeTitle(s.name, size: 29, maxLines: 1)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${s.factionId == null ? 'Sin facción' : factionDefs[s.factionId]!.name} · suturado por ${own ? 'vos' : s.ownerName}.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SuturaText.body.copyWith(fontSize: 14, letterSpacing: 1.2, color: Sutura.textMid),
                            ),
                            const SizedBox(height: 10),
                            Container(width: 46, height: 1, color: Sutura.textMid),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: 260,
                              child: Text(
                                '“${def.description} $motto”',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: SuturaText.body.copyWith(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  letterSpacing: 0.4,
                                  color: Sutura.textHi.withValues(alpha: 0.88),
                                  shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, pad.bottom + 28),
              sliver: SliverList.list(
                children: [
                  // ---- Pulsos ----
                  Row(
                    children: [
                      const Icon(Icons.groups, size: 32, color: Color(0xFFB9B6AF)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '$pulses', style: SuturaText.number.copyWith(fontSize: 23)),
                                  TextSpan(
                                    text: '  ${pulses == 1 ? 'PULSO' : 'PULSOS'}',
                                    style: SuturaText.label.copyWith(fontSize: 16, color: Sutura.textHi, letterSpacing: 2.2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'GENTE ACTIVA EN EL NODO',
                              maxLines: 1,
                              style: SuturaText.label.copyWith(fontSize: 9.5, letterSpacing: 2.2, color: Sutura.textLow),
                            ),
                          ],
                        ),
                      ),
                      _OutlineAction(icon: Icons.add, label: 'Pulso', onTap: () => _pulse(s), big: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _Rule(),
                  // ---- Antena ----
                  SizedBox(
                    height: 72,
                    child: Row(
                      children: [
                        const Icon(Icons.cell_tower, size: 30, color: Color(0xFFB9B6AF)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ANTENA', style: SuturaText.label.copyWith(fontSize: 16, letterSpacing: 2.8, color: Sutura.textMid)),
                              const SizedBox(height: 3),
                              Text(
                                'MEJORA LA COBERTURA Y CONECTA NODOS.',
                                maxLines: 2,
                                style: SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 0.8, color: Sutura.textLow, height: 1.25),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 8), color: Sutura.lineStrong),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'NIVEL ',
                                    style: SuturaText.label.copyWith(fontSize: 10.5, color: Sutura.textHi, letterSpacing: 1.4),
                                  ),
                                  TextSpan(text: '${s.level}', style: SuturaText.number.copyWith(fontSize: 17)),
                                  TextSpan(
                                    text: ' / $maxShelterLevel',
                                    style: SuturaText.number.copyWith(fontSize: 13, color: Sutura.textMid),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            _LevelSegments(level: s.level),
                          ],
                        ),
                        const SizedBox(width: 8),
                        if (s.level < maxShelterLevel)
                          _NextBox(name: shelterLevelDef(s.level + 1).name, onTap: () => _showPerks(context, s))
                        else
                          Text('MÁXIMO', style: SuturaText.label.copyWith(color: Sutura.amber, fontSize: 12)),
                      ],
                    ),
                  ),
                  const _Rule(),
                  if (next != null) ...[
                    // ---- Recursos para el nodo ----
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('RECURSOS PARA EL NODO', style: SuturaText.label.copyWith(fontSize: 12.5, letterSpacing: 2.2, color: Sutura.textHi)),
                        const Spacer(),
                        Flexible(
                          flex: 0,
                          child: Text(
                            '—  EL ESFUERZO TAMBIÉN CONSTRUYE',
                            maxLines: 1,
                            style: SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 1.2, color: Sutura.textLow),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final e in entries(next))
                      _RequirementRow(
                        id: e.key,
                        given: math.min(e.value, s.progress[e.key] ?? 0),
                        need: e.value,
                        have: countOf(p.inventory, e.key),
                        left: remaining[e.key] ?? 0,
                        enabled: near && !_busy,
                        onGive: (n) => _donate(s, {e.key: n}),
                      ),
                    const SizedBox(height: 14),
                    _PaintedButton(
                      label: near ? 'Entregar recursos' : 'Acercate para entregar',
                      icon: Icons.inventory_2,
                      onPressed: canGiveAll
                          ? () => _donate(s, {for (final e in remaining.entries) e.key: math.min(e.value, countOf(p.inventory, e.key))})
                          : null,
                    ),
                    const SizedBox(height: 18),
                    const _Rule(),
                  ],
                  // ---- Bitácora ----
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('BITÁCORA', style: SuturaText.label.copyWith(fontSize: 13.5, letterSpacing: 2.8, color: Sutura.textHi)),
                      const Spacer(),
                      _TextAction(
                        label: _writing ? 'Cerrar' : 'Escribir',
                        color: near ? Sutura.amber : Sutura.textLow,
                        onTap: () => setState(() => _writing = !_writing),
                      ),
                      Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 10), color: Sutura.lineStrong),
                      _TextAction(label: _allLog ? 'Ver menos' : 'Ver todas', chevron: true, onTap: () => setState(() => _allLog = !_allLog)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (events.isEmpty) Text('— sin registros —', style: SuturaText.mono.copyWith(color: Sutura.textLow)),
                          for (final e in events.take(_allLog ? 20 : 4)) _LogRow(entry: e),
                          const SizedBox(height: 52),
                        ],
                      ),
                      const Positioned(right: 4, bottom: 2, child: HandNote('Mañana también\nse resiste', size: 14, angle: -0.16)),
                    ],
                  ),
                  AnimatedSize(
                    duration: Sutura.base,
                    child: !_writing
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _line,
                                  enabled: near && !_busy,
                                  maxLength: 140,
                                  cursorColor: Sutura.amber,
                                  style: SuturaText.paper.copyWith(fontSize: 14.5),
                                  decoration: InputDecoration(
                                    hintText: near ? 'Escribí una línea para la red…' : 'La bitácora solo se escribe dentro del nodo',
                                    hintStyle: SuturaText.paper.copyWith(fontSize: 14, color: Sutura.textPaper.withValues(alpha: 0.35)),
                                    counterText: '',
                                    filled: true,
                                    fillColor: const Color(0xFF14130F),
                                    prefixText: '> ',
                                    prefixStyle: SuturaText.paper.copyWith(color: Sutura.amber),
                                    enabledBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: Color(0xFF3A362C)),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: Sutura.amber),
                                    ),
                                    disabledBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: Sutura.lineHair),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ChamferButton(
                                  label: 'Guardar y descansar',
                                  sublabel: '+${def.restHealth} salud y resistencia · cada 10 min',
                                  icon: Icons.bedtime_outlined,
                                  tone: ChamferTone.neutral,
                                  expand: true,
                                  height: 56,
                                  onPressed: near && !_busy ? () => _write(s) : null,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  const _Rule(),
                  // ---- Beneficios y aportes ----
                  const SizedBox(height: 14),
                  Text('BENEFICIOS', style: SuturaText.label.copyWith(fontSize: 14, letterSpacing: 3, color: Sutura.textHi)),
                  const SizedBox(height: 6),
                  for (final perk in def.perks) _Perk(text: perk, active: true),
                  if (s.level < maxShelterLevel)
                    for (final perk in shelterLevelDef(s.level + 1).perks) _Perk(text: perk, active: false),
                  const SizedBox(height: 14),
                  Text('APORTES  ·  ${s.contributions.length} ENLACES', style: SuturaText.label.copyWith(fontSize: 14, letterSpacing: 3, color: Sutura.textHi)),
                  const SizedBox(height: 4),
                  if (s.contributions.isEmpty)
                    Text('Todavía nadie aportó. Sé el primero.', style: SuturaText.bodyMid)
                  else
                    for (final (i, c) in s.contributions.take(6).indexed)
                      _ContributionRow(rank: i + 1, c: c, max: s.contributions.first.amount, me: c.playerId == p.id),
                  const SizedBox(height: 18),
                  const FooterStrip(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPerks(BuildContext context, Shelter s) {
    final nextDef = shelterLevelDef(s.level + 1);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Sutura.void_.withValues(alpha: 0.7),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GritPanel(
            background: Sutura.surface1Solid,
            corners: Sutura.amber,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PRÓXIMO NIVEL · ${s.level + 1}', style: SuturaText.label.copyWith(color: Sutura.amber, fontSize: 12)),
                const SizedBox(height: 6),
                GrungeTitle(nextDef.name, size: 28),
                const SizedBox(height: 8),
                Text(nextDef.description, style: SuturaText.bodyMid),
                const SizedBox(height: 8),
                for (final perk in nextDef.perks) _Perk(text: perk, active: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Línea divisoria fina a lo ancho.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(height: 1, color: Sutura.lineHair);
}

/// Recuadro verde "NIVEL 1".
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 48,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: const Color(0xB30C140B),
        border: Border.all(color: Sutura.refuge.withValues(alpha: 0.9), width: 1.1),
        boxShadow: [BoxShadow(color: Sutura.refuge.withValues(alpha: 0.2), blurRadius: 10)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('NIVEL', style: SuturaText.label.copyWith(fontSize: 8, letterSpacing: 1, color: Sutura.refuge)),
          const SizedBox(height: 2),
          Text('$level', style: SuturaText.number.copyWith(fontSize: 22, color: Sutura.refuge)),
        ],
      ),
    );
  }
}

/// Barra de 5 tramos del nivel de la antena.
class _LevelSegments extends StatelessWidget {
  const _LevelSegments({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= maxShelterLevel; i++)
          Container(width: 14, height: 6, margin: const EdgeInsets.only(right: 2), color: i <= level ? const Color(0xFFF0C27A) : const Color(0xFF3A3D40)),
      ],
    );
  }
}

/// Recuadro "PRÓXIMO  Barricadas  >".
class _NextBox extends StatelessWidget {
  const _NextBox({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 96),
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0x99101214),
          border: Border.all(color: Sutura.lineBright, width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PRÓXIMO', style: SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 1.4)),
                  const SizedBox(height: 2),
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: SuturaText.body.copyWith(fontSize: 13, height: 1.05)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: Sutura.textHi),
          ],
        ),
      ),
    );
  }
}

/// Acción de texto ("VER TODAS >").
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap, this.color = Sutura.textMid, this.chevron = false});

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 12.5, letterSpacing: 2.2, color: color)),
            if (chevron) Icon(Icons.chevron_right, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

/// Botón ámbar "pintado" (textura de pintura gastada), como ENTREGAR RECURSOS.
class _PaintedButton extends StatelessWidget {
  const _PaintedButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final ink = on ? const Color(0xFF15120B) : const Color(0xFF17140D);
    return GestureDetector(
      onTap: on
          ? () {
              HapticFeedback.mediumImpact();
              onPressed!();
            }
          : null,
      child: SizedBox(
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: on ? const Color(0xFFD5A42F) : const Color(0xFF7A6838),
                boxShadow: on ? const [BoxShadow(color: Color(0x55D9A233), blurRadius: 14)] : null,
              ),
            ),
            // Pintura despareja: manchas oscuras y bordes comidos.
            Opacity(
              opacity: 0.55,
              child: Image.asset(
                Sutura.texMottle,
                fit: BoxFit.cover,
                color: const Color(0xFF6B4E12),
                colorBlendMode: BlendMode.modulate,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
            Opacity(
              opacity: 0.32,
              child: Image.asset(
                Sutura.texGrunge,
                fit: BoxFit.cover,
                color: const Color(0xFF0A0B0C),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  const Spacer(),
                  Icon(icon, size: 24, color: ink),
                  const SizedBox(width: 14),
                  Flexible(
                    flex: 8,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w600, fontSize: 19, letterSpacing: 3, color: ink),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 28, color: ink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.icon, required this.label, required this.onTap, this.big = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: big ? 40 : 38,
        padding: EdgeInsets.symmetric(horizontal: big ? 18 : 10),
        decoration: BoxDecoration(
          color: const Color(0x990E1011),
          border: Border.all(color: Sutura.lineBright, width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: big ? 18 : 17, color: Sutura.textHi),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: SuturaText.label.copyWith(fontSize: big ? 15 : 11.5, color: Sutura.textHi, letterSpacing: big ? 2.4 : 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SquareIconButton(icon: Icons.arrow_back, onPressed: onBack),
            const Spacer(),
            const GrungeTitle('Nodo sin señal', size: 34),
            const SizedBox(height: 8),
            Text('Este nodo quedó fuera del alcance de la red. Acercate a la zona para volver a sincronizarlo.', style: SuturaText.bodyMid),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({
    required this.id,
    required this.given,
    required this.need,
    required this.have,
    required this.left,
    required this.enabled,
    required this.onGive,
  });

  final ItemId id;
  final int given;
  final int need;
  final int have;
  final int left;
  final bool enabled;
  final ValueChanged<int> onGive;

  @override
  Widget build(BuildContext context) {
    final give = math.min(have, left);
    final done = left == 0;
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sutura.lineHair)),
      ),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(itemIcon(id), size: 21, color: const Color(0xFFB9B6AF))),
          const SizedBox(width: 6),
          Expanded(
            flex: 11,
            child: Text(itemDefs[id]!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SuturaText.body.copyWith(fontSize: 14.5, letterSpacing: 0.5)),
          ),
          SizedBox(
            width: 52,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$given',
                    style: TextStyle(color: done ? Sutura.fine : Sutura.textHi),
                  ),
                  TextSpan(
                    text: ' / $need',
                    style: const TextStyle(fontSize: 12, color: Sutura.textMid),
                  ),
                ],
              ),
              style: SuturaText.number.copyWith(fontSize: 16),
            ),
          ),
          Expanded(
            flex: 9,
            child: Container(
              height: 8,
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF55595C), width: 0.8)),
              padding: const EdgeInsets.all(1.2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: need == 0 ? 1 : (given / need).clamp(0.0, 1.0),
                child: ColoredBox(color: done ? Sutura.fine : const Color(0xFFC9A15A)),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: done
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.check, color: Sutura.fine, size: 22),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled && give > 0 ? () => onGive(give) : null,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        give > 0 ? '+$give' : '—',
                        style: SuturaText.number.copyWith(
                          fontSize: 19,
                          color: give > 0 ? (enabled ? Sutura.amber : Sutura.amber.withValues(alpha: 0.55)) : Sutura.textLow,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final NodeLogEntry entry;

  static IconData iconOf(NodeLogKind k) => switch (k) {
    NodeLogKind.people => Icons.groups,
    NodeLogKind.supply => Icons.inventory_2_outlined,
    NodeLogKind.signal => Icons.cell_tower,
    NodeLogKind.alert => Icons.warning_amber_rounded,
    NodeLogKind.note => Icons.edit_note,
  };

  @override
  Widget build(BuildContext context) {
    final d = DateTime.fromMillisecondsSinceEpoch(entry.at);
    String two(int n) => n.toString().padLeft(2, '0');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${two(d.hour)}:${two(d.minute)}', style: SuturaText.mono.copyWith(color: Sutura.textLow, fontSize: 12)),
            ),
          ),
          Container(width: 1, color: Sutura.lineStrong),
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Icon(iconOf(entry.kind), size: 17, color: entry.kind == NodeLogKind.alert ? const Color(0xFFB9B6AF) : Sutura.textMid),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.text,
                style: SuturaText.body.copyWith(fontSize: 13, height: 1.25, letterSpacing: 0.5, color: entry.mine ? Sutura.amber : Sutura.textMid),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(active ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 18, color: active ? Sutura.amber : Sutura.textLow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: SuturaText.bodyMid.copyWith(color: active ? Sutura.textHi : Sutura.textLow)),
          ),
          if (!active) Text('PRÓXIMO NIVEL', style: SuturaText.label.copyWith(fontSize: 10, color: Sutura.textLow)),
        ],
      ),
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.rank, required this.c, required this.max, required this.me});

  final int rank;
  final ShelterContribution c;
  final int max;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(rank.toString().padLeft(2, '0'), style: SuturaText.number.copyWith(fontSize: 15, color: rank <= 3 ? Sutura.amber : Sutura.textLow)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me ? '${c.playerName} (vos)' : c.playerName, style: SuturaText.body.copyWith(fontSize: 15, color: me ? Sutura.amber : Sutura.textHi)),
                const SizedBox(height: 3),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: max <= 0 ? 0 : (c.amount / max).clamp(0.04, 1.0),
                  child: Container(height: 3, color: me ? Sutura.amber : Sutura.lineBright),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${c.amount}', style: SuturaText.number.copyWith(fontSize: 16, color: Sutura.textMid)),
        ],
      ),
    );
  }
}
