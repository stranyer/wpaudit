import '../core/core.dart';

// Comunidad simulada para jugar sin backend. Los nodos comunitarios están en
// plazas y parques públicos de Buenos Aires.

class MockSurvivor {
  const MockSurvivor(this.id, this.name, this.level, this.factionId);
  final String id;
  final String name;
  final int level;
  final FactionId? factionId;
}

const mockSurvivors = <MockSurvivor>[
  MockSurvivor('npc-lucia', 'Lucía_Z', 14, FactionId.resistencia),
  MockSurvivor('npc-tano', 'ElTano', 11, FactionId.guardia),
  MockSurvivor('npc-mati', 'Mati.Rx', 9, FactionId.nomades),
  MockSurvivor('npc-caro', 'Caro Sobrevive', 17, FactionId.guardia),
  MockSurvivor('npc-nacho', 'Nacho del Sur', 7, FactionId.nomades),
  MockSurvivor('npc-vero', 'VeroKill', 21, FactionId.resistencia),
  MockSurvivor('npc-gaucho', 'Gaucho77', 5, null),
  MockSurvivor('npc-flaca', 'La Flaca', 12, FactionId.resistencia),
  MockSurvivor('npc-tincho', 'Tincho', 3, FactionId.guardia),
  MockSurvivor('npc-rulo', 'Rulo', 8, FactionId.nomades),
  MockSurvivor('npc-pato', 'Pato_BA', 19, FactionId.guardia),
  MockSurvivor('npc-juli', 'Juli Nómade', 10, FactionId.nomades),
];

class _NodeSeed {
  const _NodeSeed(this.id, this.name, this.position, this.level, this.factionId, this.owner);
  final String id;
  final String name;
  final LatLng position;
  final int level;
  final FactionId factionId;
  final String owner;
}

const _nodeSeeds = <_NodeSeed>[
  _NodeSeed('cm-lavalle', 'Nodo Plaza Lavalle', LatLng(-34.60165, -58.38418), 1, FactionId.nomades, 'npc-rulo'),
  _NodeSeed('cm-mayo', 'Bastión de Mayo', LatLng(-34.6083, -58.3712), 4, FactionId.resistencia, 'npc-vero'),
  _NodeSeed('cm-congreso', 'Trinchera Congreso', LatLng(-34.6094, -58.3925), 2, FactionId.nomades, 'npc-mati'),
  _NodeSeed('cm-centenario', 'Antena Centenario', LatLng(-34.6063, -58.4355), 3, FactionId.guardia, 'npc-caro'),
  _NodeSeed('cm-serrano', 'Relevo Serrano', LatLng(-34.5886, -58.4302), 2, FactionId.nomades, 'npc-juli'),
  _NodeSeed('cm-lezama', 'Fuerte Lezama', LatLng(-34.628, -58.3696), 3, FactionId.resistencia, 'npc-flaca'),
  _NodeSeed('cm-francia', 'Recoleta Libre', LatLng(-34.5838, -58.3931), 2, FactionId.guardia, 'npc-tano'),
  _NodeSeed('cm-dorrego', 'San Telmo Resiste', LatLng(-34.6205, -58.3714), 2, FactionId.resistencia, 'npc-lucia'),
  _NodeSeed('cm-rosedal', 'Torre del Rosedal', LatLng(-34.5717, -58.4176), 5, FactionId.guardia, 'npc-pato'),
];

/// Nodos comunitarios simulados (determinísticos).
List<Shelter> buildMockShelters() {
  return [
    for (final seed in _nodeSeeds) _buildShelter(seed),
  ];
}

Shelter _buildShelter(_NodeSeed seed) {
  final rng = createRng('mock-shelter:${seed.id}');
  final owner = mockSurvivors.firstWhere((s) => s.id == seed.owner);
  final contributors = [owner, ...mockSurvivors.where((s) => s.id != owner.id && rng.chance(0.35))];
  final contributions = [
    for (final (i, s) in contributors.indexed)
      ShelterContribution(playerId: s.id, playerName: s.name, amount: rng.intRange(10, 40) * seed.level + (i == 0 ? 40 : 0)),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return Shelter(
    id: seed.id,
    name: seed.name,
    ownerId: owner.id,
    ownerName: owner.name,
    factionId: seed.factionId,
    level: seed.level,
    position: seed.position,
    progress: seed.level < 5 ? {ItemId.wood: rng.intRange(2, 10), ItemId.metal: rng.intRange(0, 5)} : {},
    contributions: contributions,
    createdAt: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch + rng.intRange(0, 30) * 86400000,
  );
}

/// Pulsos que cada nodo simulado ya recibió (estable por nodo).
int mockPulses(String shelterId) => createRng('pulses:$shelterId').intRange(4, 160);

/// Sobrevivientes simulados alrededor del jugador, con posiciones difuminadas.
List<PublicSurvivor> mockSurvivorsAround(LatLng center, int now) {
  final window = now ~/ 300000; // cambian cada 5 minutos
  return [
    for (final s in mockSurvivors)
      () {
        final rng = createRng('presence:${s.id}:$window');
        final raw = offsetM(center, rng.range(-1800, 1800), rng.range(-1800, 1800));
        return PublicSurvivor(
          id: s.id,
          name: s.name,
          level: s.level,
          factionId: s.factionId,
          approxPosition: fuzzPosition(raw, s.id),
          lastSeenAt: now - rng.intRange(1, 25) * 60000,
        );
      }(),
  ];
}
