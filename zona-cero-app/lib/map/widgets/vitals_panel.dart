import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/ecg_monitor.dart';
import '../../ui/widgets/grit.dart';
import '../../ui/widgets/weapon_panel.dart' show ammoSplit, displayedWeapon;

/// Panel inferior del mapa, partido en dos: "SIGNOS VITALES" (ECG, salud
/// grande y resistencia en bloques) y "ARMA EQUIPADA" (foto, nombre y
/// munición "07 / 32").
class MapVitalsPanel extends StatelessWidget {
  const MapVitalsPanel({super.key, this.height = 78});

  final double height;

  static const _cuts = Cuts(topLeft: 9, topRight: 9, bottomRight: 9, bottomLeft: 9);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        final hp = p == null ? 100.0 : p.health;
        final hpMax = p == null ? 100 : maxHealth(p);
        final st = p == null ? 100.0 : p.stamina;
        final stMax = p == null ? 100 : maxStamina(p);
        final ratio = (hp / hpMax).clamp(0.0, 1.0);
        final stRatio = (st / stMax).clamp(0.0, 1.0);
        final weapon = p == null ? null : displayedWeapon(p.equipment);
        final ammo = p == null ? 0 : countOf(p.inventory, ItemId.ammo);
        return Semantics(
          label: 'Signos vitales ${hp.round()} de $hpMax. Resistencia ${st.round()}. '
              'Arma: ${weapon == null ? 'puños' : itemDefs[weapon]!.name}.',
          child: SizedBox(
            height: height,
            child: GritPanel(
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
              background: const Color(0xEB0B0C0D),
              border: const Color(0xFF4F5356),
              corners: null,
              cuts: _cuts,
              child: Row(
                children: [
                  Expanded(flex: 55, child: _Vitals(ratio: ratio, hp: hp.round(), hpMax: hpMax, stamina: stRatio, staminaValue: st.round())),
                  Container(width: 1, margin: const EdgeInsets.fromLTRB(10, 4, 12, 2), color: Sutura.lineStrong),
                  Expanded(flex: 45, child: _Weapon(weapon: weapon, ammo: ammo)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

TextStyle get _label => SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 2.4, color: const Color(0xFF8C8F91));

class _Vitals extends StatelessWidget {
  const _Vitals({required this.ratio, required this.hp, required this.hpMax, required this.stamina, required this.staminaValue});

  final double ratio;
  final int hp;
  final int hpMax;
  final double stamina;
  final int staminaValue;

  @override
  Widget build(BuildContext context) {
    final color = vitalColor(vitalFor(ratio));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SIGNOS VITALES', style: _label),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                EcgMonitor(ratio: ratio, width: (c.maxWidth * 0.5).clamp(50.0, 110.0), height: c.maxHeight - 2, showLabel: false),
                const Spacer(),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$hp', style: TextStyle(color: color)),
                    TextSpan(text: '/$hpMax', style: const TextStyle(fontSize: 12.5, color: Color(0xFF7E8183), fontWeight: FontWeight.w500)),
                  ]),
                  style: SuturaText.number.copyWith(fontSize: 29, letterSpacing: 0.4),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Text('RES', style: _label.copyWith(letterSpacing: 1.6)),
            const SizedBox(width: 8),
            Expanded(
              child: BlockBar(ratio: stamina, segments: 10, color: const Color(0xFF9CC5D8), height: 6, gap: 3.5, empty: const Color(0xFF26292C)),
            ),
            const SizedBox(width: 8),
            Text('$staminaValue', style: SuturaText.label.copyWith(fontSize: 11, letterSpacing: 1, color: const Color(0xFF9CC5D8))),
          ],
        ),
      ],
    );
  }
}

class _Weapon extends StatelessWidget {
  const _Weapon({required this.weapon, required this.ammo});

  final ItemId? weapon;
  final int ammo;

  @override
  Widget build(BuildContext context) {
    final w = weapon;
    final def = w == null ? null : itemDefs[w]!;
    final firearm = (def?.weapon?.ammoPerShot ?? 0) > 0;
    final split = firearm ? ammoSplit(w!, ammo) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ARMA EQUIPADA', style: _label),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: w == null
                    ? const Icon(Icons.back_hand_outlined, size: 28, color: Sutura.textMid)
                    : OverflowBox(maxWidth: 70, maxHeight: 70, child: ItemArt(w, size: 66)),
              ),
              const SizedBox(width: 6),
              Expanded(
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
                        style: SuturaText.label.copyWith(color: const Color(0xFFD9D6CF), fontSize: 10.5, letterSpacing: 1.6),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (split != null)
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: split.loaded.toString().padLeft(2, '0'),
                            style: TextStyle(color: split.loaded == 0 ? Sutura.danger : const Color(0xFFDEDBD4)),
                          ),
                          TextSpan(
                            text: ' / ${split.reserve.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF8C8F91), fontWeight: FontWeight.w500),
                          ),
                        ]),
                        style: SuturaText.number.copyWith(fontSize: 26),
                      )
                    else
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: def?.weapon == null ? '3–6' : '${def!.weapon!.damage.min}–${def.weapon!.damage.max}'),
                          const TextSpan(text: '  DAÑO', style: TextStyle(fontSize: 9, letterSpacing: 1.6, color: Color(0xFF8C8F91))),
                        ]),
                        style: SuturaText.number.copyWith(fontSize: 22),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
