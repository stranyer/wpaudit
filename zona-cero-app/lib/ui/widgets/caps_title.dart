import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'grit.dart';

/// Título de pantalla/tarjeta: condensado, en mayúsculas y con desgaste.
class CapsTitle extends StatelessWidget {
  const CapsTitle(this.text, {super.key, this.size = 18, this.color = Sutura.textHi, this.weight = FontWeight.w700});

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => GrungeTitle(text, size: size * 1.25, color: color, weight: weight);
}
