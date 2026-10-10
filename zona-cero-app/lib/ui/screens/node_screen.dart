import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// Entrada de la bitácora de un nodo.
class NodeLogEntry {
  const NodeLogEntry(this.at, this.text, {this.mine = false});
  final int at;
  final String text;
  final bool mine;

  Map<String, dynamic> toJson() => {'a': at, 't': text, 'm': mine};
  static NodeLogEntry fromJson(Map j) => NodeLogEntry((j['a'] as num).toInt(), j['t'] as String, mine: j['m'] == true);
}

/// Eventos de otros enlaces derivados de los aportes del nodo (deterministas
/// por nodo y día), para que la bitácora de los nodos de la red no esté vacía.
List<NodeLogEntry> communityLog(Shelter s, int now) {
  final day = DateTime.fromMillisecondsSinceEpoch(now);
  final midnight = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
  final rng = createRng('nodelog:${s.id}:${now ~/ 86400000}');
  final out = <NodeLogEntry>[];
  final mats = [ItemId.wood, ItemId.metal, ItemId.food, ItemId.water];
  for (final c in s.contributions.take(4)) {
    final minutes = rng.intRange(30, math.max(31, (now - midnight) ~/ 60000));
    final at = midnight + minutes * 60000;
    if (at > now) continue;
    final what = mats[rng.intRange(0, mats.length - 1)];
    final verb = rng.chance(0.5) ? 'entregó' : 'dejó';
    out.add(NodeLogEntry(at, '${c.playerName} $verb ${rng.intRange(1, 8)} de ${itemName(what)}'));
  }
  if (rng.chance(0.7)) {
    out.add(NodeLogEntry(midnight + rng.intRange(10, 600) * 60000, 'Se registraron ${rng.intRange(2, 9)} pulsos en el nodo'));
  }
  return out.where((e) => e.at <= now).toList();
}

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

  void _addLog(String text) {
    _log = [NodeLogEntry(app.now, text, mine: true), ..._log].take(20).toList();
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
    if (given.isNotEmpty) _addLog('$_me entregó ${given.join(', ')}');
  }

  Future<void> _pulse(Shelter s) async {
    await app.sendPulse(s);
    _addLog('$_me dejó un pulso');
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
    _addLog('$_me: “${text.substring(0, math.min(90, text.length))}”');
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
    final heroH = 236 + pad.top;
    final events = [..._log, ...communityLog(s, app.now)]..sort((a, b) => b.at.compareTo(a.at));
    final canGiveAll = near && !_busy && remaining.keys.any((k) => countOf(p.inventory, k) > 0);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroH + 118,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: heroH + 50,
                  child: Image.asset(
                    'assets/art/bg/node_plaza.webp',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.1, -0.3),
                    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1A140C)),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: heroH + 52,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.22, 0.6, 1],
                        colors: [Color(0xCC0A0B0C), Color(0x220A0B0C), Color(0x990A0B0C), Sutura.void_],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: pad.top + 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      SquareIconButton(icon: Icons.arrow_back, size: 42, onPressed: () => Navigator.of(context).pop(), tooltip: 'Volver'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const GrungeTitle('Zona cero', size: 19, maxLines: 1),
                            Text('NODO · ${s.id.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: SuturaText.label.copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                      if (widget.onShowOnMap != null)
                        _OutlineAction(
                          icon: Icons.location_on_outlined,
                          label: 'Ver en el mapa',
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onShowOnMap!(s.id);
                          },
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 6,
                  child: HoloIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: const Color(0xCC0E1011), border: Border.all(color: own ? Sutura.amber : Sutura.lineBright)),
                              alignment: Alignment.center,
                              child: Text('${s.level}', style: SuturaText.number.copyWith(fontSize: 24, color: own ? Sutura.amber : Sutura.textHi)),
                            ),
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xCC0E1011),
                                border: Border.all(color: Sutura.lineStrong),
                              ),
                              alignment: Alignment.center,
                              child: Text(own ? 'TU REFUGIO' : 'REFUGIO', style: SuturaText.label.copyWith(fontSize: 13.5, color: Sutura.textHi, letterSpacing: 3)),
                            ),
                            const Spacer(),
                            StatusChip(
                              near ? 'En el nodo' : dist == null ? 'Sin señal' : 'A ${distanceLabel(dist)}',
                              color: near ? Sutura.signal : Sutura.textMid,
                              filled: near,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GrungeTitle(s.name, size: 36, maxLines: 2),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(width: 5, height: 13, color: factionColor(s.factionId)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${s.factionId == null ? 'Sin facción' : factionDefs[s.factionId]!.name}  ·  suturado por ${own ? 'vos' : s.ownerName}'.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SuturaText.label.copyWith(fontSize: 12, color: Sutura.textMid, letterSpacing: 2.2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(def.description, style: SuturaText.body.copyWith(fontSize: 15, color: Sutura.textHi.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, pad.bottom + 28),
          sliver: SliverList.list(
            children: [
              // ---- Pulsos ----
              GritPanel(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Image.asset('assets/art/bg/pulse_cup.webp', fit: BoxFit.cover, height: 72, errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                      Container(width: 1, color: Sutura.lineStrong),
                      const SizedBox(width: 12),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(border: Border.all(color: Sutura.lineStrong)),
                        child: const CustomPaint(painter: _EcgGlyph()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$pulses PULSOS', maxLines: 1, style: SuturaText.label.copyWith(fontSize: 15.5, color: Sutura.textHi, letterSpacing: 2.6)),
                            const SizedBox(height: 2),
                            Text('Enlaces que pasaron y dejaron señal.', maxLines: 2, style: SuturaText.bodyMid.copyWith(fontSize: 12, height: 1.15)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, left: 8),
                        child: ChamferButton(label: 'Pulso', icon: Icons.add, tone: ChamferTone.neutral, dense: true, height: 40, onPressed: () => _pulse(s)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ---- Antena ----
              GritPanel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cell_tower, size: 19, color: Sutura.textMid),
                        const SizedBox(width: 10),
                        Text('ANTENA', style: SuturaText.label.copyWith(fontSize: 15, color: Sutura.textHi, letterSpacing: 3)),
                        const Spacer(),
                        Text('NIVEL ${s.level}/$maxShelterLevel', style: SuturaText.label.copyWith(fontSize: 13.5, color: Sutura.amber, letterSpacing: 2.4)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, color: Sutura.lineHair),
                    const SizedBox(height: 14),
                    _LevelTrack(level: s.level),
                    const SizedBox(height: 14),
                    if (next == null)
                      Text('Antena al máximo. Este nodo es un faro para toda la red.', style: SuturaText.body.copyWith(color: Sutura.amber))
                    else ...[
                      Row(
                        children: [
                          Expanded(child: BlockBar(ratio: upgradeProgress(s), segments: 20, color: Sutura.amber, height: 6)),
                          const SizedBox(width: 12),
                          Text('${(upgradeProgress(s) * 100).round()} %', style: SuturaText.number.copyWith(fontSize: 15, color: Sutura.amber)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('PRÓXIMO:  ${shelterLevelDef(s.level + 1).name.toUpperCase()}', style: SuturaText.label.copyWith(fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 10),
                // ---- Recursos para mejorar ----
                GritPanel(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.build_outlined, size: 18, color: Sutura.textMid),
                          const SizedBox(width: 10),
                          Text('RECURSOS PARA MEJORAR', style: SuturaText.label.copyWith(fontSize: 14, color: Sutura.textHi, letterSpacing: 2.6)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(height: 1, color: Sutura.lineHair),
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ChamferButton(
                  label: near ? 'Entregar recursos' : 'Acercate para entregar',
                  icon: Icons.inventory_2_outlined,
                  tone: ChamferTone.amber,
                  expand: true,
                  height: 52,
                  onPressed: canGiveAll
                      ? () => _donate(s, {for (final e in remaining.entries) e.key: math.min(e.value, countOf(p.inventory, e.key))})
                      : null,
                ),
              ],
              const SizedBox(height: 10),
              // ---- Bitácora ----
              GritPanel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.description_outlined, size: 18, color: Sutura.textMid),
                        const SizedBox(width: 10),
                        Text('BITÁCORA', style: SuturaText.label.copyWith(fontSize: 15, color: Sutura.textHi, letterSpacing: 3)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _writing = !_writing),
                          child: Text(
                            _writing ? 'CERRAR' : 'ESCRIBIR',
                            style: SuturaText.label.copyWith(fontSize: 13, color: near ? Sutura.amber : Sutura.textLow),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF0E1011), border: Border.all(color: Sutura.lineHair)),
                      child: Column(
                        children: [
                          if (events.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('— sin registros —', style: SuturaText.mono.copyWith(color: Sutura.textLow)),
                            ),
                          for (final (i, e) in events.take(6).indexed) _LogRow(entry: e, first: i == 0),
                        ],
                      ),
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
                                      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Color(0xFF3A362C))),
                                      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Sutura.amber)),
                                      disabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Sutura.lineHair)),
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
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // ---- Beneficios y aportes ----
              GritPanel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('BENEFICIOS', style: SuturaText.label.copyWith(fontSize: 15, color: Sutura.textHi, letterSpacing: 3)),
                    const SizedBox(height: 6),
                    for (final perk in def.perks) _Perk(text: perk, active: true),
                    if (s.level < maxShelterLevel)
                      for (final perk in shelterLevelDef(s.level + 1).perks) _Perk(text: perk, active: false),
                    const SizedBox(height: 10),
                    Text('APORTES · ${s.contributions.length} ENLACES', style: SuturaText.label.copyWith(fontSize: 15, color: Sutura.textHi, letterSpacing: 3)),
                    const SizedBox(height: 4),
                    if (s.contributions.isEmpty)
                      Text('Todavía nadie aportó. Sé el primero.', style: SuturaText.bodyMid)
                    else
                      for (final (i, c) in s.contributions.take(6).indexed)
                        _ContributionRow(rank: i + 1, c: c, max: s.contributions.first.amount, me: c.playerId == p.id),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const FooterStrip(),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: const Color(0xCC0E1011), border: Border.all(color: Sutura.lineBright)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: Sutura.textHi),
            const SizedBox(width: 8),
            Text(label.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 13, color: Sutura.textHi, letterSpacing: 2)),
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

/// Pequeño trazo de ECG (ícono de pulsos).
class _EcgGlyph extends CustomPainter {
  const _EcgGlyph();

  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height / 2;
    final p = Path()
      ..moveTo(s.width * 0.12, y)
      ..lineTo(s.width * 0.36, y)
      ..lineTo(s.width * 0.44, y - s.height * 0.28)
      ..lineTo(s.width * 0.52, y + s.height * 0.26)
      ..lineTo(s.width * 0.6, y - s.height * 0.08)
      ..lineTo(s.width * 0.66, y)
      ..lineTo(s.width * 0.88, y);
    canvas.drawPath(p, Paint()
      ..color = Sutura.signal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_EcgGlyph oldDelegate) => false;
}

/// Cinco casilleros unidos por línea punteada: niveles de la antena.
class _LevelTrack extends StatelessWidget {
  const _LevelTrack({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: CustomPaint(
        painter: _TrackPainter(level),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= maxShelterLevel; i++)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: i == level ? const Color(0xFF2E2208) : const Color(0xFF131517),
                  border: Border.all(color: i <= level ? Sutura.amber : Sutura.lineStrong, width: i == level ? 1.8 : 1),
                  boxShadow: i == level ? const [BoxShadow(color: Color(0x55D9A233), blurRadius: 10)] : null,
                ),
                alignment: Alignment.center,
                child: Text('$i', style: SuturaText.number.copyWith(fontSize: 17, color: i <= level ? Sutura.amber : Sutura.textMid)),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.level);
  final int level;

  @override
  void paint(Canvas canvas, Size size) {
    final n = maxShelterLevel;
    const box = 34.0;
    final step = (size.width - box) / (n - 1);
    final y = size.height / 2;
    for (var i = 0; i < n - 1; i++) {
      final x0 = i * step + box + 4;
      final x1 = (i + 1) * step - 4;
      final p = Paint()
        ..color = i + 1 < level ? Sutura.amber : Sutura.lineStrong
        ..strokeWidth = 1.2;
      for (double x = x0; x < x1; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, x1), y), p);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.level != level;
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Sutura.lineHair))),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFF16181A), border: Border.all(color: Sutura.lineStrong)),
            padding: const EdgeInsets.all(4),
            child: ItemArt(id, size: 36, fallbackIcon: itemIcon(id)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(itemDefs[id]!.name, style: SuturaText.body.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: 0.6))),
                    Text('$given/$need', style: SuturaText.number.copyWith(fontSize: 15, color: left == 0 ? Sutura.fine : Sutura.textMid)),
                  ],
                ),
                const SizedBox(height: 6),
                BlockBar(ratio: need == 0 ? 1 : given / need, segments: 10, color: left == 0 ? Sutura.fine : Sutura.amber, height: 5, gap: 4),
                const SizedBox(height: 3),
                Text('TENÉS $have', style: SuturaText.label.copyWith(fontSize: 10.5, color: Sutura.textLow)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: left == 0
                ? const Center(child: Icon(Icons.check, color: Sutura.fine, size: 22))
                : ChamferButton(
                    label: give > 0 ? '+$give' : '—',
                    tone: ChamferTone.amber,
                    dense: true,
                    height: 36,
                    expand: true,
                    onPressed: enabled && give > 0 ? () => onGive(give) : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.first});

  final NodeLogEntry entry;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.fromMillisecondsSinceEpoch(entry.at);
    String two(int n) => n.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: Sutura.lineHair))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 52, child: Text('${two(d.hour)}:${two(d.minute)}', style: SuturaText.mono.copyWith(color: Sutura.textLow, fontSize: 12.5))),
          Expanded(
            child: Text(
              entry.text,
              style: SuturaText.mono.copyWith(fontSize: 12.5, color: entry.mine ? Sutura.amber : Sutura.textHi.withValues(alpha: 0.85), height: 1.3),
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
          Expanded(child: Text(text, style: SuturaText.bodyMid.copyWith(color: active ? Sutura.textHi : Sutura.textLow))),
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
          SizedBox(width: 28, child: Text(rank.toString().padLeft(2, '0'), style: SuturaText.number.copyWith(fontSize: 15, color: rank <= 3 ? Sutura.amber : Sutura.textLow))),
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
