// Herramienta de depuración: renderiza una pantalla a PNG con las fuentes y
// las imágenes reales. Solo corre si se pide:
//   OUT=/ruta/salida.png SCREEN=case|node|archive|profile flutter test test/tools/render_png_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/state/app_state.dart';
import 'package:zona_cero/ui/screens/archive_screen.dart';
import 'package:zona_cero/ui/screens/case_screen.dart';
import 'package:zona_cero/ui/screens/node_screen.dart';
import 'package:zona_cero/ui/screens/profile_screen.dart';
import 'package:zona_cero/ui/theme/theme.dart';
import 'package:zona_cero/ui/widgets/grit.dart';

Future<void> _loadFonts() async {
  // Familias tal como las declara pubspec.yaml (archivo → familia).
  const alias = {'CoveredByYourGrace': 'Handwritten'};
  final families = <String, List<String>>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final base = f.uri.pathSegments.last.split('-').first;
    (families[alias[base] ?? base] ??= []).add(f.path);
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
    await t.runAsync(() => GritAssets.load());
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => app.bootstrap());
    final p = app.player!;
    app.player = p.copyWith(
      inventory: {
        ...p.inventory,
        ItemId.water: 2,
        ItemId.medicine: 1,
        ItemId.metal: 3,
        ItemId.wood: 2,
        ItemId.ammo: 32,
        ItemId.pistol: 1,
        ItemId.adrenaline: 1,
      },
      equipment: p.equipment.copyWith(firearm: ItemId.pistol),
    );
    if (Platform.environment['SCREEN'] == 'node') {
      // Nodos simulados alrededor del Obelisco.
      final shelters = await t.runAsync(() => app.repo.getNearbyShelters(const LatLng(-34.6037, -58.3816), 3000));
      app.world.setShelters(shelters!);
    }
    final screen = switch (Platform.environment['SCREEN']) {
      'node' => NodeScreen(shelterId: app.world.shelters.first.id),
      'archive' => const ArchiveScreen(),
      'profile' => const ProfileScreen(),
      _ => const CaseScreen(),
    };
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(theme: buildSuturaTheme(), home: RepaintBoundary(key: key, child: Scaffold(body: screen))));
    // Las imágenes se decodifican fuera del reloj falso del test.
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 100));
    }
    final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await t.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 2);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!;
    });
    File(Platform.environment['OUT']!).writeAsBytesSync(bytes!.buffer.asUint8List());
    app.onPause();
  });
}
