import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/caps_title.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/item_glyph.dart';
import '../widgets/screen_frame.dart';
import '../widgets/seg_bar.dart';

/// Objeto ubicado en la grilla del maletín.
class PlacedItem {
  const PlacedItem(this.id, this.count, this.x, this.y, this.w, this.h);
  final ItemId id;
  final int count;
  final int x, y, w, h;
}

int _packOrder(ItemId id) => switch (itemDefs[id]!.category) {
      ItemCategory.weapon => 0,
      ItemCategory.armor => 1,
      ItemCategory.consumable => 2,
      ItemCategory.resource => 3,
    };

/// Acomoda los objetos en una grilla de `cols` columnas (primer hueco libre,
/// de arriba a la izquierda), como un maletín de survival horror.
/// Devuelve las ubicaciones y la cantidad de filas usadas.
({List<PlacedItem> items, int rows}) packAttache(Inventory inv, {int cols = 6}) {
  final list = entries(inv).toList()
    ..sort((a, b) {
      final o = _packOrder(a.key).compareTo(_packOrder(b.key));
      if (o != 0) return o;
      final fa = itemFootprint(a.key), fb = itemFootprint(b.key);
      final area = (fb.w * fb.h).compareTo(fa.w * fa.h);
      return area != 0 ? area : a.key.index.compareTo(b.key.index);
    });
  final occupied = <int>{};
  bool free(int x, int y, int w, int h) {
    if (x + w > cols) return false;
    for (var dy = 0; dy < h; dy++) {
      for (var dx = 0; dx < w; dx++) {
        if (occupied.contains((y + dy) * cols + x + dx)) return false;
      }
    }
    return true;
  }

  final placed = <PlacedItem>[];
  var rows = 0;
  for (final e in list) {
    final f = itemFootprint(e.key);
    final w = f.w > cols ? cols : f.w;
    var done = false;
    for (var y = 0; !done; y++) {
      for (var x = 0; x + w <= cols; x++) {
        if (!free(x, y, w, f.h)) continue;
        for (var dy = 0; dy < f.h; dy++) {
          for (var dx = 0; dx < w; dx++) {
            occupied.add((y + dy) * cols + x + dx);
          }
        }
        placed.add(PlacedItem(e.key, e.value, x, y, w, f.h));
        if (y + f.h > rows) rows = y + f.h;
        done = true;
        break;
      }
    }
  }
  return (items: placed, rows: rows);
}

/// Pestaña MALETÍN: inventario en grilla, equipo y taller.
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
        return TabScreenFrame(
          title: 'Maletín',
          code: 'VITA-7 // CARGA Y TALLER',
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: kg(carried), style: TextStyle(color: carried >= cap ? Sutura.danger : Sutura.textHi)),
                  TextSpan(text: ' / ${kg(cap)} KG', style: const TextStyle(color: Sutura.textLow)),
                ]),
                style: SuturaText.mono.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 5),
              SizedBox(
                width: 110,
                child: SegBar(value: carried.toDouble(), max: cap.toDouble(), segments: 16, color: carried >= cap ? Sutura.danger : Sutura.amber, height: 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SegmentTabs(labels: const ['Objetos', 'Taller'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
              ),
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
    final packed = packAttache(player.inventory);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        const SectionLabel('Equipo'),
        Row(
          children: [
            Expanded(child: _SlotCard(label: 'Cuerpo a cuerpo', id: eq.melee, fallback: 'Puños')),
            const SizedBox(width: 8),
            Expanded(child: _SlotCard(label: 'Arma de fuego', id: eq.firearm)),
            const SizedBox(width: 8),
            Expanded(child: _SlotCard(label: 'Protección', id: eq.armor)),
          ],
        ),
        SectionLabel('Contenido', trailing: MicroText('${entries(player.inventory).length} tipos')),
        if (packed.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('El maletín está vacío.\nEscaneá la zona y recuperá suministros.', textAlign: TextAlign.center, style: SuturaText.bodyMid)),
          )
        else
          _AttacheGrid(packed: packed, equipment: eq),
        const SizedBox(height: 10),
        Text(
          'Tocá un objeto para usarlo o equiparlo. Las armas y protecciones equipadas no pesan.',
          style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.label, required this.id, this.fallback});

  final String label;
  final ItemId? id;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final i = id;
    final color = i == null ? Sutura.lineStrong : itemColor(i);
    return GestureDetector(
      onTap: i == null ? null : () => showItemSheet(context, i),
      child: Container(
        height: 86,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Sutura.surface1Solid,
          border: Border.all(color: i == null ? Sutura.lineHair : color.withValues(alpha: 0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MicroText(label),
            const Spacer(),
            Row(
              children: [
                Icon(i == null ? Icons.remove : itemIcon(i), size: 18, color: i == null ? Sutura.textLow : color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    i == null ? (fallback ?? 'Vacío') : itemDefs[i]!.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SuturaText.caption.copyWith(color: i == null ? Sutura.textLow : Sutura.textHi, fontSize: 12.5, height: 1.1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttacheGrid extends StatelessWidget {
  const _AttacheGrid({required this.packed, required this.equipment});

  final ({List<PlacedItem> items, int rows}) packed;
  final Equipment equipment;

  static const cols = 6;
  static const gap = 4.0;

  bool _isEquipped(ItemId id) => equipment.melee == id || equipment.firearm == id || equipment.armor == id;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cell = (c.maxWidth - 16 - gap * (cols - 1)) / cols;
      final rows = packed.rows < 5 ? 5 : packed.rows + 1;
      final height = rows * cell + (rows - 1) * gap;
      return BracketPanel(
        padding: const EdgeInsets.all(8),
        color: Sutura.lineStrong,
        background: const Color(0xFF0B1013),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              // Celdas vacías del forro del maletín.
              for (var y = 0; y < rows; y++)
                for (var x = 0; x < cols; x++)
                  Positioned(
                    left: x * (cell + gap),
                    top: y * (cell + gap),
                    width: cell,
                    height: cell,
                    child: Container(decoration: BoxDecoration(border: Border.all(color: Sutura.lineHair.withValues(alpha: 0.5)))),
                  ),
              for (final it in packed.items)
                Positioned(
                  left: it.x * (cell + gap),
                  top: it.y * (cell + gap),
                  width: it.w * cell + (it.w - 1) * gap,
                  height: it.h * cell + (it.h - 1) * gap,
                  child: _ItemTile(item: it, cell: cell, equipped: _isEquipped(it.id)),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.cell, required this.equipped});

  final PlacedItem item;
  final double cell;
  final bool equipped;

  @override
  Widget build(BuildContext context) {
    final def = itemDefs[item.id]!;
    final color = itemColor(item.id);
    final wide = item.w > 1;
    return GestureDetector(
      onTap: () => showItemSheet(context, item.id),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Sutura.surface2, Color.lerp(Sutura.surface2, color, 0.08)!],
          ),
          border: Border.all(color: equipped ? Sutura.signal : color.withValues(alpha: 0.45), width: equipped ? 1.4 : 1),
        ),
        child: Stack(
          children: [
            Center(child: Icon(itemIcon(item.id), size: cell * (item.h > 1 ? 0.8 : 0.5), color: color)),
            if (wide)
              Positioned(
                left: 5,
                top: 4,
                right: 5,
                child: Text(def.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: SuturaText.micro.copyWith(color: Sutura.textMid, fontSize: 8)),
              ),
            if (item.count > 1)
              Positioned(
                right: 3,
                bottom: 1,
                child: Text('${item.count}', style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.textHi)),
              ),
            if (equipped)
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  color: Sutura.signal,
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  child: Text('EQ', style: SuturaText.mono.copyWith(fontSize: 8.5, color: Sutura.void_, height: 1.1)),
                ),
              ),
          ],
        ),
      ),
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
    barrierColor: Sutura.void_.withValues(alpha: 0.7),
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
        final equipped = slot != null && eq != null && switch (slot) {
              EquipmentSlot.melee => eq.melee == id,
              EquipmentSlot.firearm => eq.firearm == id,
              EquipmentSlot.armor => eq.armor == id,
            };
        final color = itemColor(id);
        final w = def.weapon;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: BracketPanel(
              color: color,
              background: Sutura.surface1Solid,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ItemGlyph(id, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CapsTitle(def.name, size: 18),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                StatusChip(def.rarity.label, color: color),
                                StatusChip(categoryLabel(def.category)),
                                if (equipped) const StatusChip('Equipado', color: Sutura.signal, filled: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(def.description, style: SuturaText.bodyMid),
                  const SizedBox(height: 10),
                  if (w != null) ...[
                    DataRow2('Daño', '${w.damage.min}–${w.damage.max}'),
                    DataRow2('Precisión', '${(w.accuracy * 100).round()} %'),
                    DataRow2('Crítico', '${(w.critChance * 100).round()} %'),
                    if (w.ammoPerShot > 0) DataRow2('Munición', '${w.ammoPerShot} por disparo'),
                  ],
                  if (def.armor != null) DataRow2('Defensa', '${def.armor!.defense}'),
                  if (def.effects?.health case final h? when h > 0) DataRow2('Salud', '+$h', valueColor: Sutura.fine),
                  if (def.effects?.stamina case final s? when s > 0) DataRow2('Resistencia', '+$s', valueColor: Sutura.fine),
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
                            tone: ChamferTone.primary,
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
                            style: SuturaText.caption.copyWith(color: Sutura.textLow),
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
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        SectionLabel(
          'Recetas',
          trailing: MicroText(level == 0 ? 'sin nodo propio' : 'antena nv $level', color: level == 0 ? Sutura.textLow : Sutura.amber),
        ),
        for (final r in recipes) _RecipeCard(recipe: r, player: player, workshopLevel: level),
        const SizedBox(height: 6),
        Text(
          'Las recetas avanzadas necesitan tu propio nodo con la antena mejorada. Instalalo desde la pestaña Red.',
          style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500),
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
        opacity: locked ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Sutura.surface1Solid,
            border: Border.all(color: check.ok ? Sutura.signal.withValues(alpha: 0.6) : Sutura.lineHair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ItemGlyph(recipe.output, size: 42, dim: locked),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(recipeName(recipe), style: SuturaText.body.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        if (recipe.requiresShelterLevel > 0)
                          MicroText('antena nv ${recipe.requiresShelterLevel}', color: locked ? Sutura.danger : Sutura.amber)
                        else
                          const MicroText('se fabrica en cualquier lado'),
                      ],
                    ),
                  ),
                  if (locked) const Icon(Icons.lock_outline, size: 18, color: Sutura.textLow),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in entries(recipe.inputs))
                    _InputChip(id: e.key, have: countOf(player.inventory, e.key), need: e.value),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reason ?? 'Listo para fabricar',
                      style: SuturaText.caption.copyWith(color: check.ok ? Sutura.fine : Sutura.textLow),
                    ),
                  ),
                  ChamferButton(
                    label: 'Fabricar',
                    icon: Icons.build_outlined,
                    tone: ChamferTone.primary,
                    dense: true,
                    height: 38,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: ok ? Sutura.lineStrong : Sutura.danger.withValues(alpha: 0.6))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(itemIcon(id), size: 13, color: ok ? Sutura.textMid : Sutura.danger),
          const SizedBox(width: 5),
          Text(itemDefs[id]!.name, style: SuturaText.caption.copyWith(fontSize: 11.5, color: Sutura.textMid)),
          const SizedBox(width: 6),
          Text('$have/$need', style: SuturaText.mono.copyWith(fontSize: 11, color: ok ? Sutura.textHi : Sutura.danger)),
        ],
      ),
    );
  }
}
