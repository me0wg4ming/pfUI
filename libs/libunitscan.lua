-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libunitscan ]]--
-- A pfUI library that detects and saves all kind of unit related informations.
-- Such as level, class, elite-state and playertype. Each query causes the library
-- to automatically scan for the target if not already existing. Player-data is
-- persisted within the pfUI_playerDB where the mob data is a throw-away table.
-- The automatic target scanner is only working for vanilla due to client limitations
-- on further expansions.
--
-- When Nampower is available, the TargetByName scanner is replaced entirely by
-- a GUID-based mouseover/target scan using GetUnitField() for direct memory access.
-- This avoids TargetByName, ClearTarget, and the OnUpdate scanner entirely.
--
-- External functions:
--   GetUnitData(name, active)
--     Returns information of the given unitname. Returns nil if no match is found.
--     When nothing is found and the active flag is set, the autoscanner will
--     automatically pick it up and try to fill the missing entry by targetting the unit.
--
--     class[String] - The class of the unit
--     level[Number] - The level of the unit
--     elite[String] - The elite state of the unit (See UnitClassification())
--     player[Boolean] - Returns true if unit is a player
--     guild[String] - Returns guild name of unit is a player
--
-- Internal functions:
--   AddData(db, name, class, level, elite, guild)
--     Adds unit data to a given db. Where db should be either "players" or "mobs"
--

-- return instantly when another libunitscan is already active
if pfUI.api.libunitscan then return end

local units = { players = {}, mobs = {} }
local queue = { }

-- save Nampower's GetUnitData before we overwrite the global
local NP_GetUnitField = GetUnitField

-- reusable locals to avoid per-event allocations
local _name, _class, _level, _elite, _guild, _unit

-- Nampower: classId lives in byte1 of bytes0 (race | classId<<8 | gender<<16 | powerType<<24)
local classMap = {
  [1]="WARRIOR", [2]="PALADIN",  [3]="HUNTER", [4]="ROGUE",
  [5]="PRIEST",  [7]="SHAMAN",   [8]="MAGE",   [9]="WARLOCK",
  [11]="DRUID",
}

local function ClassFromBytes0(bytes0)
  return classMap[math.mod(math.floor(bytes0 / 256), 256)]
end

function GetUnitData(name, active)
  if units["players"][name] then
    local ret = units["players"][name]
    return ret.class, ret.level, ret.elite, true, ret.guild
  elseif units["mobs"][name] then
    local ret = units["mobs"][name]
    return ret.class, ret.level, ret.elite, nil, nil
  elseif active then
    queue[name] = true
    libunitscan:Show()
  end
end

local function AddData(db, name, class, level, elite, guild)
  if not name or not db then return end
  units[db] = units[db] or {}
  units[db][name] = units[db][name] or {}
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  units[db][name].guild = guild or units[db][name].guild
  queue[name] = nil
end

-- Nampower: scan a GUID directly (called by nameplates OnShow)
-- Allows libunitscan to cache unit data as soon as a nameplate appears,
-- without requiring the user to mouseover the unit first.
local function ScanGuid(guid, name, isPlayer)
  if not NP_GetUnitField or not guid or not name then return end
  -- skip if already cached
  if units["players"][name] or units["mobs"][name] then return end

  _level = NP_GetUnitField(guid, "level")
  _level = (_level and _level > 0) and _level or nil

  if isPlayer then
    local bytes0 = NP_GetUnitField(guid, "bytes0") or 0
    _class = ClassFromBytes0(bytes0)
    AddData("players", name, _class, _level, nil, nil)
  else
    AddData("mobs", name, nil, _level, nil)
  end
end

local libunitscan = CreateFrame("Frame", "pfUnitScan", UIParent)
libunitscan:RegisterEvent("PLAYER_ENTERING_WORLD")
libunitscan:RegisterEvent("FRIENDLIST_UPDATE")
libunitscan:RegisterEvent("GUILD_ROSTER_UPDATE")
libunitscan:RegisterEvent("RAID_ROSTER_UPDATE")
libunitscan:RegisterEvent("PARTY_MEMBERS_CHANGED")
libunitscan:RegisterEvent("PLAYER_TARGET_CHANGED")
libunitscan:RegisterEvent("WHO_LIST_UPDATE")
libunitscan:RegisterEvent("CHAT_MSG_SYSTEM")
libunitscan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
libunitscan:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then

    -- load pfUI_playerDB
    units.players = pfUI_playerDB

    -- update own character details
    _name = UnitName("player")
    _, _class = UnitClass("player")
    _level = UnitLevel("player")
    _guild = GetGuildInfo("player")
    AddData("players", _name, _class, _level, nil, _guild)

  elseif event == "FRIENDLIST_UPDATE" then
    for i = 1, GetNumFriends() do
      _name, _level, _class = GetFriendInfo(i)
      _class = L["class"][_class] or nil
      -- friendlist updates due to friend going off-line return level 0, let's not overwrite good older values
      _level = _level > 0 and _level or nil
      AddData("players", _name, _class, _level)
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    _guild = GetGuildInfo("player")
    for i = 1, GetNumGuildMembers() do
      _name, _, _, _level, _class = GetGuildRosterInfo(i)
      _class = L["class"][_class] or nil
      AddData("players", _name, _class, _level, nil, _guild)
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    for i = 1, GetNumRaidMembers() do
      _name, _, _, _level, _class = GetRaidRosterInfo(i)
      _class = L["class"][_class] or nil
      AddData("players", _name, _class, _level)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    for i = 1, GetNumPartyMembers() do
      _unit = "party" .. i
      _, _class = UnitClass(_unit)
      _name = UnitName(_unit)
      _level = UnitLevel(_unit)
      _guild = GetGuildInfo(_unit)
      AddData("players", _name, _class, _level, nil, _guild)
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    for i = 1, GetNumWhoResults() do
      _name, _guild, _level, _, _class, _ = GetWhoInfo(i)
      _class = L["class"][_class] or nil
      AddData("players", _name, _class, _level, nil, _guild)
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
    local scan = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"

    -- always use Blizzard API for mouseover/target: GetUnitField with unit tokens
    -- returns unreliable data (wrong class/level), only GUID-based nameplate scan is safe
    _name = UnitName(scan)
    if not _name then return end
    -- skip if already cached
    if units["players"][_name] or units["mobs"][_name] then return end

    if UnitIsPlayer(scan) then
      _, _class = UnitClass(scan)
      _level = UnitLevel(scan)
      _level = _level > 0 and _level or nil
      _guild = GetGuildInfo(scan)
      AddData("players", _name, _class, _level, nil, _guild)
    else
      _, _class = UnitClass(scan)
      _elite = UnitClassification(scan)
      _level = UnitLevel(scan)
      _level = _level > 0 and _level or nil
      AddData("mobs", _name, _class, _level, _elite)
    end

  end
end)

-- TargetByName scanner: only active when Nampower is NOT available.
-- With Nampower, UPDATE_MOUSEOVER_UNIT + GUID passively covers most units,
-- so the OnUpdate queue stays empty and hidden most of the time.
if pfUI.client <= 11200 then
  if NP_GetUnitField then
    -- Nampower available: nameplate ScanGuid covers most units passively
    -- OnUpdate TargetByName scanner not needed
    libunitscan:Hide()
  else
    -- Vanilla fallback: TargetByName queue scanner
    local SoundOn = PlaySound
    local SoundOff = function() return end

    libunitscan:SetScript("OnUpdate", function()
      -- don't scan when another unit is in target
      if UnitExists("target") or UnitName("target") then return end

      local name = next(queue)
      if not name then
        this:Hide()
        return
      end

      _G.PlaySound = SoundOff
      TargetByName(name, true)
      ClearTarget()
      _G.PlaySound = SoundOn

      queue[name] = nil
      -- don't Hide() here: next frame processes next queue item
    end)
  end
end

pfUI.api.libunitscan = libunitscan
pfUI.api.libunitscan.ScanGuid = ScanGuid