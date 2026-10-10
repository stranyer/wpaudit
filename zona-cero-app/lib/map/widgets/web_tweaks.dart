import 'web_tweaks_stub.dart' if (dart.library.js_interop) 'web_tweaks_web.dart' as impl;

/// Ajustes del mapa que solo existen en web (la atribución de OpenStreetMap y
/// de la imagen satelital es un elemento del DOM de MapLibre que queda por
/// encima del lienzo de Flutter): la ubica arriba a la derecha, `top` px por
/// debajo del borde superior del mapa, donde no tapa el encabezado ni los
/// controles. En Android/iOS no hace nada.
void installMapWebTweaks({required double top, double right = 12}) => impl.installMapWebTweaks(top, right);

/// Pliega la atribución al botón (i), como en Android. En Android/iOS no hace nada.
void collapseMapAttribution() => impl.collapseMapAttribution();
