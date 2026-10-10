import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/tokens.dart';
import 'grit.dart';

/// Capacidad del cargador (solo para mostrar "cargado / reserva").
int magazineOf(ItemId weapon) => switch (weapon) {
      ItemId.shotgun => 2,
      _ => 7,
    };

/// Munición repartida en cargador y reserva para el HUD ("07 / 32").
({int loaded, int reserve}) ammoSplit(ItemId weapon, int ammo) {
  final mag = magazineOf(weapon);
  final loaded = ammo < mag ? ammo : mag;
  return (loaded: loaded, reserve: ammo - loaded);
}

/// Arma que se muestra en el HUD: el arma de fuego si hay una equipada, si no
/// la de cuerpo a cuerpo (o los puños).
ItemId? displayedWeapon(Equipment eq) => eq.firearm ?? eq.melee;

/// Panel "ARMA EQUIPADA": foto del arma, nombre y munición grande.
class WeaponPanel extends StatelessWidget {
  const WeaponPanel({super.key, required this.weapon, required this.ammo, this.height = 104, this.title = 'ARMA EQUIPADA'});

  /// null = puños.
  final ItemId? weapon;

  /// Munición total disponible (solo se muestra con armas de fuego).
  final int ammo;
  final double height;
  final String title;

  @override
  Widget build(BuildContext context) {
    final w = weapon;
    final def = w == null ? null : itemDefs[w]!;
    final firearm = (def?.weapon?.ammoPerShot ?? 0) > 0;
    final split = firearm ? ammoSplit(w!, ammo) : null;
    return GritPanel(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: SizedBox(
        height: height - 19,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SuturaText.label.copyWith(fontSize: 12, letterSpacing: 2.6)),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: w == null
                        ? const Icon(Icons.back_hand_outlined, size: 34, color: Sutura.textMid)
                        : ItemArt(w, size: 120),
                  ),
                  Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), color: Sutura.lineStrong),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            (def?.name ?? 'Puños').toUpperCase(),
                            maxLines: 1,
                            style: SuturaText.label.copyWith(color: Sutura.textMid, fontSize: 13, letterSpacing: 2),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (split != null)
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: split.loaded.toString().padLeft(2, '0'),
                                style: TextStyle(color: split.loaded == 0 ? Sutura.danger : Sutura.textHi),
                              ),
                              TextSpan(
                                text: ' / ${split.reserve.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 20, color: Sutura.textMid),
                              ),
                            ]),
                            style: SuturaText.number.copyWith(fontSize: 34),
                          )
                        else
                          Text(
                            def?.weapon == null ? '3–6' : '${def!.weapon!.damage.min}–${def.weapon!.damage.max}',
                            style: SuturaText.number.copyWith(fontSize: 30),
                          ),
                        if (split == null) Text('DAÑO', style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
