pfUI performance updates, use on own risk.

## DLL Integrations

pfUI includes optional integration modules for client DLLs that provide enhanced functionality beyond what the standard WoW 1.12 client supports. These features are only enabled when the corresponding DLL is installed.

---

### SuperWoW

**Repository:** https://github.com/balakethelock/SuperWoW

SuperWoW provides GUID-based unit tracking, spell information APIs, and various client enhancements.

#### Features

- **GUID-Based Focus Frame** - Focus frame uses actual unit GUIDs instead of name-based emulation
- **Native Mouseover Casting** - `/pfcast` supports true mouseover targeting via `CastSpellByName(spell, unit)`
- **Druid Mana Bar** - Shows mana while in feral forms (requires `unitframes.druidmanabar` config)
- **Enhanced Cast Bars** - Uses `UNIT_CASTEVENT` for accurate cast/channel tracking with spell IDs
- **Enhanced Debuff Tracking** - Accurate debuff application via `UNIT_CASTEVENT` with caster info
- **Group Minimap Tracking** - Track party/raid members on minimap via `TrackUnit()` API
- **Raid Marker Targeting** - Target units by raid marker (`mark1` to `mark8`)
- **Clickthrough Mode** - Click through corpses to loot underneath (`/clickthrough` or `/ct`)
- **Config Import/Export** - Save and load pfUI configs via `/pfexport` and `/pfimport`
- **Local Raid Markers** - Set raid markers visible only to yourself
- **Enchanting Link Fixes** - Converts enchant links for compatibility with non-SuperWoW clients

#### API Functions

| Function | Description |
|----------|-------------|
| `pfUI.api.GetMarkedUnit(index)` | Get unit ID for raid marker 1-8 |
| `pfUI.api.TargetMark(index)` | Target unit with raid marker |
| `pfUI.api.GetUnitOwner(unit)` | Get owner of pet/totem |
| `pfUI.api.GetSpellInfo(spellId)` | Get spell name, rank, texture, range |
| `pfUI.api.SetClickthrough(enabled)` | Enable/disable clickthrough |
| `pfUI.api.ToggleClickthrough()` | Toggle clickthrough mode |
| `pfUI.api.SetAutoloot(enabled)` | Enable/disable autoloot |
| `pfUI.api.ExportConfig(filename)` | Export config to file |
| `pfUI.api.ImportConfig(filename)` | Import config from file |
| `pfUI.api.GetPlayerBuffSpellId(index)` | Get spell ID for player buff |
| `pfUI.api.LogToCombatLog(text)` | Add text to combat log |
| `pfUI.api.SetLocalRaidTarget(unit, index)` | Set local-only raid marker |
| `pfUI.api.GetItemCharges(bag, slot)` | Get item charges (returns positive) |
| `pfUI.api.GetUnitWeaponEnchants(unit)` | Get weapon enchant info |

---

### Nampower

**Repository:** https://gitea.com/avitasia/nampower

Nampower provides spell queuing, precise cooldown tracking, and detailed aura/buff information.

#### Features

- **Spell Queue Indicator** - Shows queued spell icon near castbar (requires `unitframes.spellqueue` config)
- **Enhanced Cast Bar** - More accurate cast progress via `GetCastInfo()` (requires `unitframes.nampower_castbar`)
- **Reactive Spell Indicator** - Highlights when Overpower, Revenge, Execute, Riposte, etc. are usable (requires `unitframes.reactive_indicator`)
- **Enhanced Debuff Tracking** - GUID-based debuff tracking via `DEBUFF_ADDED/REMOVED` events
- **Enhanced Buff Tracking** - GUID-based buff tracking via `BUFF_ADDED/REMOVED` events (requires `unitframes.nampower_buffs`)
- **Swing Timer** - Track main-hand and off-hand auto-attack timers
- **Disenchant All** - `/disenchantall` or `/dea` to disenchant eligible items

#### API Functions

| Function | Description |
|----------|-------------|
| `pfUI.api.GetUnitAuras(unit)` | Get all buffs/debuffs with spell IDs via `GetUnitField` |
| `pfUI.api.UnitHasAura(unit, spellId)` | Check if unit has specific aura |
| `pfUI.api.GetUnitResistances(unit)` | Get unit's resistances (armor, fire, frost, etc.) |
| `pfUI.api.GetPreciseCooldown(spellId)` | Get precise cooldown info (remaining ms, GCD state) |
| `pfUI.api.GetPreciseItemCooldown(itemId)` | Get precise item cooldown |
| `pfUI.api.GetEquippedTrinkets()` | Get equipped trinket info |
| `pfUI.api.GetTrinketCooldown(slot)` | Get trinket cooldown |
| `pfUI.api.UseTrinket(slot, target)` | Use trinket |
| `pfUI.api.GetNampowerItemStats(itemId)` | Get item stats |
| `pfUI.api.GetNampowerItemLevel(itemId)` | Get item level |
| `pfUI.api.GetSpellBonus(spellId, modType)` | Get spell modifiers (damage, crit, cost) |
| `pfUI.api.GetSpellDamageBonus(spellId)` | Get spell damage bonus |
| `pfUI.api.GetSpellCritBonus(spellId)` | Get spell crit bonus |
| `pfUI.api.GetSpellCostReduction(spellId)` | Get spell cost reduction |
| `pfUI.api.GetAllBagItems()` | Get all bag items |
| `pfUI.api.FindItem(itemIdOrName)` | Find item in bags |
| `pfUI.api.UseItem(itemIdOrName, target)` | Use item |
| `pfUI.api.GetPlayerEquipment()` | Get player's equipped items |
| `pfUI.api.GetTargetEquipment()` | Get target's equipped items |
| `pfUI.api.GetMaxRankSpellId(spellName)` | Get spell ID for max rank |
| `pfUI.api.GetSpellSlotInfo(spellName)` | Get spell slot/book info |
| `pfUI.api.QueueLuaScript(script, priority)` | Queue Lua script for execution |
| `pfUI.api.QueueSpell(spellName)` | Queue spell by name |
| `pfUI.api.StopChannelNextTick()` | Stop channeling next tick |
| `pfUI.api.GetSpellRecord(spellId)` | Get full spell database record |
| `pfUI.api.GetSpellSchool(spellId)` | Get spell school (Fire, Frost, etc.) |
| `pfUI.api.GetCurrentCast()` | Get current cast info |
| `pfUI.api.GetDetailedCastInfo()` | Get detailed cast/GCD timing |
| `pfUI.api.GetSwingTimers()` | Get auto-attack swing timers |
| `pfUI.api.libdebuff_nampower(unit, id)` | Enhanced UnitDebuff with Nampower data |

---

### UnitXP_SP3

**Repository:** https://github.com/allfoxwy/UnitXP_SP3

UnitXP provides line-of-sight checks, positional information, precise distances, and OS-level notifications.

#### Features

- **Line of Sight Indicator** - Shows "NO LOS" text on target frame when target is obstructed (requires `unitframes.los_indicator`)
- **Behind Indicator** - Shows "BEHIND" text on target frame when positioned behind target (requires `unitframes.behind_indicator`)
- **OS Notifications** - Flashes taskbar and plays system sound on whispers, ready checks, BG queue pops (requires `unitframes.unitxp_notify`)
- **Precise Distance** - Exact yard distance between units
- **Smart Targeting** - Target nearest enemy, highest HP, cycle through enemies

#### API Functions

| Function | Description |
|----------|-------------|
| `pfUI.api.GetPreciseDistance(unit1, unit2)` | Get exact distance in yards |
| `pfUI.api.IsInMeleeRange(unit)` | Check if unit is in melee range |
| `pfUI.api.GetAoEDistance(unit1, unit2)` | Get distance for AoE calculations |
| `pfUI.api.TargetNearestEnemy()` | Target nearest hostile unit |
| `pfUI.api.TargetHighestHP()` | Target enemy with most HP |
| `pfUI.api.TargetNextEnemy()` | Cycle to next enemy |
| `pfUI.api.TargetPreviousEnemy()` | Cycle to previous enemy |
| `pfUI.api.TargetNextMarked(order)` | Target next marked enemy in order |
| `pfUI.api.UnitInLineOfSight(unit1, unit2)` | Check line of sight between units |
| `pfUI.api.UnitIsBehind(unit1, unit2)` | Check if unit1 is behind unit2 |

---

### Configuration Options

These DLL features can be enabled/disabled via `/pfui` settings under Unit Frames:

| Setting | DLL | Description |
|---------|-----|-------------|
| `unitframes.druidmanabar` | SuperWoW | Show mana bar while shapeshifted |
| `unitframes.track_group` | SuperWoW | Track group members on minimap |
| `unitframes.spellqueue` | Nampower | Show spell queue indicator |
| `unitframes.spellqueuesize` | Nampower | Spell queue icon size |
| `unitframes.nampower_castbar` | Nampower | Use precise cast bar timing |
| `unitframes.reactive_indicator` | Nampower | Show reactive ability procs |
| `unitframes.reactive_size` | Nampower | Reactive indicator icon size |
| `unitframes.nampower_buffs` | Nampower | Enhanced buff tracking |
| `unitframes.los_indicator` | UnitXP | Show line of sight indicator |
| `unitframes.behind_indicator` | UnitXP | Show behind indicator |
| `unitframes.unitxp_notify` | UnitXP | Enable OS notifications |
