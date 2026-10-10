import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../state/ui_controller.dart';
import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/caps_title.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/grit.dart';
import '../widgets/hexagon.dart';
import '../widgets/item_glyph.dart';
import '../widgets/screen_frame.dart';
import '../widgets/seg_bar.dart';
import 'node_screen.dart' show factionColor;

/// Pestaña RED: nodos, facciones, ranking y enlaces cercanos.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.onOpenNode});

  final void Function(String shelterId) onOpenNode;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  int _tab = 0;
  List<Faction>? _factions;
  List<LeaderboardEntry>? _ranking;
  List<PublicSurvivor>? _survivors;
  int _loadedAt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    final t = app.now;
    if (!force && t - _loadedAt < 30000 && _factions != null) return;
    _loadedAt = t;
    try {
      final pos = app.location.position;
      final results = await Future.wait([
        app.repo.getFactions(),
        app.repo.getLeaderboard(20),
        if (pos != null) app.repo.getNearbySurvivors(pos, 3000),
      ]);
      if (!mounted) return;
      setState(() {
        _factions = results[0] as List<Faction>;
        _ranking = results[1] as List<LeaderboardEntry>;
        _survivors = results.length > 2 ? results[2] as List<PublicSurvivor> : const [];
      });
    } catch (e) {
      if (mounted) app.ui.toast('Red inestable: no se pudo sincronizar.', ToastTone.warn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.world]),
      builder: (context, _) {
        final shelters = app.world.shelters;
        return TabScreenFrame(
          title: 'Red',
          code: 'RED DE RELEVO // ${shelters.length} NODOS EN ALCANCE',
          trailing: SquareIconButton(icon: Icons.sync, size: 36, tooltip: 'Sincronizar', onPressed: () => _load(force: true)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SegmentTabs(
                  labels: const ['Nodos', 'Facciones', 'Ranking', 'Enlaces'],
                  index: _tab,
                  onChanged: (i) {
                    setState(() => _tab = i);
                    unawaited(_load());
                  },
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Sutura.base,
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      0 => _NodesTab(shelters: shelters, onOpenNode: widget.onOpenNode),
                      1 => _FactionsTab(factions: _factions),
                      2 => _RankingTab(entries: _ranking),
                      _ => _SurvivorsTab(survivors: _survivors),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _loading() => const Center(
      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 1.5, color: Sutura.signal)),
    );

// ---------------------------------------------------------------------------
// Nodos
// ---------------------------------------------------------------------------

class _NodesTab extends StatelessWidget {
  const _NodesTab({required this.shelters, required this.onOpenNode});

  final List<Shelter> shelters;
  final void Function(String id) onOpenNode;

  @override
  Widget build(BuildContext context) {
    final own = app.ownShelter;
    final sorted = [...shelters]..sort((a, b) => (app.distanceTo(a.position) ?? 1e9).compareTo(app.distanceTo(b.position) ?? 1e9));
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        const SectionLabel('Tu nodo', color: Sutura.amber),
        if (own != null) _NodeRow(s: own, own: true, onTap: () => onOpenNode(own.id)) else const _BuildNodeCard(),
        SectionLabel('Nodos cercanos', trailing: MicroText('${sorted.length}')),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Sin nodos en alcance. Moverte amplía la red.', style: SuturaText.bodyMid, textAlign: TextAlign.center),
          ),
        for (final s in sorted)
          if (s.id != own?.id) _NodeRow(s: s, own: false, onTap: () => onOpenNode(s.id)),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.s, required this.own, required this.onTap});

  final Shelter s;
  final bool own;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = app.distanceTo(s.position);
    final near = app.isNear(s.position);
    final color = own ? Sutura.amber : Sutura.signal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Sutura.surface1Solid,
            border: Border.all(color: own ? Sutura.amber.withValues(alpha: 0.5) : Sutura.lineHair),
          ),
          child: Row(
            children: [
              HexBadge(
                size: 44,
                line: color,
                fill: color.withValues(alpha: 0.08),
                child: Text('${s.level}', style: SuturaText.mono.copyWith(color: color, fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: SuturaText.body.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(width: 7, height: 7, color: factionColor(s.factionId)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${shelterLevelDef(s.level).name} · ${own ? 'tuyo' : s.ownerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (s.level < maxShelterLevel) ...[
                      const SizedBox(height: 6),
                      SegBar(value: upgradeProgress(s), max: 1, segments: 14, color: Sutura.amber.withValues(alpha: 0.8), height: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(near ? 'EN EL NODO' : d == null ? '—' : distanceLabel(d), style: SuturaText.mono.copyWith(fontSize: 12, color: near ? Sutura.signal : Sutura.textHi)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.favorite_border, size: 12, color: Sutura.textLow),
                      const SizedBox(width: 3),
                      Text('${app.pulsesOf(s)}', style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.textLow)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildNodeCard extends StatefulWidget {
  const _BuildNodeCard();

  @override
  State<_BuildNodeCard> createState() => _BuildNodeCardState();
}

class _BuildNodeCardState extends State<_BuildNodeCard> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = app.player!;
    final canPay = hasItems(p.inventory, AppState.nodeBuildCost);
    final hasFix = app.location.position != null;
    return BracketPanel(
      color: Sutura.amber,
      background: Sutura.surface1Solid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CapsTitle('Suturá tu nodo', size: 17),
          const SizedBox(height: 6),
          Text(
            'Instalá una antena de relevo. Se ubica en una calle pública cercana (nunca en tu casa) y habilita el taller avanzado.',
            style: SuturaText.bodyMid,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in entries(AppState.nodeBuildCost))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: countOf(p.inventory, e.key) >= e.value ? Sutura.lineStrong : Sutura.danger.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 22, height: 22, child: ItemArt(e.key, size: 22, fallbackIcon: itemIcon(e.key))),
                      const SizedBox(width: 5),
                      Text('${itemDefs[e.key]!.name} ${countOf(p.inventory, e.key)}/${e.value}', style: SuturaText.mono.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: 32,
            cursorColor: Sutura.amber,
            style: SuturaText.body,
            decoration: InputDecoration(
              hintText: 'Nombre del nodo (ej. Nodo ${p.name})',
              hintStyle: SuturaText.bodyMid.copyWith(color: Sutura.textLow),
              counterText: '',
              isDense: true,
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Sutura.lineStrong)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Sutura.amber)),
            ),
          ),
          const SizedBox(height: 12),
          ChamferButton(
            label: _busy ? 'Suturando…' : 'Instalar antena',
            sublabel: !hasFix ? 'esperando señal de ubicación' : (canPay ? null : 'faltan recursos'),
            icon: Icons.cell_tower,
            tone: ChamferTone.amber,
            expand: true,
            onPressed: canPay && hasFix && !_busy
                ? () async {
                    setState(() => _busy = true);
                    await app.buildNode(_name.text);
                    if (mounted) setState(() => _busy = false);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Facciones
// ---------------------------------------------------------------------------

class _FactionsTab extends StatelessWidget {
  const _FactionsTab({required this.factions});

  final List<Faction>? factions;

  @override
  Widget build(BuildContext context) {
    final list = factions;
    if (list == null) return _loading();
    final mine = app.player?.factionId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        for (final f in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Sutura.surface1Solid,
                border: Border.all(color: f.id == mine ? factionColor(f.id) : Sutura.lineHair),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: factionColor(f.id)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: CapsTitle(f.name, size: 17)),
                                if (f.id == mine) StatusChip('Tu facción', color: factionColor(f.id), filled: true),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('“${f.motto}”', style: SuturaText.bodyMid.copyWith(fontStyle: FontStyle.italic)),
                            const SizedBox(height: 8),
                            Text(f.bonusDescription.toUpperCase(), style: SuturaText.mono.copyWith(fontSize: 11.5, color: factionColor(f.id), letterSpacing: 1)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                MicroText('${f.members} enlaces · ${f.totalContribution} aportes'),
                                const Spacer(),
                                ChamferButton(
                                  label: f.id == mine ? 'Abandonar' : 'Unirme',
                                  tone: f.id == mine ? ChamferTone.ghost : ChamferTone.primary,
                                  dense: true,
                                  height: 34,
                                  onPressed: () => app.joinFaction(f.id == mine ? null : f.id),
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
          ),
        Text(
          'Las facciones dan bonificaciones permanentes. Podés cambiar cuando quieras.',
          style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ranking
// ---------------------------------------------------------------------------

class _RankingTab extends StatelessWidget {
  const _RankingTab({required this.entries});

  final List<LeaderboardEntry>? entries;

  @override
  Widget build(BuildContext context) {
    final list = entries;
    if (list == null) return _loading();
    final me = app.player?.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Row(
          children: [
            const SizedBox(width: 34, child: MicroText('#')),
            const Expanded(child: MicroText('enlace')),
            const SizedBox(width: 44, child: MicroText('grado')),
            SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: MicroText('aportes'))),
          ],
        ),
        const SizedBox(height: 6),
        for (final (i, e) in list.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: e.playerId == me ? Sutura.accent.withValues(alpha: 0.12) : null,
              border: const Border(bottom: BorderSide(color: Sutura.lineHair)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: SuturaText.mono.copyWith(color: i < 3 ? Sutura.amber : Sutura.textLow, fontSize: 14),
                  ),
                ),
                Container(width: 7, height: 7, color: factionColor(e.factionId)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.playerId == me ? '${e.playerName} (vos)' : e.playerName,
                    style: SuturaText.body.copyWith(color: e.playerId == me ? Sutura.textHi : Sutura.textHi, fontWeight: e.playerId == me ? FontWeight.w700 : FontWeight.w500, fontSize: 15),
                  ),
                ),
                SizedBox(width: 44, child: Text('${e.level}', style: SuturaText.mono.copyWith(color: Sutura.textMid))),
                SizedBox(
                  width: 64,
                  child: Text('${e.contribution}', textAlign: TextAlign.right, style: SuturaText.mono.copyWith(fontSize: 14)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Enlaces cercanos
// ---------------------------------------------------------------------------

class _SurvivorsTab extends StatelessWidget {
  const _SurvivorsTab({required this.survivors});

  final List<PublicSurvivor>? survivors;

  @override
  Widget build(BuildContext context) {
    final list = survivors;
    if (list == null) return _loading();
    final pos = app.location.position;
    final now = app.now;
    final sorted = [...list]..sort((a, b) => pos == null ? 0 : haversineM(pos, a.approxPosition).compareTo(haversineM(pos, b.approxPosition)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: Sutura.signalDeep)),
          child: Row(
            children: [
              const Icon(Icons.blur_on, size: 18, color: Sutura.signal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Posiciones aproximadas: la red nunca muestra dónde está exactamente un enlace.',
                  style: SuturaText.caption.copyWith(color: Sutura.textMid, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty) Text('Nadie en alcance por ahora.', style: SuturaText.bodyMid),
        for (final s in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(color: Sutura.surface1Solid, border: Border(left: BorderSide(color: Sutura.lineStrong, width: 2))),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: factionColor(s.factionId), shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: SuturaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          'Grado ${s.level} · ${s.factionId == null ? 'sin facción' : factionDefs[s.factionId]!.name} · ${agoLabel(now - s.lastSeenAt)}',
                          style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    pos == null ? '—' : approximateDistanceLabel(haversineM(pos, s.approxPosition)),
                    style: SuturaText.mono.copyWith(fontSize: 12, color: Sutura.textMid),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
