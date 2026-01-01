# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

pfUI is a complete UI replacement addon for World of Warcraft vanilla (1.12). It consists of ~80K lines of Lua code across 150+ files, organized into a modular architecture.

## Development Commands

There is no build system - the addon loads directly into WoW. To test changes:
1. Edit the Lua files directly
2. Reload the WoW UI with `/rl` (provided by pfUI) or `/reload`
3. Access settings with `/pfui`
4. Test unit frames with `/pftest` or `/pfuftest`

Lua syntax can be checked with:
```bash
luac -p <filename>.lua
```

## Architecture

### Entry Point and Load Order

`pfUI.lua` is the main entry point. Load order defined in TOC file:
```
pfUI.lua → init/env.xml → init/compat.xml → init/api.xml → init/libs.xml → init/skins.xml → init/modules.xml
```

### Core Global Objects

- `pfUI` - Main addon frame and namespace
- `pfUI_config` - Configuration storage (also accessible as `C` within modules)
- `pfUI_cache` - Runtime cache
- `T` - Translation table (within modules)

### Module System

Modules register using:
```lua
pfUI:RegisterModule("modulename", "vanilla", function()
  -- module code here
  -- C = pfUI_config, T = translations available
end)
```

Modules are stored in `pfUI.module` and executed with isolated environments via `setfenv()`.

### Skin System

Similar pattern for Blizzard UI reskins:
```lua
pfUI:RegisterSkin("skinname", "vanilla", function()
  -- reskin code
end)
```

### Key Directories

- `api/` - Core utilities: `api.lua` (helpers), `config.lua` (config system), `ui-widgets.lua` (UI components), `unitframes.lua` (raid/party frame system)
- `modules/` - Feature modules (actionbar, chat, nameplates, bags, etc.)
- `skins/blizzard/` - Blizzard frame reskins
- `libs/` - Custom libraries (libcast, libpredict, libdebuff, librange, etc.)
- `compat/` - Compatibility layer (vanilla.lua)
- `env/` - Localization (locales_*.lua) and translations (translations_*.lua)

### Media Path System

pfUI uses a metatable for media paths:
- `pfUI.media["img:filename"]` → resolves to addon's img/ directory
- `pfUI.media["font:filename"]` → resolves to addon's fonts/ directory

### Configuration Structure

Two-level hierarchy:
```lua
pfUI_config = {
  global = { ... },
  [modulename] = {
    [subgroup] = { entry = value }
  }
}
```

### Key Patterns

- **Event-driven**: Modules register for specific WoW events
- **Out-of-combat execution**: `pfUI.api.RunOOC(func)` queues functions to run when player leaves combat
- **Unit frame system**: Central event dispatcher in `api/unitframes.lua` with `pfUI.uf.unitmap` for frame mapping

## Large Files

Some modules are exceptionally large due to comprehensive feature sets:
- `modules/gui.lua` - 125K+ lines (settings interface)
- `modules/turtle-wow.lua` - 423K+ lines (private server extensions)
- `modules/actionbar.lua` - 55K+ lines

## DLL Integration

The addon includes integration modules for optional client DLLs:
- `modules/superwow.lua` - SuperWoW DLL integration
- `modules/nampower.lua` - Nampower DLL integration
- `modules/unitxp.lua` - UnitXP_SP3 DLL integration

These provide enhanced functionality when the corresponding DLLs are installed.
