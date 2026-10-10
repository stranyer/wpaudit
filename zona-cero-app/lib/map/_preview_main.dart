// TEMPORAL: arnés para previsualizar MapScreen. Borrar al terminar.
import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../ui/screens/map_screen.dart';
import '../ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.bootstrap();
  unawaited(app.start(LocationMode.demo));
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Sutura.void_,
      fontFamily: Sutura.fUi,
      colorScheme: const ColorScheme.dark(primary: Sutura.signal, secondary: Sutura.amber, surface: Sutura.surface1Solid),
    ),
    home: Scaffold(
      body: MapScreen(
        onOpenEncounter: () => app.ui.toast('ENCUENTRO (preview)'),
        onOpenNode: (id) => app.ui.toast('NODO $id (preview)'),
      ),
    ),
  ));
}
