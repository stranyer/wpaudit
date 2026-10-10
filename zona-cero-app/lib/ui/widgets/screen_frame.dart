import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'grit.dart';

/// Marco común de las pestañas: encabezado en panel de metal con la esquina
/// superior derecha cortada (código chico + título gastado + dato a la derecha).
class TabScreenFrame extends StatelessWidget {
  const TabScreenFrame({super.key, required this.title, required this.code, this.trailing, required this.child});

  final String title;
  final String code;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return GritBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, top + 10, 12, 10),
            child: GritPanel(
              cuts: const Cuts(topRight: 22),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(code.toUpperCase(), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: SuturaText.label.copyWith(fontSize: 11, letterSpacing: 2.4, color: Sutura.textLow)),
                        const SizedBox(height: 4),
                        GrungeTitle(title, size: 36, maxLines: 1),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Línea fina con un tramo de acento a la izquierda.
class HairDivider extends StatelessWidget {
  const HairDivider({super.key, this.accent = Sutura.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: Row(
        children: [
          Container(width: 28, color: accent),
          Expanded(child: Container(color: Sutura.lineHair)),
        ],
      ),
    );
  }
}

/// Rótulo de sección: tick de color + texto mono + línea hasta el borde.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.color = Sutura.accent});

  final String text;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Container(width: 4, height: 15, color: color),
          const SizedBox(width: 10),
          Text(text.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 14, letterSpacing: 3, color: Sutura.textHi)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Sutura.lineHair)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Pestañas segmentadas con subrayado (estilo terminal, sin "pills").
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.badges = const {},
    this.scrollable = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Pestañas de ancho propio con desplazamiento horizontal (para muchas pestañas).
  final bool scrollable;

  /// Índice → cantidad (punto con número sobre la pestaña).
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String l) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: Sutura.fast,
                  padding: scrollable ? const EdgeInsets.symmetric(horizontal: 12) : null,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: i == index ? Sutura.accent : Sutura.lineHair, width: i == index ? 3 : 1)),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: SuturaText.button.copyWith(fontSize: 15, letterSpacing: 2.2, color: i == index ? Sutura.textHi : Sutura.textLow),
                        ),
                      ),
                      if ((badges[i] ?? 0) > 0) ...[
                        const SizedBox(width: 5),
                        CountDot(badges[i]!),
                      ],
                    ],
                  ),
                ),
              );
    if (scrollable) {
      return SizedBox(
        height: 40,
        child: Stack(
          children: [
            const Positioned(left: 0, right: 0, bottom: 0, child: Divider(height: 1, thickness: 1, color: Sutura.lineHair)),
            ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, l) in labels.indexed) Padding(padding: const EdgeInsets.only(right: 4), child: IntrinsicWidth(child: tab(i, l))),
              ],
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: Row(children: [for (final (i, l) in labels.indexed) Expanded(child: tab(i, l))]),
    );
  }
}

/// Indicador numérico pequeño (no leídos, pendientes).
class CountDot extends StatelessWidget {
  const CountDot(this.count, {super.key, this.color = Sutura.accent});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 15),
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
      alignment: Alignment.center,
      child: Text('$count', style: SuturaText.mono.copyWith(fontSize: 10, color: Sutura.textHi, height: 1)),
    );
  }
}

/// Chip de estado con borde fino.
class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.color = Sutura.textMid, this.filled = false, this.icon});

  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : const Color(0x99101214),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 4)],
          Text(text.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 12, letterSpacing: 1.8, color: color, height: 1.1)),
        ],
      ),
    );
  }
}

/// Fila "etiqueta ........ valor" en mono, como una ficha clínica.
class DataRow2 extends StatelessWidget {
  const DataRow2(this.label, this.value, {super.key, this.valueColor = Sutura.textHi});

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 13, color: Sutura.textMid, letterSpacing: 2)),
          const SizedBox(width: 8),
          const Expanded(child: _Dots()),
          const SizedBox(width: 8),
          Text(value, style: SuturaText.number.copyWith(fontSize: 17, color: valueColor)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 10, child: CustomPaint(painter: _DotsPainter()));
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Sutura.lineHair;
    for (double x = 0; x < size.width; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, size.height - 2, 1.5, 1.5), p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

/// Grilla de fondo de las pantallas de terminal.
class FaintGridPainter extends CustomPainter {
  const FaintGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Sutura.lineHair.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(FaintGridPainter oldDelegate) => false;
}

/// Botón cuadrado pequeño (volver, cerrar) con borde fino.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.onPressed, this.size = 40, this.color = Sutura.textMid, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xE6141618),
          border: Border.all(color: Sutura.lineBright),
          image: const DecorationImage(image: AssetImage(Sutura.texPanel), repeat: ImageRepeat.repeat, scale: 2, opacity: 0.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.5, color: onPressed == null ? Sutura.textLow : Sutura.textHi),
      ),
    );
    return tooltip == null ? button : Semantics(label: tooltip, button: true, child: button);
  }
}

/// Peso de inventario en "kg" de interfaz (1 unidad = 0,5 kg).
String kg(num units) => (units * 0.5).toStringAsFixed(1).replaceFirst('.', ',');

/// Distancia legible para nodos públicos ("120 m", "1,4 km").
String distanceLabel(num m) {
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1).replaceFirst('.', ',')} km';
}

/// "hace 12 min" / "hace 3 h".
String agoLabel(int ms) {
  final min = (ms / 60000).round();
  if (min < 1) return 'recién';
  if (min < 60) return 'hace $min min';
  final h = (min / 60).round();
  if (h < 48) return 'hace $h h';
  return 'hace ${(h / 24).round()} días';
}
