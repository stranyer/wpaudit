import 'web_tweaks_stub.dart' if (dart.library.js_interop) 'web_tweaks_web.dart' as impl;

/// Ajustes del mapa que solo existen en web (la atribución de OpenStreetMap es
/// un elemento del DOM de MapLibre que queda por encima del lienzo de Flutter):
/// la ubica a la derecha, `bottom` px por encima del borde inferior del mapa,
/// donde no tapa la escala ni las fichas. En Android/iOS no hace nada.
void installMapWebTweaks(double bottom) => impl.installMapWebTweaks(bottom);

/// Pliega la atribución al botón (i), como en Android. En Android/iOS no hace nada.
void collapseMapAttribution() => impl.collapseMapAttribution();
