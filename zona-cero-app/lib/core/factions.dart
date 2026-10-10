// Facciones y sus bonificaciones.

import 'types.dart';

class FactionModifiers {
  const FactionModifiers({required this.combatXp, required this.supplyLoot, required this.staminaRegen});
  final double combatXp;
  final double supplyLoot;
  final double staminaRegen;
}

/// Datos fijos de una facción (`Omit<Faction, 'members' | 'totalContribution'>` en TS).
class FactionDef {
  const FactionDef({
    required this.id,
    required this.name,
    required this.motto,
    required this.color,
    required this.bonusDescription,
  });

  final FactionId id;
  final String name;
  final String motto;

  /// Color en hexadecimal CSS.
  final String color;
  final String bonusDescription;

  /// Completa la facción con los datos de comunidad.
  Faction toFaction({int members = 0, int totalContribution = 0}) => Faction(
        id: id,
        name: name,
        motto: motto,
        color: color,
        bonusDescription: bonusDescription,
        members: members,
        totalContribution: totalContribution,
      );
}

const Map<FactionId, FactionDef> factionDefs = {
  FactionId.resistencia: FactionDef(
    id: FactionId.resistencia,
    name: 'La Resistencia',
    motto: 'Recuperamos la ciudad, cuadra por cuadra.',
    color: '#c8742c',
    bonusDescription: '+10% de experiencia en combate',
  ),
  FactionId.guardia: FactionDef(
    id: FactionId.guardia,
    name: 'Guardia del Río',
    motto: 'Lo que se guarda, se sobrevive.',
    color: '#6f8a4a',
    bonusDescription: '+15% de botín en suministros',
  ),
  FactionId.nomades: FactionDef(
    id: FactionId.nomades,
    name: 'Nómades del Sur',
    motto: 'Quien se queda quieto, se convierte.',
    color: '#7b8c99',
    bonusDescription: '+25% de regeneración de resistencia',
  ),
};

const List<FactionId> factionIds = [FactionId.resistencia, FactionId.guardia, FactionId.nomades];

FactionModifiers factionModifiers(FactionId? id) => FactionModifiers(
      combatXp: id == FactionId.resistencia ? 1.1 : 1,
      supplyLoot: id == FactionId.guardia ? 1.15 : 1,
      staminaRegen: id == FactionId.nomades ? 1.25 : 1,
    );
