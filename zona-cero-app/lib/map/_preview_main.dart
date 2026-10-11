// Arnés TEMPORAL para capturas del mapa (se borra al terminar).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../state/world_controller.dart';
import '../ui/screens/map_screen.dart';
import '../ui/theme/theme.dart';
import '../ui/widgets/grit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GritAssets.load();
  await app.bootstrap();
  // Plaza Lavalle (como la referencia), con pistola y 39 balas (07 / 32).
  app.demoPosition = const LatLng(-34.60175, -58.38455);
  final p = app.player!;
  app.setPlayer(
    p.copyWith(
      equipment: const Equipment(firearm: ItemId.pistol),
      inventory: {...p.inventory, ItemId.ammo: 39, ItemId.pistol: 1},
      createdAt: DateTime.now().subtract(const Duration(days: 6)).millisecondsSinceEpoch,
    ),
  );
  await app.start(LocationMode.demo);
  // Tecla "z": seleccionar el infectado visible más cercano (solo para capturas).
  HardwareKeyboard.instance.addHandler((e) {
    if (e is! KeyDownEvent || e.character != 'z') return false;
    final pos = app.location.position;
    if (pos == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    ZombieSpawn? best;
    var bestD = double.infinity;
    for (final s in app.world.drawable) {
      if (s is! ZombieSpawn || app.world.visibilityOf(s, pos, now) == SpawnVisibility.hidden) continue;
      final d = haversineM(pos, app.world.positionAt(s, now));
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    if (best != null) app.world.select(best.id);
    return true;
  });
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildSuturaTheme(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0B0C),
        body: Column(
          children: [
            Expanded(
              child: MapScreen(onOpenEncounter: () {}, onOpenNode: (_) {}),
            ),
            const SizedBox(height: 68, child: ColoredBox(color: Color(0xFF0D0E0F))),
          ],
        ),
      ),
    ),
  );
}
