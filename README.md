# pfUI - Turtle WoW Edition

[![Version](https://img.shields.io/badge/version-6.2.2-blue.svg)](https://github.com/me0wg4ming/pfUI)
[![Turtle WoW](https://img.shields.io/badge/Turtle%20WoW-1.18.0-brightgreen.svg)](https://turtlecraft.gg/)
[![SuperWoW](https://img.shields.io/badge/SuperWoW-Enhanced-purple.svg)](https://github.com/balakethelock/SuperWoW)
[![Nampower](https://img.shields.io/badge/Nampower-Optional-yellow.svg)](https://gitea.com/avitasia/nampower)
[![UnitXP](https://img.shields.io/badge/UnitXP__SP3-Optional-yellow.svg)](https://codeberg.org/konaka/UnitXP_SP3)

**A pfUI fork specifically optimized for [Turtle WoW](https://turtlecraft.gg/) with full SuperWoW, Nampower, and UnitXP_SP3 DLL integration.**

This version includes significant performance improvements, DLL-enhanced features, and TBC spell indicators that work with Turtle WoW's expanded spell library.

> **Looking for TBC support?** Visit the original pfUI by Shagu: [https://github.com/shagu/pfUI](https://github.com/shagu/pfUI)

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

**Version:** 6.2.2  
**Release Date:** January 10, 2026  
**Compatibility:** Turtle WoW 1.18.0  
**Status:** Stable
