# pfUI - Turtle WoW Edition

[![Version](https://img.shields.io/badge/version-8.0.0-blue.svg)](https://github.com/me0wg4ming/pfUI)
[![Turtle WoW](https://img.shields.io/badge/Turtle%20WoW-1.18.0-brightgreen.svg)](https://turtlecraft.gg/)
[![SuperWoW](https://img.shields.io/badge/SuperWoW-Optional-yellow.svg)](https://github.com/balakethelock/SuperWoW)
[![Nampower](https://img.shields.io/badge/Nampower-Required-purple.svg)](https://gitea.com/avitasia/nampower)
[![UnitXP](https://img.shields.io/badge/UnitXP__SP3-Optional-yellow.svg)](https://codeberg.org/konaka/UnitXP_SP3)

**A pfUI fork specifically optimized for [Turtle WoW](https://turtlecraft.gg/) which requires SuperWoW and Nampower with optional UnitXP_SP3 DLL integration.**

This version includes significant performance improvements, DLL-enhanced features, and TBC spell indicators that work with Turtle WoW's expanded spell library.

> **Looking for TBC support?** Visit the original pfUI by Shagu: [https://github.com/shagu/pfUI](https://github.com/shagu/pfUI)

---

🎯 What's New in Version 8.1.0
🗡️ Swing Timer Bug Fixes (swingtimer.lua)

Extra attack detection — Sword Specialization, Windfury, Hand of Justice and other extra attacks no longer double the swing timer. Added fallback detection for servers that don't set HITINFO_NOACTION correctly: if AUTO_ATTACK_SELF fires while more than 20% of the current swing remains, it's treated as an extra attack and ignored
Parry reset — Now uses correct Vanilla mechanic: resets timer to exactly 60% of weapon speed instead of incorrectly subtracting 40% from remaining time
Slam — Now hard-resets the swing timer from now instead of chaining from the previous nextSwing, which caused inflated swing times (e.g. 3.76s showing as 4.3s)

📏 UnitXP Distance Display (unitxp.lua)
Two new options under Unit Frames → General → UnitXP Settings:

Show Distance of Target — Displays live distance to target with color-coded thresholds (blue = melee, green = mid range, yellow = 35–41y, red = out of range)
Hook Distance to Portrait Frame — When enabled, shows the distance text directly on the target frame alongside the existing Behind and LOS indicators, proportionally spaced based on frame height. When disabled, shows as a free-floating movable frame

🎯 Precise Range Check via UnitXP (api.lua, librange.lua, gui.lua, config.lua)
New options under Unit Frames → General → Group Options:

Range Check Mode dropdown — Vanilla (Spellbook) keeps existing behavior; UnitXP (Precise) bypasses librange entirely and queries UnitXP("distanceBetween") directly
UnitXP Range Threshold (yards) — Configurable yard value for the UnitXP mode (default: 40). Works for all classes, no spellbook scan required
When UnitXP mode is active, the librange scan loop is fully disabled — no TargetUnit cycling, no combat interruption, no class restriction
Fixed UnitInRange referencing librange as an undefined local instead of pfUI.api.librange

🔧 Share Module Fix (share.lua)

Fixed import failures for configs containing double quotes (e.g. clickcast macros with CastSpellByName("Nature's Swiftness")). The serialize() function now correctly escapes " in addition to \

---

## 🎯 What's New in Version 8.0.0

* **Nampower 3.0.0+ now required** — minimum version bumped from 2.41.0
* **SuperWoW dependency fully removed** — all SuperWoW-specific code paths eliminated:
  * `UNIT_CASTEVENT` replaced with `SPELL_GO_SELF` hook for Druid Prowl detection
  * `UnitCastingInfo`/`UnitChannelInfo` SuperWoW fallbacks removed from libcast
  * `SpellInfo()` (SuperWoW) replaced with `GetSpellRecField()` (Nampower) throughout
  * `SPELL_HEAL_BY_SELF` CVar (`NP_EnableSpellHealEvents`) now auto-enabled by libdebuff
* **`GetUnitGUID()` migration** — replaced all `local _, guid = UnitExists(unit)` with `GetUnitGUID(unit)` across 11 files (Nampower 3.0.0 API)
* **Player castbar icon fix** — icons for custom Turtle WoW spells (e.g. Swift Travel Form) now correctly resolved via `GetSpellRecField`/`GetSpellIconTexture` instead of falling back to the previous spell's icon
* **Castbar timer rounding** — 1-decimal mode now rounds correctly to match the Blizzard spellbook display (e.g. 2798ms → 2.8s instead of 2.7s)
* **Nampower warning popup** — updated to be more prominent (`!!!WARNING!!!` in red, non-dismissable via Escape, uses pfUI URL copy frame for download link)

---

## 🎯 What's New in Version 7.8.0

### 🔗 libdebuff External Hook System (libs/libdebuff.lua)

Full event hook system exposed on `pfUI` global.
This is for external addons from other creators that want to register callbacks for all events processed by libdebuff without registering duplicate event listeners.
(always make sure to do this as an optional variant if you want your addon to still work without libdebuff from pfui)

**Usage:**
```lua
-- Register a hook (key = your addon name, value = callback function)
pfUI.libdebuff_spell_go_other_hooks["myaddon"] = function(spellId, casterGuid, targetGuid)
  -- fired when any other unit completes a spell cast
end

-- Unregister
pfUI.libdebuff_spell_go_other_hooks["myaddon"] = nil
```

**Available Hooks:**

| Hook Table | Callback Signature | Fired When |
|---|---|---|
| `pfUI.libdebuff_spell_go_hooks` | `fn(spellId, arg1..arg7)` | `SPELL_GO_SELF` processed (your own casts) |
| `pfUI.libdebuff_spell_go_other_hooks` | `fn(spellId, casterGuid, targetGuid)` | `SPELL_GO_OTHER` processed |
| `pfUI.libdebuff_spell_start_self_hooks` | `fn(spellId, casterGuid, targetGuid, castTime)` | `SPELL_START_SELF` processed |
| `pfUI.libdebuff_spell_start_other_hooks` | `fn(spellId, casterGuid, targetGuid, castTime)` | `SPELL_START_OTHER` processed |
| `pfUI.libdebuff_spell_failed_other_hooks` | `fn(casterGuid, spellId)` | `SPELL_FAILED_OTHER` processed |
| `pfUI.libdebuff_spell_cast_hooks` | `fn(success, spellId, castType, targetGuid)` | `SPELL_CAST_EVENT` processed (your own casts) |
| `pfUI.libdebuff_aura_cast_on_self_hooks` | `fn(spellId, casterGuid, targetGuid)` | `AURA_CAST_ON_SELF` processed |
| `pfUI.libdebuff_aura_cast_on_other_hooks` | `fn(spellId, casterGuid, targetGuid)` | `AURA_CAST_ON_OTHER` processed |
| `pfUI.libdebuff_debuff_added_other_hooks` | `fn(guid, luaSlot, spellId, stackCount)` | `DEBUFF_ADDED_OTHER` processed |
| `pfUI.libdebuff_debuff_removed_other_hooks` | `fn(guid, luaSlot, spellId, stackCount)` | `DEBUFF_REMOVED_OTHER` processed |
| `pfUI.libdebuff_unit_health_hooks` | `fn(unitToken)` | `UNIT_HEALTH` processed |
| `pfUI.libdebuff_unit_died_hooks` | `fn(guid)` | `UNIT_DIED` processed (real death only, not Feign Death) |
| `pfUI.libdebuff_player_target_changed_hooks` | `fn()` | `PLAYER_TARGET_CHANGED` processed |

### 📖 libdebuff Public API (pfUI.api.libdebuff)

For direct data access, `pfUI.api.libdebuff` exposes the following methods:

```lua
local libdebuff = pfUI.api.libdebuff

-- Get debuff info for a unit by display slot (equivalent to UnitDebuff)
-- Returns: texture, stacks, debuffType, duration, timeleft, caster, spellId
libdebuff:UnitDebuff(unit, displaySlot)

-- Check if you have a specific debuff on a unit (by name or spellId)
-- Returns: texture, stacks, debuffType, duration, timeleft, spellId
libdebuff:UnitOwnDebuff(unit, id)

-- Get the best/most recent aura cast info for a spell on a target
-- Returns: { casterGuid, rank, time }
libdebuff:GetBestAuraCast(guid, spellName)

-- Get all enhanced debuff data for a target GUID (Nampower path)
-- Returns table of active debuffs with full metadata
libdebuff:GetEnhancedDebuffs(targetGUID)

-- Get the spell icon texture for a spellId
-- Returns: texture path string or nil
libdebuff:GetSpellIcon(spellId)

-- Get duration info for a debuff effect
-- Returns: duration in seconds
libdebuff:GetDuration(effect, rank)

-- Get the maximum known rank for a debuff effect
-- Returns: rank number
libdebuff:GetMaxRank(effect)
```

---

## 🎯 What's New in Version 7.7.0 (February 25, 2026)

🗡️ Swingtimer Overhaul (swingtimer.lua)
Complete rewrite of HS/Cleave detection and StartSwing timing for accurate warrior swing tracking:
Previously, Heroic Strike and Cleave were detected via SPELL_GO_SELF by matching against a hardcoded spell ID list. The timer calculation used now + speed which caused visible jumps when HS consumed the swing.
HS/Cleave Detection via SPELL_GO_SELF hook:

✅ HS/Cleave now detected via pfUI.libdebuff_spell_go_hooks["swingtimer"] — reuses libdebuff's existing SPELL_GO_SELF event instead of registering a duplicate event handler
✅ cachedHSSlots / cachedCleaveSlots — actionbar slots pre-scanned on UNIT_INVENTORY_CHANGED and ACTIONBAR_SLOT_CHANGED, no per-swing scanning
✅ IsHSOrCleaveQueued() — lightweight check via CheckQueuedAction() on cached slots

StartSwing timing fix:

✅ nextSwing = previousNextSwing + speed instead of now + speed — timer continues from the previous swing boundary, preventing jumps when HS/normal swing alternates
✅ 100ms dual-wield guard — detects missing isOffhand flag by checking MH swing age, prevents MH swings being misclassified as OH

Ranged swing (Auto Shot / Throw):

✅ Triggered via SPELL_GO_SELF hook (same hook as HS/Cleave) — no separate event registration
✅ Ranged swing cancels MH bar display while active


🛡️ Raid Performance: Buff Cache Seeding (api/unitframes.lua)
Eliminated tooltip scans for all known buffs on cold cache:
Previously, DetectBuff checked pfUI_cache.buff_icons for known buff icons. On a cold cache (raid join, reload), every unknown icon triggered a scanner:SetUnitBuff + scanner:Line(1) tooltip scan. With 40 raid frames × 32 buff slots = up to 1280 scans per UNIT_AURA event.
The Fix:

✅ buff_icons_seeded flag — runs once per login
✅ On first DetectBuff call, all entries from L["icons"] are pre-loaded into pfUI_cache.buff_icons (icon path → spell name)
✅ All known buffs (Fort, MotW, Shadow Protection, Mark, etc.) hit the cache immediately — scanner never triggered for them
✅ Fixed broken cache check: removed L["icons"][detect_name] condition (detect_name was always nil at that point)


🏷️ RaidMarkers → MarkTracking Module Rename (modules/marktracking.lua)
Module renamed and extended with color configuration:

✅ Module renamed from raidmarkers to marktracking for clarity
✅ Per-marker color configuration — each of the 8 raid markers has individually configurable RGBA color
✅ Default colors per marker type (skull=red, cross=blue, square=blue, moon=silver, etc.)
✅ ParseColor() helper for robust color string parsing


🐛 Bug Fixes
Castbar: Channel spell name missing after queued cast (castbar.lua)

✅ Fixed UnitChannelInfo being called with player name string instead of "player" unitstring
✅ When a channel spell (Arcane Missiles, Icicles) was queued after a normal cast, the castbar showed only "Channeling" without spell name or icon
✅ UnitChannelInfo now always receives this.unitstr — full spell info returned correctly

Map Reveal: Memory leak and Error 132 crash fix (modules/mapreveal.lua)

✅ explorecaches cleared at the start of every pfWorldMapFrame_Update call
✅ Previously, texture references accumulated indefinitely — WoW internally recycles textures, causing stale pointers → ACCESS_VIOLATION (Error 132)
✅ alreadyknown table reused as upvalue instead of allocating a new table every update — reduces GC pressure

---

## 🎯 What's New in Version 7.6.2 (February 6, 2026)

### 🚀 Pure GetUnitField Debuff System (libdebuff.lua)

**Major performance rewrite: UnitDebuff() now runs entirely through Nampower's GetUnitField — zero Blizzard API calls, zero tooltip scans.**

Previously, every debuff icon required three expensive calls per update:
1. `UnitDebuff(unit, slot)` — Blizzard C-side API call
2. `scanner:SetUnitDebuff(unit, slot)` — Tooltip object creation + GameTooltip parse
3. `scanner:Line(1)` — String extraction from tooltip

All three are now replaced by pure Lua table lookups into cached GetUnitField data:

| Data | Old (Blizzard API) | New (GetUnitField) |
|------|-------------------|-------------------|
| Spell Name | Tooltip scan | `SpellInfo(spellId)` |
| Texture | `UnitDebuff()` ret.1 | `GetSpellIconTexture(GetSpellRecField(spellId, "spellIconID"))` |
| Stacks | `UnitDebuff()` ret.2 | `GetUnitField(guid, "auraApplications")[slot]` |
| DebuffType | `UnitDebuff()` ret.3 | `GetSpellRecField(spellId, "dispel")` → dispelTypeMap |
| Duration/Timeleft | ownDebuffs tracking | unchanged |
| Caster | slotOwnership tracking | unchanged |

**Performance impact:** With 5 debuffs on target = 15 expensive calls eliminated per update cycle. With 10 visible nameplates × 3 debuffs = 90 calls eliminated per refresh. Estimated **3-5x faster** per UnitDebuff call.

**DebuffType now works in Nampower path:** Previously dtype was only available from Blizzard's UnitDebuff(). Now resolved from SpellRec DBC via `GetSpellRecField(spellId, "dispel")`, meaning debuff frame border colors (Magic=blue, Curse=purple, Poison=green, Disease=brown) now work correctly for all units including nameplates.

### 🎨 Item-Cast Icon & Name Support (libdebuff.lua + castbar.lua)

**Castbar now shows the correct item icon and item name for item-triggered casts!**

Previously, using items with cast times (Gnomish Death Ray, Net-o-Matic, Noggenfogger Elixir etc.) showed the generic spell icon and spell name on the castbar. Now:

- ✅ `SPELL_START_SELF/OTHER` `arg1` (itemId) is now parsed and used
- ✅ `SPELL_GO_SELF/OTHER` `arg1` (itemId) is now parsed
- ✅ Item icon resolved via `GetItemStatsField(itemId, "displayInfoID")` → `GetItemIconTexture()`
- ✅ Item name resolved via `GetItemStatsField(itemId, "displayName")`
- ✅ `pfUI.libdebuff_item_icons` — Persistent item icon/name cache that survives SPELL_GO clearing cast data
- ✅ `castbar.lua` — Reads item icon + name from persistent cache with fallback to spell data

**Note:** Item icon/name detection only works for your own casts (WoW 1.12.1 protocol limitation — server sends `itemId=0` to other clients).

### 🔧 Icon Path Fix (libdebuff.lua)

**Fixed missing icons from Nampower texture functions.**

`GetSpellIconTexture()` and `GetItemIconTexture()` return short texture names (e.g. `INV_Gizmo_08`) without the `Interface\Icons\` prefix required by `SetTexture()`. Both `GetSpellIcon()` and the item icon lookup now auto-prefix the full path when needed.

### ⚡ Memory & GC Optimizations (libdebuff.lua)

- ✅ **Carnage frame recycling** — Persistent `carnageCheckFrame` reused instead of `CreateFrame()` per Ferocious Bite (eliminates frame leak in combat)
- ✅ **Recycled cleanup buffers** — `_cleanupBuf1`/`_cleanupBuf2` reused instead of `table.insert` + new table per `CleanupExpiredTimers` call
- ✅ **SelfOverwrite buffer recycling** — Reused buffer instead of new `oldCasters` table per overwrite
- ✅ **Pre-defined sort function** — `_ownDebuffSortFunc` defined once instead of anonymous closure per `UnitOwnDebuff` call
- ✅ **spellId stored in ownDebuffs** — Enables direct DBC lookups for dtype without slotMap iteration

### 📊 Code Statistics

**libdebuff.lua:**
- Blizzard API calls in Nampower path: 3 per debuff → 0
- New GetUnitField calls: `aura` + `auraApplications` (cached 50ms)
- New DBC lookups: `GetSpellRecField(spellId, "dispel")` for dtype
- New exports: `pfUI.libdebuff_item_icons`

**castbar.lua:**
- Item icon override via `pfUI.libdebuff_item_icons` (persistent cache)
- Item name override via `GetItemStatsField(itemId, "displayName")`
- Works for player + target + focus castbars

---

## 🎯 What's New in Version 7.6.1 (February 6, 2026)
- Added a new menu in /pfui named "Throttling" - Players who were unsatisfied with the throttling update rate can change it now for nameplates, Toolip Cursor and Chat Tab.

---

## 🎯 What's New in Version 7.6.0 (February 3, 2026)

### 🚀 Centralized Cast-Bar Tracking System (libdebuff.lua + nameplates.lua)

**Major architectural change: Cast tracking moved from nameplates to libdebuff for single source of truth!**

Previously, both `nameplates.lua` and `libdebuff.lua` independently tracked cast events, creating code duplication and maintenance overhead. Now all cast tracking is centralized in `libdebuff.lua` with nameplates consuming shared data.

**libdebuff.lua - NEW Cast Tracking:**
- ✅ `SPELL_START_SELF/OTHER` → Cast-Start Tracking
- ✅ `SPELL_GO_SELF/OTHER` → Cast-Completion Tracking  
- ✅ `SPELL_FAILED_OTHER` → Cast-Cancel Detection (movement, interrupts, OOM)
- ✅ `pfUI.libdebuff_casts` → Shared cast data structure `[casterGuid] = {spellID, spellName, icon, startTime, duration, endTime, event}`
- ✅ `pfUI.libdebuff_GetSpellIcon()` → Icon cache export function

**nameplates.lua - Simplified Cast Consumption:**
- ✅ `GetCastInfo(guid)` → Reads `pfUI.libdebuff_casts`
- ✅ `pfUI.libdebuff_GetSpellIcon` → Uses shared icon cache
- ❌ `UNIT_CASTEVENT` → **REMOVED** (replaced by Nampower SPELL_* events)
- ❌ Local cast tracking code → **REMOVED** (~56 lines saved)

**Benefits:**
- **100% Nampower, 0% SuperWOW** - No longer depends on UNIT_CASTEVENT
- **Single Source of Truth** - Cast data only tracked once
- **Icon Cache 100-400x faster** - First lookup via Nampower's GetSpellIconTexture, then cached
- **Easier Maintenance** - Changes only in one place
- **Code Reduction** - 56 lines removed from nameplates.lua

### ⚠️ Nampower Version Requirement Update (libdebuff.lua)

**Now requires Nampower 2.27.2+ (SPELL_FAILED_OTHER bug fix):**

Version 2.27.1 had a bug where `SPELL_FAILED_OTHER` didn't fire for movement-cancelled casts. This is now fixed in 2.27.2.

**User Warnings:**
- **2.27.2+**: ✅ Success message + auto-enable CVars
- **2.27.1**: ⚠️ Yellow warning + popup (cast-bar cancel broken)
- **< 2.27.1**: ❌ Red error + popup (debuff tracking disabled)
- **No Nampower**: ❌ Red error + popup (addon disabled)

**NEW StaticPopup Dialogs:**

Popups appear center-screen on login to ensure users don't miss the version requirement!

### 🌿 libpredict HoT Tracking Integration (libpredict.lua)

**Major enhancement: libdebuff integration for server-accurate HoT tracking!**

Previously, libpredict relied purely on prediction (UNIT_CASTEVENT + timing calculations). Now it uses libdebuff's AURA_CAST events for server-side accurate buff/debuff data when available.

**NEW Hybrid System:**
```
GetHotDuration(unit, spell):
  1. Try libdebuff first (Nampower AURA_CAST events)
     ↓
     if available: return server-accurate data
  
  2. Fallback to prediction (legacy system)
     ↓
     Use hots[] table with UNIT_CASTEVENT prediction
```

**Benefits:**
- ✅ **Server-accurate durations** - No prediction needed with Nampower
- ✅ **Automatic rank protection** - Built into libdebuff's system
- ✅ **Multi-caster support** - Multiple druids = multiple rejuvs tracked separately
- ✅ **Zero overhead** - libdebuff already tracks all auras
- ✅ **Backwards compatible** - Falls back to prediction without Nampower

**NEW Rank Support for HoTs:**

Extended `Hot()` function signature to include rank parameter:
```lua
function libpredict:Hot(sender, target, spell, duration, startTime, source, rank)
```

**Rank Protection Logic:**
- Don't overwrite Rank 10 HoT with Rank 8!
- Active higher-rank HoTs block lower-rank applications
- Works with multiple casters simultaneously

**HealComm Protocol Extended (Backwards Compatible):**
- OLD: `"Reju/TargetName/15/"`
- NEW: `"Reju/TargetName/15/10/"` (rank added)
- `"0"` = unknown rank (for non-rank-aware clients)

**Example Scenario:**
```
Druid A casts Rejuvenation Rank 10 (15s duration)
Druid B casts Rejuvenation Rank 8  (12s duration)

With rank protection:
→ Rank 8 is BLOCKED while Rank 10 is active!
→ No more accidental overwrites of better HoTs!
```

### 📊 Code Statistics

**libdebuff.lua:**
- Lines: 2743 → 2835 (+92 lines)
- Events: 12 → 15 (+3: SPELL_START_SELF/OTHER, SPELL_FAILED_OTHER)
- Exports: 14 → 16 (+2: pfUI.libdebuff_casts, pfUI.libdebuff_GetSpellIcon)

**nameplates.lua:**
- Lines: 1826 → 1770 (-56 lines)
- Events: 7 → 6 (-1: UNIT_CASTEVENT removed)
- Code removed: ~74 lines (UNIT_CASTEVENT handler, local cast tracking)

**libpredict.lua:**
- Lines: 935 → 1095 (+160 lines)
- New: libdebuff integration, rank support, rank protection logic
- Backwards compatible: Works with/without Nampower

---

## 🎯 What's New in Version 7.5.1 (February 02, 2026)

- Added icon cache system - Icons are now cached in pfUI.libdebuff_icon_cache for instant lookups after first access

- Replaced SpellInfo texture lookups with GetSpellIconTexture - Direct DBC queries via Nampower (~100-400x faster than tooltip parsing)

- Optimized UnitDebuff() function - Now uses GetUnitField("aura") to retrieve spell IDs directly from unit data, then fetches icons via GetSpellIconTexture instead of vanilla UnitDebuff API

- Changed fallback icons - Unknown spell icons now display QuestionMark instead of class-specific icons

- Performance impact - Icon lookups reduced from ~5-20ms to ~0.05ms (first) / ~0.001ms (cached) per debuff, resulting in 600-2600x speedup for full debuff bars

- Replaced in libdebuff.lua the UNIT_CASTEVENT of Superwow with Nampowers SPELL_GO and SPELL_START events (slowly trying to get away from superwow, not maintained anymore and outdated)

---

## 🎯 What's New in Version 7.5.0 (January 31, 2026)

### 🔧 Player Buff Bar Timer Fix (buffwatch.lua)

**Fixed buff timers resetting on Player Buff/Debuff Bars when other buffs expire:**

Previously, buff bar timers would reset or jump when other buffs expired because the UUID (unique identifier) included the slot number. Since slots shift when buffs expire, the same buff would get a new UUID, causing the timer bar to think it's a new buff.

**The Problem:**
- Old UUID: `texture + name + slot` (e.g., "PowerWordFortitude_tex_PWF_3")
- Buff in slot 3 expires → slots 4,5,6 shift down to 3,4,5
- UUID changes from `..._4` to `..._3` → timer resets!

**The Solution:**
- Player buffs now use: `texture + name` only (no slot)
- Target debuffs still use: `texture + name + slot` (needed for multi-caster scenarios)

```lua
-- For player: no slot in uuid (slots shift when other buffs expire)
-- For target: include slot (multiple players can have same debuff)
local uuid
if frame.unit == "player" then
  uuid = data[4] .. data[3] -- texture + name only
else
  uuid = data[4] .. data[3] .. data[2] -- texture + name + slot
end
```

### 🛡️ Immunity Check for Debuff Timers (libdebuff.lua)

**No more phantom timers for immune targets:**

When a target is immune to your debuff (e.g., Rake bleed on a bleed-immune mob), the `AURA_CAST` event fires but `DEBUFF_ADDED` never comes. Previously this could create a timer with icon for a debuff that was never actually applied.

**The Fix:**
- Debuff data now requires `slot` to be set (confirmed by `DEBUFF_ADDED_OTHER` event)
- If `AURA_CAST` fires but `DEBUFF_ADDED` never comes → `slot` stays `nil` → no timer/icon shown

```lua
-- IMMUNITY CHECK: Only show if slot is set (confirmed by DEBUFF_ADDED_OTHER)
-- This prevents showing timers for spells like Rake where the bleed is immune
if data.slot and timeleft > -1 then
  -- Show the debuff
end
```

### 🎯 UnitDebuff() Now Returns Caster Information (libdebuff.lua)

**Enhanced UnitDebuff() API - 8th return value is now `caster`:**

```lua
local name, rank, texture, stacks, dtype, duration, timeleft, caster = libdebuff:UnitDebuff(unit, id)
-- caster = "player" (your debuff), "other" (someone else's), or nil (unknown)
```

**Use Cases:**
- Buff bar tooltip can now find correct slot for "only own debuffs" mode
- UI can differentiate between your debuffs and others' debuffs
- Enables future features like "show only my debuffs" filters

### 🔄 Buff Bar Tooltip Fix for "Only Own Debuffs" Mode (buffwatch.lua)

**Fixed tooltip showing wrong debuff in "only own debuffs" mode:**

When using the "Show only own debuffs" option on Target Debuff Bars, hovering over a debuff could show the wrong tooltip because the displayed slot didn't match the actual game slot. Now searches through all game slots to find the correct one by matching spell name AND caster.

### 🔧 Lua 5.0 Local Variable Limit Workaround (libdebuff.lua)

**Fixed addon failing to load due to Lua 5.0's 32 local variable limit:**

Lua 5.0 (used by WoW 1.12) has a hard limit of 32 local variables per function scope. As libdebuff grew, it hit this limit and stopped loading entirely.

**The Solution:** Moved 11 tables from local scope to `pfUI.` namespace:

| Old (local) | New (pfUI. namespace) |
|-------------|----------------------|
| `ownDebuffs` | `pfUI.libdebuff_own` |
| `ownSlots` | `pfUI.libdebuff_own_slots` |
| `allSlots` | `pfUI.libdebuff_all_slots` |
| `allAuraCasts` | `pfUI.libdebuff_all_auras` |
| `pendingCasts` | `pfUI.libdebuff_pending` |
| `objectsByGuid` | `pfUI.libdebuff_objects_guid` |
| `debugStats` | `pfUI.libdebuff_debugstats` |
| `lastCastRanks` | `pfUI.libdebuff_lastranks` |
| `lastFailedSpells` | `pfUI.libdebuff_lastfailed` |
| `lastUnitDebuffLog` | `pfUI.libdebuff_lastlog` |
| `cache` | `pfUI.libdebuff_cache` |

### 🛑 Crash 132 Fix (Credits: jrc13245)

**Fixed client crash (Error 132) when logging out:**

WoW crashes with Error 132 when addons make API calls like `UnitExists()` during shutdown, especially with UnitXP DLL installed.

**The Fix:** Register `PLAYER_LOGOUT` event and immediately disable all event handling:

```lua
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function()
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    return
  end
  -- ... rest of event handling
end)
```

**Applied to:**
- `libdebuff.lua` - All event frames
- `nameplates.lua` - nameplates + nameplates.combat frames
- `nampower.lua` - Spell queue indicator frame
- `superwow.lua` - Secondary mana bar frames
- `actionbar.lua` - Page switch frame

### ⚡ Performance Micro-Optimizations

**Various small performance improvements across the codebase:**

| Optimization | Location | Benefit |
|-------------|----------|---------|
| `childs` table reuse | nameplates.lua | Avoids creating new table every scan cycle |
| Indexed access instead of `pairs()` | nameplates.lua | Faster debuff timeout scanning |
| Quick exit if not in combat | nameplates.lua | Skips threatcolor calculation when unnecessary |
| Player GUID caching | libdebuff.lua | Avoids repeated `UnitExists("player")` calls |
| Consistent DoNothing() pattern | unitframes.lua, nameplates.lua | Lightweight frames when animation disabled |

### 📋 Complete libdebuff.lua Feature Summary

For reference, here's everything the enhanced libdebuff system now provides:

**Debuff Detection:**
- ✅ Checks for dodges, misses, resists, parries, immunes, reflects, and evades
- ✅ Immunity check - no timer if debuff wasn't actually applied
- ✅ Tracks if debuff is from YOU or from OTHERS (including their GUID)

**Rank & Duration:**
- ✅ Rank protection - lower rank spells can't refresh higher rank timers
- ✅ Shared debuff logic (`uniqueDebuffs` and `debuffOverwritePairs`)
- ✅ Faerie Fire ↔ Faerie Fire (Feral), Demo Shout ↔ Demo Roar overwrites (with rank check!)
- ✅ Combo point finisher duration (Rip, Rupture, Kidney Shot)
- ✅ Talent-based duration modifiers (Booming Voice, Improved SW:P, etc.)

**Tracking:**
- ✅ Multi-target debuff tracking via GUID
- ✅ Debuff stack tracking for stackable debuffs
- ✅ Handles dispels and removals via events

**API:**
- ✅ `UnitDebuff()` returns: name, rank, texture, stacks, dtype, duration, timeleft, caster
- ✅ `UnitOwnDebuff()` for filtering only your own debuffs
- ✅ Cleveroids API compatibility via `objectsByGuid`

**Debug Commands:**
- `/shifttest start/stop/stats/slots` - Debug debuff slot tracking
- `/memcheck` - Show memory usage statistics

---

## 🎯 What's New in Version 7.4.3 (January 29, 2026)

### ⚡ Massive Performance Optimization - Cooldown Frame Overhaul

**Revolutionary frame creation system that eliminates unnecessary Model frames:**

Previously, pfUI created expensive Model frames for every single buff/debuff cooldown timer, even when the animation was disabled. This caused significant performance overhead, especially in 40-man raids where hundreds of frames were created but never actually used.

**The Problem:**
- Old system: **ALWAYS** created Model frames with `CooldownFrameTemplate`
- When animation was disabled, frames were just hidden with `SetAlpha(0)`
- The frames still existed and consumed CPU resources in the background
- In raids: 40 players × 32 buffs/debuffs = **1,280 Model frames** running even when animations were off!

**The Solution (Nameplates.lua + Unitframes.lua):**
- New system: Creates **Frame type based on config setting**
- Animation ON → Model frame with `CooldownFrameTemplate` (expensive but animated)
- Animation OFF → Regular Frame with dummy functions (lightweight, no animation)
- Dummy functions (`DoNothing()`) prevent crashes when `CooldownFrame_SetTimer()` is called

**Performance Impact:**

| Scenario | Before 7.4.3 | After 7.4.3 | Improvement |
|----------|--------------|-------------|-------------|
| Player frame (animation ON) | 32 Model frames | 32 Model frames | No change ✅ |
| 40 raid frames (animation OFF) | 1,280 Model frames | 1,280 Light frames | **100% lighter!** 🚀 |
| Mixed (player ON, raid OFF) | 1,312 Model frames | 32 Model + 1,280 Light | **98% less Model frames!** 🎯 |

**Real-World Example:**
```
Before: ALL frames = 1,312 expensive Model frames
After:  32 Model (player) + 1,280 Light (raid) = 98% reduction in overhead
```

**Technical Implementation:**

```lua
-- Nameplates.lua & Unitframes.lua
if cooldown_anim == 1 then
  -- Create expensive Model frame
  cd = CreateFrame("Model", ...)
else
  -- Create lightweight Frame
  cd = CreateFrame("Frame", ...)
  cd.AdvanceTime = DoNothing
  cd.SetSequence = DoNothing
  cd.SetSequenceTime = DoNothing
end
```

**User Experience:**
- ✅ **GUI Integration:** Toggling "Show Timer Animation" now prompts for `/reload`
- ✅ **Per-Frame Control:** Each unitframe type (player/target/raid/party) has independent settings
- ✅ **Immediate Effect:** Reload applies the correct frame type based on your config
- ✅ **No Visual Change:** When animation is ON, everything looks identical (just way more efficient!)

**Why This Matters:**
- **40-man raids:** Dramatically reduced frame update overhead
- **Low-end PCs:** Smoother gameplay with animations disabled
- **Battery life:** Less CPU usage = longer laptop battery
- **Future-proof:** Foundation for more performance optimizations

**Compatibility:**
- Works with existing timer text display (independent of animation)
- Fully backward compatible with all existing configs
- No changes needed to user settings (automatic on reload)

---

## 🎯 What's New in Version 7.4.2 (January 28, 2026)

### Major Performance Improvements
- **Much faster debuff tracking** - No more lag in 40-man raids
- **10x less memory usage** - Runs cleaner over long raid sessions
- **Instant cleanup** - Dead mobs cleaned up immediately (was: 2-5 minutes)

### Better Debuff Tracking
- **Multi-player debuffs** - See debuffs from all raid members with accurate timers
- **Rank protection** - Lower rank spells can't overwrite higher ranks anymore
- **100% accurate positioning** - Debuff icons always in the correct slot
- **Better combo points** - Rip, Rupture, Kidney Shot show correct duration

---

## 🎯 What's New in Version 7.4.1 (January 27, 2026)

### 🎯 Nameplate Debuff Timer Improvements

- ✅ **New Option: Enable Debuff Timers** - Toggle for debuff timer display on nameplates
  - Moved from hidden location (Appearance → Cooldown → "Display Debuff Durations") to Nameplates → Debuffs
  - All timer-related options are now grouped together for better discoverability
- ✅ **New Option: Show Timer Text** - Toggle the countdown text (e.g., "12s") on debuff icons
  - Previously always shown, now configurable
- ✅ **Show Timer Animation** - Existing pie-chart animation option, now properly grouped with other timer options

### 🖼️ Unitframe Timer Config Fix (unitframes.lua)

- ✅ **Live Config Updates** - "Show Timer Animation" and "Show Timer Text" now update immediately
  - Previously: Changes only applied after buffs/debuffs were refreshed
  - Now: Toggling the option instantly shows/hides the animation and text on existing buffs/debuffs

### 🔧 Slot Shifting Fix Attempt (libdebuff.lua)

- ✅ **DEBUFF_REMOVED now uses slotData.spellName** - Previously used spellName from scan, which could be wrong after slot shifting
  - When debuffs shift slots (e.g., slot 3 removed, slots 4+ shift down), the scan might read a different spell
  - Now uses `removedSpellName = slotData.spellName` from stored slot data for consistency
- ✅ **Cleanup empty spell tables** - After removing a caster from allAuraCasts, checks if no other casters remain and removes the empty spell table
- ✅ **Defensive casterGuid validation** - Checks for empty string and "0x0000000000000000" before looking up timer data
- ✅ **Invalid timer detection** - Warns when remaining > duration (impossible state)
- ✅ **ValidateSlotConsistency function** - Debug function to verify allSlots and allAuraCasts consistency after shifting
- ✅ **Enhanced debug logging** - All debug messages now include target= for easier filtering

---

## 🎯 What's New in Version 7.4.0 (January 26, 2026)

### 🗡️ Rogue Combo Point Fix

**PLAYER_COMBO_POINTS event now works for Rogues:**

The combo point tracking was previously only enabled for Druids. Rogues were completely ignored, causing abilities like Kidney Shot to always show base duration (1 sec) instead of the correct CP-scaled duration.

**Technical Details:**
- Nampower sends `durationMs=1000` (base duration) for Kidney Shot
- Code checked `if duration == 0` before calling `GetDuration()` 
- Since duration was 1 (not 0), the CP calculation was skipped
- Fix: Always call `GetDuration()` for CP-based abilities, regardless of event duration

### ⚙️ New Settings: Number & Timer Formatting

**Abbreviate Numbers (Settings → General):**

| Option | Example |
|--------|---------|
| Full Numbers | 4250 |
| 2 Decimals | 4.25k |
| 1 Decimal | 4.2k (always rounds DOWN) |

**Castbar Timer Decimals (Settings → General):**

| Option | Example |
|--------|---------|
| 1 Decimal | 2.1 |
| 2 Decimals | 2.14 |

### 🎬 Nameplate Castbar Improvements

**Smooth Castbar Animation:**
- Fixed stuttering castbar caused by incorrect throttle placement
- Scanner throttle (0.05s) now only affects nameplate detection
- Castbar updates run at full 50 FPS for smooth animation

**Countdown Timer:**
- Castbar timer now counts DOWN (3.0 → 0.0) instead of up
- Shows remaining cast time, not elapsed time

**Intelligent Throttling (unchanged):**
- Target OR casting nameplates: 0.02s (50 FPS)
- All other nameplates: 0.1s (10 FPS)
- Event updates bypass throttle entirely

### 🧹 Memory Management

**Cache cleanup for hidden nameplates:**
- `guidRegistry` cleared when plate hides
- `CastEvents` cleared when plate hides
- `debuffCache` cleared when plate hides
- `threatMemory` cleared when plate hides

Prevents memory leaks when mobs die or go out of range.

---

## 🎯 What's New in Version 7.3.0 (January 25, 2026)

### ⚡ O(1) Performance Optimizations for Unitframes

**Complete rewrite of health/mana lookups using Nampower's `GetUnitField` API:**

The unitframes now use direct memory access via `GetUnitField(guid, "health")` instead of the slower `UnitHealth()` API calls. This provides significant performance improvements especially in raids.

**Key Changes:**

| Component | Before (7.2.0) | After (7.3.0) |
|-----------|----------------|---------------|
| HealPredict Health | `UnitHealth()` API calls | `GetUnitField(guid, "health")` O(1) |
| Health Bar Colors | 4x redundant API calls per update | Uses cached `hp_orig`/`hpmax_orig` values |
| GetColor Function | `UnitHealth()` API calls | `GetUnitField(guid, "health")` O(1) |

**Fallback Support:**
- Automatic fallback to `UnitHealth()` when Nampower not available
- Automatic fallback for units >180 yards (out of Nampower range)
- Automatic fallback when GUID unavailable

### 🚀 Smart Roster Updates (No More Freeze!)

**GUID-based tracking eliminates screen freezes when swapping raid groups:**

Previously, any raid roster change would trigger a full update of ALL 40 raid frames, causing noticeable freezes. Now, only frames where the actual player changed get updated.

**How it works:**
```lua
-- OLD: RAID_ROSTER_UPDATE → ALL 40 frames update_full = true → FREEZE
-- NEW: RAID_ROSTER_UPDATE → Check GUID per frame → Only changed frames update
```

| Scenario | Before (7.2.0) | After (7.3.0) |
|----------|----------------|---------------|
| Swap 2 players | 40 frame updates | 2 frame updates |
| Player joins | 40 frame updates | 1 frame update |
| Player leaves | 40 frame updates | 1 frame update |
| No changes | 40 frame updates | 0 frame updates |

**Technical Implementation:**
- `pfUI.uf.guidTracker` tracks GUID per frame
- On roster change, compares old GUID vs new GUID
- Only sets `update_full = true` if GUID actually changed
- Also forces `update_aura = true` to refresh buffs/debuffs

### 🔧 libpredict.lua Optimizations

**Eliminated redundant `UnitName()` calls:**
- `UnitGetIncomingHeals()`: Removed double `UnitName()` call
- `UnitHasIncomingResurrection()`: Removed double `UnitName()` call  
- `UNIT_HEALTH` event handler: Reuses cached name variable

---

## 🎯 What's New in Version 7.2.0 (January 24, 2026)

### 🐱 Druid Secondary Mana Bar Overhaul

**Complete rewrite using Nampower's `GetUnitField` API:**

The Druid Mana Bar feature (showing base mana while in shapeshift form) has been completely rewritten to use Nampower's native `GetUnitField` instead of the deprecated `UnitMana()` extended return values.

**Key Changes:**

| Component | Before (7.1.0) | After (7.2.0) |
|-----------|----------------|---------------|
| Data Source | `UnitMana()` second return value | `GetUnitField(guid, "power1")` |
| Player Support | ✅ Druids only | ✅ Druids only |
| Target Support | ❌ Limited/broken | ✅ All classes can see Druid mana in all forms |
| Text Settings | Hardcoded format | Respects Power Bar text config |

<img width="704" height="210" alt="grafik" src="https://i.ibb.co/bgfC04Gk/grafik.png" />

**New Features:**
- ✅ **Target Secondary Mana:** See enemy/friendly Druid's base mana while they're in Cat/Bear form
- ✅ **Respects Power Text Settings:** Uses same format as your Power Bar configuration (`powerdyn`, `power`, `powerperc`, `none`, etc.)
- ✅ **Available for ALL Classes:** Any class can now see Druid mana bars (controlled by "Show Druid Mana Bar" setting)

**Technical Implementation:**
```lua
-- OLD: Extended UnitMana (unreliable for other units)
local _, baseMana = UnitMana("target")  -- Often returns nil for non-player

-- NEW: Direct field access via Nampower
local _, guid = UnitExists("target")
local baseMana = GetUnitField(guid, "power1")      -- Base mana
local baseMaxMana = GetUnitField(guid, "maxPower1") -- Max base mana
```

### 🧹 Major Code Cleanup

**superwow.lua:**
- ❌ Removed legacy `pfDruidMana` bar (old SuperWoW-style implementation)
- ❌ Removed `UnitMana()` fallback code
- ✅ Unified all secondary mana bars to use `GetUnitField`
- ✅ Fixed text centering issue (was using `SetJustifyH("RIGHT")`)

**nampower.lua - Massive Cleanup:**

Removed significant amounts of dead/unused code:

| Removed Feature | Reason |
|-----------------|--------|
| Buff tracking system | Data collected but never displayed |
| HoT Detection (AURA_CAST events) | `OnHotApplied` callback never implemented |
| Swing Timer (`GetSwingTimers()`) | Never called anywhere in codebase |
| UNIT_DIED buff/debuff cleanup | Now handled by libdebuff |

**Result:** Cleaner, more maintainable code with reduced memory footprint.

---

## 🎯 What's New in Version 7.1.0 (January 24, 2026)

### ⚡ Cooldown Timer Animation Support

**Nameplate Debuff Animations:**
- ✅ Added "Show Timer Animation" option for nameplate debuffs
- ✅ Uses proper `Model` frame with `CooldownFrameTemplate` for Vanilla client
- ✅ Pie/swipe animation now works on nameplate debuff icons
- ✅ Configurable via GUI: Nameplates → Show Timer Animation

**Target Frame Debuff Animations:**
- ✅ Timer animations now properly visible on target/player frame debuffs
- ✅ Fixed CD frame scaling and positioning for correct display
- ✅ `SetScale(size/32)`, `SetAllPoints()`, `SetFrameLevel(14)` for proper rendering

**cooldown.lua Fix:**
- ✅ Added `elseif pfCooldownStyleAnimation == 1 then SetAlpha(1)` to make animations visible
- ✅ Previously animations were created but never shown (alpha stayed 0)

### 🧹 Memory Leak Fixes

**libdebuff.lua:**
- ✅ `lastCastRanks` table now cleaned up (entries older than 3 seconds removed)
- ✅ `lastFailedSpells` table now cleaned up (entries older than 2 seconds removed)
- ✅ Previously these tables grew indefinitely over long play sessions

**unitframes.lua:**
- ✅ Cache cleanup now uses in-place `= nil` instead of creating new table every 30 seconds
- ✅ Reduces garbage collector pressure

**nameplates.lua:**
- ✅ Reusable `debuffSeen` table instead of creating `local seen = {}` on every DEBUFF_UPDATE event
- ✅ Significant reduction in table allocations during combat

---

## 🎯 What's New in Version 7.0.0 (January 21, 2026)

### 🔥 Complete libdebuff.lua Rewrite (464 → 1594 lines)

**Event-Driven Architecture:**

Replaced tooltip scanning with a pure event-based system using Nampower/SuperWoW:

**OLD (Master):**
```lua
-- Every UI update:
for slot = 1, 16 do
  scanner:SetUnitDebuff("target", slot)  -- Tooltip scan
  local name = scanner:Line(1)
end
```

**NEW (Experiment):**
```lua
-- Events fire when changes happen:
RegisterEvent("AURA_CAST_ON_SELF")     -- You cast a debuff
RegisterEvent("DEBUFF_ADDED_OTHER")    -- Debuff lands in slot
RegisterEvent("DEBUFF_REMOVED_OTHER")  -- Debuff removed

-- UI reads from pre-computed tables:
local data = ownDebuffs[guid][spell]  -- Direct lookup
```

---

### 🐱 Combo Point Finisher Support

**Dynamic Duration Calculation:**

| Ability | Formula | Durations (1-5 CP) |
|---------|---------|-------------------|
| Rip | 8s + CP × 2s | 10s / 12s / 14s / 16s / 18s |
| Rupture | 10s + CP × 2s | 12s / 14s / 16s / 18s / 20s |
| Kidney Shot | 2s + CP × 1s | 3s / 4s / 5s / 6s / 7s |

**Before:** All Rips showed 18s (wrong for 1-4 CP)
**After:** Shows actual duration based on combo points used

---

### 🎭 Carnage Talent Detection

**Ferocious Bite Refresh Mechanics:**
- Tracks Carnage talent (Rank 2) which makes Ferocious Bite refresh Rip & Rake
- Only refreshes when Ferocious Bite HITS (not on miss/dodge/parry)
- Preserves original duration (doesn't reset to new CP count)
- Uses `DidSpellFail()` API for miss detection

---

### 🔄 Additional Features

- **Debuff Overwrite Pairs:** Faerie Fire ↔ Faerie Fire (Feral), Demoralizing Shout ↔ Demoralizing Roar
- **Slot Shifting Algorithm:** Accurate icon placement when debuffs expire
- **Multi-Caster Tracking:** Multiple players' debuffs tracked separately
- **Rank Protection:** Lower rank can't overwrite higher rank timer
- **Unique Debuff System:** Hunter's Mark, Scorpid Sting, etc. handled correctly

---

## 📊 Performance Comparison

### The Core Difference: Data Access Architecture

**Master uses Blizzard API + Tooltip Scanning:**
```lua
-- Every UnitDebuff call requires tooltip scan
function libdebuff:UnitDebuff(unit, id)
  local texture, stacks, dtype = UnitDebuff(unit, id)
  if texture then
    scanner:SetUnitDebuff(unit, id)  -- Tooltip scan to get spell name
    effect = scanner:Line(1)
  end
  -- Duration comes from hardcoded lookup tables
end

-- UnitOwnDebuff iterates all 16 slots
function libdebuff:UnitOwnDebuff(unit, id)
  for i = 1, 16 do
    local effect = libdebuff:UnitDebuff(unit, i)  -- 16 tooltip scans!
    if caster == "player" then ...
  end
end
```

**Experiment uses Nampower Events + GetUnitField:**
```lua
-- Single call returns ALL 48 aura slots (32 buffs + 16 debuffs)
local auras = GetUnitField(guid, "aura")  -- Returns array[48] of spell IDs
local stacks = GetUnitField(guid, "auraApplications")  -- Returns array[48] of stack counts

-- Events fire with full data including duration
-- AURA_CAST_ON_OTHER: spellId, casterGuid, targetGuid, effect, effectAuraName, 
--                     effectAmplitude, effectMiscValue, durationMs, auraCapStatus
-- BUFF_REMOVED_OTHER: guid, slot, spellId, stackCount, auraLevel

-- UnitOwnDebuff is just a table lookup
function libdebuff:UnitOwnDebuff(unit, id)
  local _, guid = UnitExists(unit)
  local data = ownDebuffs[guid][spellName]  -- Pre-computed by events
  return data.duration, data.timeleft, ...
end
```

### Nampower Features Used (Experiment Only)

| Feature | Purpose | Data Provided |
|---------|---------|---------------|
| `GetUnitField(guid, "aura")` | Single call returns all 48 aura spell IDs | `array[48]` of spell IDs |
| `GetUnitField(guid, "auraApplications")` | Stack counts for all auras | `array[48]` of stack counts |
| `GetUnitField(guid, "power1")` | Base mana for shapeshifted Druids | Mana value (7.2.0) |
| `GetUnitField(guid, "maxPower1")` | Max base mana | Max mana value (7.2.0) |
| `AURA_CAST_ON_OTHER` | Instant debuff cast detection | spellId, casterGuid, targetGuid, **durationMs** |
| `AURA_CAST_ON_SELF` | Instant self-buff detection | Same as above |
| `BUFF_REMOVED_OTHER` | Instant aura removal detection | guid, **slot**, spellId, stackCount |
| `DEBUFF_ADDED_OTHER` | Debuff slot assignment | guid, slot, spellId, stacks |
| `DEBUFF_REMOVED_OTHER` | Debuff removal with slot info | guid, slot, spellId |

Master uses **none** of these - it relies on:
- `UnitDebuff()` API (no caster info, no duration)
- Tooltip scanning via `GameTooltip:SetUnitDebuff()` to get spell names
- Chat message parsing (`CHAT_MSG_SPELL_PERIODIC_*`) for duration detection
- Hardcoded duration lookup tables

### Performance Comparison

| Operation | Master | Experiment | Improvement |
|-----------|--------|------------|-------------|
| Initial target scan | 16 tooltip scans | 1 GetUnitField call (48 slots) | **16x fewer calls** |
| Get YOUR debuffs | Loop 16 slots + tooltip each | Direct table lookup | **~50-100x faster** |
| Debuff duration | Hardcoded tables / chat parsing | Event provides `durationMs` | **Accurate to ms** |
| Detect debuff removal | Polling / timeout | `BUFF_REMOVED_OTHER` event | **Instant** |
| Detect new debuff | Chat message delay | `AURA_CAST_ON_OTHER` event | **Instant** |
| Caster identification | Not available | Event provides `casterGuid` | **New capability** |
| Druid mana (other units) | Not available | `GetUnitField(guid, "power1")` | **New in 7.2.0** |
| Memory usage | ~50KB | ~200KB | 4x more (negligible) |

### Memory Management (7.1.0+ Fixes)

| Table | Before 7.1.0 | After 7.1.0 |
|-------|--------------|-------------|
| `lastCastRanks` | Grew indefinitely | Cleaned every 30s (>3s old) |
| `lastFailedSpells` | Grew indefinitely | Cleaned every 30s (>2s old) |
| `debuffSeen` (nameplates) | New table per DEBUFF_UPDATE | Reused single table |
| `cleanedCache` (unitframes) | New table every 30s | In-place cleanup |

---

## 📋 File Changes Summary

### Version 7.5.0

| File | Location | Changes |
|------|----------|---------|
| `buffwatch.lua` | `modules/` | Player buff bar timer fix (UUID without slot), tooltip fix for "only own debuffs" mode |
| `libdebuff.lua` | `libs/` | Immunity check, UnitDebuff() 8th return value `caster`, Lua 5.0 table limit workaround (11 tables to pfUI. namespace), Crash 132 fix, Player GUID caching |
| `unitframes.lua` | `api/` | Consistent DoNothing() pattern for lightweight cooldown frames |
| `nameplates.lua` | `modules/` | Consistent DoNothing() pattern, `childs` table reuse, indexed debuff timeout scan, quick exit optimization, Crash 132 fix |
| `nampower.lua` | `modules/` | Crash 132 fix |
| `superwow.lua` | `modules/` | Crash 132 fix |
| `actionbar.lua` | `modules/` | Crash 132 fix |

### Version 7.4.3 (January 29, 2026)

| File | Location | Changes |
|------|----------|---------|
| `libdebuff.lua` | `libs/` | Rogue PLAYER_COMBO_POINTS fix, always use GetDuration() for CP-abilities |
| `api.lua` | `api/` | Abbreviate() now supports 3 modes (off/2dec/1dec), 1dec always floors |
| `config.lua` | `api/` | Added `castbardecimals` option |
| `gui.lua` | `modules/` | Abbreviate Numbers dropdown, Castbar Timer Decimals dropdown |
| `nameplates.lua` | `modules/` | Smooth castbar (throttle fix), countdown timer, cache cleanup |
| `castbar.lua` | `modules/` | FormatCastbarTime() helper, respects castbardecimals config |

### Version 7.2.0

| File | Location | Changes |
|------|----------|---------|
| `superwow.lua` | `modules/` | Removed legacy pfDruidMana, added Target/ToT secondary mana bars, GetUnitField for all mana queries, respect Power Bar text settings |
| `nampower.lua` | `modules/` | Major cleanup: removed dead buff tracking, HoT detection, swing timer code |

### Version 7.1.0

| File | Location | Changes |
|------|----------|---------|
| `libdebuff.lua` | `libs/` | Memory leak fixes for lastCastRanks, lastFailedSpells |
| `unitframes.lua` | `api/` | In-place cache cleanup, CD frame scaling/positioning |
| `nameplates.lua` | `modules/` | Reusable debuffSeen table, Model+CooldownFrameTemplate |
| `cooldown.lua` | `modules/` | SetAlpha(1) for pfCooldownStyleAnimation == 1 |
| `config.lua` | `api/` | Added nameplates.debuffanim option |
| `gui.lua` | `modules/` | Added "Show Timer Animation" checkbox for nameplates |

---

## 📋 Installation

### Requirements

**REQUIRED:**
- SuperWoW DLL
- Nampower DLL

**Optional but Recommended:**
- UnitXP_SP3 DLL (for accurate XP tracking)

### Steps

1. Install SuperWoW + Nampower
2. Download pfUI Experiment build
3. Extract to `Interface/AddOns/pfUI`
4. `/reload`
5. Check for errors in console

### Verification

Type `/run print(GetNampowerVersion())` - should show version number.

If `nil`, Nampower is not installed correctly!

---

## 🐛 Known Issues

### Untested Scenarios

- ❌ 40-man raids with 5+ druids (slot shifting stress test)
- ❌ Rapid target swapping with Ferocious Bite spam
- ⚠️ Multi-caster tracking in AQ40/Naxx

### Edge Cases

1. **DEBUFF_ADDED race condition:** Sometimes fires before AURA_CAST_ON_SELF processes
2. **Slot shifting bugs:** Complex logic for removing/adding debuffs
3. **Combo point detection:** Relies on PLAYER_COMBO_POINTS event timing

---

## 📜 Changelog

### 7.5.0 (January 31, 2026)

**Added:**
- ✅ UnitDebuff() 8th return value: `caster` ("player"/"other"/nil)
- ✅ Immunity check - no timer/icon shown if debuff wasn't actually applied
- ✅ Buff bar tooltip correctly identifies debuff slot in "only own debuffs" mode
- ✅ `/shifttest` and `/memcheck` debug commands for libdebuff troubleshooting

**Fixed:**
- 🔧 Player Buff Bar timer reset bug (UUID no longer includes slot for player buffs)
- 🔧 Lua 5.0 local variable limit (moved 11 tables to pfUI. namespace)
- 🔧 Crash 132 on logout (Credits: jrc13245) - affects libdebuff, nameplates, nampower, superwow, actionbar
- 🔧 Consistent DoNothing() pattern across all cooldown frame creation

**Performance:**
- ⚡ `childs` table reuse in nameplate scanner (avoids GC churn)
- ⚡ Indexed access instead of `pairs()` for debuff timeout scanning
- ⚡ Quick exit if not in combat for threatcolor calculation
- ⚡ Player GUID caching in libdebuff

### 7.4.3 (January 29, 2026)

**Added:**
- ✅ Castbar Timer Decimals setting (1 or 2 decimals)
- ✅ Abbreviate Numbers dropdown (Full / 2 Decimals / 1 Decimal)
- ✅ Nameplate castbar countdown (shows remaining time)
- ✅ Cache cleanup for hidden nameplates (prevents memory leaks)

**Fixed:**
- 🔧 Rogue combo point tracking (PLAYER_COMBO_POINTS was Druid-only)
- 🔧 Kidney Shot/Rupture duration (now always uses GetDuration() for CP-abilities)
- 🔧 Nameplate castbar stuttering (throttle only affects scanner, not updates)

**Changed:**
- 🔧 Abbreviate Numbers: 1 Decimal mode always rounds DOWN (4180 → 4.1k)
- 🔧 Nameplate castbar: counts down instead of up

### 7.2.0 (January 24, 2026)

**Added:**
- ✅ Target Secondary Mana Bar (see Druid mana while in shapeshift form)
- ✅ Target-of-Target Secondary Mana Bar
- ✅ Secondary Mana Bars now respect Power Bar text settings

**Changed:**
- 🔧 Secondary Mana Bars now use `GetUnitField(guid, "power1")` instead of `UnitMana()`
- 🔧 "Show Druid Mana Bar" setting now available for ALL classes (not just Druids)

**Removed:**
- ❌ Legacy `pfDruidMana` bar (replaced by `pfPlayerSecondaryMana`)
- ❌ `UnitMana()` extended return value fallback
- ❌ Dead code in nampower.lua: buff tracking, HoT detection, swing timer

### 7.1.0 (January 24, 2026)

**Added:**
- ✅ Nameplate debuff timer animation support (pie/swipe effect)
- ✅ Target frame debuff animation improvements
- ✅ GUI option: Nameplates → Show Timer Animation

**Fixed:**
- 🔧 Memory leak: `lastCastRanks` now cleaned up (>3s old entries)
- 🔧 Memory leak: `lastFailedSpells` now cleaned up (>2s old entries)
- 🔧 Memory churn: Reusable `debuffSeen` table in nameplates
- 🔧 Memory churn: In-place cache cleanup in unitframes
- 🔧 cooldown.lua: Animation now visible when pfCooldownStyleAnimation == 1

### 7.0.0 (January 21, 2026)

**Added:**
- ✅ Event-driven debuff tracking (AURA_CAST, DEBUFF_ADDED, etc.)
- ✅ Combo point finisher support (Rip, Rupture, Kidney Shot)
- ✅ Carnage talent detection (Ferocious Bite refresh)
- ✅ Debuff overwrite pairs (Faerie Fire ↔ Faerie Fire Feral)
- ✅ Slot shifting algorithm (accurate icon placement)
- ✅ Multi-caster tracking (multiple Moonfires)
- ✅ Rank protection (Rank 1 can't overwrite Rank 10)
- ✅ Unique debuff system (Hunter's Mark, Scorpid Sting)
- ✅ Nampower GetUnitField() initial scan
- ✅ Combat indicator fix (works on player frame now)

**Changed:**
- 🔧 libdebuff.lua completely rewritten (464 → 1594 lines)
- 🔧 UnitOwnDebuff() uses table lookup instead of tooltip scan

---
## What's New in Version 6.2.6 (January 27, 2026)

### 🎯 Nameplate Debuff Timer Improvements

- ✅ **New Option: Enable Debuff Timers** - Toggle for debuff timer display on nameplates
  - Moved from hidden location (Appearance → Cooldown → "Display Debuff Durations") to Nameplates → Debuffs
  - All timer-related options are now grouped together for better discoverability
- ✅ **New Option: Show Timer Text** - Toggle the countdown text (e.g., "12s") on debuff icons
  - Previously always shown, now configurable
- ✅ **Show Timer Animation** - Existing pie-chart animation option, now properly grouped with other timer options

### 🖼️ Unitframe Timer Config Fix (unitframes.lua)

- ✅ **Live Config Updates** - "Show Timer Animation" and "Show Timer Text" now update immediately
  - Previously: Changes only applied after buffs/debuffs were refreshed
  - Now: Toggling the option instantly shows/hides the animation and text on existing buffs/debuffs

### 🐱 Combo Point Ability Fixes (libdebuff.lua)

- ✅ **Rogue & Druid Combo Point Tracking** - Fixed duration calculation for combo point abilities
  - Rupture, Kidney Shot, and Rip now correctly calculate duration based on combo points spent
  - Added `PLAYER_COMBO_POINTS` event tracking for both Rogues AND Druids
  - Stores combo points before they're consumed, ensuring accurate duration calculation
  - Fixes issue where abilities showed incorrect duration when combo points were already spent at cast time

---
## What's New in Version 6.2.5 (January 21, 2026)

### 🎯 Bug report fixes and feature requests.
- Fixed aggro indicator on "Player" frame not working properly.
- Fixed aggro and combat glow on player frames.
- Changed the Aggro indicator timer from 0.1 to 0.2 times per second (5 times per second is enough)
- Fixed the 40yard range check not working properly for Shamans and Druids in bear/cat form.
- Added 2 new buttons to the Nameplate menu: "Disable Hostile Nameplates in Friendly Zones" and "Disable Friendly Nameplates in Friendly Zones"
- changed version to 6.2.5 to push an update for everyone
- Feel free to check out https://github.com/me0wg4ming/pfUI/tree/enhanced_release - this is an experiment version with proper tracking for debuffs on current target (use on own risk)


---

---
## What's New in Version 6.2.3 (January 11, 2026)

### 🎯 Unit and Raidframes fix (unitframes.lua)
- Fixed lag spikes in raids, raid frames should be now butter smooth and cause no lags
- Fixed a bug not updating hp/mana and buffs/debuffs properly.
- Removed a scan system that scanned always all 40 raid frames 10 times per second (worked out a better solution to track those)
- debuff tracking on enemys (for your own abilitys/spells) should be working properly too now

---

## What's New in Version 6.2.2 (January 10, 2026)

### 🎯 Failed Spell Detection (libdebuff.lua)

- ✅ **Resist/Miss/Dodge/Parry Detection** - Spells that fail to land no longer create or update timers
  - Detects: Miss, Resist, Dodge, Parry, Evade, Deflect, Reflect, Block, Absorb, Immune
  - Timer is either blocked before creation or reverted if fail event arrives late
- ✅ **Public API: `libdebuff:DidSpellFail(spell)`** - Other modules can check if a spell recently failed
  - Returns true if spell failed within the last 1 second
  - Used by turtle-wow.lua for refresh mechanics

### 🐱 Druid/Warlock Refresh Fixes (turtle-wow.lua)

- ✅ **Ferocious Bite Refresh Fix** - Rip/Rake timers only refresh when Ferocious Bite actually hits
  - Previously: Timer refreshed even on dodge/parry/miss
  - Now: Uses `DidSpellFail()` to verify hit before refreshing
- ✅ **Conflagrate Refresh Fix** - Immolate duration only reduced when Conflagrate actually hits
- ✅ **Caster Inheritance** - Refresh mechanics preserve existing caster info when not explicitly provided

### ⚡ SuperWoW Compatibility (superwow.lua)

- ✅ **Removed UNIT_CASTEVENT for DoT Timers** - SuperWoW's instant event fires before resist/miss detection
  - DoT timers now use standard hook-based fallback (compatible with resist detection)
  - HoT timers (Rejuvenation, Renew, etc.) still use SuperWoW for instant detection (buffs can't be resisted)

---

## What's New in Version 6.2.1 (January 10, 2026)

### 🎯 Debuff Timer Protection System (libdebuff.lua)

- ✅ **Spell Rank Tracking** - Tracks spell rank for all your DoTs/debuffs
  - Uses `lastCastRanks` table to preserve rank information across multiple event sources
  - Fixes race condition where SuperWoW UNIT_CASTEVENT fired before QueueFunction processed pending data
- ✅ **Lower Rank Protection** - Lower rank spells cannot overwrite higher rank timers
  - Example: If Moonfire Rank 10 is active, casting Rank 5 will be blocked
- ✅ **Other Player Protection** - Other players' casts cannot overwrite your debuff timers
  - Your DoTs are tracked separately from other players' DoTs
  - Multiple players can have their own Moonfire/Corruption on the same target
- ✅ **Shared Debuff Whitelist** - Debuffs that are shared by all players update correctly:
  - Warrior: Sunder Armor, Demoralizing Shout, Thunder Clap
  - Rogue: Expose Armor
  - Druid: Faerie Fire, Faerie Fire (Feral)
  - Hunter: Hunter's Mark
  - Warlock: Curse of Weakness/Recklessness/Elements/Shadow/Tongues/Exhaustion
  - Priest: Shadow Weaving
  - Mage: Winter's Chill
  - Paladin: All Judgements

---

## What's New in Version 6.2.0 (January 10, 2026)

### 🔮 HoT Timer System (libpredict.lua)

- ✅ **Regrowth Duration Fix** - Corrected duration from 21 to 20 seconds (matching actual Turtle WoW spell duration)
- ✅ **GetTime() Synchronization** - All timing calls now use `pfUI.uf.now or GetTime()` for consistent timing across all UI elements
- ✅ **Instant-HoT Detection Fix** - Fixed Rejuvenation/Renew not being detected when cast quickly after Regrowth
  - Problem: `spell_queue` was overwritten before processing
  - Solution: Instant HoTs now processed immediately at cast hooks with `current_cast` tracking
- ✅ **SuperWoW UNIT_CASTEVENT Support** - Precise Instant-HoT detection using UNIT_CASTEVENT
  - Only fires on successful casts (not attempts), eliminating false triggers from GCD/range failures
  - Graceful fallback to hook-based detection for players without SuperWoW
- ✅ **HealComm Compatibility** - Full compatibility with standalone HealComm addon users
  - 0.3s delay compensation for Regrowth messages
  - Duplicate detection (0.5s window) prevents double timers
- ✅ **PARTY Channel Support** - HoT messages now sent to PARTY channel for 5-man dungeons

### 🎯 Nameplate Improvements (nameplates.lua)

- ✅ **Target Castbar Zoom Fix** - Fixed current target castbar not showing when zoom factor is enabled
  - Multi-method target detection: alpha check, `istarget` flag, and `zoomed` state
  - Proper GUID lookup for target castbar info (was incorrectly using string "target")
- ✅ **Flicker/Vibration Fix** - Eliminated nameplate flicker near zoom boundaries
  - Alpha check changed from `== 1` to `>= 0.99` (floating-point fix)
  - Zoom tolerance changed from `>= w` to `> w + 0.5` (prevents oscillation)
- ✅ **libdebuff Nil-Checks** - Added safety checks to prevent errors when libdebuff data is unavailable

### ⚡ Spell Queue (nampower.lua)

- ✅ **Error Handling** - Added pcall wrapper for `GetSpellNameAndRankForId` to prevent error spam when spell ID not found

### 🐱 Druid Improvements

- ✅ **Rip Duration** (libdebuff.lua) - Now dynamically calculated based on combo points (10/12/14/16/18 seconds for 1-5 CP)
- ✅ **Ferocious Bite Refresh** (turtle-wow.lua) - Now refreshes both Rip AND Rake (previously only Rip), preserving existing duration

### ⚡ Energy Tick (energytick.lua)

- ✅ **Talent/Buff Energy Filter** - Ignores energy gains from talents/buffs (e.g., Ancient Brutality and Tiger's Fury) to prevent tick timer reset from non-natural energy gains

---

## What's New in Version 6.1.1 (January 8, 2026)

### 🐛 Bugfixes

- ✅ **Chat Level Display Fix** - Fixed targeting high-level players overwriting known level with -1. Now shows "??" for unknown levels instead of -1
- ✅ **Nameplate Level Fix** - Nameplates now use stored level from database after reload instead of showing "??"
- ✅ **Nameplate Level Color** - Level color now correctly uses difficulty color when loaded from database

### ⚙️ Config Changes

- ✅ **Chat Player Levels** - Now disabled by default (was enabled)

---

## What's New in Version 6.1.0 (January 8, 2026)

### 🐛 Bugfixes

- ✅ **40-Yard Range Check Fix** - Fixed range check not working for raid/party frames due to throttle variable conflict (`this.tick` vs `this.throttleTick`)
- ✅ **Aggro Indicator Fix** - Fixed aggro indicator not displaying properly on raid/party frames (same throttle issue)
- ✅ **Aggro Detection Cache** - Improved aggro cache to only cache positive results, allowing instant detection when aggro changes while maintaining performance
- ✅ **Raid Frames with Group Display** - Fixed HP/Mana not updating when "Use Raid Frames to display group members" was enabled without being in a raid
- ✅ **SuperWoW nil-check** - Added nil-check for `SpellInfo` in superwow.lua to prevent errors when SuperWoW is not installed
- ✅ **Missing Event Registration** - Added missing events for raid/party frames: `PARTY_MEMBER_ENABLE`, `PARTY_MEMBER_DISABLE`, `PLAYER_UPDATE_RESTING`

### 🎨 UI Improvements

- ✅ **Share Button Warning** - Shows message when Share module is disabled instead of doing nothing
- ✅ **Hoverbind Button Warning** - Shows message when Hoverbind module is disabled instead of doing nothing

---

## What's New in Version 6.0.0 (January 5, 2026)

### 🚀 Major Performance Improvements

- ✅ **Central Raid/Party Event Handler** - Replaced per-frame event registration with a centralized system using O(1) unitmap lookups instead of O(n) iteration. Reduces event processing from ~5,760 calls/sec to ~400 calls/sec in 40-man raids (97.5% improvement)
- ✅ **Raid HP/Mana Update Fix** - Fixed race condition where unitmap wasn't rebuilt after frame IDs were reassigned, causing HP/Mana bars to not update when players swap positions
- ✅ **OnUpdate Throttling** - Added configurable throttles to reduce CPU usage:
  - Nameplates: 0.1s throttle (target updates remain instant)
  - Tooltip cursor following: 0.1s throttle
  - Chat tab mouseover: 0.1s throttle
  - Panel alignment: 0.2s throttle
  - Autohide hover check: 0.05s throttle
  - Libpredict cleanup: 0.1s throttle

### 🔧 Castbar & Pushback System

- ✅ **Pushback Fix** - Fixed spell pushback calculation: now correctly adds delay to `casttime` instead of `start` time, matching actual WoW behavior
- ✅ **Player GUID Caching** - Caches player GUID on PLAYER_ENTERING_WORLD for efficient self-cast detection
- ✅ **Hybrid Detection System** - Uses libcast.db for player casts (handles SPELLCAST_DELAYED events) and SuperWoW's UNIT_CASTEVENT for NPC/other player casts
- ✅ **2-Decimal Precision** - Castbar timer now displays with 2 decimal places (e.g., "1.45 / 2.50") for more precise timing

### 🐱 Druid Stealth Detection

- ✅ **Event-Based Detection** - Replaced polling-based stealth detection with event-driven system using UNIT_CASTEVENT and PLAYER_AURAS_CHANGED
- ✅ **Instant Cat Form Detection** - Detects Cat Form via UNIT_CASTEVENT (spell ID 768) for immediate actionbar page switch
- ✅ **Smart Buff Scanning** - Only scans buffs when actually needed (entering Cat Form), eliminates 31-buff scan every frame
- ✅ **Cached Variables** - Caches stealth state to prevent redundant checks

### 🎯 Nameplate Improvements

- ✅ **Friendly Player Classification** - Fixed friendly players being classified as FRIENDLY_NPC, now correctly uses FRIENDLY_PLAYER for proper nameplate coloring and behavior
- ✅ **Performance Throttle** - 0.1s update throttle for non-target nameplates while keeping target nameplate updates instant

### 🆕 New Modules

*Modules by [jrc13245](https://github.com/jrc13245/)*

- ✅ **nampower.lua** - Nampower DLL integration module:
  - Spell Queue Indicator (shows queued spell icon near castbar)
  - GCD Indicator
  - Reactive Spell Indicator
  - Enhanced buff tracking
  - Requires [Nampower DLL](https://gitea.com/avitasia/nampower)

- ✅ **unitxp.lua** - UnitXP_SP3 DLL integration module:
  - Line of Sight Indicator on target frame
  - Behind Indicator on target frame
  - OS Notifications for combat events
  - Distance-based features
  - Requires [UnitXP_SP3 DLL](https://codeberg.org/konaka/UnitXP_SP3)

- ✅ **bgscore.lua** - Battleground Score frame positioning:
  - Movable BG score frame
  - Position saving across sessions

### 🛠️ DLL Detection & API Helpers

- ✅ **HasSuperWoW()** - Detects SuperWoW DLL presence
- ✅ **HasUnitXP()** - Detects UnitXP_SP3 DLL presence
- ✅ **HasNampower()** - Detects Nampower DLL presence
- ✅ **GetUnitDistance(unit1, unit2)** - Returns distance using best available method (UnitXP or SuperWoW)
- ✅ **UnitInLineOfSight(unit1, unit2)** - Line of sight check via UnitXP
- ✅ **UnitIsBehind(unit1, unit2)** - Behind check via UnitXP

### 📝 New Slash Commands

- ✅ **/pfdll** - Shows DLL status for SuperWoW, Nampower, and UnitXP with detailed diagnostics
- ✅ **/pfbehind** - Test command for Behind/LOS detection on current target

### 🎮 SuperWoW API Wrappers

- ✅ **TrackUnit API** - Track group members on minimap (configurable)
- ✅ **Raid Marker Targeting** - Target units by raid marker ("mark1" to "mark8")
- ✅ **GetUnitOwner** - Get owner of pets/totems using "owner" suffix
- ✅ **Enhanced SpellInfo** - Wrapper returning structured spell data
- ✅ **Clickthrough API** - Toggle clicking through corpses
- ✅ **Autoloot API** - Control autoloot setting
- ✅ **GetPlayerBuffSpellId** - Get spell ID from buff index
- ✅ **LogToCombatLog** - Add custom entries to combat log
- ✅ **SetLocalRaidTarget** - Set raid markers only visible to self
- ✅ **GetItemCharges** - Get item charges (SuperWoW returns as negative)
- ✅ **GetUnitWeaponEnchants** - Get weapon enchant info on any unit

### 💬 Chat Enhancements

- ✅ **Player Level Display** - Shows player level next to names in chat (color-coded by difficulty)
- ✅ **Tab Mouseover Throttle** - 0.1s throttle for chat tab hover effects

### ⚙️ New Configuration Options

All new features are configurable via `/pfui`:

**Unit Frames → SuperWoW Settings:**
- Track Group on Minimap

**Unit Frames → Nampower Settings:**
- Show Spell Queue Indicator
- Spell Queue Icon Size
- Show Reactive Spell Indicator
- Reactive Indicator Size
- Enhanced Buff Tracking

**Unit Frames → UnitXP Settings:**
- Show Line of Sight Indicator
- Show Behind Indicator
- Enable OS Notifications

**Chat → Text:**
- Enable Player Levels

### 🐛 Bugfixes

- ✅ **superwow_active Variable** - Fixed inconsistent SuperWoW detection across modules (nameplates, castbar, librange, unitframes)
- ✅ **Unitmap Race Condition** - Fixed HP/Mana not updating when raid members swap positions
- ✅ **Friendly Nameplate Color** - Fixed friendly players using NPC color instead of player color

### 🐢 Turtle WoW TBC Spell Indicators

Turtle WoW includes TBC spells in the Vanilla client. This version includes all TBC buff indicators:
- ✅ Commanding Shout indicator
- ✅ Misdirection indicator
- ✅ Earth Shield indicator
- ✅ Prayer of Mending indicator

---

**Version:** 6.2.0  
**Release Date:** January 10, 2026  
**Compatibility:** Turtle WoW 1.18.0  
**Optional DLLs:** SuperWoW, Nampower, UnitXP_SP3 (enhanced features when available)

---

## Installation
1. Download **[Latest Version](https://github.com/me0wg4ming/pfUI/archive/master.zip)**
2. Unpack the Zip file
3. Rename the folder "pfUI-master" to "pfUI"
4. Copy "pfUI" into Wow-Directory\Interface\AddOns
5. Restart Wow

## Optional DLL Enhancements

pfUI 6.0.0 includes optional integrations with client-side DLLs for enhanced functionality. These DLLs are fully supported on Turtle WoW:

### SuperWoW
**Repository:** [https://github.com/balakethelock/SuperWoW](https://github.com/balakethelock/SuperWoW)

Provides:
- Enhanced castbar detection via UNIT_CASTEVENT
- UnitPosition for distance calculations
- SetMouseoverUnit for improved targeting
- SpellInfo for spell data queries

### Nampower
**Repository:** [https://gitea.com/avitasia/nampower](https://gitea.com/avitasia/nampower)

Provides:
- Spell queue indicator
- GCD indicator
- Reactive spell detection
- Enhanced cast information

### UnitXP_SP3
**Repository:** [https://codeberg.org/konaka/UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3)

Provides:
- Line of Sight detection
- Behind detection
- Accurate distance calculations
- OS notifications

Use `/pfdll` in-game to check which DLLs are detected.

## Commands

    /pfui         Open the configuration GUI
    /pfdll        Show DLL detection status (SuperWoW, Nampower, UnitXP)
    /pfbehind     Test Behind/LOS detection on current target
    /clickthrough Toggle clickthrough mode (or /ct)
    /share        Open the configuration import/export dialog
    /gm           Open the ticket Dialog
    /rl           Reload the whole UI
    /farm         Toggles the Farm-Mode
    /pfcast       Same as /cast but for mouseover units
    /focus        Creates a Focus-Frame for the current target
    /castfocus    Same as /cast but for focus frame
    /clearfocus   Clears the Focus-Frame
    /swapfocus    Toggle Focus and Target-Frame
    /pftest       Toggle pfUI Unitframe Test Mode
    /abp          Addon Button Panel

## Languages
pfUI supports and contains language specific code for the following gameclients.
* English (enUS)
* Korean (koKR)
* French (frFR)
* German (deDE)
* Chinese (zhCN)
* Spanish (esES)
* Russian (ruRU)

## Recommended Addons
* [pfQuest](https://shagu.org/pfQuest) A simple database and quest helper
* [WIM (continued)](https://github.com/me0wg4ming/WIM/) Give whispers an instant messenger feel

## Plugins
* [pfUI-eliteoverlay](https://shagu.org/pfUI-eliteoverlay) Add elite dragons to unitframes
* [pfUI-fonts](https://shagu.org/pfUI-fonts) Additional fonts for pfUI
* [pfUI-CustomMedia](https://github.com/mrrosh/pfUI-CustomMedia) Additional textures for pfUI
* [pfUI-Gryphons](https://github.com/mrrosh/pfUI-Gryphons) Add back the gryphons to your actionbars

## FAQ
**What does "pfUI" stand for?**  
The term "*pfui!*" is german and simply stands for "*pooh!*", because I'm not a
big fan of creating configuration UI's, especially not via the Wow-API
(you might have noticed that in ShaguUI).

**How can I donate?**  
You can donate via [GitHub](https://github.com/sponsors/shagu) or [Ko-fi](https://ko-fi.com/shagu)

**How do I report a Bug?**  
Please provide as much information as possible in the [Bugtracker](https://github.com/me0wg4ming/pfUI/issues).
If there is an error message, provide the full content of it. Just telling that "there is an error" won't help any of us.
Please consider adding additional information such as: since when did you got the error,
does it still happen using a clean configuration, what other addons are loaded and which version you're running.
When playing with a non-english client, the language might be relevant too. If possible, explain how people can reproduce the issue.

**How can I contribute?**
Report errors and issues in the [Bugtracker](https://github.com/me0wg4ming/pfUI/issues).
Please make sure to have the latest version installed and check for conflicting addons beforehand.

**I have bad performance, what can I do?**  
Version 6.0.0 includes significant performance optimizations. If you still experience issues:
1. Disable "Frame Shadows" in Settings → Appearance → Enable Frame Shadows
2. Check `/pfdll` to see which DLLs are active (some features require DLLs)
3. Disable all AddOns but pfUI and enable one-by-one to identify conflicts
4. Report issues via the [Bugtracker](https://github.com/me0wg4ming/pfUI/issues)

**Where is the happiness indicator for pets?**  
The pet happiness is shown as the color of your pet's frame. Depending on your skin, this can either be the text or the background color of your pet's healthbar:

- Green = Happy
- Yellow = Content
- Red = Unhappy

Since version 4.0.7 there is also an additional icon that can be enabled from the pet unit frame options.

**Can I use Clique with pfUI?**  
This addon already includes support for clickcasting. If you still want to make use of clique, all pfUI's unitframes are already compatible to Clique-TBC. For Vanilla, a pfUI compatible version can be found [Here](https://github.com/shagu/Clique/archive/master.zip). If you want to keep your current version of Clique, you'll have to apply this [Patch](https://github.com/shagu/Clique/commit/a5ee56c3f803afbdda07bae9cd330e0d4a75d75a).

**Where is the Experience Bar?**  
The experience bar shows up on mouseover and whenever you gain experience, next to left chatframe by default. There's also an option to make it stay visible all the time.

**How do I show the Damage- and Threatmeter Dock?**  
If you enabled the "dock"-feature for your external (third-party) meters such as DPSMate or KTM, then you'll be able to toggle between them and the Right Chat by clicking on the ">" symbol on the bottom-right panel.

**Why is my chat always resetting to only 3 lines of text?**  
This happens if "Simple Chat" is enabled in blizzards interface settings (Advanced Options).
Paste the following command into your chat to disable that option: `/run SIMPLE_CHAT="0"; pfUI.chat.SetupPositions(); ReloadUI()`

**How can I enable mouseover cast?**  
On Vanilla, create a macro with "/pfcast SPELLNAME". If you also want to see the cooldown, You might want to add "/run if nil then CastSpellByName("SPELLNAME") end" on top of the macro.

**Everything from scratch?! Are you insane?**  
Most probably, yes.

---

## 🤝 Credits & Acknowledgments

- **Shagu** - Original pfUI creator ([https://github.com/shagu/pfUI](https://github.com/shagu/pfUI))
- **me0wg4ming** - pfUI fork maintainer and Turtle WoW enhancements
- **jrc13245** - Nampower, UnitXP, and BGScore module integration ([https://github.com/jrc13245/](https://github.com/jrc13245/))
- **SuperWoW Team** - SuperWoW framework development
- **avitasia** - Nampower DLL development
- **konaka** - UnitXP_SP3 DLL development
- **Turtle WoW Team** - For the amazing Vanilla+ experience
- **Community** - Bug reports, feature suggestions, and testing

---

## 📄 License

Same as original pfUI - free to use and modify.

---

**Version:** 7.7.0
**Release Date:** February 25, 2026  
**Compatibility:** Turtle WoW 1.18.0  
**Status:** Stable