-- Nampower Integration for pfUI
-- https://github.com/pepopo978/nampower

pfUI:RegisterModule("nampower", "vanilla", function ()
  -- Detect Nampower availability
  pfUI.api.hasNampower = GetNampowerVersion ~= nil

  if not pfUI.api.hasNampower then return end

  -- Enhanced health tracking using Nampower
  if pfUI.libhealth and GetUnitField then
    local originalGetUnitHealth = pfUI.libhealth.GetUnitHealth
    pfUI.libhealth.GetUnitHealth = function(self, unitstr)
      -- Try Nampower for direct health values
      local success, health = pcall(GetUnitField, unitstr, "health")
      if success and health then
        local _, max = pcall(GetUnitField, unitstr, "maxHealth")
        if max and max > 0 then
          return health, max, true
        end
      end

      -- Fallback to original estimation
      if originalGetUnitHealth then
        return originalGetUnitHealth(self, unitstr)
      end
      return 0, 0, false
    end

    -- Also enhance GetUnitHealthByName
    local originalGetUnitHealthByName = pfUI.libhealth.GetUnitHealthByName
    pfUI.libhealth.GetUnitHealthByName = function(self, unit, level, cur, max)
      -- If we have actual values from Nampower, use them
      if cur and max and cur > 100 then
        return cur, max, true
      end
      -- Fallback to original
      if originalGetUnitHealthByName then
        return originalGetUnitHealthByName(self, unit, level, cur, max)
      end
      return cur or 0, max or 0, false
    end
  end

  -- Enhanced spell range checking
  if IsSpellInRange then
    pfUI.api.IsSpellInRange = function(spell, unit)
      local success, result = pcall(IsSpellInRange, spell, unit or "target")
      if success then
        if result == 1 then
          return true
        elseif result == 0 then
          return false
        end
      end
      return nil -- Not applicable
    end
  end

  -- Expose cast info function
  if GetCastInfo then
    pfUI.api.GetCastInfo = function()
      local success, result = pcall(GetCastInfo)
      if success then
        return result
      end
      return nil
    end
  end

  -- Expose spell cooldown info
  if GetSpellIdCooldown then
    pfUI.api.GetSpellCooldown = function(spellId)
      local success, result = pcall(GetSpellIdCooldown, spellId)
      if success then
        return result
      end
      return nil
    end
  end

  -- Spell data cache for fast lookups
  pfUI.api.spellCache = pfUI.api.spellCache or {}

  -- Get spell data from ID using Nampower
  pfUI.api.GetSpellData = function(spellId)
    if not spellId then return nil end

    -- Check cache first
    if pfUI.api.spellCache[spellId] then
      return pfUI.api.spellCache[spellId]
    end

    local data = {}

    -- Try SuperWoW SpellInfo first (if available)
    if SpellInfo then
      local success, name, rank, icon, minRange, maxRange = pcall(SpellInfo, spellId)
      if success and name then
        data.name = name
        data.rank = rank
        data.icon = icon
        data.minRange = minRange
        data.maxRange = maxRange
      end
    end

    -- Try Nampower GetSpellRec for additional data
    if GetSpellRec then
      local success, rec = pcall(GetSpellRec, spellId)
      if success and rec then
        data.name = data.name or rec.name
        data.manaCost = rec.manaCost
        data.castTime = rec.castingTimeIndex
        data.spellLevel = rec.spellLevel
        data.school = rec.school
        data.powerType = rec.powerType
      end
    end

    -- Cache if we got data
    if data.name then
      pfUI.api.spellCache[spellId] = data
      return data
    end

    return nil
  end

  -- Get spell ID from name using Nampower
  if GetSpellIdForName then
    pfUI.api.GetSpellIdByName = function(spellName)
      local success, result = pcall(GetSpellIdForName, spellName)
      if success then
        return result
      end
      return nil
    end
  end
end)