import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/grit.dart';
import '../widgets/item_glyph.dart';
import '../widgets/screen_frame.dart';
import '../widgets/weapon_panel.dart';

/// Espacios del maletín (cada tipo de objeto ocupa uno y se apila).
const caseSlots = 24;

/// Objetos que se muestran en la grilla: todo menos lo que está equipado
/// (el equipo aparece arriba, en "EQUIPO ACTUAL").
List<MapEntry<ItemId, int>> caseStacks(Inventory inv, Equipment eq) {
  final equipped = {eq.melee, eq.firearm, eq.armor}.whereType<ItemId>().toSet();
  final out = <MapEntry<ItemId, int>>[];
  for (final e in entries(inv)) {
    final n = equipped.contains(e.key) ? e.value - 1 : e.value;
    if (n > 0) out.add(MapEntry(e.key, n));
  }
  int order(ItemId id) => switch (itemDefs[id]!.category) {
        ItemCategory.consumable => 0,
        ItemCategory.resource => isConsumable(id) ? 1 : 2,
        ItemCategory.weapon => 3,
        ItemCategory.armor => 4,
      };
  out.sort((a, b) {
    final o = order(a.key).compareTo(order(b.key));
    return o != 0 ? o : a.key.index.compareTo(b.key.index);
  });
  return out;
}

/// Pestaña MALETÍN: equipo, inventario en espacios y taller.
class CaseScreen extends StatefulWidget {
  const CaseScreen({super.key});

  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        if (p == null) return const SizedBox.shrink();
        final carried = carriedWeight(p.inventory);
        final cap = capacityOf(p);
        final full = carried >= cap;
        return TabScreenFrame(
          title: 'Maletín',
          code: 'VITA-7  //  carga y taller',
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: kg(carried), style: TextStyle(color: full ? Sutura.danger : Sutura.textHi)),
                  const TextSpan(text: '  /  ', style: TextStyle(color: Sutura.textLow)),
                  TextSpan(text: kg(cap), style: const TextStyle(color: Sutura.textMid)),
                  const TextSpan(text: ' KG', style: TextStyle(color: Sutura.textMid, fontSize: 16)),
                ]),
                style: SuturaText.number.copyWith(fontSize: 22, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              SizedBox(width: 132, child: BlockBar(ratio: carried / cap, segments: 12, height: 6)),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GritTabs(labels: const ['Objetos', 'Taller'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Sutura.base,
                  child: _tab == 0 ? _ItemsTab(key: const ValueKey('items'), player: p) : _WorkshopTab(key: const ValueKey('ws'), player: p),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Objetos
// ---------------------------------------------------------------------------

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({super.key, required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final eq = player.equipment;
    final stacks = caseStacks(player.inventory, eq);
    final slots = stacks.length > caseSlots ? stacks.length : caseSlots;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        const SectionHeader('Equipo actual'),
        const SizedBox(height: 8),
        SizedBox(
          height: 168,
          child: Row(
            children: [
              Expanded(child: _GearCard(label: 'Cuerpo a cuerpo', id: eq.melee, empty: 'Puños', emptyIcon: Icons.back_hand_outlined)),
              const SizedBox(width: 8),
              Expanded(
                child: _GearCard(
                  label: 'Arma de fuego',
                  id: eq.firearm,
                  empty: 'Sin arma',
                  emptyIcon: Icons.do_not_disturb_alt_outlined,
                  ammo: eq.firearm == null ? null : countOf(player.inventory, ItemId.ammo),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _GearCard(label: 'Protección', id: eq.armor, empty: 'Sin protección', emptyIcon: Icons.shield_outlined)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionHeader('Inventario', trailing: '${stacks.length} / $slots espacios'),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.92),
          itemCount: slots,
          itemBuilder: (context, i) => i < stacks.length ? _SlotTile(id: stacks[i].key, count: stacks[i].value) : const _EmptySlot(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Sutura.textLow)),
              alignment: Alignment.center,
              child: Text('i', style: SuturaText.caption.copyWith(color: Sutura.textMid, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tocá un objeto para usarlo o equiparlo. Lo equipado no pesa.',
                style: SuturaText.bodyMid.copyWith(letterSpacing: 0.6, color: Sutura.textMid),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GearCard extends StatelessWidget {
  const _GearCard({required this.label, required this.id, required this.empty, required this.emptyIcon, this.ammo});

  final String label;
  final ItemId? id;
  final String empty;
  final IconData emptyIcon;
  final int? ammo;

  @override
  Widget build(BuildContext context) {
    final i = id;
    final split = i != null && ammo != null ? ammoSplit(i, ammo!) : null;
    return GestureDetector(
      onTap: i == null ? null : () => showItemSheet(context, i),
      child: GritPanel(
        background: const Color(0xF0111315),
        corners: i == null ? Sutura.lineStrong : Sutura.accent.withValues(alpha: 0.85),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label.toUpperCase(), maxLines: 1, style: SuturaText.label.copyWith(fontSize: 11, letterSpacing: 1.8))),
            Expanded(
              child: Center(
                child: i == null ? Icon(emptyIcon, size: 34, color: Sutura.textLow) : ItemArt(i, size: 96, fallbackIcon: itemIcon(i)),
              ),
            ),
            Text(
              i == null ? empty : itemName(i),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SuturaText.body.copyWith(fontSize: 15, height: 1.1, color: i == null ? Sutura.textLow : Sutura.textHi),
            ),
            if (split != null)
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: split.loaded.toString().padLeft(2, '0')),
                  TextSpan(text: ' / ${split.reserve.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 15, color: Sutura.textMid)),
                ]),
                style: SuturaText.number.copyWith(fontSize: 24),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.id, required this.count});

  final ItemId id;
  final int count;

  @override
  Widget build(BuildContext context) {
    final rarity = itemDefs[id]!.rarity;
    return GestureDetector(
      onTap: () => showItemSheet(context, id),
      child: GritPanel(
        background: const Color(0xF0121416),
        border: rarity.index >= Rarity.rare.index ? itemColor(id).withValues(alpha: 0.6) : Sutura.lineStrong,
        corners: Sutura.lineBright,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
        child: Stack(
          children: [
            Positioned.fill(
              bottom: 16,
              child: Center(child: ItemArt(id, size: 80, fallbackIcon: itemIcon(id))),
            ),
            Positioned(
              left: 2,
              right: 22,
              bottom: 0,
              child: Text(
                itemName(id),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SuturaText.body.copyWith(fontSize: 12.5, height: 1.05, color: Sutura.textHi, shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 0,
              child: Text('$count', style: SuturaText.number.copyWith(fontSize: 19, shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return GritPanel(
      background: const Color(0xC00E1011),
      border: Sutura.lineHair,
      corners: Sutura.lineStrong,
      texture: false,
      padding: EdgeInsets.zero,
      child: const Center(child: Icon(Icons.add, size: 22, color: Color(0xFF3A3E41))),
    );
  }
}

// ---------------------------------------------------------------------------
// Ficha de objeto
// ---------------------------------------------------------------------------

Future<void> showItemSheet(BuildContext context, ItemId id) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Sutura.void_.withValues(alpha: 0.75),
    isScrollControlled: true,
    builder: (_) => _ItemSheet(id: id),
  );
}

class _ItemSheet extends StatelessWidget {
  const _ItemSheet({required this.id});

  final ItemId id;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        final def = itemDefs[id]!;
        final count = p == null ? 0 : countOf(p.inventory, id);
        final slot = slotFor(id);
        final eq = p?.equipment;
        final equipped = slot != null &&
            eq != null &&
            switch (slot) {
              EquipmentSlot.melee => eq.melee == id,
              EquipmentSlot.firearm => eq.firearm == id,
              EquipmentSlot.armor => eq.armor == id,
            };
        final color = itemColor(id);
        final w = def.weapon;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: GritPanel(
              background: Sutura.surface1Solid,
              corners: Sutura.accent,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: const RadialGradient(colors: [Color(0xFF2A2D30), Color(0xFF111315)]),
                          border: Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: ItemArt(id, size: 100, fallbackIcon: itemIcon(id)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GrungeTitle(itemName(id), size: 28),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusChip(def.rarity.label, color: color),
                                StatusChip(categoryLabel(def.category)),
                                if (equipped) const StatusChip('Equipado', color: Sutura.accent, filled: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(def.description, style: SuturaText.bodyMid),
                  const SizedBox(height: 8),
                  if (w != null) ...[
                    DataRow2('Daño', '${w.damage.min}–${w.damage.max}'),
                    DataRow2('Precisión', '${(w.accuracy * 100).round()} %'),
                    DataRow2('Crítico', '${(w.critChance * 100).round()} %'),
                    if (w.ammoPerShot > 0) DataRow2('Munición', '${w.ammoPerShot} por disparo'),
                  ],
                  if (def.armor != null) DataRow2('Defensa', '${def.armor!.defense}'),
                  if (def.effects?.health case final h? when h > 0) DataRow2('Salud', '+$h', valueColor: Sutura.fine),
                  if (def.effects?.stamina case final s? when s > 0) DataRow2('Resistencia', '+$s', valueColor: Sutura.signal),
                  DataRow2('Peso', def.weight == 0 ? '—' : '${kg(def.weight)} kg'),
                  DataRow2('En el maletín', '$count'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (def.effects != null)
                        Expanded(
                          child: ChamferButton(
                            label: 'Usar',
                            icon: Icons.healing_outlined,
                            tone: ChamferTone.amber,
                            expand: true,
                            onPressed: count > 0 ? () => app.consume(id) : null,
                          ),
                        ),
                      if (def.effects != null && slot != null) const SizedBox(width: 8),
                      if (slot != null)
                        Expanded(
                          child: equipped
                              ? ChamferButton(label: 'Desequipar', tone: ChamferTone.ghost, expand: true, onPressed: () => app.unequip(slot))
                              : ChamferButton(
                                  label: 'Equipar',
                                  icon: Icons.back_hand_outlined,
                                  tone: ChamferTone.primary,
                                  expand: true,
                                  onPressed: count > 0 ? () => app.equip(id) : null,
                                ),
                        ),
                      if (def.effects == null && slot == null)
                        Expanded(
                          child: Text(
                            isResource(id) ? 'Material para el taller o para la antena de un nodo.' : '',
                            style: SuturaText.bodyMid.copyWith(color: Sutura.textLow),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Taller
// ---------------------------------------------------------------------------

class _WorkshopTab extends StatelessWidget {
  const _WorkshopTab({super.key, required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final level = app.workshopLevel;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        SectionHeader(
          'Recetas',
          icon: Icons.build_outlined,
          trailing: level == 0 ? 'sin nodo propio' : 'antena nv $level',
          trailingColor: level == 0 ? Sutura.textLow : Sutura.amber,
        ),
        const SizedBox(height: 8),
        for (final r in recipes) _RecipeCard(recipe: r, player: player, workshopLevel: level),
        const SizedBox(height: 6),
        Text(
          'Las recetas avanzadas necesitan tu propio nodo con la antena mejorada. Instalalo desde la pestaña Red.',
          style: SuturaText.bodyMid.copyWith(color: Sutura.textLow),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.player, required this.workshopLevel});

  final Recipe recipe;
  final PlayerState player;
  final int workshopLevel;

  @override
  Widget build(BuildContext context) {
    final check = checkRecipe(player.inventory, recipe, workshopLevel);
    final locked = check.block == CraftBlock.shelterLevel;
    final reason = switch (check.block) {
      CraftBlock.shelterLevel => 'Requiere antena nivel ${recipe.requiresShelterLevel}',
      CraftBlock.alreadyOwned => 'Ya tenés uno',
      CraftBlock.missingItems => 'Faltan: ${AppState.describeItems(check.missing)}',
      CraftBlock.noSpace => 'Sin espacio en el maletín',
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: locked ? 0.6 : 1,
        child: GritPanel(
          background: const Color(0xF0121416),
          accent: check.ok ? Sutura.amber : null,
          corners: check.ok ? Sutura.amber : Sutura.lineStrong,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(width: 64, height: 64, child: ItemArt(recipe.output, size: 64, dim: locked, fallbackIcon: itemIcon(recipe.output))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(recipeName(recipe).toUpperCase(), style: SuturaText.body.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.6, fontSize: 17)),
                        const SizedBox(height: 3),
                        Text(
                          recipe.requiresShelterLevel > 0 ? 'ANTENA NV ${recipe.requiresShelterLevel}' : 'SE FABRICA EN CUALQUIER LADO',
                          style: SuturaText.label.copyWith(fontSize: 11.5, color: locked ? Sutura.accent : Sutura.textLow),
                        ),
                      ],
                    ),
                  ),
                  if (locked) const Icon(Icons.lock_outline, size: 20, color: Sutura.textLow),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in entries(recipe.inputs)) _InputChip(id: e.key, have: countOf(player.inventory, e.key), need: e.value),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reason ?? 'Listo para fabricar',
                      style: SuturaText.caption.copyWith(color: check.ok ? Sutura.fine : Sutura.textLow, fontSize: 13.5),
                    ),
                  ),
                  ChamferButton(
                    label: 'Fabricar',
                    icon: Icons.build_outlined,
                    tone: ChamferTone.amber,
                    dense: true,
                    height: 40,
                    onPressed: check.ok ? () => app.craftRecipe(recipe) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputChip extends StatelessWidget {
  const _InputChip({required this.id, required this.have, required this.need});

  final ItemId id;
  final int have;
  final int need;

  @override
  Widget build(BuildContext context) {
    final ok = have >= need;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xFF15171A),
        border: Border.all(color: ok ? Sutura.lineStrong : Sutura.accent.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 26, height: 26, child: ItemArt(id, size: 26, fallbackIcon: itemIcon(id))),
          const SizedBox(width: 6),
          Text(itemName(id), style: SuturaText.caption.copyWith(fontSize: 13, color: Sutura.textMid)),
          const SizedBox(width: 6),
          Text('$have/$need', style: SuturaText.number.copyWith(fontSize: 15, color: ok ? Sutura.textHi : Sutura.accent)),
        ],
      ),
    );
  }
}
