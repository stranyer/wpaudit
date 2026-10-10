// TEMPORAL: vista previa de pantallas secundarias (se borra antes del commit).
import 'package:flutter/material.dart';

import '../content/lore.dart';
import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../ui/theme/theme.dart';
import '../ui/screens/archive_screen.dart';
import '../ui/screens/case_screen.dart';
import '../ui/screens/network_screen.dart';
import '../ui/screens/node_screen.dart';
import '../ui/screens/profile_screen.dart';
import '../ui/screens/boot_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.bootstrap();
  final q = Uri.base.queryParameters;
  var p = app.player!;
  p = p.copyWith(
    level: 6,
    xp: 140,
    health: 72,
    inventory: {
      ItemId.food: 4, ItemId.water: 3, ItemId.medicine: 2, ItemId.wood: 9, ItemId.metal: 6, ItemId.ammo: 11,
      ItemId.medkit: 1, ItemId.adrenaline: 1, ItemId.nailBat: 1, ItemId.pistol: 1, ItemId.scrapVest: 1,
    },
    equipment: const Equipment(melee: ItemId.nailBat, firearm: ItemId.pistol, armor: ItemId.scrapVest),
    stats: p.stats.copyWith(
      zombiesKilled: {ZombieTypeId.walker: 14, ZombieTypeId.runner: 5, ZombieTypeId.brute: 1},
      suppliesLooted: 31, itemsCrafted: 4, resourcesDonated: 22, distanceWalkedM: 6400, cellsExplored: 18,
      encountersWon: 20, encountersFled: 3, deaths: 1,
    ),
  );
  app.setPlayer(p, save: false);
  app.readLore.add('desam-001');
  await app.start(LocationMode.demo);
  final node = q['node'];
  if (node != null && q['near'] == '1') {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final s = app.world.shelterById(node);
    if (s != null) app.location.demo?.teleport(s.position);
  }
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildSuturaTheme(),
    home: Builder(builder: (context) {
      final tab = q['tab'] ?? 'case';
      final lore = q['lore'];
      if (lore != null) return LoreReader(file: loreFiles.firstWhere((f) => f.id == lore));
      if (node != null) return NodeScreen(shelterId: node);
      return Scaffold(
        body: switch (tab) {
          'boot' => BootScreen(onStart: (_) {}, returning: 'ENLACE CENIZA42 · GRADO 6'),
          'red' => NetworkScreen(onOpenNode: (_) {}),
          'archivo' => const ArchiveScreen(),
          'perfil' => const ProfileScreen(),
          'taller' => const CaseScreen(),
          _ => const CaseScreen(),
        },
      );
    }),
  ));
}
