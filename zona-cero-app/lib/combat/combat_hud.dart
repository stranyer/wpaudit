// Piezas del HUD del combate (widgets Flutter sobre el escenario Flame).
// Reutilizan el sistema SUTURA: BracketPanel, ChamferButton, EcgMonitor,
// SegBar, HexBadge, HoloIn, CapsTitle, MicroText.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../state/app_state.dart' show AppState;
import '../ui/theme/tokens.dart';
import '../ui/widgets/brackets.dart';
import '../ui/widgets/caps_title.dart';
import '../ui/widgets/chamfer_button.dart';
import '../ui/widgets/ecg_monitor.dart';
import '../ui/widgets/hexagon.dart';
import '../ui/widgets/holo_in.dart';
import '../ui/widgets/seg_bar.dart';

/// Modo del arma activa.
enum WeaponMode { melee, firearm }

const _shadow = [Shadow(color: Color(0xE6000000), blurRadius: 6), Shadow(color: Color(0x99000000), blurRadius: 14)];

String two(num v) => v.round().clamp(0, 999).toString().padLeft(2, '0');

// -----------------------------------------------------------------------------
// Signos vitales (arriba a la izquierda)
// -----------------------------------------------------------------------------

class VitalsPanel extends StatelessWidget {
  const VitalsPanel({
    super.key,
    required this.health,
    required this.maxHealth,
    required this.stamina,
    required this.maxStamina,
    this.defending = false,
  });

  final double health;
  final int maxHealth;
  final double stamina;
  final int maxStamina;
  final bool defending;

  @override
  Widget build(BuildContext context) {
    final ratio = maxHealth <= 0 ? 0.0 : (health / maxHealth).clamp(0.0, 1.0);
    final vc = vitalColor(vitalFor(ratio));
    return BracketPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      color: ratio < 0.3 ? Sutura.danger : Sutura.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('SIGNOS VITALES', style: SuturaText.micro.copyWith(color: Sutura.textMid)),
              ),
              if (defending) Text('CUBIERTO', style: SuturaText.micro.copyWith(color: Sutura.signal)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: EcgMonitor(ratio: ratio, width: 64, height: 26, showLabel: false),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                health.round().toString().padLeft(3, '0'),
                style: SuturaText.mono.copyWith(fontSize: 22, color: vc, height: 1, letterSpacing: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2, left: 1),
                child: Text('/$maxHealth', style: SuturaText.mono.copyWith(fontSize: 10, color: Sutura.textLow)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('RES', style: SuturaText.micro.copyWith(color: Sutura.textMid, fontSize: 9)),
              const SizedBox(width: 6),
              Expanded(
                child: SegBar(value: stamina, max: maxStamina.toDouble(), segments: 10, height: 4, color: Sutura.signal),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 22,
                child: Text(
                  two(stamina),
                  textAlign: TextAlign.right,
                  style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.signal),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Objetivo (arriba a la derecha)
// -----------------------------------------------------------------------------

(String, Color) threatInfo(int threat) => switch (threat) {
  0 => ('BAJA', Sutura.fine),
  1 => ('PAREJA', Sutura.textMid),
  2 => ('ALTA', Sutura.caution2),
  _ => ('MORTAL', Sutura.danger),
};

class TargetPanel extends StatelessWidget {
  const TargetPanel({super.key, required this.name, required this.level, required this.threat, required this.health, required this.maxHealth});

  final String name;
  final int level;
  final int threat;
  final int health;
  final int maxHealth;

  @override
  Widget build(BuildContext context) {
    final (tl, tc) = threatInfo(threat);
    return BracketPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      color: threat >= 2 ? tc : Sutura.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('OBJETIVO', style: SuturaText.micro.copyWith(color: Sutura.textMid)),
              ),
              Text('NV ${two(level)}', style: SuturaText.micro.copyWith(color: Sutura.textHi, fontSize: 9.5)),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CapsTitle(name, size: 15, color: Sutura.textHi),
          ),
          const SizedBox(height: 6),
          SegBar(value: health.toDouble(), max: maxHealth.toDouble(), segments: 16, height: 4, color: Sutura.danger),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'AMENAZA '),
                      TextSpan(
                        text: tl,
                        style: TextStyle(color: tc),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SuturaText.micro.copyWith(fontSize: 9),
                ),
              ),
              const SizedBox(width: 6),
              Text('${two(health)}/${two(maxHealth)}', style: SuturaText.mono.copyWith(fontSize: 10.5, color: Sutura.textMid)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip de estado del zombie (puede titilar).
class StatusChip extends StatefulWidget {
  const StatusChip(this.text, {super.key, required this.color, this.blink = false, this.icon});

  final String text;
  final Color color;
  final bool blink;
  final IconData? icon;

  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    if (widget.blink) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusChip old) {
    super.didUpdateWidget(old);
    if (widget.blink && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.blink && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.16),
        border: Border(left: BorderSide(color: widget.color, width: 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 11, color: widget.color), const SizedBox(width: 4)],
          Text(widget.text, style: SuturaText.mono.copyWith(fontSize: 10, color: widget.color, letterSpacing: 1.2)),
        ],
      ),
    );
    if (!widget.blink) return chip;
    return FadeTransition(opacity: Tween(begin: 1.0, end: 0.45).animate(_c), child: chip);
  }
}

// -----------------------------------------------------------------------------
// Panel del arma (abajo a la derecha)
// -----------------------------------------------------------------------------

class WeaponPanel extends StatelessWidget {
  const WeaponPanel({
    super.key,
    required this.mode,
    required this.meleeName,
    required this.meleeDamage,
    required this.firearmName,
    required this.ammo,
    required this.ammoPerShot,
    required this.onToggle,
  });

  final WeaponMode mode;
  final String meleeName;
  final IntRange meleeDamage;
  final String? firearmName;
  final int ammo;
  final int ammoPerShot;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final firearm = mode == WeaponMode.firearm;
    final hasFirearm = firearmName != null;
    final accent = firearm ? Sutura.amber : Sutura.signal;
    final low = hasFirearm && ammo < ammoPerShot;
    return BracketPanel(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      color: accent.withValues(alpha: 0.8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(firearm ? 'ARMA DE FUEGO' : 'CUERPO A CUERPO', style: SuturaText.micro.copyWith(color: accent, fontSize: 8.5)),
                const SizedBox(height: 2),
                Text(
                  (firearm ? firearmName! : meleeName).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SuturaText.button.copyWith(fontSize: 13, letterSpacing: 1, height: 1.1),
                ),
                const SizedBox(height: 5),
                if (hasFirearm)
                  _ModeToggle(mode: mode, onTap: onToggle)
                else
                  Text('SIN ARMA DE FUEGO', style: SuturaText.micro.copyWith(fontSize: 8.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFirearm) ...[
                Text(
                  two(ammo),
                  style: SuturaText.mono.copyWith(fontSize: 34, height: 1, color: low ? Sutura.danger : (firearm ? Sutura.textHi : Sutura.textMid)),
                ),
                Text('MUNICIÓN', style: SuturaText.micro.copyWith(fontSize: 8, color: low ? Sutura.danger : Sutura.textLow)),
              ] else ...[
                Text('${meleeDamage.min}–${meleeDamage.max}', style: SuturaText.mono.copyWith(fontSize: 24, height: 1.1, color: Sutura.textHi)),
                Text('DAÑO', style: SuturaText.micro.copyWith(fontSize: 8)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onTap});

  final WeaponMode mode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool on, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: on ? c.withValues(alpha: 0.22) : const Color(0x00000000),
      child: Text(t, style: SuturaText.mono.copyWith(fontSize: 9.5, color: on ? c : Sutura.textLow, letterSpacing: 1)),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Sutura.lineStrong, width: 1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg('C/C', mode == WeaponMode.melee, Sutura.signal),
            const Icon(Icons.swap_horiz, size: 12, color: Sutura.textMid),
            seg('FUEGO', mode == WeaponMode.firearm, Sutura.amber),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Registro de combate (teletipo)
// -----------------------------------------------------------------------------

class LogLine {
  const LogLine(this.id, this.text, this.color);
  final int id;
  final String text;
  final Color color;
}

class CombatLogTicker extends StatelessWidget {
  const CombatLogTicker({super.key, required this.lines});

  final List<LogLine> lines;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
    // Anclado abajo: si no entra, se recorta lo más viejo (arriba).
    return IgnorePointer(
      child: ClipRect(
        child: SingleChildScrollView(
          reverse: true,
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, l) in shown.indexed)
                Padding(
                  key: ValueKey(l.id),
                  padding: const EdgeInsets.only(top: 3),
                  child: HoloIn(
                    child: Opacity(
                      opacity: switch (shown.length - 1 - i) {
                        0 => 1.0,
                        1 => 0.62,
                        _ => 0.34,
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '› ',
                            style: SuturaText.mono.copyWith(fontSize: 11, color: l.color, shadows: _shadow),
                          ),
                          Expanded(
                            child: Text(
                              l.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SuturaText.mono.copyWith(
                                fontSize: 11,
                                height: 1.25,
                                color: i == shown.length - 1 ? l.color : Sutura.textMid,
                                shadows: _shadow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Números flotantes y avisos centrales
// -----------------------------------------------------------------------------

enum FloatKind { damage, crit, miss, hurt, heal, info, blocked }

class FloatSpec {
  FloatSpec({required this.id, required this.text, required this.kind, required this.at, this.sub, this.blocked = 0});
  final int id;
  final String text;
  final FloatKind kind;
  final Offset at;
  final String? sub;
  final int blocked;
}

class FloatingNumber extends StatelessWidget {
  const FloatingNumber({super.key, required this.spec});

  final FloatSpec spec;

  @override
  Widget build(BuildContext context) {
    final (color, size) = switch (spec.kind) {
      FloatKind.crit => (Sutura.amber, 40.0),
      FloatKind.damage => (Sutura.textHi, 30.0),
      FloatKind.miss => (Sutura.textMid, 20.0),
      FloatKind.hurt => (const Color(0xFFFF5A62), 28.0),
      FloatKind.heal => (Sutura.fine, 26.0),
      FloatKind.info => (Sutura.signal, 16.0),
      FloatKind.blocked => (Sutura.signal, 16.0),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: spec.kind == FloatKind.crit ? 1250 : 1050),
      builder: (context, t, child) {
        final pop = t < 0.12 ? 1.35 - 0.35 * (t / 0.12) : 1.0;
        final rise = Curves.easeOut.transform(t) * (spec.kind == FloatKind.crit ? 64 : 48);
        final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -rise),
            child: Transform.scale(scale: pop, child: child),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.sub != null)
            Text(
              spec.sub!,
              style: SuturaText.mono.copyWith(fontSize: 10, color: color, letterSpacing: 2, shadows: _shadow),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                spec.text,
                style: TextStyle(
                  fontFamily: Sutura.fMono,
                  fontSize: size,
                  height: 1,
                  color: color,
                  letterSpacing: spec.kind == FloatKind.miss ? 3 : 0.5,
                  shadows: [
                    Shadow(color: color.withValues(alpha: 0.55), blurRadius: 14),
                    ..._shadow,
                  ],
                ),
              ),
              if (spec.blocked > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.shield_outlined, size: 14, color: Sutura.signal, shadows: _shadow),
                Text(
                  '${spec.blocked}',
                  style: SuturaText.mono.copyWith(fontSize: 14, color: Sutura.signal, shadows: _shadow),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso grande en el centro ("DISPARO A LA CABEZA", "¡CUBRITE!").
class CallOut extends StatelessWidget {
  const CallOut({super.key, required this.text, required this.color, this.sub});

  final String text;
  final Color color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1150),
      builder: (context, t, child) {
        final inT = (t / 0.18).clamp(0.0, 1.0);
        final out = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
        final wide = 1.0 + 0.25 * (1 - Curves.easeOut.transform(inT));
        final flicker = inT < 1 && (t * 60).floor().isOdd ? 0.55 : 1.0;
        return Opacity(
          opacity: (out * flicker * inT).clamp(0.0, 1.0),
          child: Transform.scale(scaleX: wide, child: child),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, width: 180, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: SuturaText.display.copyWith(
              fontSize: 24,
              letterSpacing: 4,
              color: color,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: color.withValues(alpha: 0.6), blurRadius: 18),
                ..._shadow,
              ],
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: SuturaText.mono.copyWith(fontSize: 10.5, color: color.withValues(alpha: 0.85), letterSpacing: 2, shadows: _shadow),
            ),
          ],
          const SizedBox(height: 6),
          Container(height: 1, width: 180, color: color.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

/// Indicación inicial que respira.
class PulsingHint extends StatefulWidget {
  const PulsingHint({super.key, required this.text});
  final String text;

  @override
  State<PulsingHint> createState() => _PulsingHintState();
}

class _PulsingHintState extends State<PulsingHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app_outlined, size: 15, color: Sutura.signal, shadows: _shadow),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.signal, letterSpacing: 1.6, shadows: _shadow),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Menú rápido de objetos (cruz de 4 posiciones)
// -----------------------------------------------------------------------------

IconData itemIcon(ItemId id) => switch (id) {
  ItemId.food => Icons.lunch_dining_outlined,
  ItemId.water => Icons.water_drop_outlined,
  ItemId.medicine => Icons.medication_outlined,
  ItemId.medkit => Icons.medical_services_outlined,
  ItemId.ration => Icons.inventory_2_outlined,
  ItemId.adrenaline => Icons.vaccines_outlined,
  _ => Icons.category_outlined,
};

/// Orden del menú: primero lo que más cura.
List<ItemId> sortForWheel(List<ItemId> items) {
  final list = [...items];
  list.sort((a, b) {
    final ea = itemDefs[a]!.effects;
    final eb = itemDefs[b]!.effects;
    final h = (eb?.health ?? 0).compareTo(ea?.health ?? 0);
    if (h != 0) return h;
    return (eb?.stamina ?? 0).compareTo(ea?.stamina ?? 0);
  });
  return list;
}

class ItemCross extends StatefulWidget {
  const ItemCross({super.key, required this.items, required this.countOf, required this.onPick, required this.onClose});

  final List<ItemId> items;
  final int Function(ItemId id) countOf;
  final ValueChanged<ItemId> onPick;
  final VoidCallback onClose;

  @override
  State<ItemCross> createState() => _ItemCrossState();
}

class _ItemCrossState extends State<ItemCross> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final items = sortForWheel(widget.items);
    final pages = math.max(1, (items.length / 4).ceil());
    final page = _page % pages;
    final slots = items.skip(page * 4).take(4).toList();
    const slotW = 140.0;
    const slotH = 64.0;
    const hub = 60.0;
    const gap = 6.0;
    // Arriba, derecha, abajo, izquierda.
    const offsets = [
      Offset(0, -(hub / 2 + gap + slotH / 2)),
      Offset(hub / 2 + gap + slotW / 2, 0),
      Offset(0, hub / 2 + gap + slotH / 2),
      Offset(-(hub / 2 + gap + slotW / 2), 0),
    ];
    return SizedBox(
      width: slotW * 2 + hub + gap * 2,
      height: slotH * 2 + hub + gap * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 4; i++)
            Positioned(
              left: (slotW * 2 + hub + gap * 2) / 2 + offsets[i].dx - slotW / 2,
              top: (slotH * 2 + hub + gap * 2) / 2 + offsets[i].dy - slotH / 2,
              width: slotW,
              height: slotH,
              child: HoloIn(
                key: ValueKey('slot-$page-$i'),
                delay: Duration(milliseconds: 30 * i),
                child: i < slots.length
                    ? _ItemSlot(id: slots[i], count: widget.countOf(slots[i]), onTap: () => widget.onPick(slots[i]))
                    : const _EmptySlot(),
              ),
            ),
          Center(
            child: GestureDetector(
              onTap: pages > 1 ? () => setState(() => _page++) : widget.onClose,
              child: HexBadge(
                size: hub,
                glow: true,
                fill: Sutura.surface1Solid,
                line: Sutura.signal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(pages > 1 ? Icons.sync_alt : Icons.close, size: 16, color: Sutura.signal),
                    const SizedBox(height: 1),
                    Text(pages > 1 ? '${page + 1}/$pages' : 'CERRAR', style: SuturaText.micro.copyWith(color: Sutura.signal, fontSize: 7.5)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemSlot extends StatelessWidget {
  const _ItemSlot({required this.id, required this.count, required this.onTap});

  final ItemId id;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final def = itemDefs[id]!;
    final rc = rarityColor(def.rarity.key);
    final e = def.effects;
    final fx = [if ((e?.health ?? 0) > 0) '+${e!.health} SALUD', if ((e?.stamina ?? 0) > 0) '+${e!.stamina} RES'].join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        painter: ChamferPainter(fill: const Color(0xF0101619), line: rc.withValues(alpha: 0.85)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
          child: Row(
            children: [
              Icon(itemIcon(id), size: 20, color: rc),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            def.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SuturaText.caption.copyWith(color: Sutura.textHi, fontSize: 11.5, height: 1.05, letterSpacing: 0.2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('×$count', style: SuturaText.mono.copyWith(fontSize: 12, color: rc, height: 1.1)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fx,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SuturaText.micro.copyWith(color: Sutura.fine, fontSize: 7.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: ChamferPainter(fill: const Color(0x80101619), line: Sutura.lineHair),
    child: Center(child: Text('VACÍO', style: SuturaText.micro.copyWith(fontSize: 8))),
  );
}

// -----------------------------------------------------------------------------
// Resultado
// -----------------------------------------------------------------------------

class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.status,
    required this.zombieName,
    required this.zombieLevel,
    required this.turns,
    required this.xp,
    required this.added,
    required this.overflow,
    required this.lost,
    required this.levelsGained,
    required this.newLevel,
    required this.onExit,
  });

  final CombatStatus status;
  final String zombieName;
  final int zombieLevel;
  final int turns;
  final int xp;
  final Inventory added;
  final Inventory overflow;
  final Inventory lost;
  final int levelsGained;
  final int? newLevel;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final (title, color, line) = switch (status) {
      CombatStatus.won => ('NEUTRALIZADO', Sutura.signal, '$zombieName · NV $zombieLevel · $turns ${turns == 1 ? 'turno' : 'turnos'}'),
      CombatStatus.lost => ('CAÍSTE', Sutura.danger, 'Te arrastraste hasta un lugar seguro.'),
      _ => ('ESCAPASTE', Sutura.amber, 'Vivís para pelear otro día.'),
    };
    final pad = MediaQuery.paddingOf(context);
    var d = 0;
    Duration next() => Duration(milliseconds: 260 + 90 * d++);
    final addedEntries = entries(added);
    return ColoredBox(
      color: const Color(0xD9030507),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, pad.top + 24, 22, pad.bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HoloIn(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('VITA-7 // INFORME DE ENCUENTRO', style: SuturaText.micro.copyWith(color: Sutura.textMid)),
                  Text('T-${two(turns)}', style: SuturaText.micro.copyWith(color: Sutura.textMid)),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Center(
              child: _Stamp(text: title, color: color),
            ),
            const SizedBox(height: 14),
            HoloIn(
              delay: next(),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: SuturaText.bodyMid.copyWith(color: Sutura.textMid),
              ),
            ),
            const SizedBox(height: 22),
            Flexible(
              flex: 6,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (status == CombatStatus.won)
                      HoloIn(
                        delay: next(),
                        child: _ResultRow(label: 'EXPERIENCIA', value: '+$xp XP', color: Sutura.amber),
                      ),
                    if (levelsGained > 0)
                      HoloIn(
                        delay: next(),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: BracketPanel(
                            color: Sutura.signal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                HexBadge(
                                  size: 34,
                                  glow: true,
                                  child: Text('${newLevel ?? ''}', style: SuturaText.mono.copyWith(color: Sutura.signal, fontSize: 13)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('SUBISTE DE NIVEL', style: SuturaText.button.copyWith(color: Sutura.signal)),
                                      Text('Signos vitales restaurados.', style: SuturaText.caption),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (status == CombatStatus.won) ...[
                      const SizedBox(height: 14),
                      HoloIn(
                        delay: next(),
                        child: Text('RECUPERADO', style: SuturaText.micro.copyWith(color: Sutura.textMid)),
                      ),
                      const SizedBox(height: 6),
                      if (addedEntries.isEmpty)
                        HoloIn(
                          delay: next(),
                          child: Text('No llevaba nada útil.', style: SuturaText.bodyMid.copyWith(color: Sutura.textLow)),
                        ),
                      for (final e in addedEntries)
                        HoloIn(
                          delay: next(),
                          child: _ItemLine(id: e.key, count: e.value),
                        ),
                    ],
                    if (overflow.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      HoloIn(
                        delay: next(),
                        child: _Notice(text: 'No entró en el maletín: ${_describe(overflow)}', color: Sutura.caution),
                      ),
                    ],
                    if (status == CombatStatus.lost && lost.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      HoloIn(
                        delay: next(),
                        child: _Notice(text: 'Perdiste: ${_describe(lost)}', color: Sutura.danger),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            HoloIn(
              delay: next(),
              child: ChamferButton(
                label: 'Volver al mapa',
                tone: status == CombatStatus.lost ? ChamferTone.danger : ChamferTone.primary,
                icon: Icons.map_outlined,
                expand: true,
                onPressed: onExit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(Inventory items) => AppState.describeItems(items);
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: -0.06,
          child: Transform.scale(scale: 1.6 - 0.6 * t, child: child),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(border: Border.all(color: color, width: 2.5)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 14, 6),
          decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.7), width: 1)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: Sutura.fStamp,
                fontSize: 40,
                color: color,
                letterSpacing: 5,
                height: 1.1,
                shadows: [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 16)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sutura.lineHair)),
      ),
      child: Row(
        children: [
          Text(label, style: SuturaText.micro.copyWith(color: Sutura.textMid)),
          const Spacer(),
          Text(value, style: SuturaText.mono.copyWith(fontSize: 22, color: color, height: 1)),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.id, required this.count});

  final ItemId id;
  final int count;

  @override
  Widget build(BuildContext context) {
    final def = itemDefs[id]!;
    final rc = rarityColor(def.rarity.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          color: Sutura.surface1,
          border: Border(left: BorderSide(color: rc, width: 2)),
        ),
        child: Row(
          children: [
            Icon(itemIcon(id), size: 16, color: rc),
            const SizedBox(width: 10),
            Expanded(child: Text(def.name, style: SuturaText.body.copyWith(fontSize: 14))),
            Text(def.rarity.label.toUpperCase(), style: SuturaText.micro.copyWith(color: rc)),
            const SizedBox(width: 10),
            Text('×$count', style: SuturaText.mono.copyWith(color: rc)),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border(left: BorderSide(color: color, width: 2)),
    ),
    child: Text(text, style: SuturaText.caption.copyWith(color: color, fontSize: 12.5)),
  );
}
