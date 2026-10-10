import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'grit.dart';

/// Panel base de la interfaz (v2): metal gastado con borde fino y marcas en las
/// esquinas. [color] tiñe las marcas de las esquinas.
class BracketPanel extends StatelessWidget {
  const BracketPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Sutura.lineBright,
    this.background = Sutura.surface1,
    this.border = true,
    this.bracket = Sutura.bracket,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color background;
  final bool border;
  final double bracket;

  @override
  Widget build(BuildContext context) {
    return GritPanel(
      padding: padding,
      background: background,
      border: border ? Sutura.lineStrong : const Color(0x00000000),
      corners: color,
      child: child,
    );
  }
}
