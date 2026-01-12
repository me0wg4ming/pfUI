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
    queue:SetScript("OnEvent", function()
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

  -- Enhanced Debuff Tracking using Nampower events
  -- DEBUFF_ADDED_OTHER/DEBUFF_REMOVED_OTHER provide accurate debuff tracking with spellId
  if libdebuff then
    -- Storage for GUID-based debuff tracking
    pfUI.nampower_debuffs = pfUI.nampower_debuffs or {}
    local debuffdb = pfUI.nampower_debuffs

    -- Get player GUID for tracking own debuffs
    local playerGuid

    local debuffTracker = CreateFrame("Frame")
    debuffTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
    debuffTracker:RegisterEvent("DEBUFF_ADDED_OTHER")
    debuffTracker:RegisterEvent("DEBUFF_REMOVED_OTHER")
    debuffTracker:RegisterEvent("DEBUFF_ADDED_SELF")
    debuffTracker:RegisterEvent("DEBUFF_REMOVED_SELF")

    debuffTracker:SetScript("OnEvent", function()
      if event == "PLAYER_ENTERING_WORLD" then
        -- Cache player GUID
        if UnitExists then
          local _, guid = UnitExists("player")
          playerGuid = guid
        end
        return
      end

      -- DEBUFF events: arg1=guid, arg2=slot, arg3=spellId, arg4=stackCount, arg5=auraLevel
      local guid = arg1
      local slot = arg2
      local spellId = arg3
      local stackCount = arg4
      local auraLevel = arg5

      if not guid or not spellId then return end

      if event == "DEBUFF_ADDED_OTHER" or event == "DEBUFF_ADDED_SELF" then
        -- Initialize storage for this GUID
        if not debuffdb[guid] then debuffdb[guid] = {} end

        -- Get spell info
        local spellName, spellRank, texture
        if SpellInfo then
          spellName, spellRank, texture = SpellInfo(spellId)
        end
        if not spellName then
          spellName, spellRank = SafeGetSpellNameAndRank(spellId)
        end

        if spellName then
          -- Get duration from libdebuff's duration table or GetSpellRec
          local duration = 0
          if libdebuff.GetDuration then
            duration = libdebuff:GetDuration(spellName, spellRank)
          end

          -- Try GetSpellRec for duration if libdebuff doesn't have it
          if duration == 0 and GetSpellRec and spellId then
            local success, spellRec = pcall(GetSpellRec, spellId)
            if success and spellRec and spellRec.durationIndex and spellRec.durationIndex > 0 then
              -- Duration index maps to spell duration - common values:
              -- This is a rough approximation since we don't have the duration table
              duration = 30 -- Default fallback
            end
          end

          -- Store debuff data
          debuffdb[guid][spellId] = {
            spellId = spellId,
            name = spellName,
            rank = spellRank,
            texture = texture,
            stacks = stackCount or 1,
            start = GetTime(),
            duration = duration,
            slot = slot,
            auraLevel = auraLevel,
            caster = (event == "DEBUFF_ADDED_SELF" or guid == playerGuid) and "player" or nil
          }

          -- Also update libdebuff's internal tracking if we have unit info
          local unitName = UnitName and guid and UnitName(guid)
          local unitLevel = UnitLevel and guid and UnitLevel(guid)
          if unitName and duration > 0 then
            libdebuff:AddEffect(unitName, unitLevel or 0, spellName, duration, "player")
          end
        end

      elseif event == "DEBUFF_REMOVED_OTHER" or event == "DEBUFF_REMOVED_SELF" then
        -- Remove debuff from tracking
        if debuffdb[guid] and debuffdb[guid][spellId] then
          debuffdb[guid][spellId] = nil
        end
      end
    end)

    -- Enhanced UnitDebuff function that uses Nampower data
    -- This provides more accurate debuff information when available
    local originalUnitDebuff = libdebuff.UnitDebuff
    function libdebuff:UnitDebuffNampower(unit, id)
      -- First try the original method
      local effect, rank, texture, stacks, dtype, duration, timeleft, caster = originalUnitDebuff(self, unit, id)

      -- If we have Nampower data for this unit, try to enhance it
      if not UnitExists then return effect, rank, texture, stacks, dtype, duration, timeleft, caster end
      
      local exists, guid = UnitExists(unit)
      if not exists or not guid or not debuffdb[guid] then
        return effect, rank, texture, stacks, dtype, duration, timeleft, caster
      end

      -- Find the debuff by slot
      for spellId, data in pairs(debuffdb[guid]) do
        if data.slot == id then
          -- Use Nampower data for more accurate timing
          if data.duration and data.duration > 0 and data.start then
            duration = data.duration
            timeleft = data.duration + data.start - GetTime()
            if timeleft < 0 then timeleft = 0 end
            caster = data.caster
            stacks = data.stacks or stacks
          end
          break
        end
      end

      return effect, rank, texture, stacks, dtype, duration, timeleft, caster
    end

    -- Expose enhanced function
    pfUI.api.libdebuff_nampower = libdebuff.UnitDebuffNampower
  end

  -- Enhanced buff tracking using BUFF events
  if C.unitframes.nampower_buffs == "1" then
    pfUI.nampower_buffs = pfUI.nampower_buffs or {}
    local buffdb = pfUI.nampower_buffs

    local buffTracker = CreateFrame("Frame")
    buffTracker:RegisterEvent("BUFF_ADDED_OTHER")
    buffTracker:RegisterEvent("BUFF_REMOVED_OTHER")
    buffTracker:RegisterEvent("BUFF_ADDED_SELF")
    buffTracker:RegisterEvent("BUFF_REMOVED_SELF")

    buffTracker:SetScript("OnEvent", function()
      local guid = arg1
      local slot = arg2
      local spellId = arg3
      local stackCount = arg4
      local auraLevel = arg5

      if not guid or not spellId then return end

      if event == "BUFF_ADDED_OTHER" or event == "BUFF_ADDED_SELF" then
        if not buffdb[guid] then buffdb[guid] = {} end

        local spellName, spellRank, texture
        if SpellInfo then
          spellName, spellRank, texture = SpellInfo(spellId)
        end
        if not spellName then
          spellName, spellRank = SafeGetSpellNameAndRank(spellId)
        end

        if spellName then
          buffdb[guid][spellId] = {
            spellId = spellId,
            name = spellName,
            rank = spellRank,
            texture = texture,
            stacks = stackCount or 1,
            start = GetTime(),
            slot = slot,
            auraLevel = auraLevel
          }
        end
      elseif event == "BUFF_REMOVED_OTHER" or event == "BUFF_REMOVED_SELF" then
        if buffdb[guid] and buffdb[guid][spellId] then
          buffdb[guid][spellId] = nil
        end
      end
    end)
  end

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

  -- UNIT_DIED event handling
  -- Can be used to clear tracking data or trigger effects on unit death
  local deathTracker = CreateFrame("Frame")
  deathTracker:RegisterEvent("UNIT_DIED")
  deathTracker:SetScript("OnEvent", function()
    local guid = arg1
    if not guid then return end

    -- Clean up debuff tracking for dead units
    if pfUI.nampower_debuffs and pfUI.nampower_debuffs[guid] then
      pfUI.nampower_debuffs[guid] = nil
    end
    if pfUI.nampower_buffs and pfUI.nampower_buffs[guid] then
      pfUI.nampower_buffs[guid] = nil
    end
  end)

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

  -- Enhanced Heal Prediction with AURA_CAST events
  -- This helps libpredict detect HoT applications more accurately
  if libpredict then
    local auraCastFrame = CreateFrame("Frame")
    auraCastFrame:RegisterEvent("AURA_CAST_ON_SELF")
    auraCastFrame:RegisterEvent("AURA_CAST_ON_OTHER")

    auraCastFrame:SetScript("OnEvent", function()
      local casterGuid = arg1
      local targetGuid = arg2
      local spellId = arg3

      if not spellId or not targetGuid then return end

      -- Get spell name
      local spellName
      if SpellInfo then
        spellName = SpellInfo(spellId)
      end
      if not spellName then
        spellName = SafeGetSpellNameAndRank(spellId)
      end

      if not spellName then return end

      -- Check if this is a HoT spell we care about
      local hotSpells = {
        ["Rejuvenation"] = true,
        ["Renew"] = true,
        ["Regrowth"] = true,
        ["Verjüngung"] = true, -- German
        ["Erneuerung"] = true,
        ["Nachwachsen"] = true,
      }

      if hotSpells[spellName] then
        -- Signal to libpredict that a HoT was applied
        -- This can be used to update heal predictions
        if pfUI.api.libpredict and pfUI.api.libpredict.OnHotApplied then
          pfUI.api.libpredict:OnHotApplied(targetGuid, spellName, spellId)
        end
      end
    end)
  end

  -- Swing Timer Integration
  -- Track auto-attack swing timers for melee classes
  local swingFrame = CreateFrame("Frame")
  swingFrame.mainHand = { start = 0, speed = 0 }
  swingFrame.offHand = { start = 0, speed = 0 }
  swingFrame.ranged = { start = 0, speed = 0 }

  swingFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
  swingFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
  swingFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
  swingFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")

  swingFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTER_COMBAT" then
      local mainSpeed, offSpeed = UnitAttackSpeed("player")
      this.mainHand.speed = mainSpeed or 2
      this.offHand.speed = offSpeed or 0
      this.mainHand.start = GetTime()
      if this.offHand.speed > 0 then
        this.offHand.start = GetTime()
      end
    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
      -- Reset swing timer on hit/miss
      local mainSpeed, offSpeed = UnitAttackSpeed("player")
      this.mainHand.speed = mainSpeed or 2
      this.mainHand.start = GetTime()
    end
  end)

  pfUI.api.GetSwingTimers = function()
    local now = GetTime()
    local mainRemaining = swingFrame.mainHand.speed - (now - swingFrame.mainHand.start)
    local offRemaining = swingFrame.offHand.speed > 0 and (swingFrame.offHand.speed - (now - swingFrame.offHand.start)) or 0

    return {
      mainHand = {
        remaining = math.max(0, mainRemaining),
        speed = swingFrame.mainHand.speed,
        progress = swingFrame.mainHand.speed > 0 and (1 - math.max(0, mainRemaining) / swingFrame.mainHand.speed) or 0,
      },
      offHand = {
        remaining = math.max(0, offRemaining),
        speed = swingFrame.offHand.speed,
        progress = swingFrame.offHand.speed > 0 and (1 - math.max(0, offRemaining) / swingFrame.offHand.speed) or 0,
      },
    }
  end
end)