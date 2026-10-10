import 'dart:async';

import 'package:flutter/foundation.dart';

enum ToastTone { info, good, loot, warn, bad, network }

class Toast {
  Toast(this.id, this.text, this.tone);
  final int id;
  final String text;
  final ToastTone tone;
}

class Celebration {
  const Celebration(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Estado de interfaz: avisos apilados (estilo feed de terminal), celebraciones
/// y pestaña activa.
class UiController extends ChangeNotifier {
  final List<Toast> toasts = [];
  Celebration? celebration;
  int tab = 0;
  int _seq = 1;

  void toast(String text, [ToastTone tone = ToastTone.info]) {
    final t = Toast(_seq++, text, tone);
    toasts.add(t);
    if (toasts.length > 3) toasts.removeAt(0);
    notifyListeners();
    final ms = tone == ToastTone.warn || tone == ToastTone.bad ? 4200 : 3500;
    Timer(Duration(milliseconds: ms), () {
      toasts.remove(t);
      notifyListeners();
    });
  }

  void celebrate(Celebration? c) {
    celebration = c;
    notifyListeners();
  }

  void goTab(int i) {
    if (tab == i) return;
    tab = i;
    notifyListeners();
  }
}
