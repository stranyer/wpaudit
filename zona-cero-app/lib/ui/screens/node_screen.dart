import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/caps_title.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/hexagon.dart';
import '../widgets/holo_in.dart';
import '../widgets/item_glyph.dart';
import '../widgets/screen_frame.dart';
import '../widgets/seg_bar.dart';

Color factionColor(FactionId? id) {
  if (id == null) return Sutura.textLow;
  final hex = factionDefs[id]!.color.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// Pantalla de un NODO (refugio comunitario): antena, bitácora, pulsos y aportes.
class NodeScreen extends StatefulWidget {
  const NodeScreen({super.key, required this.shelterId});

  final String shelterId;

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  final _line = TextEditingController();
  List<({String text, int at})> _log = [];
  String? _typing;
  int _typed = 0;
  Timer? _typer;
  bool _busy = false;

  String get _logKey => 'zc:log:${widget.shelterId}';

  @override
  void initState() {
    super.initState();
    _log = app.store.readJson(_logKey, (j) => [
              for (final e in (j as List).cast<Map>()) (text: e['t'] as String, at: (e['a'] as num).toInt()),
            ]) ??
        [];
  }

  @override
  void dispose() {
    _typer?.cancel();
    _line.dispose();
    super.dispose();
  }

  Future<void> _write(Shelter s) async {
    final text = _line.text.trim().isEmpty ? 'Sin novedades. La antena sigue en pie.' : _line.text.trim();
    setState(() => _busy = true);
    final ok = await app.logAndRest(s, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _line.clear();
    FocusScope.of(context).unfocus();
    final entry = (text: text.substring(0, math.min(140, text.length)), at: app.now);
    _log = [entry, ..._log].take(12).toList();
    unawaited(app.store.writeJson(_logKey, [for (final e in _log) {'t': e.text, 'a': e.at}]));
    // Efecto máquina de escribir sobre la última línea.
    _typer?.cancel();
    setState(() {
      _typing = entry.text;
      _typed = 0;
    });
    _typer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted) return t.cancel();
      setState(() => _typed++);
      if (_typed >= entry.text.length) {
        t.cancel();
        setState(() => _typing = null);
      }
    });
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
          return _body(context, s);
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 330 + pad.top,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/combat/bg_shelter.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                  errorBuilder: (_, _, _) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(0, 0.3), radius: 0.9, colors: [Color(0xFF3A2A14), Sutura.void_]),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.35, 0.78, 1],
                      colors: [Color(0xCC05070A), Color(0x0005070A), Color(0xB305070A), Sutura.void_],
                    ),
                  ),
                ),
                Positioned(
                  top: pad.top + 10,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: [
                      SquareIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop(), tooltip: 'Volver'),
                      const SizedBox(width: 12),
                      Expanded(child: MicroText('NODO · ${s.id.toUpperCase()}', color: Sutura.signal)),
                      StatusChip(near ? 'En el nodo' : dist == null ? 'Sin señal' : 'A ${distanceLabel(dist)}', color: near ? Sutura.signal : Sutura.textMid, filled: near),
                    ],
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: HoloIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            HexBadge(
                              size: 30,
                              line: own ? Sutura.amber : Sutura.signal,
                              glow: true,
                              child: Text('${s.level}', style: SuturaText.mono.copyWith(fontSize: 13, color: own ? Sutura.amber : Sutura.signal)),
                            ),
                            const SizedBox(width: 8),
                            Text(def.name.toUpperCase(), style: SuturaText.mono.copyWith(color: Sutura.amber, letterSpacing: 2, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CapsTitle(s.name, size: 26),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(width: 8, height: 8, color: factionColor(s.factionId)),
                            const SizedBox(width: 6),
                            Text(
                              '${s.factionId == null ? 'Sin facción' : factionDefs[s.factionId]!.name} · suturado por ${own ? 'vos' : s.ownerName}',
                              style: SuturaText.caption.copyWith(color: Sutura.textMid),
                            ),
                          ],
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
          padding: EdgeInsets.fromLTRB(18, 0, 18, pad.bottom + 28),
          sliver: SliverList.list(
            children: [
              Text(def.description, style: SuturaText.bodyMid),
              // ---- Pulsos ----
              const SizedBox(height: 14),
              BracketPanel(
                color: Sutura.signalDeep,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 18, color: Sutura.signal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$pulses PULSOS', style: SuturaText.mono.copyWith(fontSize: 15, color: Sutura.signal)),
                          Text('Enlaces que pasaron y dejaron señal', style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    ChamferButton(label: 'Pulso', icon: Icons.add, tone: ChamferTone.primary, dense: true, height: 38, onPressed: () => app.sendPulse(s)),
                  ],
                ),
              ),
              // ---- Antena ----
              SectionLabel('Antena', trailing: MicroText('nivel ${s.level}/$maxShelterLevel', color: Sutura.amber), color: Sutura.amber),
              _LevelTrack(level: s.level),
              const SizedBox(height: 14),
              if (next == null)
                Text('Antena al máximo. Este nodo es un faro para toda la red.', style: SuturaText.bodyMid.copyWith(color: Sutura.amber))
              else ...[
                Row(
                  children: [
                    Expanded(child: SegBar(value: upgradeProgress(s), max: 1, segments: 20, color: Sutura.amber, height: 6)),
                    const SizedBox(width: 10),
                    Text('${(upgradeProgress(s) * 100).round()} %', style: SuturaText.mono.copyWith(color: Sutura.amber)),
                  ],
                ),
                const SizedBox(height: 4),
                MicroText('próximo: ${shelterLevelDef(s.level + 1).name}'),
                const SizedBox(height: 10),
                for (final e in entries(next))
                  _RequirementRow(
                    id: e.key,
                    given: math.min(e.value, s.progress[e.key] ?? 0),
                    need: e.value,
                    have: countOf(p.inventory, e.key),
                    left: remaining[e.key] ?? 0,
                    enabled: near,
                    onGive: (n) => app.donate(s, {e.key: n}),
                  ),
                const SizedBox(height: 8),
                ChamferButton(
                  label: near ? 'Entregar todo lo posible' : 'Acercate para entregar',
                  icon: Icons.move_to_inbox_outlined,
                  tone: ChamferTone.amber,
                  expand: true,
                  onPressed: near && remaining.keys.any((k) => countOf(p.inventory, k) > 0)
                      ? () => app.donate(s, {for (final e in remaining.entries) e.key: math.min(e.value, countOf(p.inventory, e.key))})
                      : null,
                ),
              ],
              // ---- Bitácora ----
              const SectionLabel('Bitácora'),
              _Typewriter(
                log: _log,
                typing: _typing,
                typed: _typed,
                controller: _line,
                enabled: near && !_busy,
                hint: near ? 'Escribí una línea para la red…' : 'La bitácora solo se escribe dentro del nodo',
              ),
              const SizedBox(height: 10),
              ChamferButton(
                label: 'Escribir · guardar y descansar',
                sublabel: '+${def.restHealth} salud y resistencia · cada 10 min',
                icon: Icons.keyboard_alt_outlined,
                tone: ChamferTone.primary,
                expand: true,
                height: 56,
                onPressed: near && !_busy ? () => _write(s) : null,
              ),
              // ---- Beneficios ----
              const SectionLabel('Beneficios'),
              for (final perk in def.perks) _Perk(text: perk, active: true),
              if (s.level < maxShelterLevel)
                for (final perk in shelterLevelDef(s.level + 1).perks) _Perk(text: perk, active: false),
              // ---- Aportes ----
              SectionLabel('Aportes', trailing: MicroText('${s.contributions.length} enlaces')),
              if (s.contributions.isEmpty)
                Text('Todavía nadie aportó. Sé el primero.', style: SuturaText.bodyMid)
              else
                for (final (i, c) in s.contributions.take(8).indexed)
                  _ContributionRow(rank: i + 1, c: c, max: s.contributions.first.amount, me: c.playerId == p.id),
            ],
          ),
        ),
      ],
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
            const CapsTitle('Nodo sin señal', size: 22),
            const SizedBox(height: 8),
            Text('Este nodo quedó fuera del alcance de la red. Acercate a la zona para volver a sincronizarlo.', style: SuturaText.bodyMid),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

/// Cinco hexágonos unidos por una sutura punteada: niveles de la antena.
class _LevelTrack extends StatelessWidget {
  const _LevelTrack({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: CustomPaint(
        painter: _TrackPainter(level),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= maxShelterLevel; i++)
              HexBadge(
                size: 44,
                fill: i <= level ? Sutura.amber.withValues(alpha: 0.16) : Sutura.surface1Solid,
                line: i <= level ? Sutura.amber : Sutura.lineStrong,
                glow: i == level,
                child: Text('$i', style: SuturaText.mono.copyWith(color: i <= level ? Sutura.amber : Sutura.textLow, fontSize: 14)),
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
    final step = (size.width - 44) / (n - 1);
    final y = size.height / 2;
    for (var i = 0; i < n - 1; i++) {
      final x0 = 22 + i * step + 22;
      final x1 = 22 + (i + 1) * step - 22;
      final p = Paint()
        ..color = i + 1 < level ? Sutura.amber : Sutura.lineStrong
        ..strokeWidth = 1;
      for (double x = x0; x < x1; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, x1), y), p);
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          ItemGlyph(id, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(itemDefs[id]!.name, style: SuturaText.caption.copyWith(color: Sutura.textHi, fontSize: 13))),
                    Text('$given/$need', style: SuturaText.mono.copyWith(fontSize: 12, color: left == 0 ? Sutura.fine : Sutura.textMid)),
                  ],
                ),
                const SizedBox(height: 4),
                SegBar(value: given.toDouble(), max: need.toDouble(), segments: 10, color: left == 0 ? Sutura.fine : Sutura.amber, height: 3),
                const SizedBox(height: 3),
                MicroText('tenés $have'),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: left == 0
                ? Center(child: Icon(Icons.check, color: Sutura.fine.withValues(alpha: 0.8), size: 18))
                : ChamferButton(
                    label: give > 0 ? '+$give' : '—',
                    tone: ChamferTone.amber,
                    dense: true,
                    height: 34,
                    expand: true,
                    onPressed: enabled && give > 0 ? () => onGive(give) : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Máquina de escribir: líneas anteriores en papel y renglón para escribir.
class _Typewriter extends StatelessWidget {
  const _Typewriter({
    required this.log,
    required this.typing,
    required this.typed,
    required this.controller,
    required this.enabled,
    required this.hint,
  });

  final List<({String text, int at})> log;
  final String? typing;
  final int typed;
  final TextEditingController controller;
  final bool enabled;
  final String hint;

  String _stamp(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final lines = log.take(5).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14130F),
        border: Border.all(color: const Color(0xFF3A362C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty)
            Text('— hoja en blanco —', style: SuturaText.paper.copyWith(color: Sutura.textPaper.withValues(alpha: 0.4), fontSize: 13)),
          for (final (i, l) in lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_stamp(l.at)}  ', style: TextStyle(color: Sutura.textPaper.withValues(alpha: 0.45))),
                  TextSpan(text: i == 0 && typing != null ? typing!.substring(0, math.min(typed, typing!.length)) : l.text),
                  if (i == 0 && typing != null) const TextSpan(text: '▌', style: TextStyle(color: Sutura.amber)),
                ]),
                style: SuturaText.paper.copyWith(fontSize: 13.5, height: 1.45, color: Sutura.textPaper.withValues(alpha: i == 0 ? 1 : 0.7 - i * 0.1)),
              ),
            ),
          Container(height: 1, color: const Color(0xFF3A362C), margin: const EdgeInsets.only(top: 4)),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLength: 140,
            cursorColor: Sutura.amber,
            style: SuturaText.paper.copyWith(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: SuturaText.paper.copyWith(fontSize: 13.5, color: Sutura.textPaper.withValues(alpha: 0.35)),
              border: InputBorder.none,
              counterText: '',
              prefixText: '> ',
              prefixStyle: SuturaText.paper.copyWith(color: Sutura.amber),
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
          Icon(active ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 16, color: active ? Sutura.amber : Sutura.textLow),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: SuturaText.bodyMid.copyWith(color: active ? Sutura.textHi : Sutura.textLow))),
          if (!active) const MicroText('próximo nivel'),
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
          SizedBox(width: 26, child: Text(rank.toString().padLeft(2, '0'), style: SuturaText.mono.copyWith(color: Sutura.textLow))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me ? '${c.playerName} (vos)' : c.playerName, style: SuturaText.caption.copyWith(color: me ? Sutura.signal : Sutura.textHi, fontSize: 13)),
                const SizedBox(height: 3),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: max <= 0 ? 0 : (c.amount / max).clamp(0.04, 1.0),
                  child: Container(height: 2, color: me ? Sutura.signal : Sutura.amber.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${c.amount}', style: SuturaText.mono.copyWith(color: Sutura.textMid)),
        ],
      ),
    );
  }
}
