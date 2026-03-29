-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libtotem ]]--
-- A pfUI library that tries to emulate the TotemAPI that was introduced in Patch 2.4.
-- It detects and saves all current totems of the player and returns information based
-- on the totem slot ID. The function GetTotemInfo is supposed to work as it would
-- on later expansions.
--
--  GetTotemInfo(id)
--    Returns totem informations on the givent totem slot
--    active, name, start, duration, icon

-- return instantly when another libtotem is already active
if pfUI.api.libtotem then return end

MAX_TOTEMS       = MAX_TOTEMS       or 4
FIRE_TOTEM_SLOT  = FIRE_TOTEM_SLOT  or 1
EARTH_TOTEM_SLOT = EARTH_TOTEM_SLOT or 2
WATER_TOTEM_SLOT = WATER_TOTEM_SLOT or 3
AIR_TOTEM_SLOT   = AIR_TOTEM_SLOT   or 4

local _, class = UnitClass("player")

local libtotem
local active = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }

-- SpellID -> { slot, duration } mapping
-- rank-specific durations are handled via spellId directly
local spellids = {
  -- FIRE (slot 1)
  [1535]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R1
  [8498]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R2
  [8499]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R3
  [11314] = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R4
  [11315] = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R5
  [8227]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R1
  [8249]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R2
  [10526] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R3
  [16387] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R4
  [8184]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R1
  [10478] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R2
  [10479] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R3
  [8190]  = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R1
  [10585] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R2
  [10586] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R3
  [10587] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R4
  [3599]  = { slot = FIRE_TOTEM_SLOT, duration = 30  }, -- Searing Totem R1
  [6363]  = { slot = FIRE_TOTEM_SLOT, duration = 35  }, -- Searing Totem R2
  [6364]  = { slot = FIRE_TOTEM_SLOT, duration = 40  }, -- Searing Totem R3
  [6365]  = { slot = FIRE_TOTEM_SLOT, duration = 45  }, -- Searing Totem R4
  [10437] = { slot = FIRE_TOTEM_SLOT, duration = 50  }, -- Searing Totem R5
  [10438] = { slot = FIRE_TOTEM_SLOT, duration = 55  }, -- Searing Totem R6

  -- EARTH (slot 2)
  [2484]  = { slot = EARTH_TOTEM_SLOT, duration = 45  }, -- Earthbind Totem
  [5730]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R1
  [6390]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R2
  [6391]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R3
  [6392]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R4
  [10427] = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R5
  [10428] = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R6
  [8071]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R1
  [8154]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R2
  [8155]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R3
  [10406] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R4
  [10407] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R5
  [10408] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R6
  [8075]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R1
  [8160]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R2
  [8161]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R3
  [10442] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R4
  [25361] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R5
  [8143]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Tremor Totem

  -- WATER (slot 3)
  [8170]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Disease Cleansing Totem
  [8185]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R1
  [10537] = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R2
  [10538] = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R3
  [5394]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R1
  [6375]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R2
  [6377]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R3
  [10462] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R4
  [10463] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R5
  [5675]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R1
  [10495] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R2
  [10496] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R3
  [10497] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R4
  [16190] = { slot = WATER_TOTEM_SLOT, duration = 12  }, -- Mana Tide Totem
  [8166]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Poison Cleansing Totem

  -- AIR (slot 4)
  [8835]  = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Grace of Air Totem R1
  [10627] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Grace of Air Totem R2
  [8177]  = { slot = AIR_TOTEM_SLOT, duration = 45  }, -- Grounding Totem
  [10595] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R1
  [10600] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R2
  [10601] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R3
  [25359] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Tranquil Air Totem
  [8512]  = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R1
  [10613] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R2
  [10614] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R3
  [15107] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R1
  [15421] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R2
  [15422] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R3
}

-- icon-based fallback table (used by CastSpell/UseAction hooks that don't have spellId)
local totems = {
  [FIRE_TOTEM_SLOT] = {
    ["Spell_Fire_SealOfFire"] = {[-1] = 5},
    ["Spell_Nature_GuardianWard"] = {[-1] = 120},
    ["Spell_FrostResistanceTotem_01"] = {[-1] = 120},
    ["Spell_Fire_SelfDestruct"] = {[-1] = 20},
    ["Spell_Fire_SearingTotem"] = {[-1] = 55,[1] = 30,[2] = 35,[3] = 40,[4] = 45,[5] = 50,[6] = 55},
  },
  [EARTH_TOTEM_SLOT] = {
    ["Spell_Nature_StrengthOfEarthTotem02"] = {[-1] = 45},
    ["Spell_Nature_StoneClawTotem"] = {[-1] = 15},
    ["Spell_Nature_StoneSkinTotem"] = {[-1] = 120},
    ["Spell_Nature_EarthBindTotem"] = {[-1] = 120},
    ["Spell_Nature_TremorTotem"] = {[-1] = 120},
  },
  [WATER_TOTEM_SLOT] = {
    ["Spell_Nature_DiseaseCleansingTotem"] = {[-1] = 120},
    ["Spell_FireResistanceTotem_01"] = {[-1] = 120},
    ["INV_Spear_04"] = {[-1] = 60},
    ["Spell_Nature_ManaRegenTotem"] = {[-1] = 60},
    ["Spell_Frost_SummonWaterElemental"] = {[-1] = 12},
    ["Spell_Nature_PoisonCleansingTotem"] = {[-1] = 120},
  },
  [AIR_TOTEM_SLOT] = {
    ["Spell_Nature_InvisibilityTotem"] = {[-1] = 120},
    ["Spell_Nature_GroundingTotem"] = {[-1] = 45},
    ["Spell_Nature_NatureResistanceTotem"] = {[-1] = 120},
    ["Spell_Nature_Brilliance"] = {[-1] = 120},
    ["Spell_Nature_Windfury"] = {[-1] = 120},
    ["Spell_Nature_EarthBind"] = {[-1] = 120},
  },
}

GetTotemInfo = function(id)
  if not active[id] or not active[id].name then return end
  if active[id].start + active[id].duration - GetTime() < 0 then
    libtotem:Clean(id)
    return nil
  end
  return 1, active[id].name, active[id].start, active[id].duration, active[id].icon
end

if class ~= "SHAMAN" then return end

libtotem = CreateFrame("Frame")
libtotem:RegisterEvent("PLAYER_DEAD")
libtotem:SetScript("OnEvent", function()
  if event == "PLAYER_DEAD" then
    for i = 1, 4 do libtotem:Clean(i) end
  end
end)

libtotem.totems = totems

libtotem.Clean = function(self, slot)
  active[slot].name = nil
  active[slot].start = nil
  active[slot].duration = nil
  active[slot].icon = nil
end

-- Direct SpellID commit (Nampower SPELL_GO_SELF, most accurate)
libtotem.CommitBySpellId = function(spellId, icon)
  local data = spellids[spellId]
  if not data then return false end
  local slot = data.slot
  active[slot].name     = active[slot].pending_name or active[slot].name
  active[slot].duration = data.duration
  active[slot].icon     = icon or active[slot].pending_icon
  active[slot].start    = GetTime()
  active[slot].pending_name = nil
  active[slot].pending_icon = nil
  return true
end

-- Fallback: icon-based lookup (for CastSpell/UseAction without spellId)
libtotem.CheckAddQueue = function(self, name, rank, icon, spellId)
  -- if we have a spellId, just store the name/icon as pending for SPELL_GO
  if spellId and spellids[spellId] then
    local slot = spellids[spellId].slot
    active[slot].pending_name = name
    active[slot].pending_icon = icon
    return true
  end

  -- icon-based fallback
  for slot = 1, 4 do
    for texture, data in pairs(totems[slot]) do
      if string.find(icon, texture, 1) then
        if rank then
          _, _, rank = string.find(rank, "%s(%d+)")
        end
        local duration
        if rank and tonumber(rank) and data[tonumber(rank)] then
          duration = data[tonumber(rank)]
        else
          duration = data[-1]
        end
        active[slot].pending_name = name
        active[slot].pending_icon = icon
        active[slot].pending_duration = duration
        return true
      end
    end
  end
  return nil
end

-- assign library to global space
pfUI.api.libtotem = libtotem

-- SPELL_GO_SELF from libdebuff: commit directly by SpellID, no queue needed
pfUI.libdebuff_spell_go_hooks = pfUI.libdebuff_spell_go_hooks or {}
pfUI.libdebuff_spell_go_hooks["libtotem"] = function(spellId)
  if not spellId then return end
  local data = spellids[spellId]
  if not data then return end
  local slot = data.slot
  -- use pending name/icon if available (set by CastSpellByName hook), else GetSpellInfo
  local name = active[slot].pending_name
  local icon = active[slot].pending_icon
  if not name and GetSpellInfo then
    name = GetSpellInfo(spellId)
  end
  active[slot].name     = name
  active[slot].duration = data.duration
  active[slot].icon     = icon
  active[slot].start    = GetTime()
  active[slot].pending_name = nil
  active[slot].pending_icon = nil
  active[slot].pending_duration = nil
end

-- Hook CastSpellByName to store pending name/icon per slot
hooksecurefunc("CastSpellByName", function(effect, target)
  local name, rank, icon, _, _, _, spellId = libspell.GetSpellInfo(effect)
  if not name then return end
  libtotem:CheckAddQueue(name, rank, icon, spellId)
end)

-- Hook CastSpell to store pending name/icon per slot
hooksecurefunc("CastSpell", function(id, bookType)
  if not id or not bookType then return end
  if bookType ~= BOOKTYPE_SPELL and bookType ~= BOOKTYPE_PET then return end
  local name, rank, icon, _, _, _, spellId = libspell.GetSpellInfo(id, bookType)
  if not name then return end
  libtotem:CheckAddQueue(name, rank, icon, spellId)
end)

-- Hook UseAction (no spellId available, icon-based fallback)
local scanner = libtipscan:GetScanner("prediction")
hooksecurefunc("UseAction", function(slot, target, selfcast)
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  scanner:SetAction(slot)
  local name, rank = scanner:Line(1)
  local icon = GetActionTexture(slot)
  if not name then return end
  libtotem:CheckAddQueue(name, rank, icon, nil)
end)