// Plataforma sin `dart:io` ni `dart:js_interop`: sin audio.

import 'sfx.dart';

SfxBackend createPlatformEngine() => _NoAudio();

class _NoAudio implements SfxBackend {
  @override
  Future<void> init() async {}
  @override
  void play(SfxId id, {double volume = 1, double rate = 1}) {}
  @override
  void ambience(Ambience? a, {double volume = 0.5}) {}
  @override
  void dispose() {}
}
