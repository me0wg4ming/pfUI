pfUI:RegisterModule("hunterbar", function ()
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

    local wingclipInRange   = IsSpellInRange(WINGCLIP_ID,   "target")
    local arcaneshotInRange = IsSpellInRange(ARCANESHOT_ID, "target")

    -- swap to ranged bar: out of melee range AND arcane shot (8yd) in range
    if wingclipInRange == 0 and arcaneshotInRange == 1 then
      if this.lastPage ~= 2 then
        this.lastPage = 2
        _G.CURRENT_ACTIONBAR_PAGE = 2
        ChangeActionBarPage()
      end

    -- swap to melee bar: in melee range AND arcane shot (8yd) out of range
    elseif wingclipInRange == 1 and arcaneshotInRange == 0 then
      if this.lastPage ~= 1 then
        this.lastPage = 1
        _G.CURRENT_ACTIONBAR_PAGE = 1
        ChangeActionBarPage()
      end
    end
  end)
end)