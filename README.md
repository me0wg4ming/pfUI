# pfUI

[![Version](https://img.shields.io/badge/version-6.0.0-blue.svg)](https://github.com/me0wg4ming/pfUI)
[![WoW](https://img.shields.io/badge/WoW-1.12.1%20Vanilla-orange.svg)](#)
[![TBC](https://img.shields.io/badge/WoW-2.4.3%20TBC-green.svg)](https://github.com/shagu/pfUI/)
[![SuperWoW](https://img.shields.io/badge/SuperWoW-Enhanced-purple.svg)](https://github.com/balakethelock/SuperWoW)
[![Nampower](https://img.shields.io/badge/Nampower-Optional-yellow.svg)](https://gitea.com/avitasia/nampower)
[![UnitXP](https://img.shields.io/badge/UnitXP__SP3-Optional-yellow.svg)](https://codeberg.org/konaka/UnitXP_SP3)

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
- ✅ **/clickthrough** or **/ct** - Toggle clickthrough mode (click through corpses)

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

### 🔄 TBC Compatibility Preserved

All TBC-specific features remain intact:
- ✅ Commanding Shout indicator
- ✅ Misdirection indicator
- ✅ Earth Shield indicator
- ✅ Prayer of Mending indicator

---

**Version:** 6.0.0  
**Release Date:** January 5, 2026  
**Compatibility:** World of Warcraft 1.12.1 (Vanilla) & 2.4.3 (TBC)  
**Optional DLLs:** SuperWoW, Nampower, UnitXP_SP3 (enhanced features when available)

---

## Installation (Vanilla)
1. Download **[Latest Version](https://github.com/shagu/pfUI/archive/master.zip)**
2. Unpack the Zip file
3. Rename the folder "pfUI-master" to "pfUI"
4. Copy "pfUI" into Wow-Directory\Interface\AddOns
5. Restart Wow

## Installation (The Burning Crusade)
1. Download **[Latest Version](https://github.com/shagu/pfUI/archive/master.zip)**
2. Unpack the Zip file
3. Rename the folder "pfUI-master" to "pfUI-tbc"
4. Copy "pfUI-tbc" into Wow-Directory\Interface\AddOns
5. Restart Wow

## Optional DLL Enhancements

pfUI 6.0.0 includes optional integrations with client-side DLLs for enhanced functionality:

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
Please provide as much information as possible in the [Bugtracker](https://github.com/shagu/pfUI/issues).
If there is an error message, provide the full content of it. Just telling that "there is an error" won't help any of us.
Please consider adding additional information such as: since when did you got the error,
does it still happen using a clean configuration, what other addons are loaded and which version you're running.
When playing with a non-english client, the language might be relevant too. If possible, explain how people can reproduce the issue.

**How can I contribute?**
Report errors and issues in the [Bugtracker](https://github.com/shagu/pfUI/issues).
Please make sure to have the latest version installed and check for conflicting addons beforehand.

**I have bad performance, what can I do?**  
Version 6.0.0 includes significant performance optimizations. If you still experience issues:
1. Disable "Frame Shadows" in Settings → Appearance → Enable Frame Shadows
2. Check `/pfdll` to see which DLLs are active (some features require DLLs)
3. Disable all AddOns but pfUI and enable one-by-one to identify conflicts
4. Report issues via the [Bugtracker](https://github.com/shagu/pfUI/issues)

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
On Vanilla, create a macro with "/pfcast SPELLNAME". If you also want to see the cooldown, You might want to add "/run if nil then CastSpellByName("SPELLNAME") end" on top of the macro. For The Burning Crusade, just use the regular mouseover macros.

**Will there be pfUI for Activision's "Classic" remakes?**  
No, it would require an entire rewrite of the AddOn since the game is now a different one. The AddOn-API has evolved during the last 15 years and the new "Classic" versions are based on a current retail gameclient. I don't plan to play any of those new versions, so I won't be porting any of my addons to it.

**Everything from scratch?! Are you insane?**  
Most probably, yes.

---

## 🤝 Credits & Acknowledgments

- **Shagu** - Original pfUI creator ([https://github.com/shagu/pfUI](https://github.com/shagu/pfUI))
- **me0wg4ming** - pfUI fork maintainer and enhancements
- **SuperWoW Team** - SuperWoW framework development
- **avitasia** - Nampower DLL development
- **konaka** - UnitXP_SP3 DLL development
- **Community** - Bug reports, feature suggestions, and testing

---

## 📄 License

Same as original pfUI - free to use and modify.

---

**Version:** 6.0.0  
**Release Date:** January 5, 2026  
**Compatibility:** World of Warcraft 1.12.1 (Vanilla)
**Status:** Stable & Production-Ready
