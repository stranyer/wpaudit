import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/tokens.dart';
import 'grit.dart';

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

/// Nombre para mostrar en la interfaz (más corto que el del catálogo).
String itemName(ItemId id) => switch (id) {
      ItemId.water => 'Agua',
      ItemId.medicine => 'Medicinas',
      ItemId.metal => 'Chatarra',
      ItemId.ammo => 'Munición 9 mm',
      ItemId.adrenaline => 'Inyectable VITA-7',
      _ => itemDefs[id]!.name,
    };

String categoryLabel(ItemCategory c) => switch (c) {
      ItemCategory.resource => 'Recurso',
      ItemCategory.consumable => 'Consumible',
      ItemCategory.weapon => 'Arma',
      ItemCategory.armor => 'Protección',
    };

/// Objeto (foto HD) dentro de un marco oscuro con borde según rareza.
class ItemGlyph extends StatelessWidget {
  const ItemGlyph(this.id, {super.key, this.size = 40, this.dim = false});

  final ItemId id;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = dim ? Sutura.lineHair : itemColor(id).withValues(alpha: 0.55);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFF16181A), border: Border.all(color: c)),
      padding: EdgeInsets.all(size * 0.08),
      child: ItemArt(id, size: size, fallbackIcon: itemIcon(id), dim: dim),
    );
  }
}
