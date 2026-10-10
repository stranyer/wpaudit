import { useMemo, useState } from 'react';
import { Lock, Shield, Crosshair, HandFist } from 'lucide-react';
import { checkRecipe, RECIPES, recipeName } from '../../core/crafting';
import { carriedWeight, countOf, entries } from '../../core/inventory';
import { ITEMS, RARITY_LABEL, RARITY_ORDER } from '../../core/items';
import { capacityOf, slotFor } from '../../core/player';
import { SHELTER_LEVELS } from '../../core/shelter';
import type { EquipmentSlot, ItemDef, ItemId } from '../../core/types';
import { consumeFromInventory, craftRecipe, equip, unequip, workshopLevel } from '../../game/actions';
import { useGameStore } from '../../store/gameStore';
import { useWorldStore } from '../../store/worldStore';
import { ItemIcon } from '../components/ItemIcon';
import { StatBar } from '../components/StatBar';

type Tab = 'resources' | 'consumables' | 'gear' | 'craft';

const TABS: { id: Tab; label: string }[] = [
  { id: 'resources', label: 'Recursos' },
  { id: 'consumables', label: 'Consumibles' },
  { id: 'gear', label: 'Equipo' },
  { id: 'craft', label: 'Fabricar' },
];

const SLOT_LABEL: Record<EquipmentSlot, string> = { melee: 'Cuerpo a cuerpo', firearm: 'Arma de fuego', armor: 'Protección' };
const SLOT_ICON = { melee: HandFist, firearm: Crosshair, armor: Shield };

function inTab(def: ItemDef, tab: Tab): boolean {
  if (tab === 'resources') return def.category === 'resource';
  if (tab === 'consumables') return def.effects !== undefined;
  if (tab === 'gear') return def.category === 'weapon' || def.category === 'armor';
  return false;
}

function statLines(def: ItemDef): string[] {
  const out: string[] = [];
  if (def.effects?.health) out.push(`+${def.effects.health} salud`);
  if (def.effects?.stamina) out.push(`+${def.effects.stamina} resistencia`);
  if (def.weapon) {
    out.push(`Daño ${def.weapon.damage[0]}–${def.weapon.damage[1]}`);
    out.push(`Precisión ${Math.round(def.weapon.accuracy * 100)}%`);
    out.push(`Crítico ${Math.round(def.weapon.critChance * 100)}%`);
    if (def.weapon.ammoPerShot > 0) out.push(`Usa ${def.weapon.ammoPerShot} munición`);
  }
  if (def.armor) out.push(`Defensa +${def.armor.defense}`);
  return out;
}

export function InventoryScreen() {
  const player = useGameStore((s) => s.player);
  // Re-render cuando cambia el refugio propio (habilita recetas).
  useWorldStore((s) => s.shelters);
  const [tab, setTab] = useState<Tab>('resources');
  const [selected, setSelected] = useState<ItemId | null>(null);

  const items = useMemo(() => {
    if (!player) return [];
    return entries(player.inventory)
      .filter(([id]) => inTab(ITEMS[id], tab))
      .sort((a, b) => RARITY_ORDER.indexOf(ITEMS[a[0]].rarity) - RARITY_ORDER.indexOf(ITEMS[b[0]].rarity));
  }, [player, tab]);

  if (!player) return null;
  const weight = carriedWeight(player.inventory);
  const capacity = capacityOf(player);
  const equipped = new Set(Object.values(player.equipment).filter(Boolean));
  const sel = selected && countOf(player.inventory, selected) > 0 ? ITEMS[selected] : null;
  const workshop = workshopLevel();

  return (
    <div className="screen">
      <div className="screen-header">
        <h1 className="screen-title">
          Mochila
          <small>
            Carga {weight}/{capacity}
          </small>
        </h1>
        <div style={{ width: 120 }}>
          <StatBar value={weight} max={capacity} kind="progress" />
        </div>
      </div>

      <div className="tabs">
        {TABS.map((t) => (
          <button key={t.id} className={`tab ${tab === t.id ? 'active' : ''}`} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'gear' && (
        <div className="panel" style={{ marginBottom: 12 }}>
          <h3 className="panel-title">Equipado</h3>
          <div className="list">
            {(Object.keys(SLOT_LABEL) as EquipmentSlot[]).map((slot) => {
              const id = player.equipment[slot];
              const Icon = SLOT_ICON[slot];
              return (
                <div key={slot} className={`list-row ${id ? `rarity-${ITEMS[id].rarity}` : ''}`}>
                  {id ? <ItemIcon id={id} size={26} className="rarity-text" /> : <Icon size={24} color="var(--muted)" />}
                  <div className="list-main">
                    <div className="list-title">{id ? ITEMS[id].name : slot === 'melee' ? 'Puños' : 'Vacío'}</div>
                    <div className="list-sub">{SLOT_LABEL[slot]}</div>
                  </div>
                  {id && (
                    <button className="btn btn-sm btn-ghost" onClick={() => unequip(slot)}>
                      Quitar
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {tab !== 'craft' && (
        <>
          {items.length === 0 ? (
            <div className="empty-state">
              {tab === 'gear'
                ? 'Todavía no encontraste equipo. Revisá ferreterías y cajas militares, o fabricá un bate con clavos.'
                : 'Nada por acá. Salí a explorar y saqueá suministros.'}
            </div>
          ) : (
            <div className="item-grid">
              {items.map(([id, n]) => {
                const def = ITEMS[id];
                return (
                  <button
                    key={id}
                    className={`item-card rarity-${def.rarity} ${selected === id ? 'selected' : ''}`}
                    onClick={() => setSelected(selected === id ? null : id)}
                  >
                    {equipped.has(id) && <span className="equipped-tag">EQUIPADO</span>}
                    {def.weight > 0 && <span className="item-count">{n}</span>}
                    <ItemIcon id={id} size={34} className="item-icon" />
                    <span className="item-name">{def.name}</span>
                  </button>
                );
              })}
            </div>
          )}

          {sel && (
            <div className={`panel rarity-${sel.rarity}`} style={{ marginTop: 12 }}>
              <div className="sheet-head">
                <div className="sheet-icon">
                  <ItemIcon id={sel.id} size={30} />
                </div>
                <div>
                  <h3 className="sheet-title">{sel.name}</h3>
                  <span className="label rarity-text">{RARITY_LABEL[sel.rarity]}</span>
                </div>
              </div>
              <p className="sheet-desc">{sel.description}</p>
              <div className="cost-chips" style={{ marginBottom: 12 }}>
                {statLines(sel).map((l) => (
                  <span key={l} className="chip">
                    {l}
                  </span>
                ))}
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                {sel.effects && (
                  <button className="btn btn-primary" style={{ flex: 1 }} onClick={() => consumeFromInventory(sel.id)}>
                    Usar
                  </button>
                )}
                {slotFor(sel.id) &&
                  (equipped.has(sel.id) ? (
                    <button className="btn" style={{ flex: 1 }} onClick={() => unequip(slotFor(sel.id)!)}>
                      Quitar
                    </button>
                  ) : (
                    <button className="btn btn-green" style={{ flex: 1 }} onClick={() => equip(sel.id)}>
                      Equipar
                    </button>
                  ))}
              </div>
            </div>
          )}
        </>
      )}

      {tab === 'craft' && (
        <>
          <p className="dim" style={{ marginTop: 0, fontSize: 13 }}>
            Taller disponible: {workshop > 0 ? `refugio nivel ${workshop}` : 'ninguno (creá tu refugio para desbloquear más recetas)'}
          </p>
          <div className="list">
            {RECIPES.map((r) => {
              const check = checkRecipe(player.inventory, r, workshop);
              const out = ITEMS[r.output];
              return (
                <div key={r.id} className={`panel rarity-${out.rarity}`} style={{ padding: 12, margin: 0 }}>
                  <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                    <div className="sheet-icon" style={{ width: 46, height: 46 }}>
                      <ItemIcon id={r.output} size={26} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="list-title">{recipeName(r)}</div>
                      <div className="cost-chips" style={{ marginTop: 6 }}>
                        {entries(r.inputs).map(([id, n]) => {
                          const have = countOf(player.inventory, id);
                          return (
                            <span key={id} className={`chip ${have >= n ? 'ok' : 'bad'}`}>
                              <ItemIcon id={id} size={13} /> {have}/{n}
                            </span>
                          );
                        })}
                      </div>
                    </div>
                    <button className="btn btn-primary btn-sm" disabled={!check.ok} onClick={() => craftRecipe(r.id)}>
                      {check.block === 'shelter_level' ? <Lock size={14} /> : 'Fabricar'}
                    </button>
                  </div>
                  {check.block === 'shelter_level' && (
                    <div className="label" style={{ marginTop: 8, color: 'var(--orange)' }}>
                      Requiere refugio nivel {r.requiresShelterLevel} · {SHELTER_LEVELS[r.requiresShelterLevel - 1].name}
                    </div>
                  )}
                  {check.block === 'already_owned' && (
                    <div className="label" style={{ marginTop: 8 }}>
                      Ya lo tenés
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
