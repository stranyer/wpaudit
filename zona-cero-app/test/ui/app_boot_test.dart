import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zona_cero/state/app_state.dart';
import 'package:zona_cero/ui/app.dart';

/// Carga las tipografías reales: con la fuente de prueba (Ahem) los textos miden distinto.
Future<void> _loadFonts() async {
  final families = <String, List<String>>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last.split('-').first;
    (families[name] ??= []).add(f.path);
  }
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  // Tamaños lógicos de teléfonos: chico, medio y alto.
  for (final size in const [Size(360, 640), Size(390, 844), Size(412, 915)]) {
    testWidgets('arranque sin desbordes ni subrayado de depuración en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ZonaCeroApp());
      // Secuencia completa del registro de arranque (7 líneas cada 330 ms).
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(tester.takeException(), isNull);

      final title = find.text('ZONA CERO');
      expect(title, findsOneWidget);
      // Sin un Material ancestro, Flutter dibuja los textos con un subrayado amarillo doble.
      expect(find.ancestor(of: title, matching: find.byType(Material)), findsWidgets);
      expect(DefaultTextStyle.of(tester.element(title)).style.decoration, isNot(TextDecoration.underline));
      expect(find.text('CONECTAR GPS'), findsOneWidget);
      expect(find.text('SIMULACIÓN · BUENOS AIRES'), findsOneWidget);

      // Detener el reloj del juego (Timer periódico del AppState) antes de cerrar.
      app.onPause();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
