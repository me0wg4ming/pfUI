pfUI:RegisterModule("player", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  PlayerFrame:Hide()
  PlayerFrame:UnregisterAllEvents()

  pfUI.uf.player = pfUI.uf:CreateUnitFrame("Player", nil, C.unitframes.player)

  pfUI.uf.player:UpdateFrameSize()
  pfUI.uf.player:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -75, 125)
  UpdateMovable(pfUI.uf.player)

  -- infoTopCenterText: used to display haste / spell power above health bar
  local playerFrame = pfUI.uf.player
  if not playerFrame.infoTopCenterText then
    playerFrame.infoTopCenterText = playerFrame.texts:CreateFontString(nil, "OVERLAY")
    playerFrame.infoTopCenterText:SetFontObject(GameFontWhite)
    local cfg = playerFrame.config
    local fontname, fontsize, fontstyle
    if cfg.customfont == "1" then
      fontname = pfUI.media[cfg.customfont_name]
      fontsize = tonumber(cfg.customfont_size)
      fontstyle = cfg.customfont_style
    else
      fontname = pfUI.font_unit
      fontsize = tonumber(C.global.font_unit_size)
      fontstyle = C.global.font_unit_style
    end
    playerFrame.infoTopCenterText:SetFont(fontname, fontsize, fontstyle)
    playerFrame.infoTopCenterText:SetJustifyH("CENTER")
    playerFrame.infoTopCenterText:SetPoint("TOPLEFT", playerFrame.hp.bar, "TOPLEFT", 0, 0)
    playerFrame.infoTopCenterText:SetPoint("TOPRIGHT", playerFrame.hp.bar, "TOPRIGHT", 0, 0)
    playerFrame.infoTopCenterText:SetHeight(14)
  end

  local _, myclass = UnitClass("player")
  playerFrame.myclass = myclass
  playerFrame.isSpellCaster = myclass ~= "WARRIOR" and myclass ~= "ROGUE" and myclass ~= "HUNTER"

  -- Compute class-based casting speed modifier and cache on the frame.
  -- This is re-evaluated on LEARNED_SPELL_IN_TAB (with 1s delay) so talent changes are handled.
  -- Not sure if there are any other effects that give % cast reduction time
  local function UpdatePlayerModCastingTime()
    playerFrame.modCastingTime = 1
    if myclass == "MAGE" then
      local _, _, _, _, acceleratedArcana = GetTalentInfo(1, 16)
      if acceleratedArcana and acceleratedArcana > 0 then
        playerFrame.modCastingTime = 0.95
      end
    elseif myclass == "WARLOCK" then
      local _, _, _, _, rapidDeter = GetTalentInfo(1, 14)
      if rapidDeter and rapidDeter > 0 then
        playerFrame.modCastingTime = 1 - (rapidDeter * 0.03)
      end
    end
  end

  UpdatePlayerModCastingTime()

  local talentFrame = CreateFrame("Frame")
  talentFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
  talentFrame:SetScript("OnEvent", function()
    -- Debounce LEARNED_SPELL_IN_TAB by delaying 1s
    local checkAt = GetTime() + 1
    talentFrame:SetScript("OnUpdate", function()
      if GetTime() >= checkAt then
        talentFrame:SetScript("OnUpdate", nil)
        UpdatePlayerModCastingTime()
      end
    end)
  end)

  -- Convert "r,g,b,a" config color string to a 6-char hex string, or nil if unset
  local function cfgColorToHex(colorStr)
    if not colorStr or colorStr == "" then return nil end
    local r, g, b = strsplit(",", colorStr)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b then return nil end
    return string.format("%02X%02X%02X", r * 255, g * 255, b * 255)
  end

  -- SP school colors indexed by GetSpellPower("net") return order
  -- (1=phys, 2=holy, 3=fire, 4=nature, 5=frost, 6=shadow, 7=arcane)
  local spColors = { "FFFFFF", "FFFF80", "FF8000", "4DFF4D", "80FFFF", "9482C9", "FFFFFF" }

  -- Default SP school per class used as tiebreaker when multiple schools are equal
  local spDefaultSchool = {
    PALADIN = 2, PRIEST  = 2,
    SHAMAN  = 4, DRUID   = 4,
    MAGE    = 7, WARLOCK = 6,
  }

  -- Compute and cache the haste/SP text; called from OnUpdate, throttled to 0.25s
  local function UpdateInfoText()
    local cfg = playerFrame.config
    if not cfg then
      return
    end
    local hasteMode = cfg.display_haste  -- "0"=none, "1"=modCastSpeed, "2"=modCastSpeed*modCastingTime
    local showSP = cfg.display_spellpower == "1"

    local isSpellCaster = playerFrame.isSpellCaster
    if (hasteMode == "0" or not isSpellCaster) and not showSP then
      playerFrame.infoTopCenterText:SetText("")
      return
    end

    local haste = GetUnitField("player", "modCastSpeed")
    local modCastingTime = playerFrame.modCastingTime or 1
    local text = ""

    if isSpellCaster and haste then
      local hasteHex = cfgColorToHex(cfg.display_haste_color) or "FFFFFF"
      if hasteMode == "1" then
        text = string.format("|cff%s%.1f%%|r", hasteHex, (1 / haste - 1) * 100)
      elseif hasteMode == "2" then
        text = string.format("|cff%s%.1f%%|r", hasteHex, (1 / (haste * modCastingTime) - 1) * 100)
      end
    end

    if showSP and isSpellCaster then
      local schools = { GetSpellPower("net") }
      local defSchool = spDefaultSchool[myclass] or 2
      local maxSP = schools[defSchool] or 0
      local maxColor = spColors[defSchool]
      for i = 2, 7 do  -- skip physical (1)
        local v = schools[i] or 0
        if v > maxSP then
          maxSP = v
          maxColor = spColors[i]
        end
      end
      if maxSP > 0 then
        local spHex = (cfg.display_sp_color_override == "1" and cfgColorToHex(cfg.display_sp_color)) or maxColor
        if text ~= "" then text = text .. "    " end
        text = text .. string.format("|cff%s+%d SP|r", spHex, maxSP)
      end
    end

    playerFrame.infoTopCenterText:SetText(text)
  end

  function playerFrame:UpdateConfig()
    UpdateInfoText()
  end

  -- Add throttle to player frame OnUpdate
  if pfUI.uf.player:GetScript("OnUpdate") then
    local originalOnUpdate = pfUI.uf.player:GetScript("OnUpdate")
    pfUI.uf.player:SetScript("OnUpdate", function()
      if (this.throttleTick or 0) > GetTime() then
        return
      end
      this.throttleTick = GetTime() + 0.05  -- Default: 20 FPS
      originalOnUpdate()
      if (this.infoTextTick or 0) <= GetTime() then
        this.infoTextTick = GetTime() + 0.25 -- Don't need to update haste/SP text as often
        UpdateInfoText()
      end
    end)
  end

  -- Replace default's RESET_INSTANCES button with an always working one
  UnitPopupButtons["RESET_INSTANCES_FIX"] = { text = RESET_INSTANCES, dist = 0 }
  for id, text in pairs(UnitPopupMenus["SELF"]) do
    if text == "RESET_INSTANCES" then
      UnitPopupMenus["SELF"][id] = "RESET_INSTANCES_FIX"
    end
  end

  hooksecurefunc("UnitPopup_OnClick", function()
    local button = this.value
    if button == "RESET_INSTANCES_FIX" then
      StaticPopup_Show("CONFIRM_RESET_INSTANCES")
    end
  end)
end)
