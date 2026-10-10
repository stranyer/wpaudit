// Herramienta de depuración: renderiza el Maletín a PNG con las fuentes reales.
// Solo corre si se pide: OUT=/ruta/salida.png flutter test test/tools/render_png_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zona_cero/state/app_state.dart';
import 'package:zona_cero/ui/screens/case_screen.dart';
import 'package:zona_cero/ui/theme/theme.dart';

Future<void> _loadFonts() async {
  final families = <String, List<String>>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    (families[f.uri.pathSegments.last.split('-').first] ??= []).add(f.path);
  }
  for (final e in families.entries) {
    final l = FontLoader(e.key);
    for (final p in e.value) {
      l.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await l.load();
  }
}

void main() {
  testWidgets('render', skip: Platform.environment['OUT'] == null, (t) async {
    await t.runAsync(_loadFonts);
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => app.bootstrap());
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(theme: buildSuturaTheme(), home: RepaintBoundary(key: key, child: const Scaffold(body: CaseScreen()))));
    await t.pump(const Duration(milliseconds: 500));
    final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await t.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 2);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!;
    });
    File(Platform.environment['OUT']!).writeAsBytesSync(bytes!.buffer.asUint8List());
    app.onPause();
  });
}
