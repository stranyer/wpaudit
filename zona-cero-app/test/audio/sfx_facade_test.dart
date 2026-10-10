import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/audio/sfx.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend fake;

  setUp(() {
    Sfx.resetForTest();
    fake = FakeBackend();
    Sfx.install(fake);
  });

  tearDown(Sfx.resetForTest);

  group('activado / desactivado', () {
    test('con el sonido apagado no se llama al motor', () {
      Sfx.enabled = false;
      Sfx.play(SfxId.pistolShot);
      Sfx.play(SfxId.tap, volume: 0.4);
      expect(fake.plays, isEmpty);
    });

    test('apagar silencia el ambiente y encender lo restaura con su volumen', () {
      Sfx.master = 1;
      Sfx.ambience(Ambience.map, volume: 0.4);
      expect(fake.ambiences.last, (a: Ambience.map, volume: 0.4));

      Sfx.enabled = false;
      expect(fake.ambiences.last.a, isNull);
      // Pedidos con el sonido apagado se recuerdan pero no suenan.
      Sfx.ambience(Ambience.combat, volume: 0.6);
      expect(fake.ambiences.last.a, isNull);
      expect(Sfx.currentAmbience, Ambience.combat);

      Sfx.enabled = true;
      expect(fake.ambiences.last, (a: Ambience.combat, volume: 0.6));
    });

    test('asignar el mismo valor no reenvía nada', () {
      Sfx.ambience(Ambience.map);
      final n = fake.ambiences.length;
      Sfx.enabled = true;
      Sfx.master = Sfx.master;
      expect(fake.ambiences.length, n);
    });
  });

  group('volumen general', () {
    test('escala el volumen de cada efecto', () {
      Sfx.master = 0.5;
      Sfx.play(SfxId.loot, volume: 0.8);
      expect(fake.plays.single.volume, closeTo(0.4, 1e-9));
    });

    test('recorta a 0..1 y omite efectos inaudibles', () {
      Sfx.master = 1;
      Sfx.play(SfxId.loot, volume: 3);
      expect(fake.plays.single.volume, 1.0);
      Sfx.play(SfxId.loot, volume: 0);
      Sfx.play(SfxId.loot, volume: double.nan);
      expect(fake.plays, hasLength(1));
      Sfx.master = 0;
      Sfx.play(SfxId.loot);
      expect(fake.plays, hasLength(1));
    });

    test('master fuera de rango se acota', () {
      Sfx.master = 4;
      expect(Sfx.master, 1.0);
      Sfx.master = -1;
      expect(Sfx.master, 0.0);
      Sfx.master = double.nan;
      expect(Sfx.master, 0.0);
    });

    test('cambiar el master reaplica el ambiente en curso', () {
      Sfx.master = 1;
      Sfx.ambience(Ambience.shelter, volume: 0.5);
      Sfx.master = 0.4;
      expect(fake.ambiences.last.a, Ambience.shelter);
      expect(fake.ambiences.last.volume, closeTo(0.2, 1e-9));
      // Master en cero equivale a apagar el ambiente.
      Sfx.master = 0;
      expect(fake.ambiences.last.a, isNull);
    });

    test('la velocidad de reproducción se acota a 0.5..2', () {
      Sfx.play(SfxId.zombieGroan, rate: 5);
      Sfx.play(SfxId.zombieGroan, rate: 0.1);
      Sfx.play(SfxId.zombieGroan, rate: double.infinity);
      expect(fake.plays.map((p) => p.rate), [2.0, 0.5, 1.0]);
    });
  });

  group('resistencia a fallos', () {
    test('un archivo faltante no rompe nada y no afecta a los demás', () {
      Sfx.install(fake = FakeBackend(missing: {SfxId.bruteRoar}));
      expect(() => Sfx.play(SfxId.bruteRoar), returnsNormally);
      Sfx.play(SfxId.headshot);
      expect(fake.plays.single.id, SfxId.headshot);
    });

    test('init y ambiente que fallan quedan contenidos', () async {
      Sfx.install(FakeBackend(throwOnInit: true, throwOnAmbience: true));
      await expectLater(Sfx.init(), completes);
      expect(() => Sfx.ambience(Ambience.map), returnsNormally);
      expect(() => Sfx.enabled = false, returnsNormally);
    });

    test('sin motor instalado todo es silencioso', () async {
      Sfx.resetForTest();
      await Sfx.init();
      expect(() => Sfx.play(SfxId.victory), returnsNormally);
      expect(() => Sfx.ambience(Ambience.combat), returnsNormally);
    });
  });

  test('cada sonido apunta a un asset mp3 propio', () {
    final files = [...SfxId.values.map((e) => e.asset), ...Ambience.values.map((e) => e.asset)];
    expect(files.toSet(), hasLength(files.length));
    for (final f in files) {
      expect(f, matches(RegExp(r'^assets/audio/[a-z0-9_]+\.mp3$')));
    }
  });
}
