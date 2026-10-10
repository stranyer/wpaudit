import 'dart:math' as math;

import '../core/core.dart';
import '../core/interaction.dart' as rules show validateInteraction;
import 'game_repository.dart';
import 'mock_community.dart';
import 'storage.dart';

/// Repositorio local: persiste en el dispositivo y simula la comunidad.
/// Replica las validaciones que hace el servidor (alcance, velocidad, reclamos).
class LocalRepository implements GameRepository {
  LocalRepository(this._store, {int Function()? now}) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final KeyValueStore _store;
  final int Function() _now;
  SpeedGuardState _speedGuard = SpeedGuardState.initial;

  static const _kPlayerId = 'zc:playerId';
  static const _kPlayer = 'zc:player';
  static const _kShelters = 'zc:shelters';
  static const _kClaims = 'zc:claims';
  static const _kPulses = 'zc:pulses';

  @override
  String get kind => 'local';

  @override
  Future<String> init() async {
    var id = _store.getString(_kPlayerId);
    if (id == null) {
      final r = math.Random.secure();
      id = 'local-${List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join()}';
      await _store.setString(_kPlayerId, id);
    }
    return id;
  }

  @override
  Future<PlayerState?> loadPlayer() async =>
      _store.readJson(_kPlayer, (j) => PlayerState.fromJson(Map<String, dynamic>.from(j as Map)));

  @override
  Future<void> savePlayer(PlayerState player) => _store.writeJson(_kPlayer, player.toJson());

  /// Olvida la última posición validada (teletransporte de la simulación).
  void resetSpeedGuard() => _speedGuard = SpeedGuardState.initial;

  Map<String, int> _claims() {
    final claims = _store.readJson(_kClaims, (j) => Map<String, int>.from((j as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())))) ?? {};
    final now = _now();
    claims.removeWhere((_, exp) => exp <= now);
    return claims;
  }

  @override
  Future<InteractionResult> validateInteraction(InteractionRequest request) async {
    final claims = _claims();
    _speedGuard = updateSpeedGuard(
      _speedGuard,
      SpeedSample(position: request.playerPosition, time: request.timestamp),
      gameConfig.maxInteractionSpeedMps,
      gameConfig.speedLockMs,
    );
    final scavenge = request.action == InteractionAction.scavenge;
    final result = rules.validateInteraction(
      request,
      gameConfig.interactionRules,
      InteractionContext(
        speedLocked: _speedGuard.isLocked(request.timestamp),
        depleted: scavenge && claims.containsKey(request.targetId),
        expiresAt: request.targetExpiresAt,
      ),
    );
    if (result.ok && scavenge) {
      claims[request.targetId] = request.targetExpiresAt ?? request.timestamp + 3600000;
      await _store.writeJson(_kClaims, claims);
    }
    return result;
  }

  Map<String, Shelter> _stored() =>
      _store.readJson(_kShelters, (j) => (j as Map).map((k, v) => MapEntry(k as String, Shelter.fromJson(Map<String, dynamic>.from(v as Map))))) ?? {};

  List<Shelter> _allShelters() {
    final merged = <String, Shelter>{for (final s in buildMockShelters()) s.id: s};
    merged.addAll(_stored());
    return merged.values.toList();
  }

  Future<void> _persist(Shelter s) async {
    final stored = _stored()..[s.id] = s;
    await _store.writeJson(_kShelters, stored.map((k, v) => MapEntry(k, v.toJson())));
  }

  @override
  Future<List<Shelter>> getNearbyShelters(LatLng center, double radiusM) async {
    final list = _allShelters().where((s) => haversineM(center, s.position) <= radiusM).toList()
      ..sort((a, b) => haversineM(center, a.position).compareTo(haversineM(center, b.position)));
    return list;
  }

  @override
  Future<Shelter?> getShelter(String id) async {
    for (final s in _allShelters()) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<Shelter> createShelter(CreateShelterInput input) async {
    for (final s in _allShelters()) {
      if (s.ownerId == input.ownerId) return s;
    }
    final shelter = Shelter(
      id: 'sh-${input.ownerId}',
      name: input.name,
      ownerId: input.ownerId,
      ownerName: input.ownerName,
      factionId: input.factionId,
      level: 1,
      position: input.publicPosition,
      progress: const {},
      contributions: const [],
      createdAt: _now(),
    );
    await _persist(shelter);
    return shelter;
  }

  @override
  Future<DonationResult> donateToShelter(DonationInput input) async {
    final shelter = await getShelter(input.shelterId);
    if (shelter == null) return const DonationResult(ok: false, reason: DonationRejection.notFound);
    final check = rules.validateInteraction(
      InteractionRequest(
        playerId: input.playerId,
        action: InteractionAction.shelter,
        targetId: shelter.id,
        targetPosition: shelter.position,
        playerPosition: input.playerPosition,
        accuracyM: input.accuracyM,
        timestamp: _now(),
      ),
      gameConfig.interactionRules,
      const InteractionContext(speedLocked: false, depleted: false),
    );
    if (!check.ok) return const DonationResult(ok: false, reason: DonationRejection.outOfRange);
    final outcome = applyDonation(shelter, input.playerId, input.playerName, input.resources);
    if (outcome.acceptedTotal == 0) {
      return DonationResult(ok: false, reason: DonationRejection.invalidAmount, shelter: shelter);
    }
    await _persist(outcome.shelter);
    return DonationResult(ok: true, shelter: outcome.shelter, accepted: outcome.accepted, leveledUp: outcome.leveledUp);
  }

  @override
  Future<List<Faction>> getFactions() async {
    final player = await loadPlayer();
    final shelters = _allShelters();
    return [
      for (final id in factionIds)
        Faction(
          id: id,
          name: factionDefs[id]!.name,
          motto: factionDefs[id]!.motto,
          color: factionDefs[id]!.color,
          bonusDescription: factionDefs[id]!.bonusDescription,
          members: mockSurvivors.where((s) => s.factionId == id).length * 37 + (player?.factionId == id ? 1 : 0),
          totalContribution: shelters
              .where((s) => s.factionId == id)
              .fold(0, (acc, s) => acc + s.contributions.fold(0, (a, c) => a + c.amount)),
        ),
    ];
  }

  @override
  Future<void> joinFaction(String playerId, FactionId? factionId) async {
    // La facción vive en el estado del jugador; en Supabase se registra vía RPC.
  }

  @override
  Future<List<LeaderboardEntry>> getLeaderboard(int limit) async {
    final totals = <String, int>{};
    for (final s in _allShelters()) {
      for (final c in s.contributions) {
        totals[c.playerId] = (totals[c.playerId] ?? 0) + c.amount;
      }
    }
    final player = await loadPlayer();
    final list = [
      for (final s in mockSurvivors)
        LeaderboardEntry(playerId: s.id, playerName: s.name, factionId: s.factionId, level: s.level, contribution: totals[s.id] ?? 0),
      if (player != null)
        LeaderboardEntry(
          playerId: player.id,
          playerName: player.name,
          factionId: player.factionId,
          level: player.level,
          contribution: totals[player.id] ?? 0,
        ),
    ]..sort((a, b) => b.contribution.compareTo(a.contribution));
    return list.take(limit).toList();
  }

  @override
  Future<List<PublicSurvivor>> getNearbySurvivors(LatLng center, double radiusM) async {
    final list = mockSurvivorsAround(center, _now()).where((s) => haversineM(center, s.approxPosition) <= radiusM).toList()
      ..sort((a, b) => haversineM(center, a.approxPosition).compareTo(haversineM(center, b.approxPosition)));
    return list;
  }

  @override
  Future<void> publishPresence(PlayerState player, LatLng approxPosition) async {}

  @override
  Future<int> sendPulse(String shelterId, String playerId, int count) async {
    final pulses = _store.readJson(_kPulses, (j) => Map<String, int>.from((j as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())))) ?? {};
    pulses[shelterId] = (pulses[shelterId] ?? mockPulses(shelterId)) + count;
    await _store.writeJson(_kPulses, pulses);
    return pulses[shelterId]!;
  }

  /// Pulsos totales de un nodo (simulados + los enviados por el jugador).
  int pulsesOf(String shelterId) {
    final pulses = _store.readJson(_kPulses, (j) => Map<String, int>.from((j as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())))) ?? {};
    return pulses[shelterId] ?? mockPulses(shelterId);
  }

  Future<void> reset() async {
    for (final k in [_kPlayerId, _kPlayer, _kShelters, _kClaims, _kPulses]) {
      await _store.remove(k);
    }
  }
}
