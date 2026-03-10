pfUI:RegisterModule("hunterbar", "vanilla", function ()
  local _,class = UnitClass("player")
  if class ~= "HUNTER" or C.bars.hunterbar == "0" then return end

  -- Wing Clip (any rank) and Arcane Shot (any rank) spell IDs.
  -- IsSpellInRange(spellId) works with any spell ID via Nampower,
  -- no actionbar slot needed.
  local WINGCLIP_ID   = 2974  -- melee range indicator (~5 yd)
  local ARCANESHOT_ID = 3044  -- ranged range indicator (~8-41 yd)

  pfUI.hunterbar = CreateFrame("Frame", "pfHunterBar", UIParent)
  pfUI.hunterbar.lastPage = nil

  -- bar switch: throttled to 0.1s
  pfUI.hunterbar:SetScript("OnUpdate", function()
    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + 0.1

    if not UnitExists("target") or not UnitCanAttack("player", "target") then
      this.lastPage = nil
      return
    end

    local melee  = IsSpellInRange(WINGCLIP_ID,   "target")
    local ranged = IsSpellInRange(ARCANESHOT_ID, "target")

    -- swap to ranged bar: out of melee range AND arcane shot in range
    if melee == 0 and ranged == 1 then
      if this.lastPage ~= 2 then
        this.lastPage = 2
        _G.CURRENT_ACTIONBAR_PAGE = 2
        ChangeActionBarPage()
      end
    -- swap to melee bar: in melee range AND arcane shot out of range
    elseif melee == 1 and ranged == 0 then
      if this.lastPage ~= 1 then
        this.lastPage = 1
        _G.CURRENT_ACTIONBAR_PAGE = 1
        ChangeActionBarPage()
      end
    end
  end)
end)