-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libunitscan ]]--
-- A pfUI library that detects and saves all kind of unit related informations.
-- Such as level, class, elite-state and playertype. Each query causes the library
-- to automatically scan for the target if not already existing. Player-data is
-- persisted within the pfUI_playerDB where the mob data is a throw-away table.
--
-- Requires Nampower. Uses GUID-based GetUnitField() for direct memory access.
-- mouseover and target are scanned via GetUnitGUID() + GetUnitField().
-- elite is the only value still read via UnitClassification() as it has no
-- equivalent in the Nampower unit fields.
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

-- save Nampower's GetUnitField before we overwrite the global
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

-- Nampower: scan a GUID directly.
-- Called by nameplates OnShow and mouseover/target events.
-- elite is passed in from UnitClassification() when available (mouseover/target only).
local function ScanGuid(guid, name, isPlayer, elite)
  if not NP_GetUnitField or not guid or not name then return end
  -- skip if already fully cached (elite only available on mouseover/target)
  if not elite and (units["players"][name] or units["mobs"][name]) then return end

  _level = NP_GetUnitField(guid, "level")
  _level = (_level and _level > 0) and _level or nil

  if isPlayer then
    local bytes0 = NP_GetUnitField(guid, "bytes0") or 0
    _class = ClassFromBytes0(bytes0)
    AddData("players", name, _class, _level, nil, nil)
  else
    AddData("mobs", name, nil, _level, elite or nil)
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

    _name = UnitName(scan)
    if not _name then return end

    local guid = GetUnitGUID(scan)
    if not guid then return end

    if UnitIsPlayer(scan) then
      -- guild requires Blizzard API, patch in after ScanGuid
      _guild = GetGuildInfo(scan)
      ScanGuid(guid, _name, true, nil)
      if units["players"][_name] then
        units["players"][_name].guild = _guild or units["players"][_name].guild
      end
    else
      -- elite has no equivalent in Nampower unit fields, only available here
      _elite = UnitClassification(scan)
      ScanGuid(guid, _name, false, _elite)
    end

  end
end)

-- Nampower: nameplate ScanGuid passively covers units as nameplates appear.
-- OnUpdate TargetByName scanner not needed with Nampower.
libunitscan:Hide()

pfUI.api.libunitscan = libunitscan
pfUI.api.libunitscan.ScanGuid = ScanGuid