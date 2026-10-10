import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../content/lore.dart';
import '../core/core.dart';
import '../data/game_repository.dart';
import '../data/local_repository.dart';
import '../data/supabase_repository.dart';
import '../data/storage.dart';
import '../services/location/location_types.dart';
import 'location_controller.dart';
import 'signals.dart';
import 'ui_controller.dart';
import 'world_controller.dart';

/// Resultado de un encuentro, para la pantalla de cierre.
class CombatOutcome {
  CombatOutcome(this.status);
  final CombatStatus status;
  Reward? reward;
  Inventory added = {};
  Inventory overflow = {};
  Inventory lost = {};
  int levelsGained = 0;
}

/// Estado global del juego: conecta ubicación, mundo, jugador y persistencia.
/// Es la "capa de motor" entre la lógica pura (core) y la interfaz.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  late KeyValueStore store;
  late GameRepository repo;
  final ui = UiController();
  final location = LocationController();
  final world = WorldController();

  bool ready = false;
  PlayerState? player;

  // Combate
  CombatState? combat;
  ZombieSpawn? combatSpawn;
  CombatOutcome? outcome;

  // Sesión local (no viaja al servidor). Nunca se guarda la posición GPS real.
  Map<String, int> depleted = {};
  Set<String> explored = {};
  double walkBuffer = 0;
  LocationMode? lastMode;
  LatLng? demoPosition;
  Set<String> readLore = {};

  /// Señales de auxilio respondidas (desbloquean transmisiones del Archivo).
  int signalsAnswered = 0;

  Timer? _tick;
  Timer? _saveTimer;
  SpeedGuardState _speedGuard = SpeedGuardState.initial;
  LatLng? _lastPos;
  int _nextWindowAt = 0;
  ({int at, LatLng pos})? _lastShelterFetch;
  int _lastPresenceAt = 0;

  static const _kSession = 'zc:session';
  static const _shelterRadiusM = 20000.0;

  int get now => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------------------
  // Arranque y persistencia
  // ---------------------------------------------------------------------------

  Future<void> bootstrap({GameRepository? repository, Future<GameRepository> Function(KeyValueStore store)? repositoryFactory}) async {
    store = await KeyValueStore.open();
    repo = repository ?? (repositoryFactory != null ? await repositoryFactory(store) : LocalRepository(store));
    final id = await repo.init();
    final saved = await repo.loadPlayer();
    final t = now;
    final p = saved != null && saved.id == id ? saved : createPlayer(id, _randomName(), t);
    player = applyRegen(p, t, gameConfig.regen);
    _loadSession();
    location.onFix = _onFix;
    location.onError = (e) => ui.toast(locationErrorMessages[e]!, ToastTone.warn);
    _tick ??= Timer.periodic(Duration(milliseconds: gameConfig.tickMs), (_) => _onTick());
    ready = true;
    notifyListeners();
  }

  static const _names = ['Sombra', 'Lobo', 'Ceniza', 'Halcón', 'Óxido', 'Zorro', 'Trueno', 'Niebla', 'Chispa', 'Cuervo'];
  String _randomName() {
    final r = math.Random();
    return '${_names[r.nextInt(_names.length)]}${10 + r.nextInt(89)}';
  }

  /// Matrícula estable del Enlace (ENL-0042-BA).
  String get badge {
    final id = player?.id ?? '0';
    final n = id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) % 10000);
    return 'ENL-${n.toString().padLeft(4, '0')}-BA';
  }

  void _loadSession() {
    final s = store.readJson(_kSession, (j) => Map<String, dynamic>.from(j as Map));
    if (s == null) return;
    depleted = Map<String, int>.from((s['depleted'] as Map? ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    explored = Set<String>.from(s['explored'] as List? ?? const []);
    walkBuffer = (s['walkBuffer'] as num?)?.toDouble() ?? 0;
    lastMode = switch (s['lastMode']) { 'gps' => LocationMode.gps, 'demo' => LocationMode.demo, _ => null };
    final dp = s['demoPosition'];
    demoPosition = dp is Map ? LatLng.fromJson(Map<String, dynamic>.from(dp)) : null;
    readLore = Set<String>.from(s['readLore'] as List? ?? const []);
    signalsAnswered = (s['signalsAnswered'] as num?)?.toInt() ?? 0;
  }

  Future<void> _saveSession() => store.writeJson(_kSession, {
        'depleted': depleted,
        'explored': explored.toList(),
        'walkBuffer': walkBuffer,
        'lastMode': lastMode?.name,
        'demoPosition': demoPosition?.toJson(),
        'readLore': readLore.toList(),
        'signalsAnswered': signalsAnswered,
      });

  /// Cambia el jugador y programa un guardado (con límite de frecuencia).
  void setPlayer(PlayerState p, {bool save = true}) {
    player = p;
    notifyListeners();
    if (save) _scheduleSave();
  }

  void _scheduleSave() {
    if (_saveTimer != null) return;
    final delay = repo.kind == 'supabase' ? 10000 : gameConfig.saveDebounceMs;
    _saveTimer = Timer(Duration(milliseconds: delay), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final p = player;
    if (p != null) {
      try {
        await repo.savePlayer(p);
      } catch (e) {
        // Sin red: el progreso queda en memoria y se reintenta en el próximo guardado.
        debugPrint('[Zona Cero] No se pudo guardar en la red: $e');
        _scheduleSave();
      }
    }
    await _saveSession();
  }

  /// Ejecuta una llamada a la red y muestra el error en el feed si falla.
  Future<T?> _net<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      ui.toast(e is SupabaseRepositoryException ? '$e' : 'Red inestable. Probá de nuevo.', ToastTone.bad);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  Future<void> start(LocationMode mode) async {
    lastMode = mode;
    _speedGuard = SpeedGuardState.initial;
    _lastPos = null;
    await location.start(mode, demoStart: demoPosition);
    unawaited(_saveSession());
  }

  void onPause() {
    unawaited(flush());
    location.pause();
    _tick?.cancel();
    _tick = null;
  }

  void onResume() {
    _tick ??= Timer.periodic(Duration(milliseconds: gameConfig.tickMs), (_) => _onTick());
    unawaited(location.resume());
    _onTick();
  }

  void _onTick() {
    final t = now;
    final p = player;
    if (p != null && combat == null) {
      final next = applyRegen(p, t, gameConfig.regen);
      // No se guarda si solo avanzó el reloj de regeneración.
      final changed = next.health != p.health || next.stamina != p.stamina;
      player = next;
      if (changed) {
        notifyListeners();
        _scheduleSave();
      }
    }
    depleted.removeWhere((_, exp) => exp <= t);
    final pos = location.position;
    if (pos != null && t >= _nextWindowAt) _refreshWorld(pos, force: true);
    if (pos != null && t - _lastPresenceAt > 120000) _publishPresence(pos);
    // El escáner revela/apaga ecos con el tiempo: refrescar el mapa.
    world.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ubicación → mundo
  // ---------------------------------------------------------------------------

  void _onFix(LocationFix fix) {
    if (fix.jump) {
      _speedGuard = SpeedGuardState.initial;
      _lastPos = null;
      final r = repo;
      if (r is LocalRepository) r.resetSpeedGuard();
    }
    _speedGuard = updateSpeedGuard(
      _speedGuard,
      SpeedSample(position: fix.position, time: fix.timestamp),
      gameConfig.maxInteractionSpeedMps,
      gameConfig.speedLockMs,
    );
    location.setSpeedLock(_speedGuard.lockedUntil);
    if (location.mode == LocationMode.demo) demoPosition = fix.position;

    final last = _lastPos;
    if (last != null) {
      final d = haversineM(last, fix.position);
      if (d > 0.5 && d < 100 && !location.speedLocked) _recordWalk(d);
    }
    _lastPos = fix.position;
    _exploreCell(fix.position);
    _refreshWorld(fix.position);
  }

  void _recordWalk(double meters) {
    final p = player;
    if (p == null) return;
    walkBuffer += meters;
    var xp = 0;
    while (walkBuffer >= 250) {
      walkBuffer -= 250;
      xp += gameConfig.xp.per250mWalked;
    }
    player = p.copyWith(stats: p.stats.copyWith(distanceWalkedM: p.stats.distanceWalkedM + meters));
    if (xp > 0) awardXp(xp, null);
  }

  void _exploreCell(LatLng p) {
    final id = cellId(cellOf(p));
    if (explored.contains(id)) return;
    explored.add(id);
    final pl = player;
    if (pl != null) player = pl.copyWith(stats: pl.stats.copyWith(cellsExplored: pl.stats.cellsExplored + 1));
    if (explored.length > 1) awardXp(gameConfig.xp.perCellExplored, 'Sector explorado');
    _scheduleSave();
  }

  void _refreshWorld(LatLng p, {bool force = false}) {
    final t = now;
    final cell = cellId(cellOf(p));
    if (force || cell != world.centerCellId || t >= _nextWindowAt) {
      world.regenerate(p, t, depleted);
      _nextWindowAt = nextWindowChange(t, gameConfig.spawn);
    }
    final lf = _lastShelterFetch;
    if (lf == null || t - lf.at > 60000 || haversineM(lf.pos, p) > 1500) {
      _lastShelterFetch = (at: t, pos: p);
      unawaited(loadShelters(p));
    }
  }

  Future<void> loadShelters(LatLng p) async {
    try {
      world.setShelters(await repo.getNearbyShelters(p, _shelterRadiusM));
    } catch (e) {
      debugPrint('[Zona Cero] No se pudieron cargar nodos: $e');
    }
  }

  void _publishPresence(LatLng p) {
    final pl = player;
    if (pl == null) return;
    _lastPresenceAt = now;
    unawaited(repo.publishPresence(pl, fuzzPosition(p, pl.id)).catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // Utilidades de recompensa
  // ---------------------------------------------------------------------------

  int awardXp(int amount, String? reason) {
    final p = player;
    if (p == null) return 0;
    final r = grantXp(p, amount);
    setPlayer(r.player);
    if (reason != null) ui.toast('$reason · +$amount XP', ToastTone.good);
    if (r.levelsGained > 0) {
      HapticFeedback.heavyImpact();
      ui.celebrate(Celebration('GRADO ${r.player.level}', 'Signos vitales restaurados. Capacidad del maletín ampliada.'));
    }
    return r.levelsGained;
  }

  static String describeItems(Inventory items) =>
      entries(items).map((e) => '${e.value} ${itemDefs[e.key]!.name}').join(', ');

  ({LatLng position, double accuracyM})? get _fix {
    final p = location.position;
    return p == null ? null : (position: p, accuracyM: location.accuracyM);
  }

  Shelter? get ownShelter {
    final p = player;
    if (p == null) return null;
    for (final s in world.shelters) {
      if (s.ownerId == p.id) return s;
    }
    return null;
  }

  int get workshopLevel => ownShelter?.level ?? 0;

  void _markDepleted(String id, int expiresAt) {
    depleted[id] = expiresAt;
    world.removeSpawn(id);
    unawaited(_saveSession());
  }

  // ---------------------------------------------------------------------------
  // Escáner
  // ---------------------------------------------------------------------------

  bool scan() {
    final f = _fix;
    if (f == null) return false;
    final ok = world.scan(f.position, now);
    if (!ok) {
      ui.toast('Escáner recargando…', ToastTone.warn);
      return false;
    }
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: WorldController.scanDurationMs), () {
      final n = world.revealedCount(now);
      ui.toast(n == 0 ? 'Pulso sin contactos en 250 m' : 'Pulso: $n contactos en 250 m', ToastTone.network);
    });
    return true;
  }

  // ---------------------------------------------------------------------------
  // Exploración
  // ---------------------------------------------------------------------------

  Future<void> scavenge(SupplySpawn spawn) async {
    final p = player;
    final f = _fix;
    if (p == null || f == null) return;
    final def = supplyDefs[spawn.supplyType]!;
    if (p.stamina < def.staminaCost) {
      ui.toast('Resistencia insuficiente. Comé algo o descansá.', ToastTone.warn);
      return;
    }
    final result = await _net(() => repo.validateInteraction(InteractionRequest(
      playerId: p.id,
      action: InteractionAction.scavenge,
      targetId: spawn.id,
      targetExpiresAt: spawn.expiresAt,
      targetPosition: spawn.position,
      playerPosition: f.position,
      accuracyM: f.accuracyM,
      timestamp: now,
    )));
    if (result == null) return;
    if (!result.ok) {
      ui.toast((result.reason ?? InteractionRejection.outOfRange).message, ToastTone.warn);
      if (result.reason == InteractionRejection.depleted || result.reason == InteractionRejection.expired) {
        _markDepleted(spawn.id, spawn.expiresAt);
      }
      return;
    }
    final current = player!;
    final multiplier = factionModifiers(current.factionId).supplyLoot + shelterLevelDef(math.max(1, workshopLevel)).lootBonus;
    final loot = rollSupplyLoot(def, randomRng(), multiplier: multiplier);
    final gain = giveItems(current.copyWith(stamina: math.max(0, current.stamina - def.staminaCost)), loot);
    setPlayer(gain.player.copyWith(stats: gain.player.stats.copyWith(suppliesLooted: gain.player.stats.suppliesLooted + 1)));
    _markDepleted(spawn.id, spawn.expiresAt);
    HapticFeedback.lightImpact();
    if (gain.added.isNotEmpty) ui.toast('Recuperado: ${describeItems(gain.added)}', ToastTone.loot);
    if (gain.overflow.isNotEmpty) ui.toast('Maletín lleno: quedó ${describeItems(gain.overflow)}', ToastTone.warn);
    awardXp(def.xp, null);
  }

  // ---------------------------------------------------------------------------
  // Señales de auxilio
  // ---------------------------------------------------------------------------

  /// Responde una señal en el lugar: botín de la caja que dejaron, XP y avance
  /// en las transmisiones del Archivo. Devuelve el texto de la transmisión.
  Future<String?> answerSignal(DistressSignal signal) async {
    final p = player;
    final f = _fix;
    if (p == null || f == null) return null;
    final result = await _net(() => repo.validateInteraction(InteractionRequest(
          playerId: p.id,
          action: InteractionAction.scavenge,
          targetId: signal.id,
          targetExpiresAt: signal.expiresAt,
          targetPosition: signal.position,
          playerPosition: f.position,
          accuracyM: f.accuracyM,
          timestamp: now,
        )));
    if (result == null) return null;
    if (!result.ok) {
      ui.toast((result.reason ?? InteractionRejection.outOfRange).message, ToastTone.warn);
      if (result.reason == InteractionRejection.depleted || result.reason == InteractionRejection.expired) {
        _markDepleted(signal.id, signal.expiresAt);
      }
      return null;
    }
    final loot = rollSupplyLoot(supplyDefs[SupplyTypeId.military]!, createRng('loot:${signal.id}:${p.id}'));
    final gain = giveItems(player!, loot);
    setPlayer(gain.player);
    signalsAnswered++;
    _markDepleted(signal.id, signal.expiresAt);
    HapticFeedback.mediumImpact();
    ui.toast('Señal respondida', ToastTone.network);
    if (gain.added.isNotEmpty) ui.toast('Recuperado: ${describeItems(gain.added)}', ToastTone.loot);
    if (gain.overflow.isNotEmpty) ui.toast('Maletín lleno: quedó ${describeItems(gain.overflow)}', ToastTone.warn);
    awardXp(signalXp, null);
    return signal.message;
  }

  // ---------------------------------------------------------------------------
  // Combate
  // ---------------------------------------------------------------------------

  /// Valida y arranca un encuentro. Devuelve true si hay que abrir la pantalla.
  Future<bool> engage(ZombieSpawn spawn) async {
    final p = player;
    final f = _fix;
    if (p == null || f == null || combat != null) return false;
    if (p.health <= 5) {
      ui.toast('Signos vitales críticos. Curate antes de enfrentar.', ToastTone.warn);
      return false;
    }
    final result = await _net(() => repo.validateInteraction(InteractionRequest(
      playerId: p.id,
      action: InteractionAction.encounter,
      targetId: spawn.id,
      targetExpiresAt: spawn.expiresAt,
      targetPosition: spawn.position,
      playerPosition: f.position,
      accuracyM: f.accuracyM,
      timestamp: now,
    )));
    if (result == null) return false;
    if (!result.ok) {
      ui.toast((result.reason ?? InteractionRejection.outOfRange).message, ToastTone.warn);
      return false;
    }
    combat = startCombat(spawnId: spawn.id, zombieType: spawn.zombieType, player: player!, rng: randomRng());
    combatSpawn = spawn;
    outcome = null;
    notifyListeners();
    return true;
  }

  /// Resuelve un turno y devuelve el nuevo estado para animar sus eventos.
  CombatState? combatAction(CombatAction action) {
    final state = combat;
    if (state == null || state.status != CombatStatus.ongoing) return state;
    final next = resolveTurn(state, action, randomRng());
    combat = next;
    if (next.status != CombatStatus.ongoing) _settleCombat();
    notifyListeners();
    return next;
  }

  void _settleCombat() {
    final state = combat;
    final spawn = combatSpawn;
    final p0 = player;
    if (state == null || spawn == null || p0 == null || state.status == CombatStatus.ongoing) return;
    var p = p0.copyWith(health: state.player.health.toDouble(), stamina: state.player.stamina.toDouble(), lastRegenAt: now);
    p = takeItems(p, state.consumed) ?? p;
    final out = CombatOutcome(state.status);
    switch (state.status) {
      case CombatStatus.won:
        final reward = combatReward(state, randomRng());
        final gain = giveItems(p, reward.items);
        final killed = Map<ZombieTypeId, int>.from(gain.player.stats.zombiesKilled);
        killed[state.zombie.typeId] = (killed[state.zombie.typeId] ?? 0) + 1;
        p = gain.player.copyWith(
          stats: gain.player.stats.copyWith(encountersWon: gain.player.stats.encountersWon + 1, zombiesKilled: killed),
        );
        out
          ..reward = reward
          ..added = gain.added
          ..overflow = gain.overflow;
        _markDepleted(spawn.id, spawn.expiresAt);
      case CombatStatus.lost:
        final death = applyDeathPenalty(p, gameConfig.death);
        p = death.player;
        out.lost = death.lost;
      default:
        p = p.copyWith(stats: p.stats.copyWith(encountersFled: p.stats.encountersFled + 1));
    }
    setPlayer(p);
    if (out.reward != null) out.levelsGained = awardXp(out.reward!.xp, null);
    outcome = out;
  }

  void leaveCombat() {
    combat = null;
    combatSpawn = null;
    outcome = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Maletín y taller
  // ---------------------------------------------------------------------------

  void consume(ItemId id) {
    final p = player;
    if (p == null) return;
    final next = consumeItem(p, id);
    if (next == null) return;
    setPlayer(next);
    final dh = (next.health - p.health).round();
    final ds = (next.stamina - p.stamina).round();
    final parts = [if (dh > 0) '+$dh salud', if (ds > 0) '+$ds resistencia'];
    ui.toast('${itemDefs[id]!.name}: ${parts.isEmpty ? 'sin efecto, ya estabas al máximo' : parts.join(', ')}', ToastTone.good);
  }

  void equip(ItemId id) {
    final p = player;
    final next = p == null ? null : equipItem(p, id);
    if (next == null) return;
    setPlayer(next);
    ui.toast('Equipado: ${itemDefs[id]!.name}', ToastTone.good);
  }

  void unequip(EquipmentSlot slot) {
    final p = player;
    if (p == null) return;
    setPlayer(unequipSlot(p, slot));
  }

  void craftRecipe(Recipe recipe) {
    final p = player;
    if (p == null) return;
    final result = craft(p.inventory, recipe, workshopLevel, capacity: capacityOf(p));
    if (result == null) {
      ui.toast('No se puede fabricar ahora.', ToastTone.warn);
      return;
    }
    setPlayer(p.copyWith(inventory: result.inventory, stats: p.stats.copyWith(itemsCrafted: p.stats.itemsCrafted + 1)));
    HapticFeedback.mediumImpact();
    ui.toast('Fabricado: ${describeItems(result.crafted)}', ToastTone.good);
    awardXp(gameConfig.xp.craft, null);
  }

  // ---------------------------------------------------------------------------
  // Nodos (refugios)
  // ---------------------------------------------------------------------------

  static const Inventory nodeBuildCost = {ItemId.wood: 5, ItemId.metal: 3};

  /// Instala la antena propia. Por privacidad NO se ubica en la posición real:
  /// se difumina a una grilla de ~250 m y se ajusta a una calle pública.
  Future<Shelter?> buildNode(String name) async {
    final p = player;
    final f = _fix;
    if (p == null || f == null) return null;
    if (ownShelter != null) {
      ui.toast('Ya tenés un nodo suturado.', ToastTone.warn);
      return null;
    }
    final paid = takeItems(p, nodeBuildCost);
    if (paid == null) {
      ui.toast('Necesitás ${describeItems(nodeBuildCost)} para la antena.', ToastTone.warn);
      return null;
    }
    final fuzzed = fuzzPosition(f.position, 'shelter:${p.id}');
    final data = world.placementSource?.call();
    final publicPosition = (data != null ? placePoint(fuzzed, data, 150) : null) ?? fuzzed;
    try {
      final shelter = await repo.createShelter(CreateShelterInput(
        name: name.trim().isEmpty ? 'Nodo de ${p.name}' : name.trim().substring(0, math.min(32, name.trim().length)),
        ownerId: p.id,
        ownerName: p.name,
        factionId: p.factionId,
        publicPosition: publicPosition,
      ));
      setPlayer(paid);
      world.upsertShelter(shelter);
      HapticFeedback.heavyImpact();
      ui.toast('Nodo suturado a la red. Está en un punto público cercano.', ToastTone.network);
      awardXp(25, null);
      return shelter;
    } catch (e) {
      ui.toast('No se pudo instalar la antena: $e', ToastTone.bad);
      return null;
    }
  }

  double? distanceTo(LatLng target) {
    final f = _fix;
    return f == null ? null : haversineM(f.position, target);
  }

  bool isNear(LatLng target) {
    final f = _fix;
    return f != null && isWithinReach(f.position, target, f.accuracyM, gameConfig.interactionRules);
  }

  Future<void> donate(Shelter shelter, Inventory resources) async {
    final p = player;
    final f = _fix;
    if (p == null || f == null) return;
    final offered = <ItemId, int>{};
    for (final e in resources.entries) {
      final amount = math.min(countOf(p.inventory, e.key), e.value);
      if (amount > 0) offered[e.key] = amount;
    }
    if (offered.isEmpty) {
      ui.toast('No tenés esos recursos.', ToastTone.warn);
      return;
    }
    final r = await _net(() => repo.donateToShelter(DonationInput(
      shelterId: shelter.id,
      playerId: p.id,
      playerName: p.name,
      resources: offered,
      playerPosition: f.position,
      accuracyM: f.accuracyM,
    )));
    if (r == null) return;
    if (!r.ok || r.shelter == null) {
      ui.toast(
        switch (r.reason) {
          DonationRejection.outOfRange => 'Tenés que estar en el nodo para entregar.',
          DonationRejection.invalidAmount => 'La antena no necesita esos recursos ahora.',
          _ => 'No se encontró el nodo.',
        },
        ToastTone.warn,
      );
      return;
    }
    final total = r.accepted.values.fold(0, (a, b) => a + b);
    final current = player!;
    setPlayer(current.copyWith(
      inventory: removeItems(current.inventory, r.accepted) ?? current.inventory,
      stats: current.stats.copyWith(resourcesDonated: current.stats.resourcesDonated + total),
    ));
    world.upsertShelter(r.shelter!);
    ui.toast('Entregado: ${describeItems(r.accepted)}', ToastTone.loot);
    awardXp(total * gameConfig.xp.donatePerUnit, null);
    if (r.leveledUp) {
      final def = shelterLevelDef(r.shelter!.level);
      HapticFeedback.heavyImpact();
      ui.celebrate(Celebration('ANTENA NIVEL ${r.shelter!.level}', '${r.shelter!.name} · ${def.name}'));
    }
  }

  /// Ritual de la bitácora: escribir en la máquina guarda la partida y descansa.
  Future<bool> logAndRest(Shelter shelter, String line) async {
    final p = player;
    if (p == null) return false;
    if (!isNear(shelter.position)) {
      ui.toast('La bitácora solo se escribe dentro del nodo.', ToastTone.warn);
      return false;
    }
    final r = restAtShelter(p, shelter.level, now);
    if (!r.ok) {
      setPlayer(p);
      await flush();
      ui.toast('Partida guardada. Descanso disponible en ${(r.cooldownLeftMs / 60000).ceil()} min.', ToastTone.info);
      return true;
    }
    setPlayer(r.player);
    await flush();
    ui.toast('Bitácora actualizada. Partida guardada y signos vitales estabilizados.', ToastTone.good);
    return true;
  }

  Future<void> sendPulse(Shelter shelter) async {
    final p = player;
    if (p == null) return;
    HapticFeedback.selectionClick();
    final total = await _net(() => repo.sendPulse(shelter.id, p.id, 1));
    if (total == null) return;
    notifyListeners();
    ui.toast('+1 PULSO · ${shelter.name} ($total)', ToastTone.network);
  }

  int pulsesOf(Shelter shelter) {
    final r = repo;
    return switch (r) {
      LocalRepository() => r.pulsesOf(shelter.id),
      SupabaseRepository() => r.pulsesOf(shelter.id),
      _ => 0,
    };
  }

  // ---------------------------------------------------------------------------
  // Perfil, comunidad y archivo
  // ---------------------------------------------------------------------------

  Future<void> joinFaction(FactionId? id) async {
    final p = player;
    if (p == null) return;
    setPlayer(p.copyWith(factionId: id));
    await repo.joinFaction(p.id, id).catchError((_) {});
    if (id != null) ui.toast('Te uniste a ${factionDefs[id]!.name}.', ToastTone.good);
  }

  void rename(String name) {
    final clean = name.trim();
    final p = player;
    if (p == null || clean.length < 2) return;
    setPlayer(p.copyWith(name: clean.substring(0, math.min(20, clean.length))));
  }

  bool isLoreUnlocked(LoreFile f) {
    final p = player;
    if (p == null) return false;
    final kills = p.stats.zombiesKilled.values.fold(0, (a, b) => a + b);
    return switch (f.unlock.stat) {
      UnlockStat.always => true,
      UnlockStat.level => p.level >= f.unlock.value,
      UnlockStat.kills => kills >= f.unlock.value,
      UnlockStat.explored => p.stats.cellsExplored >= f.unlock.value,
      UnlockStat.looted => p.stats.suppliesLooted >= f.unlock.value,
      UnlockStat.donated => p.stats.resourcesDonated >= f.unlock.value,
      UnlockStat.bruteKills => (p.stats.zombiesKilled[ZombieTypeId.brute] ?? 0) >= 1,
      UnlockStat.shelters => ownShelter != null,
      UnlockStat.signals => signalsAnswered >= f.unlock.value,
    };
  }

  void markLoreRead(String id) {
    if (readLore.add(id)) {
      unawaited(_saveSession());
      notifyListeners();
    }
  }

  int get unreadLore => loreFiles.where((f) => isLoreUnlocked(f) && !readLore.contains(f.id)).length;

  /// Simulación: ir hasta un punto lejano (refugios de otra zona).
  void demoTravel(LatLng to) => location.demo?.teleport(to);

  Future<void> resetProgress() async {
    final r = repo;
    if (r is LocalRepository) await r.reset();
    await store.remove(_kSession);
    depleted = {};
    explored = {};
    walkBuffer = 0;
    readLore = {};
    signalsAnswered = 0;
    final id = await repo.init();
    setPlayer(createPlayer(id, _randomName(), now));
    ui.toast('Progreso reiniciado.', ToastTone.info);
  }
}

AppState get app => AppState.instance;
