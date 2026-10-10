// VISTA PREVIA TEMPORAL del mapa (no forma parte de la app).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../ui/screens/map_screen.dart';
import '../ui/theme/theme.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/grit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GritAssets.load();
  await app.bootstrap();
  app.demoPosition = const LatLng(-34.60085, -58.38545);
  await app.start(LocationMode.demo);
  final q = Uri.base.queryParameters;
  final at = q['at'];
  if (at != null) {
    final parts = at.split(',').map(double.parse).toList();
    app.location.demo?.teleport(LatLng(parts[0], parts[1]));
  }
  final heading = q['heading'];
  if (heading != null) {
    // Caminar un instante para que el jugador tenga rumbo (cono de visión).
    final a = double.parse(heading) * 3.14159265 / 180;
    Timer(const Duration(seconds: 4), () {
      app.location.demo?.setVelocity(Uri.base.queryParameters['run'] == null ? _sin(a) : 0, _cos(a));
      Timer(const Duration(milliseconds: 600), () => app.location.demo?.setVelocity(0, 0));
    });
  }
  final select = q['select'];
  if (select != null) {
    Timer(const Duration(seconds: 7), () {
      final pos = app.location.position!;
      String? id;
      LatLng? where;
      var best = double.infinity;
      final far = q['pick'] == 'far';
      void consider(String i, LatLng p) {
        var d = haversineM(pos, p);
        if (far) d = d > 450 ? double.infinity : -d;
        if (d < best) {
          best = d;
          id = i;
          where = p;
        }
      }

      if (select == 'zombie') {
        for (final s in app.world.spawns) {
          if (s is ZombieSpawn) consider(s.id, s.position);
        }
      } else if (select == 'signal') {
        for (final s in app.world.signals) {
          consider(s.id, s.position);
        }
      } else if (select == 'node') {
        for (final s in app.world.shelters) {
          consider(s.id, s.position);
        }
      }
      if (id == null) return;
      if (q['near'] == '1') app.location.demo?.teleport(offsetM(where!, 0, -12));
      app.world.select(id);
      if (q['answer'] == '1' && select == 'signal') {
        // El panel muestra RESPONDER; el clic lo hace Playwright.
      }
    });
  }
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildSuturaTheme(),
    home: Scaffold(
      backgroundColor: Sutura.void_,
      body: Column(
        children: [
          Expanded(child: MapScreen(onOpenEncounter: () {}, onOpenNode: (_) {})),
          Container(
            height: 68,
            decoration: const BoxDecoration(color: Color(0xFF0D0E0F), border: Border(top: BorderSide(color: Sutura.lineStrong))),
            alignment: Alignment.center,
            child: Text('MAPA   MALETÍN   RED   ARCHIVO   PERFIL', style: SuturaText.label.copyWith(fontSize: 12)),
          ),
        ],
      ),
    ),
  ));
}

double _sin(double a) => math.sin(a);
double _cos(double a) => math.cos(a);
