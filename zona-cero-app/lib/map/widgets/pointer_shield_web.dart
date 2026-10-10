import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

const _viewType = 'zc-pointer-shield';
bool _registered = false;

/// Registra (una vez) una vista de plataforma que es un `div` vacío: queda por
/// encima del mapa en el DOM y se queda con los eventos de puntero.
String? shieldViewType() {
  if (!_registered) {
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final document = globalContext['document']! as JSObject;
        final div = document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
        final style = div['style']! as JSObject;
        style['width'] = '100%'.toJS;
        style['height'] = '100%'.toJS;
        return div;
      },
      isVisible: false,
    );
  }
  return _viewType;
}
