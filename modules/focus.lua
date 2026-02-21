pfUI:RegisterModule("focus", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  pfUI.uf.focus = pfUI.uf:CreateUnitFrame("Focus", nil, C.unitframes.focus, .2)
  pfUI.uf.focus:UpdateFrameSize()
  pfUI.uf.focus:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
  UpdateMovable(pfUI.uf.focus)
  pfUI.uf.focus:Hide()

  pfUI.uf.focustarget = pfUI.uf:CreateUnitFrame("FocusTarget", nil, C.unitframes.focustarget, .2)
  pfUI.uf.focustarget:UpdateFrameSize()
  pfUI.uf.focustarget:SetPoint("BOTTOMLEFT", pfUI.uf.focus, "TOP", 0, 10)
  UpdateMovable(pfUI.uf.focustarget)
  pfUI.uf.focustarget:Hide()
end)

-- register focus emulation commands for vanilla
if pfUI.client > 11200 then return end

-- Helper: set focus frame to a GUID
local function SetFocusByGUID(guid)
  pfUI.uf.focus.unitname = nil
  pfUI.uf.focus.label = guid
  pfUI.uf.focus.id = ""

  if pfUI.uf.focustarget then
    pfUI.uf.focustarget.unitname = nil
    pfUI.uf.focustarget.label = guid .. "target"
    pfUI.uf.focustarget.id = ""
  end
end

-- Helper: set focus frame by name (fallback, no Nampower)
local function SetFocusByName(name)
  pfUI.uf.focus.unitname = strlower(name)
  pfUI.uf.focus.label = nil
  pfUI.uf.focus.id = nil

  if pfUI.uf.focustarget then
    pfUI.uf.focustarget.unitname = strlower(name) .. "target"
    pfUI.uf.focustarget.label = nil
    pfUI.uf.focustarget.id = nil
  end
end

SLASH_PFFOCUS1, SLASH_PFFOCUS2 = '/focus', '/pffocus'
function SlashCmdList.PFFOCUS(msg)
  if not pfUI.uf or not pfUI.uf.focus then return end

  if msg ~= "" then
    -- Try to resolve GUID via short target swap
    if UnitExists then
      TargetByName(msg, true)
      local _, guid = UnitExists("target")
      TargetLastTarget()

      if guid and guid ~= "0x0000000000000000" then
        SetFocusByGUID(guid)
        return
      end
    end

    -- Fallback: name-based (non-Nampower clients)
    SetFocusByName(msg)
  else
    -- No msg: use current target
    if UnitExists then
      local _, guid = UnitExists("target")
      if guid and guid ~= "0x0000000000000000" then
        SetFocusByGUID(guid)
        return
      end
    end

    -- Fallback: name-based
    local name = UnitName("target")
    if name then
      SetFocusByName(name)
    end
  end
end

SLASH_PFCLEARFOCUS1, SLASH_PFCLEARFOCUS2 = '/clearfocus', '/pfclearfocus'
function SlashCmdList.PFCLEARFOCUS(msg)
  if pfUI.uf and pfUI.uf.focus then
    pfUI.uf.focus.unitname = nil
    pfUI.uf.focus.label = nil
    pfUI.uf.focus.id = nil
  end

  if pfUI.uf and pfUI.uf.focustarget then
    pfUI.uf.focustarget.unitname = nil
    pfUI.uf.focustarget.label = nil
    pfUI.uf.focustarget.id = nil
  end
end

SLASH_PFCASTFOCUS1, SLASH_PFCASTFOCUS2 = '/castfocus', '/pfcastfocus'
function SlashCmdList.PFCASTFOCUS(msg)
  if not pfUI.uf.focus or not pfUI.uf.focus:IsShown() then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
  local focusGUID = pfUI.uf.focus.label
  local hasGUID = focusGUID and focusGUID ~= "" and focusGUID ~= "0x0000000000000000"

  -- GUID-based cast (Nampower) - no target toggle needed
  if hasGUID and CastSpellByName and not func then
    CastSpellByName(msg, focusGUID)
    return
  end

  -- For lua functions with GUID: short target swap via GUID
  if hasGUID and func then
    local _, currentGUID = UnitExists("target")
    local isPlayer = UnitIsUnit("target", "player")

    TargetUnit(focusGUID)
    local _, newGUID = UnitExists("target")

    if newGUID ~= focusGUID then
      -- Could not target focus, restore and fail
      if currentGUID and currentGUID ~= "0x0000000000000000" then
        TargetUnit(currentGUID)
      elseif isPlayer then
        TargetUnit("player")
      else
        TargetLastTarget()
      end
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end

    func()

    if currentGUID and currentGUID ~= "0x0000000000000000" then
      TargetUnit(currentGUID)
    elseif isPlayer then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
    return
  end

  -- Fallback: name-based target swap (no Nampower / no GUID)
  local skiptarget = false
  local player = UnitIsUnit("target", "player")
  local unitname = ""

  if pfUI.uf.focus.label and pfUI.uf.focus.id and
     UnitIsUnit("target", pfUI.uf.focus.label .. pfUI.uf.focus.id) then
    skiptarget = true
  else
    pfScanActive = true
    if pfUI.uf.focus.label and pfUI.uf.focus.id then
      unitname = UnitName(pfUI.uf.focus.label .. pfUI.uf.focus.id)
      TargetUnit(pfUI.uf.focus.label .. pfUI.uf.focus.id)
    else
      unitname = pfUI.uf.focus.unitname
      TargetByName(pfUI.uf.focus.unitname, true)
    end

    if strlower(UnitName("target") or "") ~= strlower(unitname or "") then
      pfScanActive = nil
      TargetLastTarget()
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end
  end

  if func then
    func()
  else
    CastSpellByName(msg)
  end

  if skiptarget == false then
    pfScanActive = nil
    if player then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
  end
end

SLASH_PFSWAPFOCUS1, SLASH_PFSWAPFOCUS2 = '/swapfocus', '/pfswapfocus'
function SlashCmdList.PFSWAPFOCUS(msg)
  if not pfUI.uf or not pfUI.uf.focus then return end

  local _, guid = nil, nil
  if UnitExists then
    _, guid = UnitExists("target")
  end

  if guid and guid ~= "0x0000000000000000" then
    local oldGUID = pfUI.uf.focus.label

    SetFocusByGUID(guid)

    -- Target old focus if we had one
    if oldGUID and oldGUID ~= "" and oldGUID ~= "0x0000000000000000" then
      TargetUnit(oldGUID)
    end
  else
    -- Fallback: name-based swap
    local oldunit = UnitExists("target") and strlower(UnitName("target") or "")
    if oldunit and pfUI.uf.focus.unitname then
      TargetByName(pfUI.uf.focus.unitname, true)
      pfUI.uf.focus.unitname = oldunit
    end
  end
end