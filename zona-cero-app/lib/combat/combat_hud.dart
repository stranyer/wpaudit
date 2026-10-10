// Piezas del HUD del combate (widgets Flutter sobre el escenario Flame), con el
// lenguaje visual v2 de la referencia: paneles de metal gastado con esquinas
// cortadas (GritPanel), títulos con desgaste (GrungeTitle), barras de bloques
// y fotos de objetos (ItemArt).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../state/app_state.dart' show AppState;
import '../ui/theme/tokens.dart';
import '../ui/widgets/chamfer_button.dart';
import '../ui/widgets/ecg_monitor.dart';
import '../ui/widgets/grit.dart';
import '../ui/widgets/holo_in.dart';
import '../ui/widgets/weapon_panel.dart' show ammoSplit;

export 'fp_hand.dart' show WeaponMode;

/// Rojo de alerta legible sobre la escena oscura.
const hudRed = Color(0xFFE5483F);

/// Fondo de los paneles del HUD (casi negro, translúcido).
const _panelBg = Color(0xCC0B0C0E);

/// Línea fina de los marcos.
const _frame = Color(0xFF55595C);

const _shadow = [Shadow(color: Color(0xE6000000), blurRadius: 6), Shadow(color: Color(0x99000000), blurRadius: 14)];

String two(num v) => v.round().clamp(0, 999).toString().padLeft(2, '0');

/// "15:58" de un instante.
String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TextStyle _label([double size = 10.5, Color color = Sutura.textMid]) =>
    SuturaText.label.copyWith(fontSize: size, color: color, letterSpacing: size * 0.26);

// -----------------------------------------------------------------------------
// Íconos dibujados (la referencia usa trazos finos, no los de Material)
// -----------------------------------------------------------------------------

/// Triángulo de advertencia con "!" (contorno).
class WarningGlyph extends StatelessWidget {
  const WarningGlyph({super.key, this.size = 18, this.color = hudRed, this.stroke});

  final double size;
  final Color color;
  final double? stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 1.12, size),
    painter: _WarningPainter(color, stroke ?? math.max(1.4, size * 0.085)),
  );
}

class _WarningPainter extends CustomPainter {
  _WarningPainter(this.color, this.stroke);
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.miter;
    final h = stroke / 2;
    final tri = Path()
      ..moveTo(s.width / 2, h)
      ..lineTo(s.width - h, s.height - h)
      ..lineTo(h, s.height - h)
      ..close();
    canvas.drawPath(tri, Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 2.5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.6));
    canvas.drawPath(tri, p);
    final bar = Paint()
      ..color = color
      ..strokeWidth = stroke * 1.15
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset(s.width / 2, s.height * 0.36), Offset(s.width / 2, s.height * 0.68), bar);
    canvas.drawCircle(Offset(s.width / 2, s.height * 0.8), stroke * 0.75, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WarningPainter old) => old.color != color || old.stroke != stroke;
}

/// Mira (avisos de tiro a la cabeza y golpe crítico).
class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.shortestSide / 2 - 1.5;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r * 0.62, p);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * (r * 0.32), c + d * r, p);
    }
    canvas.drawCircle(c, 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.color != color;
}

/// Escudo de contorno (esquiva, cubierto).
class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.9, h * 0.18)
      ..cubicTo(w * 0.9, h * 0.6, w * 0.72, h * 0.82, w * 0.5, h * 0.96)
      ..cubicTo(w * 0.28, h * 0.82, w * 0.1, h * 0.6, w * 0.1, h * 0.18)
      ..close();
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.color != color;
}

/// Figura agachada cubriéndose (botón CUBRIRSE).
class CrouchGlyph extends StatelessWidget {
  const CrouchGlyph({super.key, this.size = 26, this.color = Sutura.textHi});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size * 0.9, size), painter: _CrouchPainter(color));
}

class _CrouchPainter extends CustomPainter {
  _CrouchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()..color = color;
    final limb = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.17
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Cabeza.
    canvas.drawCircle(Offset(w * 0.6, h * 0.12), w * 0.13, fill);
    // Torso inclinado hacia adelante.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.52, h * 0.3)
        ..lineTo(w * 0.36, h * 0.56),
      limb..strokeWidth = w * 0.24,
    );
    limb.strokeWidth = w * 0.15;
    // Brazos en guardia delante de la cara.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.52, h * 0.32)
        ..lineTo(w * 0.78, h * 0.42)
        ..lineTo(w * 0.86, h * 0.26),
      limb,
    );
    // Pierna adelantada (rodilla arriba) y pierna de atrás (arrodillada).
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h * 0.58)
        ..lineTo(w * 0.7, h * 0.68)
        ..lineTo(w * 0.66, h * 0.95),
      limb,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.34, h * 0.6)
        ..lineTo(w * 0.24, h * 0.84)
        ..lineTo(w * 0.04, h * 0.92),
      limb,
    );
  }

  @override
  bool shouldRepaint(_CrouchPainter old) => old.color != color;
}

// -----------------------------------------------------------------------------
// Signos vitales (arriba a la izquierda, debajo del logo)
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
      padding: const EdgeInsets.fromLTRB(11, 8, 12, 10),
      background: _panelBg,
      border: ratio < 0.3 ? Sutura.danger : _frame,
      corners: null,
      cuts: const Cuts(bottomLeft: 7, bottomRight: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('SIGNOS VITALES', maxLines: 1, overflow: TextOverflow.clip, style: _label(10, Sutura.textMid))),
              if (defending) Text('CUBIERTO', style: _label(9, Sutura.signal)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              EcgMonitor(ratio: ratio, width: 74, height: 28, showLabel: false),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: health.round().toString().padLeft(2, '0'),
                          style: SuturaText.number.copyWith(fontSize: 30, color: vc, fontWeight: FontWeight.w600, shadows: [Shadow(color: vc.withValues(alpha: 0.4), blurRadius: 10)]),
                        ),
                        TextSpan(text: ' /$maxHealth', style: SuturaText.number.copyWith(fontSize: 15, color: Sutura.textLow, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('RESISTENCIA', maxLines: 1, style: _label(9.5, Sutura.textMid)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: BlockBar(ratio: sRatio, segments: 7, color: Sutura.fine.withValues(alpha: 0.85), empty: const Color(0xFF34373A), height: 5, gap: 4),
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
  1 => ('PAREJA', Sutura.caution),
  2 => ('ALTA', hudRed),
  _ => ('MORTAL', hudRed),
};

/// Retrato de la criatura (`assets/art/avatars/<tipo>.webp`).
String avatarAsset(ZombieTypeId type) => 'assets/art/avatars/${type.key}.webp';

class TargetPanel extends StatelessWidget {
  const TargetPanel({
    super.key,
    required this.name,
    required this.level,
    required this.threat,
    required this.health,
    required this.maxHealth,
    this.type,
  });

  final String name;
  final int level;
  final int threat;
  final int health;
  final int maxHealth;

  /// Para el retrato (sin tipo, no hay retrato).
  final ZombieTypeId? type;

  @override
  Widget build(BuildContext context) {
    final (tl, tc) = threatInfo(threat);
    final ratio = maxHealth <= 0 ? 0.0 : (health / maxHealth).clamp(0.0, 1.0);
    return GritPanel(
      padding: EdgeInsets.zero,
      background: _panelBg,
      border: _frame,
      corners: null,
      cuts: const Cuts(topLeft: 7, bottomLeft: 12, topRight: 4, bottomRight: 7),
      child: Stack(
        children: [
          // Retrato desaturado que se funde con el panel por la izquierda y abajo.
          if (type != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 22,
              width: 82,
              child: IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0x00000000), Color(0xC0000000), Color(0xFF000000)],
                    stops: [0, 0.38, 1],
                  ).createShader(r),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                      stops: [0, 0.7, 1],
                    ).createShader(r),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.42, 0.42, 0.12, 0, 0, //
                        0.36, 0.46, 0.12, 0, 0,
                        0.34, 0.4, 0.18, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                      child: Image.asset(
                        avatarAsset(type!),
                        fit: BoxFit.cover,
                        alignment: const Alignment(0.2, -0.4),
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('OBJETIVO', style: _label(10, Sutura.textMid)),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 28),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: GrungeTitle(name, size: 23, letterSpacing: 1.6, maxLines: 1, wear: 0.6),
                  ),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'NV ', style: _label(11, Sutura.textLow).copyWith(letterSpacing: 1.5)),
                      TextSpan(text: two(level), style: SuturaText.number.copyWith(fontSize: 20, color: Sutura.textMid, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(height: 1, color: const Color(0xFF34383B)),
                const SizedBox(height: 6),
                Semantics(
                  label: 'Salud del objetivo $health de $maxHealth',
                  child: Container(
                    height: 6,
                    color: const Color(0xFF34373A),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFFC23A30), Color(0xFFDA4C3E)]),
                          boxShadow: [BoxShadow(color: Color(0x55E5483F), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [const TextSpan(text: 'AMENAZA '), TextSpan(text: tl)]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(9.5, tc).copyWith(letterSpacing: 2.6, fontWeight: FontWeight.w600),
                ),
              ],
            ),
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
    return CustomPaint(
      painter: const _TagFramePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 6, 14, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WarningGlyph(size: 14),
            const SizedBox(width: 9),
            Text(text, style: _label(10, Sutura.textHi).copyWith(letterSpacing: 2.4, fontWeight: FontWeight.w600, shadows: _shadow)),
          ],
        ),
      ),
    );
  }
}

/// Marco de la etiqueta: línea fina arriba que se apaga a la derecha y una
/// escuadra roja abajo a la izquierda.
class _TagFramePainter extends CustomPainter {
  const _TagFramePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()
      ..shader = const LinearGradient(colors: [Color(0xCC120A09), Color(0x660B0C0E), Color(0x000B0C0E)], stops: [0, 0.7, 1]).createShader(r));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, 1),
      Paint()..shader = const LinearGradient(colors: [_frame, Color(0x0055595C)], stops: [0.6, 1]).createShader(r),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, s.height - 1, s.width, 1),
      Paint()..shader = const LinearGradient(colors: [Color(0xFF3A3D40), Color(0x003A3D40)], stops: [0.5, 1]).createShader(r),
    );
    final red = Paint()
      ..color = hudRed
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, s.height * 0.35)
        ..lineTo(0, s.height)
        ..lineTo(s.width * 0.22, s.height),
      red,
    );
    canvas.drawLine(const Offset(0, 0), Offset(0, s.height * 0.35), Paint()..color = _frame);
  }

  @override
  bool shouldRepaint(_TagFramePainter oldDelegate) => false;
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
        color: Color.alphaBlend(widget.color.withValues(alpha: 0.12), const Color(0xCC0B0C0E)),
        border: Border(
          left: BorderSide(color: widget.color, width: 2),
          top: BorderSide(color: widget.color.withValues(alpha: 0.3)),
          right: BorderSide(color: widget.color.withValues(alpha: 0.3)),
          bottom: BorderSide(color: widget.color.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 13, color: widget.color), const SizedBox(width: 6)],
          Text(widget.text, style: _label(10, widget.color).copyWith(fontWeight: FontWeight.w700)),
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
  LogLine(this.id, this.text, this.color, {DateTime? at}) : at = at ?? DateTime.now();
  final int id;
  final String text;
  final Color color;

  /// Cuándo pasó (se muestra "HH:MM").
  final DateTime at;
}

class CombatLog extends StatelessWidget {
  const CombatLog({super.key, required this.lines, this.visible = 3});

  final List<LogLine> lines;
  final int visible;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length > visible ? lines.sublist(lines.length - visible) : lines;
    final line = SuturaText.body.copyWith(fontSize: 12.5, height: 1.3, letterSpacing: 0.7, fontWeight: FontWeight.w500);
    return IgnorePointer(
      child: CustomPaint(
        painter: const _LogFramePainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REGISTRO DE COMBATE', maxLines: 1, style: _label(8.5, Sutura.textLow).copyWith(letterSpacing: 2)),
              const SizedBox(height: 3),
              Expanded(
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
                            padding: const EdgeInsets.only(top: 1),
                            child: HoloIn(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(clock(l.at), style: line.copyWith(color: Sutura.textMid, fontFeatures: const [FontFeature.tabularFigures()])),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      l.text,
                                      maxLines: i == shown.length - 1 ? 2 : 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: line.copyWith(color: i == shown.length - 1 ? l.color : (i == shown.length - 2 ? Sutura.textHi.withValues(alpha: 0.85) : Sutura.textMid)),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Marco del registro: fondo oscuro, línea fina arriba que se apaga a la
/// derecha y filete rojo a la izquierda.
class _LogFramePainter extends CustomPainter {
  const _LogFramePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()
      ..shader = const LinearGradient(colors: [Color(0xD00B0C0E), Color(0xB00B0C0E), Color(0x400B0C0E)], stops: [0, 0.7, 1]).createShader(r));
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, 1), Paint()
      ..shader = const LinearGradient(colors: [_frame, Color(0x0055595C)], stops: [0.55, 1]).createShader(r));
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, s.height), Paint()..color = const Color(0xFF3A3D40));
    canvas.drawRect(Rect.fromLTWH(0, s.height * 0.38, 1.6, s.height * 0.62), Paint()..color = hudRed.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_LogFramePainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Arma (abajo a la derecha, encima de la mano)
// -----------------------------------------------------------------------------

/// Panel compacto del arma: foto, nombre y "07 / 32" (o el daño, cuerpo a cuerpo).
class CombatWeaponPanel extends StatelessWidget {
  const CombatWeaponPanel({super.key, required this.weapon, required this.ammo, this.height = 64, this.swapLabel, this.swapColor = Sutura.amber});

  /// null = puños.
  final ItemId? weapon;

  /// Munición total disponible (solo se muestra con armas de fuego).
  final int ammo;
  final double height;

  /// "FUEGO" / "C/C": se puede tocar para cambiar.
  final String? swapLabel;
  final Color swapColor;

  @override
  Widget build(BuildContext context) {
    final w = weapon;
    final def = w == null ? null : itemDefs[w]!;
    final firearm = (def?.weapon?.ammoPerShot ?? 0) > 0;
    final split = firearm ? ammoSplit(w!, ammo) : null;
    final name = (def?.name ?? 'Puños').toUpperCase();
    return GritPanel(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      background: _panelBg,
      border: _frame,
      corners: null,
      cuts: const Cuts(topLeft: 7, bottomRight: 12),
      child: SizedBox(
        height: height - 12,
        child: Row(
          children: [
            SizedBox(
              width: height * 0.95,
              child: w == null
                  ? const Icon(Icons.back_hand_outlined, size: 28, color: Sutura.textMid)
                  : ItemArt(w, size: height * 0.95),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (swapLabel != null) ...[
                        Icon(Icons.swap_horiz, size: 12, color: swapColor),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(name, maxLines: 1, style: _label(10.5, Sutura.textHi).copyWith(letterSpacing: 1.6)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: split != null
                        ? Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: split.loaded.toString().padLeft(2, '0'),
                                  style: TextStyle(color: split.loaded == 0 ? Sutura.danger : Sutura.textHi),
                                ),
                                TextSpan(
                                  text: ' / ${split.reserve.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 18, color: Sutura.textMid),
                                ),
                              ],
                            ),
                            style: SuturaText.number.copyWith(fontSize: 30, fontWeight: FontWeight.w500),
                          )
                        : Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'DAÑO ', style: _label(9.5, Sutura.textMid)),
                                TextSpan(
                                  text: def?.weapon == null ? '3–6' : '${def!.weapon!.damage.min}–${def.weapon!.damage.max}',
                                  style: SuturaText.number.copyWith(fontSize: 24, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Botonera: CUBRIRSE enmarcado (rojo) · OBJETOS · HUIR
// -----------------------------------------------------------------------------

/// Botón de acción. `framed` = el destacado con marco rojo (CUBRIRSE).
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.onTap,
    this.framed = false,
    this.highlight = false,
    this.active = false,
    this.height = 58,
  });

  /// Ícono (un widget: hay glifos dibujados).
  final Widget icon;
  final String label;
  final String? sub;
  final VoidCallback? onTap;

  /// Botón enmarcado con contorno rojo (CUBRIRSE).
  final bool framed;

  /// Resplandor fuerte (CUBRIRSE ante una embestida, HUIR al tocar atrás).
  final bool highlight;

  /// Menú abierto (OBJETOS).
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = active ? Sutura.amber : (framed || highlight ? Sutura.textHi : Sutura.textMid);
    Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconTheme.merge(data: IconThemeData(color: fg, size: 24), child: icon),
        SizedBox(width: framed ? 14 : 9),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: SuturaText.button.copyWith(fontSize: framed ? 18 : 15.5, letterSpacing: framed ? 2.6 : 2.2, color: fg, height: 1.05, fontWeight: FontWeight.w600),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!.toUpperCase(), style: _label(9.5, fg.withValues(alpha: 0.62)).copyWith(letterSpacing: 1.6)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    if (framed) {
      content = _CoverFrame(highlight: highlight && enabled, child: content);
    } else if (highlight && enabled) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(radius: 0.9, colors: [hudRed.withValues(alpha: 0.22), hudRed.withValues(alpha: 0)]),
        ),
        child: content,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label${sub == null ? '' : ' $sub'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: Sutura.fast,
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(height: height, child: content),
        ),
      ),
    );
  }
}

/// Marco rojo con esquinas cortadas y resplandor (late si [highlight]).
class _CoverFrame extends StatefulWidget {
  const _CoverFrame({required this.highlight, required this.child});
  final bool highlight;
  final Widget child;

  @override
  State<_CoverFrame> createState() => _CoverFrameState();
}

class _CoverFrameState extends State<_CoverFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.highlight) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_CoverFrame old) {
    super.didUpdateWidget(old);
    if (widget.highlight && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.highlight && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        painter: _CoverFramePainter(widget.highlight ? 0.55 + 0.45 * _c.value : 0.0),
        child: child,
      ),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: widget.child),
    );
  }
}

class _CoverFramePainter extends CustomPainter {
  _CoverFramePainter(this.pulse);

  /// 0 = marco rojo tranquilo; 1 = resplandor pleno.
  final double pulse;

  static Path frame(Size s) {
    const c = 12.0, k = 5.0;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(s.width - k, 0)
      ..lineTo(s.width, k)
      ..lineTo(s.width, s.height - c)
      ..lineTo(s.width - c, s.height)
      ..lineTo(k, s.height)
      ..lineTo(0, s.height - k)
      ..lineTo(0, c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final path = frame(s);
    final r = Offset.zero & s;
    canvas.drawPath(path, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.9, 1),
        radius: 1.4,
        colors: [Color.lerp(const Color(0xE0301010), const Color(0xF04A1410), pulse)!, const Color(0xE6120D0D)],
      ).createShader(r));
    canvas.drawPath(path, Paint()
      ..color = hudRed.withValues(alpha: 0.28 + 0.42 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + 5 * pulse
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 6 * pulse));
    canvas.drawPath(path, Paint()
      ..color = Color.lerp(const Color(0xFFB8352C), const Color(0xFFFF5A4C), pulse)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_CoverFramePainter old) => old.pulse != pulse;
}

/// Fila de acciones como en la referencia: CUBRIRSE enmarcado y OBJETOS /
/// HUIR sin marco, separados por filetes verticales, dentro de un marco fino.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.cover, required this.items, required this.flee, this.height = 58});

  final Widget cover;
  final Widget items;
  final Widget flee;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 14), color: const Color(0xFF3E4245));
    return CustomPaint(
      painter: const _BarFramePainter(),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 23, child: cover),
            const SizedBox(width: 4),
            rule(),
            Expanded(flex: 19, child: items),
            rule(),
            Expanded(flex: 16, child: flee),
          ],
        ),
      ),
    );
  }
}

class _BarFramePainter extends CustomPainter {
  const _BarFramePainter();

  @override
  void paint(Canvas canvas, Size s) {
    const c = 12.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width - c, 0)
      ..lineTo(s.width, c)
      ..lineTo(s.width, s.height)
      ..lineTo(c, s.height)
      ..lineTo(0, s.height - c)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xB00A0B0C));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF3A3E41)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_BarFramePainter oldDelegate) => false;
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

/// Ícono sobre el aviso central.
enum CallIcon { warning, crosshair, shield, none }

/// Aviso central como en la referencia: ícono de contorno arriba, el aviso
/// grande con desgaste ("¡CUBRITE!") y una bajada en minúsculas debajo
/// ("Prepara una embestida").
class CallOut extends StatelessWidget {
  const CallOut({super.key, required this.text, required this.color, this.sub, this.sticky = false, this.icon = CallIcon.warning});

  final String text;
  final Color color;
  final String? sub;
  final CallIcon icon;

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
        final pop = 1.0 + 0.18 * (1 - Curves.easeOut.transform(inT));
        final flicker = inT < 1 && (t * 60).floor().isOdd ? 0.5 : 1.0;
        return Opacity(
          opacity: (out * flicker * inT).clamp(0.0, 1.0),
          child: Transform.scale(scale: pop, child: child),
        );
      },
      child: body,
    );
  }

  Widget _icon() => switch (icon) {
    CallIcon.warning => WarningGlyph(size: 30, color: color, stroke: 2.6),
    CallIcon.crosshair => CustomPaint(size: const Size(32, 32), painter: _CrosshairPainter(color)),
    CallIcon.shield => CustomPaint(size: const Size(28, 32), painter: _ShieldPainter(color)),
    CallIcon.none => const SizedBox.shrink(),
  };

  Widget _body() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(radius: 0.75, colors: [Color(0x8C050607), Color(0x00050607)]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != CallIcon.none) ...[_icon(), const SizedBox(height: 7)],
          FittedBox(
            fit: BoxFit.scaleDown,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 30, spreadRadius: -6)],
              ),
              child: GrungeTitle(text, size: 42, color: color, letterSpacing: 2.2, maxLines: 1, textAlign: TextAlign.center),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                sub!,
                textAlign: TextAlign.center,
                style: SuturaText.body.copyWith(fontSize: 16.5, height: 1.1, letterSpacing: 1.1, color: const Color(0xFFDAD6CE), fontWeight: FontWeight.w500, shadows: _shadow),
              ),
            ),
          ],
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
