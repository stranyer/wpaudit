import '../core/core.dart';

/// Contrato de persistencia y datos compartidos (igual que la versión web).
///
/// - [LocalRepository]: dispositivo + comunidad simulada (sin backend).
/// - [SupabaseRepository]: Supabase/PostGIS con las mismas funciones RPC.
///
/// Privacidad: la ubicación real solo viaja para validar distancias; lo público
/// se difumina en el cliente y otra vez en el servidor.
abstract interface class GameRepository {
  String get kind;

  /// Inicializa sesión (anónima en Supabase). Devuelve el id del jugador.
  Future<String> init();

  Future<PlayerState?> loadPlayer();
  Future<void> savePlayer(PlayerState player);

  Future<InteractionResult> validateInteraction(InteractionRequest request);

  Future<List<Shelter>> getNearbyShelters(LatLng center, double radiusM);
  Future<Shelter?> getShelter(String id);
  Future<Shelter> createShelter(CreateShelterInput input);
  Future<DonationResult> donateToShelter(DonationInput input);

  Future<List<Faction>> getFactions();
  Future<void> joinFaction(String playerId, FactionId? factionId);

  Future<List<LeaderboardEntry>> getLeaderboard(int limit);
  Future<List<PublicSurvivor>> getNearbySurvivors(LatLng center, double radiusM);

  /// Publica presencia aproximada (posición ya difuminada).
  Future<void> publishPresence(PlayerState player, LatLng approxPosition);

  /// Pulsos (el "me gusta" de la red) enviados a un nodo ajeno.
  Future<int> sendPulse(String shelterId, String playerId, int count);
}

class CreateShelterInput {
  const CreateShelterInput({
    required this.name,
    required this.ownerId,
    required this.ownerName,
    required this.factionId,
    required this.publicPosition,
  });

  final String name;
  final String ownerId;
  final String ownerName;
  final FactionId? factionId;

  /// Posición pública ya ajustada (grilla + calle).
  final LatLng publicPosition;
}

class DonationInput {
  const DonationInput({
    required this.shelterId,
    required this.playerId,
    required this.playerName,
    required this.resources,
    required this.playerPosition,
    required this.accuracyM,
  });

  final String shelterId;
  final String playerId;
  final String playerName;
  final Inventory resources;

  /// Posición real, solo para validar distancia. No se persiste en tablas públicas.
  final LatLng playerPosition;
  final double accuracyM;
}

enum DonationRejection { outOfRange, notFound, invalidAmount }

class DonationResult {
  const DonationResult({required this.ok, this.reason, this.shelter, this.accepted = const {}, this.leveledUp = false});

  final bool ok;
  final DonationRejection? reason;
  final Shelter? shelter;
  final Inventory accepted;
  final bool leveledUp;
}
