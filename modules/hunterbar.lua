pfUI:RegisterModule("hunterbar", "vanilla", function ()
  local _,class = UnitClass("player")
  if class ~= "HUNTER" or C.bars.hunterbar == "0" then return end

  -- Wing Clip (any rank) and Arcane Shot (any rank) spell IDs.
  -- IsSpellInRange(spellId) works with any spell ID via Nampower,
  -- no actionbar slot needed.
  local WINGCLIP_ID  = 2974   -- melee range indicator (~5 yd)
  local ARCANESHOT_ID = 3044  -- ranged range indicator (~35 yd)

  -- Hysteresis: only swap TO ranged bar when Arcane Shot is actually in range.
  -- Only swap BACK to melee bar when Wing Clip is actually in range.
  -- This prevents rapid bar-flipping in the transition zone.

  pfUI.hunterbar = CreateFrame("Frame", "pfHunterBar", UIParent)

  -- track which page we last forced so we don't spam ChangeActionBarPage()
  pfUI.hunterbar.lastPage = nil

  pfUI.hunterbar:SetScript("OnUpdate", function()
    -- only act when there is a live, attackable target
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
      return
    end

    local onMeleeBar  = (_G.CURRENT_ACTIONBAR_PAGE == 1)
    local onRangedBar = (_G.CURRENT_ACTIONBAR_PAGE == 9)

    -- IsSpellInRange returns: 1 = in range, 0 = out of range, -1 = not applicable
    -- IsSpellUsable  returns: usable(0/1), outOfMana(0/1)
    -- We only swap when the *destination* condition is fully confirmed.

    if onMeleeBar then
      -- Currently on melee bar → switch to ranged bar only when:
      --   • Wing Clip is OUT of range  (we are far enough away)
      --   • Arcane Shot IS in range    (ranged attack would actually land)
      --   • Arcane Shot is usable      (not dead / phase / etc.)
      local wingclipInRange  = IsSpellInRange(WINGCLIP_ID,  "target")
      local arcaneshotInRange = IsSpellInRange(ARCANESHOT_ID, "target")
      local arcaneshotUsable  = IsSpellUsable(ARCANESHOT_ID)

      if wingclipInRange == 0 and arcaneshotInRange == 1 and arcaneshotUsable == 1 then
        if this.lastPage ~= 9 then
          this.lastPage = 9
          _G.CURRENT_ACTIONBAR_PAGE = 9
          ChangeActionBarPage()
        end
      end

    elseif onRangedBar then
      -- Currently on ranged bar → switch back to melee bar only when:
      --   • Wing Clip IS in range      (we are close enough to melee)
      --   • Wing Clip is usable        (not dead / phase / etc.)
      --   • Arcane Shot is OUT of range (fully in melee – belt-and-suspenders)
      local wingclipInRange   = IsSpellInRange(WINGCLIP_ID,  "target")
      local wingclipUsable    = IsSpellUsable(WINGCLIP_ID)
      local arcaneshotInRange = IsSpellInRange(ARCANESHOT_ID, "target")

      if wingclipInRange == 1 and wingclipUsable == 1 and arcaneshotInRange == 0 then
        if this.lastPage ~= 1 then
          this.lastPage = 1
          _G.CURRENT_ACTIONBAR_PAGE = 1
          ChangeActionBarPage()
        end
      end

    else
      -- Player manually switched to a different page → stop tracking
      -- until they return to page 1 or 9.
      this.lastPage = nil
    end
  end)
end)