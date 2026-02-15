-- Compatibility layer to use castbars provided by SuperWoW:
-- https://github.com/balakethelock/SuperWoW

-- DLL Status Check Command (always available)
SLASH_PFDLLSTATUS1 = "/pfdll"
SlashCmdList["PFDLLSTATUS"] = function()
  local chat = DEFAULT_CHAT_FRAME
  chat:AddMessage("|cff33ffccpfUI|r: DLL Status Check")

  -- SuperWoW
  if SUPERWOW_VERSION then
    chat:AddMessage("  |cff00ff00SuperWoW|r: v" .. tostring(SUPERWOW_VERSION))
  elseif SpellInfo or SetAutoloot then
    chat:AddMessage("  |cffffff00SuperWoW|r: Detected (old version)")
  else
    chat:AddMessage("  |cffff0000SuperWoW|r: Not detected")
  end

  -- Nampower
  if GetNampowerVersion then
    chat:AddMessage("  |cff00ff00Nampower|r: v" .. tostring(GetNampowerVersion()))
  else
    chat:AddMessage("  |cffff0000Nampower|r: Not detected")
  end

  -- UnitXP
  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if hasUnitXP then
    chat:AddMessage("  |cff00ff00UnitXP_SP3|r: Detected")
  else
    chat:AddMessage("  |cffff0000UnitXP_SP3|r: Not detected")
  end

  -- Check if castbar exists for indicator positioning
  if pfUI.castbar and pfUI.castbar.player then
    chat:AddMessage("  |cff00ff00Castbar|r: Available for indicator anchoring")
  else
    chat:AddMessage("  |cffffff00Castbar|r: Not available (indicators use fallback position)")
  end

  -- Check indicator frames
  if pfUI.uf and pfUI.uf.target then
    chat:AddMessage("  |cff00ff00Target frame|r: exists")
    if pfUI.uf.target.behindIndicator then
      chat:AddMessage("  |cff00ff00Behind indicator|r: created")
    else
      chat:AddMessage("  |cffff0000Behind indicator|r: NOT created")
    end
    if pfUI.uf.target.losIndicator then
      chat:AddMessage("  |cff00ff00LOS indicator|r: created")
    else
      chat:AddMessage("  |cffff0000LOS indicator|r: NOT created")
    end
  else
    chat:AddMessage("  |cffff0000Target frame|r: NOT found")
  end
end

-- UnitXP Behind/LOS test command
SLASH_PFBEHIND1 = "/pfbehind"
SlashCmdList["PFBEHIND"] = function()
  local chat = DEFAULT_CHAT_FRAME
  if not UnitExists("target") then
    chat:AddMessage("|cff33ffccpfUI|r: No target")
    return
  end

  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if not hasUnitXP then
    chat:AddMessage("|cff33ffccpfUI|r: UnitXP not available")
    return
  end

  local successB, behind = pcall(UnitXP, "behind", "player", "target")
  local successL, inSight = pcall(UnitXP, "inSight", "player", "target")

  chat:AddMessage("|cff33ffccpfUI|r: Behind=" .. tostring(behind) .. " LOS=" .. tostring(inSight))
end

pfUI:RegisterModule("superwow", "vanilla", function ()
  if SetAutoloot and SpellInfo and not SUPERWOW_VERSION then
    -- Turn every enchanting link that we create in the enchanting frame,
    -- from "spell:" back into "enchant:". The enchant-version is what is
    -- used by all unmodified game clients. This is required to generate
    -- usable links for everyone from the enchant frame while having SuperWoW.
    local HookGetCraftItemLink = GetCraftItemLink
    _G.GetCraftItemLink = function(index)
      local link = HookGetCraftItemLink(index)
      return string.gsub(link, "spell:", "enchant:")
    end

    -- Convert every enchanting link that we receive into a
    -- spell link, as for some reason SuperWoW can't handle
    -- enchanting links at all and requires it to be a spell.
    local HookSetItemRef = SetItemRef
    _G.SetItemRef = function(link, text, button)
      link = string.gsub(link, "enchant:", "spell:")
      HookSetItemRef(link, text, button)
    end

    local HookGameTooltipSetHyperlink = GameTooltip.SetHyperlink
    _G.GameTooltip.SetHyperlink = function(self, link)
      link = string.gsub(link, "enchant:", "spell:")
      HookGameTooltipSetHyperlink(self, link)
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffffffaaAn old version of SuperWoW was detected. Please consider updating:")
    DEFAULT_CHAT_FRAME:AddMessage("-> https://github.com/balakethelock/SuperWoW/releases/")
  end

  if SUPERWOW_VERSION == "1.5" then
    QueueFunction(function()
      local pfCombatText_AddMessage = _G.CombatText_AddMessage
      _G.CombatText_AddMessage = function(message, a, b, c, d, e, f)
        local _, _, hex = string.find(message, ".+ %[(0x.+)%]")
        if hex and UnitName(hex) then
          message = string.gsub(message, hex, UnitName(hex))
        end

        pfCombatText_AddMessage(message, a, b, c, d, e, f)
      end
    end)
  end

  -- Add native mouseover support
  if SUPERWOW_VERSION and pfUI.uf and pfUI.uf.mouseover then
    _G.SlashCmdList.PFCAST = function(msg)
      local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
      local unit = "mouseover"

      if not UnitExists(unit) then
        local frame = GetMouseFocus()
        if frame.label and frame.id then
          unit = frame.label .. frame.id
        elseif UnitExists("target") then
          unit = "target"
        elseif GetCVar("autoSelfCast") == "1" then
          unit = "player"
        else
          return
        end
      end

      if func then
        -- set mouseover to target for script if needed
        local switch_target = not UnitIsUnit("target", unit)
        if switch_target then TargetUnit(unit) end
        func()
        if switch_target then TargetLastTarget() end
      else
        -- write temporary unit name
        pfUI.uf.mouseover.unit = unit

        -- cast spell to unitstr
        CastSpellByName(msg, unit)

        -- remove temporary mouseover unit
        pfUI.uf.mouseover.unit = nil
      end
    end
  end

  -- Add support for druid mana bars
  -- Uses Nampower's GetUnitField to get base mana when in shapeshift form
  local hasNampower = (GetUnitField ~= nil)

  -- Add support for player secondary power bar (shows base mana when in shapeshift form)
  -- Works with SuperWoW OR Nampower - both extend UnitMana() to return base mana as second value
  -- Only for Druids (only class that can shapeshift in Vanilla)
  -- Controlled by "Show Druid Mana Bar" setting
  local _, playerClass = UnitClass("player")
  if hasNampower and pfUI.uf and pfUI.uf.player and playerClass == "DRUID" and pfUI_config.unitframes.druidmanabar == "1" then
    local rawborder, default_border = GetBorderSize("unitframes")
    local config = pfUI.uf.player.config

    -- Create secondary mana bar below the power bar
    local playerMana = CreateFrame("StatusBar", "pfPlayerSecondaryMana", pfUI.uf.player)
    playerMana:SetFrameStrata(pfUI.uf.player:GetFrameStrata())
    playerMana:SetFrameLevel(pfUI.uf.player:GetFrameLevel() + 5)
    playerMana:SetStatusBarTexture(pfUI.media[config.pbartexture])
    
    -- Mana color
    local manacolor = config.defcolor == "0" and config.manacolor or C.unitframes.manacolor
    local r, g, b, a = pfUI.api.strsplit(",", manacolor)
    playerMana:SetStatusBarColor(r, g, b, a)
    
    -- Use SAME size as normal power bar (pwidth/pheight from config)
    local width = config.pwidth ~= "-1" and config.pwidth or config.width
    local height = config.pheight
    playerMana:SetWidth(width)
    playerMana:SetHeight(height)
    playerMana:SetPoint("TOPLEFT", pfUI.uf.player.power, "BOTTOMLEFT", 0, -2*default_border - (config.pspace or 0))
    playerMana:SetPoint("TOPRIGHT", pfUI.uf.player.power, "BOTTOMRIGHT", 0, -2*default_border - (config.pspace or 0))
    playerMana:Hide()

    CreateBackdrop(playerMana)
    CreateBackdropShadow(playerMana)

    -- Text overlay - same font settings as power bar
    local fontname = pfUI.font_unit
    local fontsize = tonumber(pfUI_config.global.font_unit_size)
    local fontstyle = pfUI_config.global.font_unit_style

    if config.customfont == "1" then
      fontname = pfUI.media[config.customfont_name]
      fontsize = tonumber(config.customfont_size)
      fontstyle = config.customfont_style
    end

    playerMana.text = playerMana:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerMana.text:SetFontObject(GameFontWhite)
    playerMana.text:SetFont(fontname, fontsize, fontstyle)
    playerMana.text:SetPoint("CENTER", playerMana, "CENTER", 0, 0)
    
    -- Set text color like normal power bar (mana = type 0)
    local tr, tg, tb = 1, 1, 1
    if config["powercolor"] == "1" then
      tr = ManaBarColor[0].r
      tg = ManaBarColor[0].g
      tb = ManaBarColor[0].b
    end
    if C.unitframes.pastel == "1" then
      tr, tg, tb = (tr + .75) * .5, (tg + .75) * .5, (tb + .75) * .5
    end
    playerMana.text:SetTextColor(tr, tg, tb, 1)

    -- Update function
    local function UpdatePlayerSecondaryMana()
      local powerType = UnitPowerType("player")
      
      -- Only show when NOT using mana (i.e., in Bear/Cat form)
      if powerType == 0 then
        playerMana:Hide()
        return
      end

      -- Get base mana using Nampower's GetUnitField
      local baseMana, baseMaxMana
      
      if GetUnitField then
        local _, guid = UnitExists("player")
        if guid then
          baseMana = GetUnitField(guid, "power1")
          baseMaxMana = GetUnitField(guid, "maxPower1")
        end
      end

      -- Round down power values (Nampower can return decimals, especially for rage)
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        playerMana:Hide()
        return
      end

      -- Update bar
      playerMana:SetMinMaxValues(0, baseMaxMana)
      playerMana:SetValue(baseMana)

      -- Update text based on power text config (uses same setting as normal power bar)
      -- Check txtpowercenter first (centered text), then txtpowerright, then txtpowerleft
      local textConfig = config.txtpowercenter or config.txtpowerright or config.txtpowerleft
      
      if not textConfig or textConfig == "" or textConfig == "none" then
        -- No text configured - hide text
        playerMana.text:SetText("")
      elseif textConfig == "power" then
        playerMana.text:SetText(Abbreviate(baseMana))
      elseif textConfig == "powermax" then
        playerMana.text:SetText(Abbreviate(baseMaxMana))
      elseif textConfig == "powerperc" then
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        playerMana.text:SetText(perc)
      elseif textConfig == "powermiss" then
        local miss = math.ceil(baseMana - baseMaxMana)
        playerMana.text:SetText(miss == 0 and "0" or Abbreviate(miss))
      elseif textConfig == "powerdyn" then
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        if perc == 100 then
          playerMana.text:SetText(Abbreviate(baseMana))
        else
          playerMana.text:SetText(string.format("%s - %s%%", Abbreviate(baseMana), perc))
        end
      elseif textConfig == "powerminmax" then
        playerMana.text:SetText(string.format("%s/%s", Abbreviate(baseMana), Abbreviate(baseMaxMana)))
      else
        -- Default: show dynamic (value + percentage if not full)
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        if perc == 100 then
          playerMana.text:SetText(Abbreviate(baseMana))
        else
          playerMana.text:SetText(string.format("%s - %s%%", Abbreviate(baseMana), perc))
        end
      end

      playerMana:Show()
    end

    -- Register events
    playerMana:RegisterEvent("UNIT_MANA")
    playerMana:RegisterEvent("UNIT_MAXMANA")
    playerMana:RegisterEvent("UNIT_DISPLAYPOWER")
    playerMana:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    playerMana:RegisterEvent("PLAYER_LOGOUT")
    playerMana:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      if arg1 == nil or arg1 == "player" then
        UpdatePlayerSecondaryMana()
      end
    end)

    -- Initial update
    UpdatePlayerSecondaryMana()

    -- Store reference
    pfUI.uf.player.secondaryMana = playerMana
  end

  -- Add support for target secondary power bar (shows base mana when target is in shapeshift form)
  -- Works with SuperWoW OR Nampower - both extend UnitMana() to return base mana as second value
  -- Controlled by "Show Druid Mana Bar" setting - available for ALL classes
  if hasNampower and pfUI.uf and pfUI.uf.target and pfUI_config.unitframes.druidmanabar == "1" then
    local rawborder, default_border = GetBorderSize("unitframes")
    local config = pfUI.uf.target.config

    -- Create secondary mana bar below the power bar
    local targetMana = CreateFrame("StatusBar", "pfTargetSecondaryMana", pfUI.uf.target)
    targetMana:SetFrameStrata(pfUI.uf.target:GetFrameStrata())
    targetMana:SetFrameLevel(pfUI.uf.target:GetFrameLevel() + 5)
    targetMana:SetStatusBarTexture(pfUI.media[config.pbartexture])
    
    -- Mana color
    local manacolor = config.defcolor == "0" and config.manacolor or C.unitframes.manacolor
    local r, g, b, a = pfUI.api.strsplit(",", manacolor)
    targetMana:SetStatusBarColor(r, g, b, a)
    
    -- Use SAME size as normal power bar (pwidth/pheight from config)
    local width = config.pwidth ~= "-1" and config.pwidth or config.width
    local height = config.pheight  -- Same height as power bar!
    targetMana:SetWidth(width)
    targetMana:SetHeight(height)
    targetMana:SetPoint("TOPLEFT", pfUI.uf.target.power, "BOTTOMLEFT", 0, -2*default_border - (config.pspace or 0))
    targetMana:SetPoint("TOPRIGHT", pfUI.uf.target.power, "BOTTOMRIGHT", 0, -2*default_border - (config.pspace or 0))
    targetMana:Hide()

    CreateBackdrop(targetMana)
    CreateBackdropShadow(targetMana)

    -- Text overlay - same font settings as power bar
    local fontname = pfUI.font_unit
    local fontsize = tonumber(pfUI_config.global.font_unit_size)
    local fontstyle = pfUI_config.global.font_unit_style

    if config.customfont == "1" then
      fontname = pfUI.media[config.customfont_name]
      fontsize = tonumber(config.customfont_size)
      fontstyle = config.customfont_style
    end

    targetMana.text = targetMana:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetMana.text:SetFontObject(GameFontWhite)
    targetMana.text:SetFont(fontname, fontsize, fontstyle)
    targetMana.text:SetPoint("CENTER", targetMana, "CENTER", 0, 0)
    
    -- Set text color like normal power bar (mana = type 0)
    -- Uses powercolor setting and pastel effect
    local function UpdateTextColor()
      local tr, tg, tb = 1, 1, 1
      if config["powercolor"] == "1" then
        tr = ManaBarColor[0].r
        tg = ManaBarColor[0].g
        tb = ManaBarColor[0].b
      end
      if C.unitframes.pastel == "1" then
        tr, tg, tb = (tr + .75) * .5, (tg + .75) * .5, (tb + .75) * .5
      end
      targetMana.text:SetTextColor(tr, tg, tb, 1)
    end
    UpdateTextColor()

    -- Update function
    local function UpdateTargetSecondaryMana()
      if not UnitExists("target") then
        targetMana:Hide()
        return
      end

      local powerType = UnitPowerType("target")
      
      -- Only show if target is NOT using mana (i.e., in shapeshift form with energy/rage)
      if powerType == 0 then
        -- Target is using mana as primary power - no need for secondary bar
        targetMana:Hide()
        return
      end

      -- Get base mana using Nampower's GetUnitField
      local baseMana, baseMaxMana
      
      if GetUnitField then
        local _, guid = UnitExists("target")
        if guid then
          baseMana = GetUnitField(guid, "power1")
          baseMaxMana = GetUnitField(guid, "maxPower1")
        end
      end

      -- Round down power values (Nampower can return decimals, especially for rage)
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      -- Check if we got valid mana values
      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        targetMana:Hide()
        return
      end

      -- Update bar
      targetMana:SetMinMaxValues(0, baseMaxMana)
      targetMana:SetValue(baseMana)

      -- Update text based on power text config (uses same setting as normal power bar)
      local textConfig = config.txtpowercenter or config.txtpowerright or config.txtpowerleft
      
      if not textConfig or textConfig == "" or textConfig == "none" then
        targetMana.text:SetText("")
      elseif textConfig == "power" then
        targetMana.text:SetText(Abbreviate(baseMana))
      elseif textConfig == "powermax" then
        targetMana.text:SetText(Abbreviate(baseMaxMana))
      elseif textConfig == "powerperc" then
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        targetMana.text:SetText(perc)
      elseif textConfig == "powermiss" then
        local miss = math.ceil(baseMana - baseMaxMana)
        targetMana.text:SetText(miss == 0 and "0" or Abbreviate(miss))
      elseif textConfig == "powerdyn" then
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        if perc == 100 then
          targetMana.text:SetText(Abbreviate(baseMana))
        else
          targetMana.text:SetText(string.format("%s - %s%%", Abbreviate(baseMana), perc))
        end
      elseif textConfig == "powerminmax" then
        targetMana.text:SetText(string.format("%s/%s", Abbreviate(baseMana), Abbreviate(baseMaxMana)))
      else
        local perc = math.ceil(baseMana / baseMaxMana * 100)
        if perc == 100 then
          targetMana.text:SetText(Abbreviate(baseMana))
        else
          targetMana.text:SetText(string.format("%s - %s%%", Abbreviate(baseMana), perc))
        end
      end

      targetMana:Show()
    end

    -- Register events
    targetMana:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetMana:RegisterEvent("UNIT_MANA")
    targetMana:RegisterEvent("UNIT_MAXMANA")
    targetMana:RegisterEvent("UNIT_DISPLAYPOWER")
    targetMana:RegisterEvent("PLAYER_LOGOUT")
    targetMana:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      if event == "PLAYER_TARGET_CHANGED" then
        UpdateTargetSecondaryMana()
      elseif arg1 == "target" then
        UpdateTargetSecondaryMana()
      end
    end)

    -- Store reference
    pfUI.uf.target.secondaryMana = targetMana
  end


  -- Add support for guid based focus frame
  if SUPERWOW_VERSION and pfUI.uf and pfUI.uf.focus then
    local focus = function(unitstr)
      -- try to read target's unit guid
      local _, guid = UnitExists(unitstr)

      if guid and pfUI.uf.focus then
        -- update focus frame
        pfUI.uf.focus.unitname = nil
        pfUI.uf.focus.label = guid
        pfUI.uf.focus.id = ""

        -- update focustarget frame
        pfUI.uf.focustarget.unitname = nil
        pfUI.uf.focustarget.label = guid .. "target"
        pfUI.uf.focustarget.id = ""
      end

      return guid
    end

    -- optimize the builtin /castfocus and /pfcastfocus slash commands when possible by using superwow
    -- to cast directly to the focus-target-unit-guid thus skipping the need for complex target-swapping
    local legacy_cast_focus = SlashCmdList.PFCASTFOCUS
    function SlashCmdList.PFCASTFOCUS(msg)
      local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg) --10 caution
      if func then --10 caution
        legacy_cast_focus(func)
        return
      end

      if not pfUI.uf.focus.label then --50
        UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
        return
      end

      CastSpellByName(msg, pfUI.uf.focus.label) --90

      --10  if the spellcast is in fact raw lua-function we cant cast by guid    we have to fallback
      --    to the legacy method which does support func-scriptlets
      --
      --50  the superwow-approach requires just the unit-guid-label   it doesnt care about the focus.id
      --    which is typically dud anyway
      --
      --90  by using superwow to cast directly to a unit-guid we completely sidestep the complex mechanics
      --    of target-swapping altogether which is the entire point here for vastly improved ui-performance
      --    when spamming spells
    end

    -- extend the builtin /focus slash command
    local legacyfocus = SlashCmdList.PFFOCUS
    function SlashCmdList.PFFOCUS(msg)
      -- try to perform guid based focus
      local guid = focus("target")

      -- run old focus emulation
      if not guid then legacyfocus(msg) end
    end

    -- extend the builtin /swapfocus slash command
    local legacyswapfocus = SlashCmdList.PFSWAPFOCUS
    function SlashCmdList.PFSWAPFOCUS(msg)
      -- save previous focus values
      local oldlabel = pfUI.uf.focus.label or ""
      local oldid = pfUI.uf.focus.id or ""

      -- try to perform guid based focus
      local guid = focus("target")

      -- target old focus
      if guid and oldlabel and oldid then
        TargetUnit(oldlabel..oldid)
      end

      -- run old focus emulation
      if not guid then legacyswapfocus(msg) end
    end
  end

  -- NOTE: SuperWoW libdebuff enhancement removed.
  -- UNIT_CASTEVENT fires before resist/miss/dodge events arrive,
  -- which breaks the failed spell detection system in libdebuff.
  -- DoT timers use the standard hook-based fallback instead.

  -- TrackUnit API for adding group members to minimap
  -- Tracks friendly units on the minimap for easier group coordination
  if TrackUnit and C.unitframes.track_group == "1" then
    local trackFrame = CreateFrame("Frame")
    trackFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    trackFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    trackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    trackFrame:RegisterEvent("PLAYER_LOGOUT")

    trackFrame:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end

      -- Track party members
      for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsConnected(unit) then
          pcall(TrackUnit, unit)
        end
      end

      -- Track raid members
      for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsUnit(unit, "player") then
          pcall(TrackUnit, unit)
        end
      end
    end)
  end

  -- Raid Marker Targeting API
  -- Allows targeting units by raid marker ("mark1" to "mark8")
  if SUPERWOW_VERSION then
    pfUI.api.GetMarkedUnit = function(markIndex)
      local markUnit = "mark" .. markIndex
      if UnitExists(markUnit) then
        return markUnit
      end
      return nil
    end

    pfUI.api.TargetMark = function(markIndex)
      local markUnit = "mark" .. markIndex
      if UnitExists(markUnit) then
        TargetUnit(markUnit)
        return true
      end
      return false
    end

    -- Get owner of pet/totem using "owner" suffix
    pfUI.api.GetUnitOwner = function(unit)
      local ownerUnit = unit .. "owner"
      if UnitExists(ownerUnit) then
        return UnitName(ownerUnit), ownerUnit
      end
      return nil
    end
  end

  -- Enhanced SpellInfo API wrapper
  if SpellInfo then
    pfUI.api.GetSpellInfo = function(spellId)
      local name, rank, texture, minRange, maxRange = SpellInfo(spellId)
      return {
        name = name,
        rank = rank,
        texture = texture,
        minRange = minRange,
        maxRange = maxRange,
        spellId = spellId
      }
    end
  end

  -- Clickthrough Mode API
  -- Allows clicking through corpses to loot underneath
  if Clickthrough then
    pfUI.api.SetClickthrough = function(enabled)
      Clickthrough(enabled and 1 or 0)
    end

    pfUI.api.GetClickthrough = function()
      return Clickthrough() == 1
    end

    pfUI.api.ToggleClickthrough = function()
      local current = Clickthrough()
      Clickthrough(current == 1 and 0 or 1)
      return Clickthrough() == 1
    end

    -- Add slash command for clickthrough toggle
    SLASH_PFCLICKTHROUGH1 = "/clickthrough"
    SLASH_PFCLICKTHROUGH2 = "/ct"
    SlashCmdList["PFCLICKTHROUGH"] = function()
      local enabled = pfUI.api.ToggleClickthrough()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Clickthrough mode " .. (enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
    end
  end

  -- Autoloot Control API
  if SetAutoloot then
    pfUI.api.SetAutoloot = function(enabled)
      SetAutoloot(enabled and 1 or 0)
    end

    pfUI.api.GetAutoloot = function()
      return SetAutoloot() == 1
    end

    pfUI.api.ToggleAutoloot = function()
      local current = SetAutoloot()
      SetAutoloot(current == 1 and 0 or 1)
      return SetAutoloot() == 1
    end
  end

  -- GetPlayerBuffID wrapper
  if GetPlayerBuffID then
    pfUI.api.GetPlayerBuffSpellId = function(buffIndex)
      return GetPlayerBuffID(buffIndex)
    end
  end

  -- CombatLogAdd wrapper for logging
  if CombatLogAdd then
    pfUI.api.LogToCombatLog = function(text, raw)
      CombatLogAdd(text, raw and 1 or nil)
    end
  end

  -- Local Raid Markers (marks only visible to self)
  if SetRaidTarget then
    local origSetRaidTarget = SetRaidTarget
    pfUI.api.SetLocalRaidTarget = function(unit, index)
      origSetRaidTarget(unit, index, "local")
    end
  end

  -- Enhanced GetContainerItemInfo for charges
  -- SuperWoW returns charges as negative numbers
  pfUI.api.GetItemCharges = function(bag, slot)
    local texture, count = GetContainerItemInfo(bag, slot)
    if count and count < 0 then
      return math.abs(count) -- Return positive charge count
    end
    return nil -- Not a charged item
  end

  -- Weapon Enchant Info on other players
  if GetWeaponEnchantInfo then
    local origGetWeaponEnchantInfo = GetWeaponEnchantInfo
    pfUI.api.GetUnitWeaponEnchants = function(unit)
      if unit and unit ~= "player" then
        local mhName, ohName = GetWeaponEnchantInfo(unit)
        return {
          mainHand = mhName,
          offHand = ohName,
        }
      else
        local hasMainHandEnchant, mainHandExpiration, mainHandCharges, hasOffHandEnchant, offHandExpiration, offHandCharges = origGetWeaponEnchantInfo()
        return {
          mainHand = hasMainHandEnchant and true or false,
          mainHandExpiration = mainHandExpiration,
          mainHandCharges = mainHandCharges,
          offHand = hasOffHandEnchant and true or false,
          offHandExpiration = offHandExpiration,
          offHandCharges = offHandCharges,
        }
      end
    end
  end

  -- Enhance libcast with SuperWoW data for NPCs and other players
  -- Player casts use SPELLCAST_* events for proper pushback handling
  local supercast = CreateFrame("Frame")
  local playerGuid = nil

  supercast:RegisterEvent("PLAYER_ENTERING_WORLD")
  supercast:RegisterEvent("UNIT_CASTEVENT")
  supercast:RegisterEvent("PLAYER_LOGOUT")
  supercast:SetScript("OnEvent", function()
    -- Handle shutdown to prevent crash 132
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      -- Cache player GUID
      if UnitExists then
        local _, guid = UnitExists("player")
        playerGuid = guid
      end
      return
    end

    local guid = arg1
    local isPlayer = guid == playerGuid
    
    -- For non-player units: disable combat parsing events (one-time init)
    if not isPlayer and not supercast.init then
      -- disable combat parsing events in superwow mode (for non-player units)
      libcast:UnregisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
      supercast.init = true
    end

    if arg3 == "START" or arg3 == "CAST" or arg3 == "CHANNEL" then
      local target = arg2
      local event_type = arg3
      local spell_id = arg4
      local timer = arg5

      -- get spell info from spell id
      local spell, icon, _
      if SpellInfo and SpellInfo(spell_id) then
        spell, _, icon = SpellInfo(spell_id)
      end

      -- set fallback values
      spell = spell or UNKNOWN
      icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"

      -- skip on buff procs during cast
      if event_type == "CAST" then
        if not libcast.db[guid] or libcast.db[guid].cast ~= spell then
          -- ignore casts without 'START' event, while there is already another cast.
          -- those events can be for example a frost shield proc while casting frostbolt.
          -- we want to keep the cast itself, so we simply skip those.
          return
        end
      end

      -- For player: store in libcast.db[playerName] so pushback tracking works
      -- For others: store by GUID
      local dbKey = isPlayer and UnitName("player") or guid
      
      -- add cast action to the database
      if not libcast.db[dbKey] then libcast.db[dbKey] = {} end
      libcast.db[dbKey].cast = spell
      libcast.db[dbKey].rank = nil
      libcast.db[dbKey].start = GetTime()
      libcast.db[dbKey].casttime = timer or 0
      libcast.db[dbKey].icon = icon
      libcast.db[dbKey].channel = event_type == "CHANNEL" or false
    elseif arg3 == "FAIL" then
      -- For player: use playerName, for others: use GUID
      local dbKey = isPlayer and UnitName("player") or guid
      
      -- delete all cast entries
      if libcast.db[dbKey] then
        libcast.db[dbKey].cast = nil
        libcast.db[dbKey].rank = nil
        libcast.db[dbKey].start = nil
        libcast.db[dbKey].casttime = nil
        libcast.db[dbKey].icon = nil
        libcast.db[dbKey].channel = nil
      end
    end
  end)
end)
