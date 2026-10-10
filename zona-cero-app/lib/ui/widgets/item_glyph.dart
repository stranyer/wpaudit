import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/tokens.dart';

/// Ícono de cada objeto (trazo fino, sin relleno).
IconData itemIcon(ItemId id) => switch (id) {
      ItemId.food => Icons.lunch_dining_outlined,
      ItemId.water => Icons.water_drop_outlined,
      ItemId.medicine => Icons.medication_outlined,
      ItemId.wood => Icons.forest_outlined,
      ItemId.metal => Icons.hardware_outlined,
      ItemId.ammo => Icons.grain,
      ItemId.medkit => Icons.medical_services_outlined,
      ItemId.ration => Icons.fastfood_outlined,
      ItemId.adrenaline => Icons.vaccines_outlined,
      ItemId.pipe => Icons.plumbing_outlined,
      ItemId.nailBat => Icons.sports_cricket_outlined,
      ItemId.machete => Icons.content_cut,
      ItemId.fireAxe => Icons.carpenter_outlined,
      ItemId.pistol => Icons.gps_fixed,
      ItemId.shotgun => Icons.gps_not_fixed,
      ItemId.leatherJacket => Icons.checkroom_outlined,
      ItemId.scrapVest => Icons.shield_outlined,
      ItemId.riotArmor => Icons.security_outlined,
    };

Color itemColor(ItemId id) => rarityColor(itemDefs[id]!.rarity.key);

String categoryLabel(ItemCategory c) => switch (c) {
      ItemCategory.resource => 'Recurso',
      ItemCategory.consumable => 'Consumible',
      ItemCategory.weapon => 'Arma',
      ItemCategory.armor => 'Protección',
    };

/// Huella del objeto en la grilla del maletín (columnas × filas).
({int w, int h}) itemFootprint(ItemId id) {
  final def = itemDefs[id]!;
  return switch (def.category) {
    ItemCategory.weapon when id == ItemId.shotgun => (w: 4, h: 1),
    ItemCategory.weapon when (def.weapon?.ammoPerShot ?? 0) > 0 => (w: 2, h: 1),
    ItemCategory.weapon => (w: 3, h: 1),
    ItemCategory.armor => (w: 2, h: 2),
    _ => (w: 1, h: 1),
  };
}

/// Glifo de objeto dentro de un cuadro con chaflán.
class ItemGlyph extends StatelessWidget {
  const ItemGlyph(this.id, {super.key, this.size = 40, this.dim = false});

  final ItemId id;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = dim ? Sutura.textLow : itemColor(id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Sutura.surface2,
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Icon(itemIcon(id), size: size * 0.52, color: c),
    );
  }
}
