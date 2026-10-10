import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';
import '../theme/tokens.dart';

/// Texturas compartidas que se precargan al iniciar (máscara de desgaste).
abstract final class GritAssets {
  /// Puntitos y rayones (alfa) que "comen" la tinta de los títulos.
  static ui.Image? grunge;

  /// Manchas claras/oscuras (gris) que ensucian la tinta.
  static ui.Image? mottle;

  /// Carga las texturas de desgaste de los títulos. Si falla, se ven limpios.
  static Future<void> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<ui.Image?> img(String key) async {
      try {
        final data = await b.load(key);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      } catch (_) {
        return null;
      }
    }

    grunge ??= await img(Sutura.texGrunge);
    mottle ??= await img(Sutura.texMottle);
  }
}

/// Título condensado en mayúsculas con desgaste (tinta gastada, rayones).
class GrungeTitle extends StatelessWidget {
  const GrungeTitle(
    this.text, {
    super.key,
    this.size = 34,
    this.color = Sutura.textHi,
    this.letterSpacing,
    this.weight = FontWeight.w700,
    this.maxLines = 2,
    this.textAlign,
    this.wear = 1,
  });

  final String text;
  final double size;
  final Color color;
  final double? letterSpacing;
  final FontWeight weight;
  final int maxLines;
  final TextAlign? textAlign;

  /// 0 = sin desgaste (texto limpio).
  final double wear;

  @override
  Widget build(BuildContext context) {
    final t = Text(
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: Sutura.fDisplay,
        fontWeight: weight,
        fontSize: size,
        height: 1.02,
        letterSpacing: letterSpacing ?? size * 0.06,
        color: color,
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
    );
    if (wear <= 0) return t;
    // Las texturas se escalan con el tamaño del texto para que el desgaste
    // tenga una granulometría pareja en títulos chicos y grandes.
    final scale = (size / 60).clamp(0.35, 1.6);
    final matrix = Matrix4.diagonal3Values(scale, scale, 1).storage;
    Widget out = t;
    final mottle = GritAssets.mottle;
    if (mottle != null) {
      out = ShaderMask(
        blendMode: BlendMode.modulate,
        shaderCallback: (rect) => ImageShader(mottle, TileMode.repeated, TileMode.repeated, matrix),
        child: out,
      );
    }
    final mask = GritAssets.grunge;
    if (mask != null) {
      out = ShaderMask(
        blendMode: BlendMode.dstOut,
        shaderCallback: (rect) => ImageShader(mask, TileMode.repeated, TileMode.repeated, matrix),
        child: out,
      );
    }
    return out;
  }
}

/// Esquinas que se recortan en diagonal en un [GritPanel].
class Cuts {
  const Cuts({this.topLeft = 0, this.topRight = 0, this.bottomRight = 0, this.bottomLeft = 0});
  const Cuts.none() : this();
  const Cuts.br([double c = Sutura.chamfer]) : this(bottomRight: c);
  const Cuts.tr([double c = Sutura.chamfer]) : this(topRight: c);
  final double topLeft, topRight, bottomRight, bottomLeft;

  Path path(Size s) => Path()
    ..moveTo(topLeft, 0)
    ..lineTo(s.width - topRight, 0)
    ..lineTo(s.width, topRight)
    ..lineTo(s.width, s.height - bottomRight)
    ..lineTo(s.width - bottomRight, s.height)
    ..lineTo(bottomLeft, s.height)
    ..lineTo(0, s.height - bottomLeft)
    ..lineTo(0, topLeft)
    ..close();
}

/// Panel de metal gastado: fondo oscuro con textura, borde fino, marcas en las
/// esquinas y (opcional) un acento lateral de color.
class GritPanel extends StatelessWidget {
  const GritPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.background = Sutura.surface1,
    this.border = Sutura.lineStrong,
    this.corners = Sutura.lineBright,
    this.accent,
    this.cuts = const Cuts.none(),
    this.texture = true,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color border;

  /// Color de las marcas en L de las esquinas (null = sin marcas).
  final Color? corners;

  /// Franja de color a la izquierda (rojo para secciones activas, ámbar para recursos).
  final Color? accent;
  final Cuts cuts;
  final bool texture;

  /// Resplandor exterior (botón destacado, advertencia).
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GritPainter(background: background, border: border, corners: corners, accent: accent, cuts: cuts, glow: glow),
      child: ClipPath(
        clipper: _CutsClipper(cuts),
        child: Stack(
          children: [
            if (texture)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.55,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(image: AssetImage(Sutura.texPanel), repeat: ImageRepeat.repeat, scale: 2),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _CutsClipper extends CustomClipper<Path> {
  _CutsClipper(this.cuts);
  final Cuts cuts;
  @override
  Path getClip(Size size) => cuts.path(size);
  @override
  bool shouldReclip(_CutsClipper old) => old.cuts != cuts;
}

class _GritPainter extends CustomPainter {
  _GritPainter({required this.background, required this.border, required this.corners, required this.accent, required this.cuts, this.glow});

  final Color background;
  final Color border;
  final Color? corners;
  final Color? accent;
  final Cuts cuts;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size s) {
    final path = cuts.path(s);
    if (glow != null) {
      canvas.drawPath(path, Paint()
        ..color = glow!.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
    }
    canvas.drawPath(path, Paint()..color = background);
    canvas.drawPath(path, Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    if (accent != null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, 4, s.height), Paint()..color = accent!);
    }
    final c = corners;
    if (c != null) {
      final p = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.square;
      const k = 7.0;
      final path2 = Path();
      if (cuts.topLeft == 0) {
        path2..moveTo(0, k)..lineTo(0, 0)..lineTo(k, 0);
      }
      if (cuts.topRight == 0) {
        path2..moveTo(s.width - k, 0)..lineTo(s.width, 0)..lineTo(s.width, k);
      }
      if (cuts.bottomRight == 0) {
        path2..moveTo(s.width, s.height - k)..lineTo(s.width, s.height)..lineTo(s.width - k, s.height);
      }
      if (cuts.bottomLeft == 0) {
        path2..moveTo(k, s.height)..lineTo(0, s.height)..lineTo(0, s.height - k);
      }
      canvas.drawPath(path2, p);
    }
  }

  @override
  bool shouldRepaint(_GritPainter old) =>
      old.background != background || old.border != border || old.corners != corners || old.accent != accent || old.glow != glow;
}

/// Encabezado de sección: barra con acento rojo, título espaciado y dato a la derecha.
/// ("EQUIPO ACTUAL", "INVENTARIO · 9 / 24 ESPACIOS", "ANTENA · NIVEL 1/5").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.icon, this.accent = Sutura.accent, this.trailingColor});

  final String title;
  final String? trailing;
  final IconData? icon;
  final Color accent;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF181A1D),
        border: Border(bottom: BorderSide(color: Sutura.lineStrong), top: BorderSide(color: Sutura.lineHair)),
      ),
      child: Row(
        children: [
          Container(width: 6, color: accent),
          const SizedBox(width: 12),
          if (icon != null) ...[Icon(icon, size: 19, color: Sutura.textMid), const SizedBox(width: 10)],
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 15.5, letterSpacing: 3.2, color: Sutura.textHi),
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                trailing!.toUpperCase(),
                style: SuturaText.label.copyWith(color: trailingColor ?? Sutura.textMid, fontSize: 13.5, letterSpacing: 2.2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pestañas grandes ("OBJETOS" / "TALLER"): la activa con tinte rojo.
class GritTabs extends StatelessWidget {
  const GritTabs({super.key, required this.labels, required this.index, required this.onChanged, this.height = 48});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final (i, l) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != index) HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: Sutura.fast,
                  decoration: BoxDecoration(
                    gradient: i == index
                        ? const LinearGradient(colors: [Color(0xFF4A1310), Color(0xFF2A0D0B)], begin: Alignment.centerLeft, end: Alignment.centerRight)
                        : null,
                    color: i == index ? null : const Color(0xFF151719),
                    border: Border.all(color: i == index ? Sutura.accent : Sutura.lineStrong, width: i == index ? 1.4 : 1),
                    boxShadow: i == index ? const [BoxShadow(color: Color(0x66C8322B), blurRadius: 12)] : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    l.toUpperCase(),
                    style: TextStyle(
                      fontFamily: Sutura.fUi,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      letterSpacing: 3.6,
                      color: i == index ? Sutura.textHi : Sutura.textMid,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barra de segmentos gruesos (peso, progreso de antena, salud del enemigo).
class BlockBar extends StatelessWidget {
  const BlockBar({super.key, required this.ratio, this.segments = 14, this.color = Sutura.accent, this.height = 7, this.gap = 3, this.empty = const Color(0xFF2A2D30)});

  final double ratio;
  final int segments;
  final Color color;
  final double height;
  final double gap;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    final r = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
    final filled = (r * segments).ceil().clamp(r > 0 ? 1 : 0, segments);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: ColoredBox(color: i < filled ? color : empty)),
          ],
        ],
      ),
    );
  }
}

/// Barra continua de estado (SALUD / RESISTENCIA) con fondo oscuro.
class StatBar extends StatelessWidget {
  const StatBar({super.key, required this.ratio, required this.color, this.height = 7});

  final double ratio;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: const Color(0xFF26292C),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: ratio.isNaN ? 0 : ratio.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.75), color]),
          ),
        ),
      ),
    );
  }
}

/// Foto del objeto (render HD) con alternativa de ícono si falta el asset.
class ItemArt extends StatelessWidget {
  const ItemArt(this.id, {super.key, this.size = 64, this.fallbackIcon, this.dim = false});

  final ItemId id;
  final double size;
  final IconData? fallbackIcon;
  final bool dim;

  static String assetFor(ItemId id) => 'assets/art/items/${id.key}.webp';

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      assetFor(id),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Icon(fallbackIcon ?? Icons.inventory_2_outlined, size: size * 0.6, color: Sutura.textMid),
    );
    if (!dim) return img;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.25, 0.25, 0.25, 0, 0, //
        0.25, 0.25, 0.25, 0, 0,
        0.25, 0.25, 0.25, 0, 0,
        0, 0, 0, 0.55, 0,
      ]),
      child: img,
    );
  }
}

/// Fondo de pantalla: negro con textura de metal muy tenue y viñeta.
class GritBackground extends StatelessWidget {
  const GritBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Sutura.void_),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(image: AssetImage(Sutura.texPanel), repeat: ImageRepeat.repeat, scale: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(radius: 1.15, colors: [Color(0x00000000), Color(0xB0000000)], stops: [0.55, 1]),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Pie de pantalla ornamental: "VITA-7 // PROTOCOLO SUTURA ····· C.A.B.A. ZONA CERO ||||".
class FooterStrip extends StatelessWidget {
  const FooterStrip({super.key, this.left = 'VITA-7  //  PROTOCOLO SUTURA', this.right = 'C.A.B.A.   ZONA CERO'});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(left, maxLines: 1, style: SuturaText.micro.copyWith(fontSize: 9, color: Sutura.textLow)),
          ),
        ),
        const SizedBox(width: 12),
        const Spacer(),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(right, maxLines: 1, style: SuturaText.micro.copyWith(fontSize: 9, color: Sutura.textLow)),
          ),
        ),
        const SizedBox(width: 8),
        const SizedBox(width: 34, height: 11, child: CustomPaint(painter: _BarcodePainter())),
      ],
    );
  }
}

class _BarcodePainter extends CustomPainter {
  const _BarcodePainter();
  static const _bars = [2, 1, 1, 3, 1, 2, 1, 1, 2, 1, 3, 1, 1, 2, 1];
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Sutura.textLow;
    var x = 0.0;
    for (final (i, w) in _bars.indexed) {
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w * 1.0, size.height), p);
      x += w + 0.6;
      if (x > size.width) break;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => false;
}

/// Precarga las imágenes más usadas para que no "parpadeen" al aparecer.
Future<void> precacheGrit(BuildContext context) async {
  final futures = <Future<void>>[
    precacheImage(const AssetImage(Sutura.texPanel), context),
    for (final id in ItemId.values) precacheImage(AssetImage(ItemArt.assetFor(id)), context).catchError((_) {}),
  ];
  await Future.wait(futures);
}
