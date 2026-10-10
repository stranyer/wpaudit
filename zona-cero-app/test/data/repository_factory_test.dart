// Elección del repositorio: local sin credenciales (o si Supabase falla),
// Supabase con credenciales y sesión iniciada.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:zona_cero/data/local_repository.dart';
import 'package:zona_cero/data/repository_factory.dart';
import 'package:zona_cero/data/storage.dart';
import 'package:zona_cero/data/supabase_repository.dart';

import 'fake_supabase.dart';

void main() {
  late KeyValueStore store;

  setUp(() => store = KeyValueStore.memory());

  test('sin --dart-define: no hay configuración y se usa LocalRepository', () async {
    expect(hasSupabaseConfig, isFalse);
    final repo = await createRepository(store);
    expect(repo, isA<LocalRepository>());
    expect(repo.kind, 'local');
    expect(await repo.init(), startsWith('local-'));
  });

  group('createRepositoryFromConfig', () {
    Future<SupabaseClient> mustNotConnect(String url, String key) => fail('no debía conectarse');

    test('configuración incompleta o URL inválida → local, sin intentar conectar', () async {
      for (final (url, key) in [
        ('', ''),
        ('https://abc.supabase.co', ''),
        ('', 'clave'),
        ('   ', 'clave'),
        ('abc.supabase.co', 'clave'),
        ('ftp://abc.supabase.co', 'clave'),
        ('https://', 'clave'),
      ]) {
        final repo = await createRepositoryFromConfig(store, url: url, anonKey: key, connect: mustNotConnect);
        expect(repo, isA<LocalRepository>(), reason: '"$url" / "$key"');
      }
    });

    test('si la inicialización falla o se cuelga → local', () async {
      final failing = await createRepositoryFromConfig(
        store,
        url: 'https://abc.supabase.co',
        anonKey: 'clave',
        connect: (_, _) async => throw StateError('sin plugin'),
      );
      expect(failing, isA<LocalRepository>());

      final hanging = await createRepositoryFromConfig(
        store,
        url: 'https://abc.supabase.co',
        anonKey: 'clave',
        connect: (_, _) => Completer<SupabaseClient>().future,
        timeout: const Duration(milliseconds: 100),
      );
      expect(hanging, isA<LocalRepository>());
    });

    group('con servidor', () {
      late FakeSupabase fake;

      setUp(() async => fake = await FakeSupabase.start());
      tearDown(() => fake.close());

      test('credenciales válidas → SupabaseRepository con la sesión ya iniciada', () async {
        String? connectedTo;
        final repo = await createRepositoryFromConfig(
          store,
          url: ' ${fake.url}/ ',
          anonKey: ' anon-key ',
          connect: (url, key) async {
            connectedTo = '$url|$key';
            return fake.client();
          },
        );
        expect(repo, isA<SupabaseRepository>());
        expect(repo.kind, 'supabase');
        expect((repo as SupabaseRepository).userId, fakeUid);
        expect(connectedTo, '${fake.url}|anon-key');
        expect(fake.signups, 1);
      });

      test('proveedor anónimo deshabilitado → local', () async {
        fake.anonymousEnabled = false;
        final repo = await createRepositoryFromConfig(
          store,
          url: fake.url,
          anonKey: 'anon-key',
          connect: (_, _) async => fake.client(),
        );
        expect(repo, isA<LocalRepository>());
      });

      test('servidor caído → local', () async {
        await fake.stopServer();
        final repo = await createRepositoryFromConfig(
          store,
          url: fake.url,
          anonKey: 'anon-key',
          connect: (_, _) async => fake.client(),
        );
        expect(repo, isA<LocalRepository>());
      });
    });
  });
}
