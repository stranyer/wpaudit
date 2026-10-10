import 'dart:async';

import 'package:flutter/material.dart';

import '../data/game_repository.dart';
import '../data/storage.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import 'screens/boot_screen.dart';
import 'shell.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

/// Raíz de la app: arranque VITA-7 → estructura principal.
class ZonaCeroApp extends StatelessWidget {
  const ZonaCeroApp({super.key, this.repositoryFactory});

  final Future<GameRepository> Function(KeyValueStore store)? repositoryFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zona Cero',
      debugShowCheckedModeBanner: false,
      theme: buildSuturaTheme(),
      home: _Root(repositoryFactory: repositoryFactory),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({this.repositoryFactory});

  final Future<GameRepository> Function(KeyValueStore store)? repositoryFactory;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  late final Future<void> _boot = app.ready ? Future.value() : app.bootstrap(repositoryFactory: widget.repositoryFactory);
  bool _started = false;
  bool _busy = false;
  String? _returning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_boot.then((_) {
      final p = app.player;
      if (mounted && p != null && (p.level > 1 || p.xp > 0)) {
        setState(() => _returning = 'ENLACE ${p.name.toUpperCase()} · GRADO ${p.level}');
      }
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        app.onPause();
      case AppLifecycleState.resumed:
        app.onResume();
      default:
        break;
    }
  }

  Future<void> _start(bool gps) async {
    setState(() => _busy = true);
    await _boot;
    unawaited(app.start(gps ? LocationMode.gps : LocationMode.demo));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _started = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Sutura.heavy,
      switchInCurve: Sutura.easeIn,
      child: _started
          ? const Shell(key: ValueKey('shell'))
          : BootScreen(key: const ValueKey('boot'), onStart: _start, busy: _busy, returning: _returning),
    );
  }
}
