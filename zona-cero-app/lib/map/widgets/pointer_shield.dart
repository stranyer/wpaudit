import 'package:flutter/widgets.dart';

import 'pointer_shield_stub.dart' if (dart.library.js_interop) 'pointer_shield_web.dart' as impl;

/// Evita que los toques sobre la interfaz atraviesen hasta el mapa.
///
/// Solo hace falta en web: allí MapLibre es un elemento del DOM debajo del
/// lienzo de Flutter y recibe los eventos aunque haya un widget encima (misma
/// técnica que el paquete `pointer_interceptor`: un `div` invisible detrás del
/// widget). En Android/iOS devuelve el hijo tal cual.
class PointerShield extends StatelessWidget {
  const PointerShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final type = impl.shieldViewType();
    if (type == null) return child;
    return Stack(
      children: [
        Positioned.fill(child: HtmlElementView(viewType: type)),
        child,
      ],
    );
  }
}
