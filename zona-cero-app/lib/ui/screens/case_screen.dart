import 'dart:math' as math;

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

/// Pestaña MALETÍN: la valija abierta (equipo en la tapa, inventario en la
/// base) y el taller.
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
        return LogoScreenFrame(
          subtitle: 'VITA-7  //  carga y taller'.toUpperCase(),
          trailing: _WeightGauge(carried: carriedWeight(p.inventory), capacity: capacityOf(p)),
          note: 'Mismas calles otra historia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 16, 0),
                child: LineTabs(labels: const ['Objetos', 'Taller'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
              ),
              const SizedBox(height: 8),
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

/// "18,5 / 65,0 KG", barra de acero y "PESO ACTUAL".
class _WeightGauge extends StatelessWidget {
  const _WeightGauge({required this.carried, required this.capacity});

  final int carried;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final ratio = capacity <= 0 ? 0.0 : (carried / capacity).clamp(0.0, 1.0);
    final full = carried >= capacity;
    final fill = full ? Sutura.danger : (ratio > 0.8 ? Sutura.caution : const Color(0xFFCFD8DE));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: kg(carried), style: TextStyle(color: full ? Sutura.danger : Sutura.textHi)),
            TextSpan(text: ' / ${kg(capacity)} KG', style: const TextStyle(color: Sutura.textMid, fontSize: 14)),
          ]),
          style: SuturaText.number.copyWith(fontSize: 19, letterSpacing: 1),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 92,
          height: 5,
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFF1E2124), border: Border.all(color: const Color(0xFF3A3E41), width: 0.6)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [fill.withValues(alpha: 0.7), fill]),
                  boxShadow: [BoxShadow(color: fill.withValues(alpha: 0.35), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text('PESO ACTUAL', style: SuturaText.label.copyWith(fontSize: 9.5, letterSpacing: 2.2, color: Sutura.textLow)),
      ],
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        CasePart.lid(
          contentHeight: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 2, color: Sutura.textMid),
                  const SizedBox(width: 8),
                  Text('EQUIPO ACTUAL', style: SuturaText.label.copyWith(fontSize: 11.5, letterSpacing: 2.8)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _GearCard(sub: 'Arma cuerpo a cuerpo', id: eq.melee, empty: 'Puños', emptyIcon: Icons.back_hand_outlined)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _GearCard(
                        sub: 'Arma secundaria',
                        id: eq.firearm,
                        empty: 'Sin arma',
                        emptyIcon: Icons.do_not_disturb_alt_outlined,
                        ammo: eq.firearm == null ? null : countOf(player.inventory, ItemId.ammo),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: _GearCard(sub: 'Protección', id: eq.armor, empty: 'Sin protección', emptyIcon: Icons.shield_outlined)),
                  ],
                ),
              ),
            ],
          ),
        ),
        CaseTray(stacks: stacks),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Sutura.textLow)),
                alignment: Alignment.center,
                child: Text('i', style: SuturaText.caption.copyWith(color: Sutura.textMid, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tocá un objeto para usarlo o equiparlo. ${stacks.length} de $caseSlots espacios.',
                  style: SuturaText.bodyMid.copyWith(letterSpacing: 0.6, color: Sutura.textMid, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GearCard extends StatelessWidget {
  const _GearCard({required this.sub, required this.id, required this.empty, required this.emptyIcon, this.ammo});

  final String sub;
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF17191B), Color(0xFF0E0F10)]),
          border: Border.all(color: const Color(0x38FFFFFF), width: 0.8),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('— ${sub.toUpperCase()}', maxLines: 1, style: SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 1.4, color: Sutura.textLow)),
              ),
              Expanded(
                child: Center(
                  child: i == null ? Icon(emptyIcon, size: 30, color: Sutura.textLow) : ItemArt(i, size: 96, fallbackIcon: itemIcon(i)),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        (i == null ? empty : itemName(i)).toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: Sutura.fUi,
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                          letterSpacing: 1.2,
                          color: i == null ? Sutura.textLow : Sutura.textHi,
                        ),
                      ),
                    ),
                  ),
                  if (split != null) ...[
                    const SizedBox(width: 4),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: split.loaded.toString().padLeft(2, '0'), style: TextStyle(color: split.loaded == 0 ? Sutura.danger : Sutura.textHi)),
                        TextSpan(text: ' / ${split.reserve.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 11, color: Sutura.textMid)),
                      ]),
                      style: SuturaText.number.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parte de la valija (tapa o base) dibujada como nine-patch: el centro de
/// la foto se estira para que entre el contenido y el marco de metal queda
/// intacto. [frameScale] achica el marco respecto del ancho de pantalla.
class CasePart extends StatelessWidget {
  const CasePart({
    super.key,
    required this.asset,
    required this.imageSize,
    required this.slice,
    required this.inset,
    required this.contentHeight,
    required this.child,
    this.frameScale = 0.8,
    this.bleed = 10,
  });

  /// Tapa: equipo actual.
  const CasePart.lid({super.key, required this.contentHeight, required this.child})
      : asset = 'assets/art/bg/case_lid.webp',
        imageSize = const Size(976, 598),
        slice = const Rect.fromLTRB(160, 170, 816, 470),
        inset = const EdgeInsets.fromLTRB(54, 118, 52, 34),
        frameScale = 0.8,
        bleed = 10;

  final String asset;

  /// Tamaño de la imagen en px.
  final Size imageSize;

  /// Zona que se estira (px de la imagen).
  final Rect slice;

  /// Margen del contenido respecto del borde de la imagen (px).
  final EdgeInsets inset;
  final double contentHeight;
  final double frameScale;

  /// Cuánto se sale la valija por cada costado de la pantalla (puntos).
  final double bleed;
  final Widget child;

  /// Px de imagen por punto lógico para un ancho de pantalla [w].
  static double scaleFor(Size imageSize, double w, double frameScale, double bleed) => imageSize.width / ((w + 2 * bleed) * frameScale);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final s = scaleFor(imageSize, w, frameScale, bleed);
        final pad = EdgeInsets.fromLTRB(inset.left / s - bleed, inset.top / s, inset.right / s - bleed, inset.bottom / s);
        final h = math.max(imageSize.height / s, contentHeight + pad.vertical);
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -bleed,
                right: -bleed,
                top: 0,
                bottom: 0,
                child: Image.asset(
                  asset,
                  scale: s,
                  centerSlice: Rect.fromLTRB(slice.left / s, slice.top / s, slice.right / s, slice.bottom / s),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF15171A)),
                ),
              ),
              Positioned(left: pad.left, top: pad.top, right: pad.right, bottom: pad.bottom, child: child),
            ],
          ),
        );
      },
    );
  }
}

/// La base de la valija con el inventario en compartimentos sobre el fieltro.
class CaseTray extends StatelessWidget {
  const CaseTray({super.key, required this.stacks, this.columns = 4, this.minRows = 3});

  final List<MapEntry<ItemId, int>> stacks;
  final int columns;
  final int minRows;

  static const _imageSize = Size(976, 944);
  static const _slice = Rect.fromLTRB(166, 250, 810, 560);
  static const _inset = EdgeInsets.fromLTRB(96, 140, 84, 304);
  static const _frameScale = 0.8;
  static const _gap = 5.0;
  static const _bleed = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final s = CasePart.scaleFor(_imageSize, w, _frameScale, _bleed);
        final cellW = (w + 2 * _bleed - (_inset.left + _inset.right) / s - _gap * (columns - 1)) / columns;
        final cellH = cellW * 1.02;
        final rows = math.max(minRows, (stacks.length / columns).ceil());
        final gridH = rows * cellH + (rows - 1) * _gap;
        return CasePart(
          asset: 'assets/art/bg/case_tray.webp',
          imageSize: _imageSize,
          slice: _slice,
          inset: _inset,
          frameScale: _frameScale,
          bleed: _bleed,
          contentHeight: gridH,
          child: Column(
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: _gap),
                SizedBox(
                  height: cellH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var k = 0; k < columns; k++) ...[
                        if (k > 0) const SizedBox(width: _gap),
                        Expanded(
                          child: r * columns + k < stacks.length
                              ? _SlotTile(id: stacks[r * columns + k].key, count: stacks[r * columns + k].value)
                              : const _EmptySlot(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Compartimento hundido en la espuma de la valija.
const _slotDecoration = BoxDecoration(
  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B0C0D), Color(0xFF151719)]),
  border: Border(
    top: BorderSide(color: Color(0xFF050606), width: 1.2),
    left: BorderSide(color: Color(0xFF070809), width: 1),
    right: BorderSide(color: Color(0x2EFFFFFF), width: 0.8),
    bottom: BorderSide(color: Color(0x33FFFFFF), width: 0.8),
  ),
);

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.id, required this.count});

  final ItemId id;
  final int count;

  @override
  Widget build(BuildContext context) {
    final rare = itemDefs[id]!.rarity.index >= Rarity.rare.index;
    return GestureDetector(
      onTap: () => showItemSheet(context, id),
      child: DecoratedBox(
        decoration: _slotDecoration,
        position: DecorationPosition.background,
        child: Stack(
          children: [
            if (rare) Positioned(left: 0, top: 0, child: Container(width: 10, height: 2, color: itemColor(id))),
            Positioned.fill(
              bottom: 12,
              child: Padding(padding: const EdgeInsets.fromLTRB(3, 4, 3, 0), child: Center(child: ItemArt(id, size: 96, fallbackIcon: itemIcon(id)))),
            ),
            Positioned(
              left: 5,
              right: 4,
              bottom: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      itemName(id).toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: Sutura.fUi,
                        fontWeight: FontWeight.w500,
                        fontSize: 9.5,
                        height: 1.05,
                        letterSpacing: 0.9,
                        color: Sutura.textHi,
                        shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                      ),
                    ),
                  ),
                  Text(
                    'x$count',
                    style: const TextStyle(
                      fontFamily: Sutura.fUi,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1,
                      color: Sutura.textHi,
                      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
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

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: _slotDecoration,
      child: Center(child: Icon(Icons.add, size: 18, color: Color(0xFF3C4043))),
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
