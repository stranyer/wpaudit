import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/audio/audio_prefs.dart';
import 'package:zona_cero/audio/sfx.dart';
import 'package:zona_cero/data/storage.dart';

void main() {
  setUp(Sfx.resetForTest);
  tearDown(Sfx.resetForTest);

  test('guarda y restaura encendido + volumen en zc:audio', () async {
    final store = KeyValueStore.memory();
    Sfx.enabled = false;
    Sfx.master = 0.35;
    await AudioPrefs.save(store);
    expect(store.getString('zc:audio'), contains('"enabled":false'));

    Sfx.resetForTest();
    expect(Sfx.enabled, isTrue);
    AudioPrefs.apply(store);
    expect(Sfx.enabled, isFalse);
    expect(Sfx.master, closeTo(0.35, 1e-9));
  });

  test('sin preferencia guardada quedan los valores por defecto', () {
    AudioPrefs.apply(KeyValueStore.memory());
    expect(Sfx.enabled, isTrue);
    expect(Sfx.master, 0.9);
  });

  test('datos corruptos o fuera de rango no rompen', () async {
    final store = KeyValueStore.memory();
    await store.setString('zc:audio', '{no es json');
    expect(() => AudioPrefs.apply(store), returnsNormally);
    expect(Sfx.enabled, isTrue);

    await store.setString('zc:audio', '{"enabled":"si","master":7}');
    AudioPrefs.apply(store);
    expect(Sfx.enabled, isTrue);
    expect(Sfx.master, 1.0);

    await store.setString('zc:audio', '[1,2,3]');
    expect(() => AudioPrefs.apply(store), returnsNormally);
  });
}
