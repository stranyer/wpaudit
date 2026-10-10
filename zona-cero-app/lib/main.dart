import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/audio_engine.dart';
import 'audio/audio_prefs.dart';
import 'audio/sfx.dart';
import 'data/repository_factory.dart';
import 'ui/app.dart';
import 'ui/widgets/grit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sonido: motor real (audioplayers en el teléfono, Web Audio en el navegador),
  // preferencia guardada y precarga de efectos en segundo plano (no demora el arranque).
  Sfx.install(createAudioEngine());
  unawaited(AudioPrefs.restore());
  unawaited(Sfx.init());
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF05070A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Máscara de desgaste de los títulos (si falla, los títulos se ven limpios).
  await GritAssets.load();
  runApp(const ZonaCeroApp(repositoryFactory: createRepository));
}
