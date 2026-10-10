// Piezas del HUD del combate (widgets Flutter sobre el escenario Flame), con el
// lenguaje visual v2: paneles de metal gastado (GritPanel), títulos con
// desgaste (GrungeTitle), barras de bloques y fotos de objetos (ItemArt).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../state/app_state.dart' show AppState;
import '../ui/theme/tokens.dart';
import '../ui/widgets/chamfer_button.dart';
import '../ui/widgets/ecg_monitor.dart';
import '../ui/widgets/grit.dart';
import '../ui/widgets/holo_in.dart';

/// Modo del arma activa.
enum WeaponMode { melee, firearm }

/// Rojo de alerta legible sobre la escena oscura.
const hudRed = Color(0xFFE5483F);

const _shadow = [Shadow(color: Color(0xE6000000), blurRadius: 6), Shadow(color: Color(0x99000000), blurRadius: 14)];

String two(num v) => v.round().clamp(0, 999).toString().padLeft(2, '0');

TextStyle _label([double size = 10.5, Color color = Sutura.textMid]) =>
    SuturaText.label.copyWith(fontSize: size, color: color, letterSpacing: size * 0.26);

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
    final sRatio = maxStamina <= 0 ? 0.0 : (stamina / maxStamina).clamp(0.0, 1.0);
    return GritPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      background: const Color(0xD8101214),
      border: ratio < 0.3 ? Sutura.danger : Sutura.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('SIGNOS VITALES', maxLines: 1, overflow: TextOverflow.clip, style: _label(10.5, Sutura.textHi))),
              if (defending) Text('CUBIERTO', style: _label(9, Sutura.signal)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 70,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0x99060809),
                  border: Border.all(color: Sutura.lineHair),
                ),
                alignment: Alignment.center,
                child: EcgMonitor(ratio: ratio, width: 66, height: 28, showLabel: false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: health.round().toString().padLeft(2, '0'),
                          style: SuturaText.number.copyWith(fontSize: 31, color: vc, fontWeight: FontWeight.w700, shadows: [Shadow(color: vc.withValues(alpha: 0.35), blurRadius: 10)]),
                        ),
                        TextSpan(text: ' / $maxHealth', style: SuturaText.number.copyWith(fontSize: 15, color: Sutura.textMid)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RESISTENCIA', maxLines: 1, style: _label(9.5)),
                    const SizedBox(height: 4),
                    BlockBar(ratio: sRatio, segments: 10, color: Sutura.signal, height: 6, gap: 2),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: stamina.round().toString().padLeft(2, '0'), style: const TextStyle(color: Sutura.signal)),
                    TextSpan(text: '/$maxStamina', style: const TextStyle(color: Sutura.textMid)),
                  ],
                ),
                style: SuturaText.number.copyWith(fontSize: 15, height: 1),
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
  _ => ('MORTAL', hudRed),
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
    return GritPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      background: const Color(0xD8101214),
      border: threat >= 2 ? tc.withValues(alpha: 0.8) : Sutura.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('OBJETIVO', style: _label(10.5))),
              Text('NV ${two(level)}', style: SuturaText.number.copyWith(fontSize: 15, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: GrungeTitle(name, size: 27, letterSpacing: 3, maxLines: 1),
          ),
          const SizedBox(height: 6),
          BlockBar(ratio: maxHealth <= 0 ? 0 : health / maxHealth, segments: 15, color: Sutura.accent, height: 8, gap: 2),
          const SizedBox(height: 7),
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
                  style: _label(9.5),
                ),
              ),
              const SizedBox(width: 6),
              Text('${two(health)}/${two(maxHealth)}', style: SuturaText.number.copyWith(fontSize: 15, color: Sutura.textMid, height: 1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Etiqueta "⚠ HOSTIL DETECTADO" (al empezar el encuentro).
class HostileTag extends StatelessWidget {
  const HostileTag({super.key, this.text = 'HOSTIL DETECTADO'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
      decoration: BoxDecoration(
        color: const Color(0xB31E0907),
        border: Border.all(color: Sutura.accent, width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x55C8322B), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_rounded, size: 16, color: hudRed),
          const SizedBox(width: 8),
          Text(text, style: _label(11.5, hudRed).copyWith(fontWeight: FontWeight.w700, letterSpacing: 3)),
        ],
      ),
    );
  }
}

/// Chip de estado de la criatura (puede titilar).
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
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(widget.color.withValues(alpha: 0.14), const Color(0xCC0C0E10)),
        border: Border(
          left: BorderSide(color: widget.color, width: 3),
          top: BorderSide(color: widget.color.withValues(alpha: 0.35)),
          right: BorderSide(color: widget.color.withValues(alpha: 0.35)),
          bottom: BorderSide(color: widget.color.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 13, color: widget.color), const SizedBox(width: 6)],
          Text(widget.text, style: _label(10.5, widget.color).copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    if (!widget.blink) return chip;
    return FadeTransition(opacity: Tween(begin: 1.0, end: 0.5).animate(_c), child: chip);
  }
}

// -----------------------------------------------------------------------------
// Registro de combate
// -----------------------------------------------------------------------------

class LogLine {
  const LogLine(this.id, this.text, this.color);
  final int id;
  final String text;
  final Color color;
}

class CombatLog extends StatelessWidget {
  const CombatLog({super.key, required this.lines, this.visible = 3});

  final List<LogLine> lines;
  final int visible;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length > visible ? lines.sublist(lines.length - visible) : lines;
    return IgnorePointer(
      child: GritPanel(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        background: const Color(0xD80D0F11),
        corners: Sutura.lineStrong,
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
                    padding: const EdgeInsets.only(top: 2),
                    child: HoloIn(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('>', style: SuturaText.mono.copyWith(fontSize: 10.5, height: 1.35, color: i == shown.length - 1 ? l.color : Sutura.textLow)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.text,
                              maxLines: i == shown.length - 1 ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: SuturaText.mono.copyWith(
                                fontSize: 10.5,
                                height: 1.35,
                                letterSpacing: 0.2,
                                color: i == shown.length - 1 ? l.color : (i == shown.length - 2 ? Sutura.textMid : Sutura.textLow),
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Botones de acción
// -----------------------------------------------------------------------------

class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.icon, required this.label, required this.sub, this.onTap, this.highlight = false, this.active = false, this.height = 58});

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;

  /// Rojo con resplandor (CUBRIRSE ante una embestida).
  final bool highlight;

  /// Menú abierto (OBJETOS).
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final hi = highlight && enabled;
    final fg = hi ? const Color(0xFFF2D5D0) : (active ? Sutura.amber : Sutura.textHi);
    final panel = GritPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      background: hi ? const Color(0xE63A120E) : (active ? const Color(0xE62A2008) : const Color(0xE0121416)),
      border: hi ? Sutura.accent : (active ? Sutura.amber : Sutura.lineStrong),
      corners: hi ? hudRed : (active ? Sutura.amber : Sutura.lineBright),
      glow: hi ? Sutura.accent : null,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 25, color: hi ? const Color(0xFFE79A92) : fg.withValues(alpha: 0.85)),
            const SizedBox(width: 9),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), style: SuturaText.button.copyWith(fontSize: 17, letterSpacing: 2.2, color: fg, height: 1.05)),
                    const SizedBox(height: 2),
                    Text(sub.toUpperCase(), style: _label(11.5, fg.withValues(alpha: 0.72)).copyWith(letterSpacing: 1.8)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label $sub',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(duration: Sutura.fast, opacity: enabled ? 1 : 0.5, child: panel),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Números flotantes, avisos centrales y sacudida del HUD
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
      FloatKind.crit => (Sutura.amber, 46.0),
      FloatKind.damage => (Sutura.textHi, 36.0),
      FloatKind.miss => (Sutura.textMid, 22.0),
      FloatKind.hurt => (hudRed, 34.0),
      FloatKind.heal => (Sutura.fine, 30.0),
      FloatKind.info => (Sutura.signal, 18.0),
      FloatKind.blocked => (Sutura.signal, 18.0),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: spec.kind == FloatKind.crit ? 1250 : 1050),
      builder: (context, t, child) {
        final pop = t < 0.12 ? 1.4 - 0.4 * (t / 0.12) : 1.0;
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
          if (spec.sub != null) Text(spec.sub!, style: _label(11, color).copyWith(fontWeight: FontWeight.w700, letterSpacing: 3, shadows: _shadow)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                spec.text,
                style: TextStyle(
                  fontFamily: Sutura.fUi,
                  fontWeight: FontWeight.w700,
                  fontSize: size,
                  height: 1,
                  color: color,
                  letterSpacing: spec.kind == FloatKind.miss || spec.kind == FloatKind.info || spec.kind == FloatKind.blocked ? 3 : 0.5,
                  shadows: [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 16), ..._shadow],
                ),
              ),
              if (spec.blocked > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.shield_outlined, size: 15, color: Sutura.signal, shadows: _shadow),
                Text('${spec.blocked}', style: SuturaText.number.copyWith(fontSize: 16, color: Sutura.signal, shadows: _shadow)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso grande entre filetes ("¡CUBRITE!", "DISPARO A LA CABEZA").
class CallOut extends StatelessWidget {
  const CallOut({super.key, required this.text, required this.color, this.sub, this.sticky = false});

  final String text;
  final Color color;
  final String? sub;

  /// Se queda en pantalla (embestida preparada) en vez de desvanecerse.
  final bool sticky;

  @override
  Widget build(BuildContext context) {
    final body = _body();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: sticky ? 260 : 1350),
      builder: (context, t, child) {
        final inT = sticky ? t : (t / 0.16).clamp(0.0, 1.0);
        final out = sticky || t < 0.78 ? 1.0 : 1 - (t - 0.78) / 0.22;
        final wide = 1.0 + 0.22 * (1 - Curves.easeOut.transform(inT));
        final flicker = inT < 1 && (t * 60).floor().isOdd ? 0.5 : 1.0;
        return Opacity(
          opacity: (out * flicker * inT).clamp(0.0, 1.0),
          child: Transform.scale(scaleX: wide, child: child),
        );
      },
      child: body,
    );
  }

  Widget _body() {
    final rule = Container(
      height: 1.6,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.1), color, color, color.withValues(alpha: 0.1)], stops: const [0, 0.15, 0.85, 1]),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(radius: 1.1, colors: [Color(0x99050607), Color(0x00050607)]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rule,
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GrungeTitle(text, size: 44, color: color, letterSpacing: 3, maxLines: 1, textAlign: TextAlign.center),
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  sub!.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: _label(11.5, color).copyWith(fontWeight: FontWeight.w700, letterSpacing: 6, shadows: _shadow),
                ),
              ),
            ],
            const SizedBox(height: 9),
            rule,
          ],
        ),
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
          const Icon(Icons.touch_app_outlined, size: 16, color: Sutura.textHi, shadows: _shadow),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: _label(11.5, Sutura.textHi).copyWith(fontWeight: FontWeight.w700, letterSpacing: 2.4, shadows: _shadow),
            ),
          ),
        ],
      ),
    );
  }
}

/// [FooterStrip] que se achica en pantallas angostas (sus textos no se cortan).
class NarrowFooter extends StatelessWidget {
  const NarrowFooter({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 362.0;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(width: math.max(w, 362), height: 14, child: const FooterStrip()),
      );
    },
  );
}

/// Sacudida corta del HUD (grito, embestida). Cambiar [trigger] la dispara.
class HudShake extends StatelessWidget {
  const HudShake({super.key, required this.trigger, required this.child, this.amplitude = 7});

  final int trigger;
  final double amplitude;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (trigger == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 560),
      builder: (context, t, child) {
        final k = (1 - t) * (1 - t) * amplitude;
        return Transform.translate(offset: Offset(math.sin(t * 63) * k, math.cos(t * 51) * k * 0.6), child: child);
      },
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// Menú rápido de objetos
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
List<ItemId> sortForMenu(List<ItemId> items) {
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

String effectsText(ItemId id) {
  final e = itemDefs[id]!.effects;
  return [if ((e?.health ?? 0) > 0) '+${e!.health} SALUD', if ((e?.stamina ?? 0) > 0) '+${e!.stamina} RES'].join(' · ');
}

class ItemMenu extends StatelessWidget {
  const ItemMenu({super.key, required this.items, required this.countOf, required this.onPick, required this.onClose});

  final List<ItemId> items;
  final int Function(ItemId id) countOf;
  final ValueChanged<ItemId> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final sorted = sortForMenu(items);
    return GritPanel(
      padding: EdgeInsets.zero,
      background: const Color(0xF20F1113),
      border: Sutura.lineBright,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFF15171A),
              border: Border(bottom: BorderSide(color: Sutura.lineStrong)),
            ),
            child: Row(
              children: [
                Container(width: 5, color: Sutura.amber),
                const SizedBox(width: 12),
                Expanded(child: Text('MALETÍN · USO RÁPIDO', style: _label(14, Sutura.textHi).copyWith(letterSpacing: 3))),
                Text('${items.length} DISP.', style: _label(12, Sutura.amber)),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18, color: Sutura.textMid),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cerrar',
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 268),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 120),
              itemCount: sorted.length,
              itemBuilder: (context, i) => HoloIn(
                delay: Duration(milliseconds: 30 * i),
                child: _ItemTile(id: sorted[i], count: countOf(sorted[i]), onTap: () => onPick(sorted[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.id, required this.count, required this.onTap});

  final ItemId id;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final def = itemDefs[id]!;
    final rc = rarityColor(def.rarity.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GritPanel(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
        background: const Color(0xFF15181A),
        border: Sutura.lineStrong,
        corners: rc.withValues(alpha: 0.9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(child: ItemArt(id, size: 58, fallbackIcon: itemIcon(id))),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    def.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SuturaText.caption.copyWith(color: Sutura.textHi, fontSize: 12.5, height: 1.05, letterSpacing: 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                Text('$count', style: SuturaText.number.copyWith(fontSize: 17, color: Sutura.textHi)),
              ],
            ),
            const SizedBox(height: 2),
            Text(effectsText(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(9, Sutura.fine).copyWith(letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
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
    final (title, color, line, code) = switch (status) {
      CombatStatus.won => ('NEUTRALIZADO', Sutura.signal, '$zombieName · NV ${two(zombieLevel)} · $turns ${turns == 1 ? 'turno' : 'turnos'}', 'AMENAZA ELIMINADA'),
      CombatStatus.lost => ('CAÍSTE', hudRed, 'Te arrastraste hasta un lugar seguro.', 'SIGNOS VITALES CRÍTICOS'),
      _ => ('ESCAPASTE', Sutura.amber, 'Vivís para pelear otro día.', 'CONTACTO EVADIDO'),
    };
    final pad = MediaQuery.paddingOf(context);
    var d = 0;
    Duration next() => Duration(milliseconds: 280 + 90 * d++);
    final addedEntries = entries(added);
    final lostEntries = entries(lost);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6050607), Color(0xCC050607), Color(0xF5050607)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, pad.top + 16, 16, pad.bottom + 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HoloIn(
              child: Row(
                children: [
                  Expanded(child: Text('VITA-7  //  INFORME DE ENCUENTRO', style: _label(10.5))),
                  Text('T-${two(turns)}', style: _label(10.5)),
                ],
              ),
            ),
            const Spacer(flex: 3),
            Center(child: _Stamp(text: title, color: color, code: code)),
            const SizedBox(height: 16),
            HoloIn(
              delay: next(),
              child: Text(line, textAlign: TextAlign.center, style: SuturaText.bodyMid.copyWith(color: Sutura.textMid, fontSize: 16)),
            ),
            const SizedBox(height: 20),
            Expanded(
              flex: 7,
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
                          child: GritPanel(
                            accent: Sutura.signal,
                            border: Sutura.signal.withValues(alpha: 0.6),
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                            child: Row(
                              children: [
                                Text('${newLevel ?? ''}'.padLeft(2, '0'), style: SuturaText.number.copyWith(fontSize: 30, color: Sutura.signal)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('SUBISTE DE NIVEL', style: SuturaText.button.copyWith(color: Sutura.signal, fontSize: 16)),
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
                        child: SectionHeader('Recuperado', trailing: addedEntries.isEmpty ? null : '${addedEntries.length} ${addedEntries.length == 1 ? 'objeto' : 'objetos'}', accent: Sutura.amber),
                      ),
                      const SizedBox(height: 8),
                      if (addedEntries.isEmpty)
                        HoloIn(
                          delay: next(),
                          child: Text('No llevaba nada útil.', style: SuturaText.bodyMid.copyWith(color: Sutura.textLow)),
                        )
                      else
                        HoloIn(
                          delay: next(),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [for (final e in addedEntries) _LootTile(id: e.key, count: e.value)],
                          ),
                        ),
                    ],
                    if (overflow.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      HoloIn(
                        delay: next(),
                        child: _Notice(text: 'No entró en el maletín: ${AppState.describeItems(overflow)}', color: Sutura.caution),
                      ),
                    ],
                    if (status == CombatStatus.lost && lostEntries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      HoloIn(
                        delay: next(),
                        child: SectionHeader('Perdido', accent: Sutura.accent, trailingColor: hudRed, trailing: '${lostEntries.length}'),
                      ),
                      const SizedBox(height: 8),
                      HoloIn(
                        delay: next(),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final e in lostEntries) _LootTile(id: e.key, count: e.value, lost: true)],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            HoloIn(
              delay: next(),
              child: ChamferButton(
                label: 'Volver al mapa',
                tone: status == CombatStatus.lost ? ChamferTone.danger : ChamferTone.primary,
                icon: Icons.map_outlined,
                height: 56,
                expand: true,
                onPressed: onExit,
              ),
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 14, child: NarrowFooter()),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color, required this.code});

  final String text;
  final Color color;
  final String code;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: -0.05,
          child: Transform.scale(scale: 1.7 - 0.7 * t, child: child),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 24)],
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 16, 8),
          decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.65), width: 1)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: GrungeTitle(text, size: 50, color: color, letterSpacing: 5, maxLines: 1),
              ),
              const SizedBox(height: 4),
              Text(code, style: _label(11, color).copyWith(fontWeight: FontWeight.w700, letterSpacing: 4.5)),
            ],
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
    return GritPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      accent: color,
      child: Row(
        children: [
          Text(label, style: _label(12, Sutura.textHi)),
          const Spacer(),
          Text(value, style: SuturaText.number.copyWith(fontSize: 28, color: color, height: 1)),
        ],
      ),
    );
  }
}

class _LootTile extends StatelessWidget {
  const _LootTile({required this.id, required this.count, this.lost = false});

  final ItemId id;
  final int count;
  final bool lost;

  @override
  Widget build(BuildContext context) {
    final def = itemDefs[id]!;
    final rc = rarityColor(def.rarity.key);
    return SizedBox(
      width: 108,
      height: 112,
      child: GritPanel(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
        background: const Color(0xFF15181A),
        corners: lost ? hudRed : rc,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Center(child: ItemArt(id, size: 56, fallbackIcon: itemIcon(id), dim: lost))),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    def.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SuturaText.caption.copyWith(color: lost ? Sutura.textMid : Sutura.textHi, fontSize: 12, height: 1.05, letterSpacing: 0.3),
                  ),
                ),
                Text('${lost ? '−' : '×'}$count', style: SuturaText.number.copyWith(fontSize: 16, color: lost ? hudRed : rc)),
              ],
            ),
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
      border: Border(left: BorderSide(color: color, width: 3)),
    ),
    child: Text(text, style: SuturaText.caption.copyWith(color: color, fontSize: 13)),
  );
}
