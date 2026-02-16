-- Nampower integration module
-- Provides spell queue indicator and enhanced cast information
-- Requires Nampower DLL: https://gitea.com/avitasia/nampower

pfUI:RegisterModule("nampower", "vanilla", function ()
  -- Only load if Nampower is available
  if not GetNampowerVersion then return end

  -- Safe wrapper for SuperWoW's GetSpellNameAndRankForId (may not be available)
  local function SafeGetSpellNameAndRank(spellId)
    if not GetSpellNameAndRankForId then return nil, nil end
    local success, name, rank = pcall(GetSpellNameAndRankForId, spellId)
    if success then
      return name, rank
    end
    return nil, nil
  end

  local rawborder, border = GetBorderSize()

  -- Spell Queue Indicator
  -- Shows the currently queued spell icon near the castbar
  if C.unitframes.spellqueue == "1" then
    local size = tonumber(C.unitframes.spellqueuesize) or 32

    pfUI.spellqueue = CreateFrame("Frame", "pfSpellQueue", UIParent)
    pfUI.spellqueue:SetFrameStrata("HIGH")
    pfUI.spellqueue:SetWidth(size)
    pfUI.spellqueue:SetHeight(size)
    pfUI.spellqueue:Hide()

    -- Position near player castbar if available
    if pfUI.castbar and pfUI.castbar.player then
      pfUI.spellqueue:SetPoint("LEFT", pfUI.castbar.player, "RIGHT", border*3, 0)
    else
      pfUI.spellqueue:SetPoint("CENTER", UIParent, "CENTER", 100, -100)
    end

    pfUI.spellqueue.icon = pfUI.spellqueue:CreateTexture("OVERLAY")
    pfUI.spellqueue.icon:SetAllPoints(pfUI.spellqueue)
    pfUI.spellqueue.icon:SetTexCoord(.08, .92, .08, .92)

    UpdateMovable(pfUI.spellqueue)
    CreateBackdrop(pfUI.spellqueue)
    CreateBackdropShadow(pfUI.spellqueue)

    -- Event codes from Nampower
    local ON_SWING_QUEUED = 0
    local ON_SWING_QUEUE_POPPED = 1
    local NORMAL_QUEUED = 2
    local NORMAL_QUEUE_POPPED = 3
    local NON_GCD_QUEUED = 4
    local NON_GCD_QUEUE_POPPED = 5

    local queue = CreateFrame("Frame")
    queue:RegisterEvent("SPELL_QUEUE_EVENT")
    queue:RegisterEvent("PLAYER_LOGOUT")
    queue:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      
      local eventCode = arg1
      local spellId = arg2

      if eventCode == NORMAL_QUEUED or eventCode == NON_GCD_QUEUED or eventCode == ON_SWING_QUEUED then
        -- Get spell texture from SpellInfo (SuperWoW) or GetSpellTexture
        local texture
        if SpellInfo then
          local _, _, tex = SpellInfo(spellId)
          texture = tex
        end

        if texture then
          pfUI.spellqueue.icon:SetTexture(texture)
          pfUI.spellqueue:Show()
        end
      elseif eventCode == NORMAL_QUEUE_POPPED or eventCode == NON_GCD_QUEUE_POPPED or eventCode == ON_SWING_QUEUE_POPPED then
        pfUI.spellqueue:Hide()
      end
    end)
  end

  -- NOTE: Buff tracking removed - was dead code (data collected but never used for display)

  -- Direct Aura Access API using GetUnitField
  -- Much faster than tooltip scanning - reads aura arrays directly from unit fields
  if GetUnitField then
    pfUI.api.GetUnitAuras = function(unit)
      local auras = GetUnitField(unit, "aura")
      local auraLevels = GetUnitField(unit, "auraLevels")
      local auraStacks = GetUnitField(unit, "auraApplications")

      if not auras then return nil end

      local result = {}
      for i = 1, 48 do
        local spellId = auras[i]
        if spellId and spellId > 0 then
          local name, rank, texture
          if SpellInfo then
            name, rank, texture = SpellInfo(spellId)
          end
          if not name then
            name, rank = SafeGetSpellNameAndRank(spellId)
          end

          result[i] = {
            spellId = spellId,
            name = name,
            rank = rank,
            texture = texture,
            level = auraLevels and auraLevels[i] or 0,
            stacks = auraStacks and auraStacks[i] or 1,
            isBuff = i <= 32, -- First 32 slots are buffs, rest are debuffs
          }
        end
      end
      return result
    end

    -- Quick check if unit has specific aura by spellId
    pfUI.api.UnitHasAura = function(unit, spellId)
      local auras = GetUnitField(unit, "aura")
      if not auras then return false end
      for i = 1, 48 do
        if auras[i] == spellId then return true, i end
      end
      return false
    end

    -- Get unit resistances directly
    pfUI.api.GetUnitResistances = function(unit)
      local res = GetUnitField(unit, "resistances")
      if not res then return nil end
      return {
        armor = res[1] or 0,
        holy = res[2] or 0,
        fire = res[3] or 0,
        nature = res[4] or 0,
        frost = res[5] or 0,
        shadow = res[6] or 0,
        arcane = res[7] or 0
      }
    end
  end

  -- Reactive Spell Indicator using IsSpellUsable
  -- Shows when reactive abilities like Overpower, Revenge, Execute are usable
  if IsSpellUsable and C.unitframes.reactive_indicator == "1" then
    local size = tonumber(C.unitframes.reactive_size) or 28
    local _, class = UnitClass("player")

    -- Reactive spells by class
    local reactiveSpells = {
      WARRIOR = {
        { name = "Overpower", texture = "Interface\\Icons\\Ability_MeleeDamage" },
        { name = "Revenge", texture = "Interface\\Icons\\Ability_Warrior_Revenge" },
        { name = "Execute", texture = "Interface\\Icons\\INV_Sword_48" },
      },
      ROGUE = {
        { name = "Riposte", texture = "Interface\\Icons\\Ability_Warrior_Challange" },
      },
      HUNTER = {
        { name = "Mongoose Bite", texture = "Interface\\Icons\\Ability_Hunter_SwiftStrike" },
        { name = "Counterattack", texture = "Interface\\Icons\\Ability_Warrior_Challange" },
      },
    }

    local spells = reactiveSpells[class]
    if spells then
      pfUI.reactive = CreateFrame("Frame", "pfReactiveIndicator", UIParent)
      pfUI.reactive:SetFrameStrata("HIGH")
      local spellCount = table.getn(spells)
      pfUI.reactive:SetWidth(size * spellCount + 4 * (spellCount - 1))
      pfUI.reactive:SetHeight(size)
      pfUI.reactive:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
      pfUI.reactive:Hide()

      pfUI.reactive.icons = {}
      for i, spell in ipairs(spells) do
        local icon = CreateFrame("Frame", nil, pfUI.reactive)
        icon:SetWidth(size)
        icon:SetHeight(size)
        icon:SetPoint("LEFT", pfUI.reactive, "LEFT", (i-1) * (size + 4), 0)

        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints(icon)
        icon.texture:SetTexture(spell.texture)
        icon.texture:SetTexCoord(.08, .92, .08, .92)

        icon.glow = icon:CreateTexture(nil, "OVERLAY")
        icon.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
        icon.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
        icon.glow:SetTexture(pfUI.media["img:glow"])
        icon.glow:SetVertexColor(1, 1, 0, 0.8)

        CreateBackdrop(icon)
        icon:Hide()
        icon.spellName = spell.name
        pfUI.reactive.icons[i] = icon
      end

      UpdateMovable(pfUI.reactive)

      pfUI.reactive:SetScript("OnUpdate", function()
        local anyVisible = false
        for _, icon in ipairs(this.icons) do
          local usable = IsSpellUsable(icon.spellName)
          if usable == 1 then
            icon:Show()
            anyVisible = true
          else
            icon:Hide()
          end
        end
        if anyVisible then
          this:Show()
        else
          this:Hide()
        end
      end)
    end
  end

  -- Enhanced Cooldown Tracking API using GetSpellIdCooldown
  if GetSpellIdCooldown then
    pfUI.api.GetPreciseCooldown = function(spellId)
      local cd = GetSpellIdCooldown(spellId)
      if not cd then return nil end
      return {
        onCooldown = (cd.isOnCooldown or 0) == 1,
        remaining = (cd.cooldownRemainingMs or 0) / 1000,
        remainingMs = cd.cooldownRemainingMs or 0,
        gcdRemaining = (cd.gcdCategoryRemainingMs or 0) / 1000,
        gcdRemainingMs = cd.gcdCategoryRemainingMs or 0,
        individualRemaining = (cd.individualRemainingMs or 0) / 1000,
        categoryRemaining = (cd.categoryRemainingMs or 0) / 1000,
      }
    end

    -- Item cooldown helper
    pfUI.api.GetPreciseItemCooldown = function(itemId)
      if not GetItemIdCooldown then return nil end
      local cd = GetItemIdCooldown(itemId)
      if not cd then return nil end
      return {
        onCooldown = (cd.isOnCooldown or 0) == 1,
        remaining = (cd.cooldownRemainingMs or 0) / 1000,
        remainingMs = cd.cooldownRemainingMs or 0,
      }
    end
  end

  -- UNIT_DIED event handling - placeholder for future use
  -- (Debuff/buff cleanup removed as tracking is now handled by libdebuff)

  -- Trinket Management API
  if GetTrinkets then
    pfUI.api.GetEquippedTrinkets = function()
      local trinkets = GetTrinkets()
      if not trinkets then return {} end
      local equipped = {}
      for _, trinket in pairs(trinkets) do
        if trinket and trinket.bagIndex == nil then -- nil bagIndex = equipped
          table.insert(equipped, trinket)
        end
      end
      return equipped
    end

    pfUI.api.GetTrinketCooldown = function(slot)
      if not GetTrinketCooldown then return nil end
      local cd = GetTrinketCooldown(slot)
      if cd == -1 or not cd then return nil end
      return {
        onCooldown = (cd.isOnCooldown or 0) == 1,
        remaining = (cd.cooldownRemainingMs or 0) / 1000,
        remainingMs = cd.cooldownRemainingMs or 0,
      }
    end

    pfUI.api.UseTrinket = function(slot, target)
      if not UseTrinket then return false end
      return UseTrinket(slot, target) == 1
    end
  end

  -- Nampower Item Stats API (use distinct name to avoid conflicts)
  if GetItemStats then
    pfUI.api.GetNampowerItemStats = function(itemId)
      local success, stats = pcall(GetItemStats, itemId, true)
      if not success or not stats then return nil end
      return stats
    end

    -- Quick item level lookup
    pfUI.api.GetNampowerItemLevel = function(itemId)
      if GetItemLevel then
        return GetItemLevel(itemId)
      end
      local success, stats = pcall(GetItemStats, itemId, true)
      if success and stats and stats.itemLevel then
        return stats.itemLevel
      end
      return nil
    end
  end

  -- Spell Modifiers API for damage/heal predictions
  if GetSpellModifiers then
    pfUI.api.GetSpellBonus = function(spellId, modType)
      -- modType: 0=DAMAGE, 1=DURATION, 6=RADIUS, 7=CRIT, 10=CAST_TIME, 14=COST, etc.
      local flat, percent, hasmod = GetSpellModifiers(spellId, modType or 0)
      return {
        flat = flat or 0,
        percent = percent or 0,
        hasModifier = hasmod and hasmod ~= 0,
      }
    end

    -- Common spell modifier lookups
    pfUI.api.GetSpellDamageBonus = function(spellId)
      return pfUI.api.GetSpellBonus(spellId, 0) -- DAMAGE
    end

    pfUI.api.GetSpellCritBonus = function(spellId)
      return pfUI.api.GetSpellBonus(spellId, 7) -- CRITICAL_CHANCE
    end

    pfUI.api.GetSpellCostReduction = function(spellId)
      return pfUI.api.GetSpellBonus(spellId, 14) -- COST
    end
  end

  -- Inventory/Bag API
  if GetBagItems then
    pfUI.api.GetAllBagItems = function()
      return GetBagItems()
    end

    pfUI.api.FindItem = function(itemIdOrName)
      if FindPlayerItemSlot then
        local bag, slot = FindPlayerItemSlot(itemIdOrName)
        return bag, slot
      end
      return nil, nil
    end

    pfUI.api.UseItem = function(itemIdOrName, target)
      if UseItemIdOrName then
        return UseItemIdOrName(itemIdOrName, target) == 1
      end
      return false
    end
  end

  -- Equipment Inspection API
  if GetEquippedItems then
    pfUI.api.GetPlayerEquipment = function()
      return GetEquippedItems("player")
    end

    pfUI.api.GetTargetEquipment = function()
      return GetEquippedItems("target")
    end

    pfUI.api.GetEquippedItemInfo = function(unit, slot)
      if GetEquippedItem then
        return GetEquippedItem(unit, slot)
      end
      return nil
    end
  end

  -- Spell Lookup Helpers
  if GetSpellIdForName then
    pfUI.api.GetMaxRankSpellId = function(spellName)
      return GetSpellIdForName(spellName)
    end
  end

  if GetSpellSlotTypeIdForName then
    pfUI.api.GetSpellSlotInfo = function(spellName)
      local slot, bookType, spellId = GetSpellSlotTypeIdForName(spellName)
      return {
        slot = slot,
        bookType = bookType,
        spellId = spellId,
      }
    end
  end

  -- Queue Script API for advanced macro functionality
  if QueueScript then
    pfUI.api.QueueLuaScript = function(script, priority)
      QueueScript(script, priority or 1)
    end
  end

  if QueueSpellByName then
    pfUI.api.QueueSpell = function(spellName)
      QueueSpellByName(spellName)
    end
  end

  -- Channel optimization
  if ChannelStopCastingNextTick then
    pfUI.api.StopChannelNextTick = function()
      ChannelStopCastingNextTick()
    end
  end

  -- Spell Database Access via GetSpellRec
  if GetSpellRec then
    pfUI.api.GetSpellRecord = function(spellId)
      local success, rec = pcall(GetSpellRec, spellId)
      if not success or not rec then return nil end
      return {
        spellId = spellId,
        name = rec.name or "",
        rank = rec.rank or "",
        description = rec.description or "",
        manaCost = rec.manaCost or 0,
        baseLevel = rec.baseLevel or 0,
        spellLevel = rec.spellLevel or 0,
        maxLevel = rec.maxLevel or 0,
        maxTargetLevel = rec.maxTargetLevel or 0,
        maxTargets = rec.maxTargets or 0,
        durationIndex = rec.durationIndex or 0,
        powerType = rec.powerType or 0,
        rangeIndex = rec.rangeIndex or 0,
        speed = rec.speed or 0,
        schoolMask = rec.schoolMask or 0,
        runeCostID = rec.runeCostID or 0,
        spellMissileID = rec.spellMissileID or 0,
        iconID = rec.iconID or 0,
        activeIconID = rec.activeIconID or 0,
        nameSubtext = rec.nameSubtext or "",
        castingTimeIndex = rec.castingTimeIndex or 0,
        categoryRecoveryTime = rec.categoryRecoveryTime or 0,
        recoveryTime = rec.recoveryTime or 0,
        startRecoveryCategory = rec.startRecoveryCategory or 0,
        startRecoveryTime = rec.startRecoveryTime or 0,
      }
    end

    -- Get spell school (fire, frost, nature, etc.)
    pfUI.api.GetSpellSchool = function(spellId)
      local success, rec = pcall(GetSpellRec, spellId)
      if not success or not rec or not rec.schoolMask then return nil end
      local schools = {
        [1] = "Physical",
        [2] = "Holy",
        [4] = "Fire",
        [8] = "Nature",
        [16] = "Frost",
        [32] = "Shadow",
        [64] = "Arcane",
      }
      return schools[rec.schoolMask] or "Unknown"
    end
  end

  -- Disenchant All utility
  if DisenchantAll then
    pfUI.api.DisenchantAllItems = function()
      DisenchantAll()
    end

    SLASH_PFDISENCHANTALL1 = "/disenchantall"
    SLASH_PFDISENCHANTALL2 = "/dea"
    SlashCmdList["PFDISENCHANTALL"] = function()
      DisenchantAll()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Disenchanting all eligible items...")
    end
  end

  -- Druid Secondary Mana Bar
  -- Shows base mana when druid is in shapeshift form (Bear/Cat uses Rage/Energy)
  -- Uses Nampower's GetUnitField to get base mana values
  -- Controlled by "Show Druid Mana Bar" setting in GUI
  local _, playerClass = UnitClass("player")
  
  if GetUnitField and pfUI.uf and pfUI.uf.player and playerClass == "DRUID" and pfUI_config.unitframes.druidmanabar == "1" then
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
    
    -- Use SAME size as normal power bar
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
      local _, guid = UnitExists("player")
      
      if guid then
        baseMana = GetUnitField(guid, "power1")
        baseMaxMana = GetUnitField(guid, "maxPower1")
      end

      -- Round down power values (Nampower can return decimals)
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        playerMana:Hide()
        return
      end

      -- Update bar
      playerMana:SetMinMaxValues(0, baseMaxMana)
      playerMana:SetValue(baseMana)

      -- Update text based on power text config
      local textConfig = config.txtpowercenter or config.txtpowerright or config.txtpowerleft
      
      if not textConfig or textConfig == "" or textConfig == "none" then
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
        -- Default: show dynamic
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
  end

  -- Target Secondary Mana Bar (shows when target is a druid in shapeshift form)
  if GetUnitField and pfUI.uf and pfUI.uf.target and pfUI_config.unitframes.druidmanabar == "1" then
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
    
    -- Use SAME size as normal power bar
    local width = config.pwidth ~= "-1" and config.pwidth or config.width
    local height = config.pheight
    targetMana:SetWidth(width)
    targetMana:SetHeight(height)
    targetMana:SetPoint("TOPLEFT", pfUI.uf.target.power, "BOTTOMLEFT", 0, -2*default_border - (config.pspace or 0))
    targetMana:SetPoint("TOPRIGHT", pfUI.uf.target.power, "BOTTOMRIGHT", 0, -2*default_border - (config.pspace or 0))
    targetMana:Hide()

    CreateBackdrop(targetMana)
    CreateBackdropShadow(targetMana)

    -- Text overlay
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
    
    -- Set text color
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

    -- Update function
    local function UpdateTargetSecondaryMana()
      if not UnitExists("target") then
        targetMana:Hide()
        return
      end

      local powerType = UnitPowerType("target")
      
      -- Only show if target is NOT using mana
      if powerType == 0 then
        targetMana:Hide()
        return
      end

      -- Get base mana using Nampower's GetUnitField
      local baseMana, baseMaxMana
      local _, guid = UnitExists("target")
      
      if guid then
        baseMana = GetUnitField(guid, "power1")
        baseMaxMana = GetUnitField(guid, "maxPower1")
      end

      -- Round down power values
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        targetMana:Hide()
        return
      end

      -- Update bar
      targetMana:SetMinMaxValues(0, baseMaxMana)
      targetMana:SetValue(baseMana)

      -- Update text
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
        -- Default: show dynamic
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
    targetMana:RegisterEvent("UNIT_MANA")
    targetMana:RegisterEvent("UNIT_MAXMANA")
    targetMana:RegisterEvent("UNIT_DISPLAYPOWER")
    targetMana:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetMana:RegisterEvent("PLAYER_LOGOUT")
    targetMana:SetScript("OnEvent", function()
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      if event == "PLAYER_TARGET_CHANGED" or arg1 == nil or arg1 == "target" then
        UpdateTargetSecondaryMana()
      end
    end)

    -- Initial update
    UpdateTargetSecondaryMana()
  end
end)
