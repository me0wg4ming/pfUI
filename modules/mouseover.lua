pfUI:RegisterModule("mouseover", "vanilla", function ()
  pfUI.uf.mouseover = CreateFrame("Frame", "pfMouseOver", UIParent)

  -- Prepare a list of units that can be used via SpellTargetUnit
  local st_units = { [1] = "player", [2] = "target", [3] = "mouseover" }
  for i=1, MAX_PARTY_MEMBERS do table.insert(st_units, "party"..i) end
  for i=1, MAX_RAID_MEMBERS do table.insert(st_units, "raid"..i) end

  -- Try to find a valid (friendly) unitstring that can be used for
  -- SpellTargetUnit(unit) to avoid another target switch
  local function GetUnitString(unit)
    for index, unitstr in pairs(st_units) do
      if UnitIsUnit(unit, unitstr) then
        return unitstr
      end
    end
    return nil
  end

  -- Same as CastSpellByName but with disabled AutoSelfCast
  local function NoSelfCast(spell, onself)
    local cvar_selfcast = GetCVar("AutoSelfCast")

    if cvar_selfcast ~= "0" then
      SetCVar("AutoSelfCast", "0")
      pcall(CastSpellByName, spell, onself)
      SetCVar("AutoSelfCast", cvar_selfcast)
    else
      CastSpellByName(spell, onself)
    end
  end

  -- Check if a string looks like a GUID (0x prefixed hex)
  local function IsGUID(str)
    return str and type(str) == "string" and strsub(str, 1, 2) == "0x"
  end

  -- Resolve the best cast target for a given unit string or pfUI frame.
  -- Returns: guid (string) or nil
  local function ResolveGUID(unit)
    if not UnitExists then return nil end
    local _, guid = UnitExists(unit)
    if guid and guid ~= "0x0000000000000000" then
      return guid
    end
    return nil
  end

  _G.SLASH_PFCAST1, _G.SLASH_PFCAST2 = "/pfcast", "/pfmouse"
  function SlashCmdList.PFCAST(msg)
    local restore_target = true
    local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
    local unit = "mouseover"
    local castGUID = nil

    if UnitExists(unit) then
      -- Valid mouseover unit - try to get GUID
      if GetNampowerVersion then
        castGUID = ResolveGUID(unit)
      end
    else
      -- No mouseover unit - check hovered pfUI frame
      local frame = GetMouseFocus()

      if frame and frame.label ~= nil then
        if IsGUID(frame.label) and frame.id == "" then
          -- Frame has a cached GUID (e.g. focus frame set via /focus name)
          castGUID = frame.label
          unit = nil
        elseif frame.label and frame.id then
          -- Frame has a label+id unitstring (e.g. "party1", "raid5")
          unit = frame.label .. frame.id
          if GetNampowerVersion then
            castGUID = ResolveGUID(unit)
          end
        end
      elseif UnitExists("target") then
        unit = "target"
        if GetNampowerVersion then
          castGUID = ResolveGUID(unit)
        end
      elseif GetCVar("autoSelfCast") == "1" then
        unit = "player"
        if GetNampowerVersion then
          castGUID = ResolveGUID(unit)
        end
      else
        return
      end
    end

    -- Nampower path: cast directly via GUID, no target toggle needed
    if not func and GetNampowerVersion and castGUID then
      CastSpellByName(msg, castGUID)
      return
    end

    -- No GUID available (no Nampower) but we have a unit string
    if not unit then
      -- Had a GUID frame but no Nampower - nothing we can do
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end

    -- Classic path (no Nampower): target swap if needed
    local unitstr = not UnitCanAssist("player", "target") and UnitCanAssist("player", unit) and GetUnitString(unit)

    if UnitIsUnit("target", unit) or (not func and unitstr) then
      restore_target = false
    else
      TargetUnit(unit)
    end

    if func then
      func()
    else
      pfUI.uf.mouseover.unit = unit
      NoSelfCast(msg)
      if SpellIsTargeting() then SpellTargetUnit(unitstr or "player") end
      if SpellIsTargeting() then SpellStopTargeting() end
      pfUI.uf.mouseover.unit = nil
    end

    if restore_target then
      TargetLastTarget()
    end
  end
end)
