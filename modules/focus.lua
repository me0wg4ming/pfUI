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

SLASH_PFFOCUS1, SLASH_PFFOCUS2 = '/focus', '/pffocus'
function SlashCmdList.PFFOCUS(msg)
  if not pfUI.uf or not pfUI.uf.focus then return end

  -- Try GUID-based focus (Turtle WoW native)
  local unitstr = msg ~= "" and msg or "target"
  local _, guid = nil, nil
  
  if UnitExists then
    if msg ~= "" then
      -- When msg is provided, we need to target by name first to get GUID
      -- Save this for later - for now just use name-based
      pfUI.uf.focus.unitname = strlower(msg)
      pfUI.uf.focus.label = nil
      pfUI.uf.focus.id = nil
    else
      -- Get GUID from current target
      _, guid = UnitExists("target")
    end
  end
  
  if guid then
    -- GUID-based focus (works with unitframes API)
    pfUI.uf.focus.unitname = nil
    pfUI.uf.focus.label = guid
    pfUI.uf.focus.id = ""
    
    -- Update focustarget frame
    if pfUI.uf.focustarget then
      pfUI.uf.focustarget.unitname = nil
      pfUI.uf.focustarget.label = guid .. "target"
      pfUI.uf.focustarget.id = ""
    end
  elseif msg == "" and not guid then
    -- No target and no msg - clear focus
    if UnitName("target") then
      pfUI.uf.focus.unitname = strlower(UnitName("target"))
    else
      pfUI.uf.focus.unitname = nil
      pfUI.uf.focus.label = nil
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
  
  -- Check if we have GUID-based focus
  local focusGUID = pfUI.uf.focus.label
  local hasGUID = focusGUID and focusGUID ~= ""
  
  -- Nampower path with GUID targeting (if available and we have GUID focus)
  if hasGUID and CastSpellByNameNoQueue then
    local _, currentGUID = nil, nil
    if UnitExists then
      _, currentGUID = UnitExists("target")
    end
    local player = UnitIsUnit("target", "player")
    
    -- Target focus by GUID
    if TargetByGUID then
      TargetByGUID(focusGUID)
    else
      -- Fallback: use GUID as unitstring (works on Turtle)
      TargetUnit(focusGUID)
    end
    
    -- Verify we actually targeted the focus
    local _, targetGUID = nil, nil
    if UnitExists then
      _, targetGUID = UnitExists("target")
    end
    
    if targetGUID ~= focusGUID then
      -- Restore original target
      if currentGUID and TargetByGUID then
        TargetByGUID(currentGUID)
      elseif currentGUID then
        TargetUnit(currentGUID)
      elseif player then
        TargetUnit("player")
      else
        TargetLastTarget()
      end
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end
    
    -- Execute the spell cast
    if func then
      func()
    else
      CastSpellByNameNoQueue(msg)
    end
    
    -- Restore original target
    if currentGUID and TargetByGUID then
      TargetByGUID(currentGUID)
    elseif currentGUID then
      TargetUnit(currentGUID)
    elseif player then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
    
    return
  end
  
  -- Fallback: Classic target-swapping method (name-based or GUID-based)
  local skiptarget = false
  local player = UnitIsUnit("target", "player")
  local unitname = ""

  if pfUI.uf.focus.label and UnitIsUnit("target", pfUI.uf.focus.label .. pfUI.uf.focus.id) then
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

    if strlower(UnitName("target")) ~= strlower(unitname) then
      pfScanActive = nil
      TargetLastTarget()
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end
  end

  if func then
    func()
  else
    if CastSpellByNameNoQueue then
      CastSpellByNameNoQueue(msg)
    else
      CastSpellByName(msg)
    end
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

  -- Try GUID-based swap
  local _, guid = nil, nil
  if UnitExists then
    _, guid = UnitExists("target")
  end
  
  if guid then
    -- Save old focus GUID
    local oldlabel = pfUI.uf.focus.label or ""
    local oldid = pfUI.uf.focus.id or ""
    
    -- Set new focus to current target
    pfUI.uf.focus.unitname = nil
    pfUI.uf.focus.label = guid
    pfUI.uf.focus.id = ""
    
    -- Update focustarget
    if pfUI.uf.focustarget then
      pfUI.uf.focustarget.unitname = nil
      pfUI.uf.focustarget.label = guid .. "target"
      pfUI.uf.focustarget.id = ""
    end
    
    -- Target old focus
    if oldlabel and oldlabel ~= "" then
      TargetUnit(oldlabel .. oldid)
    end
  else
    -- Fallback: name-based swap
    local oldunit = UnitExists("target") and strlower(UnitName("target"))
    if oldunit and pfUI.uf.focus.unitname then
      TargetByName(pfUI.uf.focus.unitname)
      pfUI.uf.focus.unitname = oldunit
    end
  end
end
