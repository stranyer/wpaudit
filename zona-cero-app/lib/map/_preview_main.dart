// Arnés TEMPORAL para capturas del mapa (se borra al terminar).
import 'package:flutter/material.dart';

import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
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
  app.setPlayer(p.copyWith(
    equipment: const Equipment(firearm: ItemId.pistol),
    inventory: {...p.inventory, ItemId.ammo: 39, ItemId.pistol: 1},
    createdAt: DateTime.now().subtract(const Duration(days: 6)).millisecondsSinceEpoch,
  ));
  await app.start(LocationMode.demo);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildSuturaTheme(),
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0B0C),
      body: Column(
        children: [
          Expanded(child: MapScreen(onOpenEncounter: () {}, onOpenNode: (_) {})),
          const SizedBox(height: 68, child: ColoredBox(color: Color(0xFF0D0E0F))),
        ],
      ),
    ),
  ));
}
