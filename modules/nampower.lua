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
        -- Get spell texture from GetSpellRec (Nampower) or SpellInfo (SuperWoW fallback)
        local texture
        if GetSpellRec then
          local rec = GetSpellRec(spellId)
          texture = rec and rec.spellIconID and GetSpellIconTexture(rec.spellIconID) or nil
        elseif SpellInfo then
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
          if GetSpellRec then
            local rec = GetSpellRec(spellId)
            if rec then
              name = rec.name
              rank = rec.rank
              local iconID = rec.spellIconID
              texture = iconID and GetSpellIconTexture(iconID) or nil
            end
          elseif SpellInfo then
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
  -- Fully self-contained: uses its own config settings from C.unitframes.druidmana*
  local _, playerClass = UnitClass("player")
  
  if GetUnitField and pfUI.uf and playerClass == "DRUID" and pfUI_config.unitframes.druidmanabar == "1" then
    local rawborder, default_border = GetBorderSize("unitframes")
    local DC = C.unitframes -- druid mana config lives here as druidmana* keys

    -- Shared helper: create a druid mana bar on a unit frame
    local function CreateDruidManaBar(parent, unit)
      if not parent then return nil end

      local parentConfig = parent.config

      -- Read own config values
      local dmHeight = tonumber(DC.druidmanaheight) or 10
      local dmWidth = DC.druidmanawidth or "-1"
      local dmOffX = tonumber(DC.druidmanaoffx) or 0
      local dmOffY = tonumber(DC.druidmanaoffy) or 0
      local dmSpace = tonumber(DC.druidmanaspace) or -3
      local dmTexture = DC.druidmanatexture or "Interface\\AddOns\\pfUI\\img\\bar"

      local bar = CreateFrame("StatusBar", "pfDruidMana_" .. unit, parent)
      bar:SetFrameStrata(parent:GetFrameStrata())
      bar:SetFrameLevel(parent:GetFrameLevel() + 5)
      bar:SetStatusBarTexture(pfUI.media[dmTexture] or dmTexture)

      -- Bar color: use same manacolor logic as the normal power bar
      local manacolor = parentConfig.defcolor == "0" and parentConfig.manacolor or C.unitframes.manacolor
      local r, g, b, a = pfUI.api.strsplit(",", manacolor)
      bar:SetStatusBarColor(tonumber(r) or .25, tonumber(g) or .25, tonumber(b) or 1, tonumber(a) or 1)

      -- Size: own width/height, fallback to parent power bar width if -1
      local width = dmWidth ~= "-1" and tonumber(dmWidth) or nil
      if width then
        bar:SetWidth(width)
      end
      bar:SetHeight(dmHeight)

      -- Position below the power bar with own spacing + offsets
      local spacing = -2 * default_border - dmSpace
      if width then
        -- Fixed width: use single point with offset
        bar:SetPoint("TOP", parent.power, "BOTTOM", dmOffX, spacing + dmOffY)
      else
        -- Auto width: anchor to both sides of power bar
        bar:SetPoint("TOPLEFT", parent.power, "BOTTOMLEFT", dmOffX, spacing + dmOffY)
        bar:SetPoint("TOPRIGHT", parent.power, "BOTTOMRIGHT", dmOffX, spacing + dmOffY)
      end
      bar:Hide()

      CreateBackdrop(bar)
      CreateBackdropShadow(bar)

      -- Font settings (same logic as power bar)
      local fontname = pfUI.font_unit
      local fontsize = tonumber(pfUI_config.global.font_unit_size)
      local fontstyle = pfUI_config.global.font_unit_style

      if parentConfig.customfont == "1" then
        fontname = pfUI.media[parentConfig.customfont_name]
        fontsize = tonumber(parentConfig.customfont_size)
        fontstyle = parentConfig.customfont_style
      end

      -- Text color (always mana-colored)
      local tr, tg, tb = ManaBarColor[0].r, ManaBarColor[0].g, ManaBarColor[0].b
      if C.unitframes.pastel == "1" then
        tr, tg, tb = (tr + .75) * .5, (tg + .75) * .5, (tb + .75) * .5
      end

      -- Single center text showing current/max
      bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      bar.text:SetFontObject(GameFontWhite)
      bar.text:SetFont(fontname, fontsize, fontstyle)
      bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
      bar.text:SetJustifyH("CENTER")
      bar.text:SetTextColor(tr, tg, tb, 1)

      return bar
    end

    -- Shared helper: update druid mana bar values and text
    local function UpdateDruidManaBar(bar, unit)
      if not UnitExists(unit) then
        bar:Hide()
        return
      end

      local powerType = UnitPowerType(unit)

      -- Only show when NOT using mana (i.e., in Bear/Cat form)
      if powerType == 0 then
        bar:Hide()
        return
      end

      -- Get base mana using Nampower's GetUnitField
      local baseMana, baseMaxMana
      local _, guid = UnitExists(unit)

      if guid then
        baseMana = GetUnitField(guid, "power1")
        baseMaxMana = GetUnitField(guid, "maxPower1")
      end

      -- Round down power values (Nampower can return decimals)
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        bar:Hide()
        return
      end

      -- Update bar
      bar:SetMinMaxValues(0, baseMaxMana)
      bar:SetValue(baseMana)

      -- Always show current/max
      bar.text:SetText(string.format("%s/%s", Abbreviate(baseMana), Abbreviate(baseMaxMana)))

      bar:Show()
    end

    -- ===== Player Druid Mana Bar =====
    if pfUI.uf.player then
      local playerMana = CreateDruidManaBar(pfUI.uf.player, "player")

      if playerMana then
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
            UpdateDruidManaBar(playerMana, "player")
          end
        end)

        -- Initial update
        UpdateDruidManaBar(playerMana, "player")
      end
    end

    -- ===== Target Druid Mana Bar =====
    if pfUI.uf.target then
      local targetMana = CreateDruidManaBar(pfUI.uf.target, "target")

      if targetMana then
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
            UpdateDruidManaBar(targetMana, "target")
          end
        end)

        -- Initial update
        UpdateDruidManaBar(targetMana, "target")
      end
    end
  end
end)
