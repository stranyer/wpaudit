import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _installed = false;

JSObject get _document => globalContext['document']! as JSObject;

/// Agrega (una vez) una hoja de estilo que reubica la atribución del mapa.
void installMapWebTweaks(double top, double right) {
  if (_installed) return;
  _installed = true;
  try {
    final style = _document.callMethod<JSObject>('createElement'.toJS, 'style'.toJS);
    style['textContent'] = [
      for (final corner in ['top-right', 'bottom-right'])
        '.maplibregl-ctrl-$corner{bottom:auto!important;top:${top.round()}px!important;right:${right.round()}px!important}',
      // Botón (i) compacto y oscuro, a tono con los controles.
      '.maplibregl-ctrl-attrib.maplibregl-compact{background:rgba(12,13,14,.78)!important;min-height:22px!important}',
      '.maplibregl-ctrl-attrib-button{filter:invert(1) brightness(.75)!important;background-color:transparent!important;width:22px!important;height:22px!important}',
    ].join('\n').toJS;
    final head = _document['head']! as JSObject;
    head.callMethod<JSAny?>('appendChild'.toJS, style);
  } catch (_) {
    // Sin DOM accesible: la atribución queda donde la pone index.html.
  }
}

/// La atribución compacta de MapLibre arranca desplegada; se pliega al botón
/// (i), como en Android. Tocarlo la vuelve a abrir.
void collapseMapAttribution() {
  try {
    final list = _document.callMethod<JSObject>('querySelectorAll'.toJS, '.maplibregl-ctrl-attrib.maplibregl-compact-show'.toJS);
    final n = (list['length']! as JSNumber).toDartInt;
    for (var i = 0; i < n; i++) {
      final el = list.callMethod<JSObject>('item'.toJS, i.toJS);
      el.callMethod<JSAny?>('removeAttribute'.toJS, 'open'.toJS);
      (el['classList']! as JSObject).callMethod<JSAny?>('remove'.toJS, 'maplibregl-compact-show'.toJS);
    }
  } catch (_) {
    // Si cambia el DOM de MapLibre, la atribución simplemente queda desplegada.
  }
}
