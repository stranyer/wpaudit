// Contrato entre la UI de combate y la escena 3D.
// La UI traduce cada `CombatEvent` del motor a una o más animaciones.

export type CombatAnimation =
  | 'player_hit'
  | 'player_crit'
  | 'player_miss'
  | 'player_shoot'
  | 'zombie_attack'
  | 'zombie_miss'
  | 'zombie_charge_prepare'
  | 'zombie_charge'
  | 'zombie_scream'
  | 'zombie_stunned'
  | 'zombie_death'
  | 'toxic_burst'
  | 'defend'
  | 'heal'
  | 'flee';

export interface CombatViewportHandle {
  play(animation: CombatAnimation): void;
}
