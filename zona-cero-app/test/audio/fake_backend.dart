import 'package:zona_cero/audio/sfx.dart';

/// Motor falso que registra las llamadas (y puede simular archivos faltantes).
class FakeBackend implements SfxBackend {
  FakeBackend({this.missing = const {}, this.throwOnInit = false, this.throwOnAmbience = false});

  final Set<SfxId> missing;
  final bool throwOnInit;
  final bool throwOnAmbience;
  final plays = <({SfxId id, double volume, double rate})>[];
  final ambiences = <({Ambience? a, double volume})>[];
  int inits = 0;

  @override
  Future<void> init() async {
    inits++;
    if (throwOnInit) throw StateError('sin audio');
  }

  @override
  void play(SfxId id, {double volume = 1, double rate = 1}) {
    if (missing.contains(id)) throw StateError('Unable to load asset: ${id.asset}');
    plays.add((id: id, volume: volume, rate: rate));
  }

  @override
  void ambience(Ambience? a, {double volume = 0.5}) {
    if (throwOnAmbience) throw StateError('ambiente roto');
    ambiences.add((a: a, volume: volume));
  }

  @override
  void dispose() {}
}
