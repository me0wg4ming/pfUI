-- Nampower Own Debuff Tracker
-- Tracks your own debuffs using Nampower events (no tooltip scanning!)
-- Uses libdebuff for duration data
-- Requires Nampower DLL: https://gitea.com/avitasia/nampower

pfUI:RegisterModule("nampower-debuffs", "vanilla", function ()
  -- Only load if Nampower is available
  if not GetNampowerVersion then 
    return 
  end

  -- Only load if libdebuff is available
  if not pfUI.api.libdebuff then
    return
  end

  -- Create the API
  pfUI.api.nampower_debuffs = pfUI.api.nampower_debuffs or {}
  local api = pfUI.api.nampower_debuffs

  -- Storage: [guid][slot] = { spellId, name, rank, texture, stacks, start, duration }
  local myDebuffs = {}
  
  -- Player GUID
  local playerGuid = nil

  -- Safe wrapper for SuperWoW's GetSpellNameAndRankForId
  local function SafeGetSpellNameAndRank(spellId)
    if not GetSpellNameAndRankForId then return nil, nil end
    local success, name, rank = pcall(GetSpellNameAndRankForId, spellId)
    if success then
      return name, rank
    end
    return nil, nil
  end

  -- Event handler
  local tracker = CreateFrame("Frame")
  tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
  tracker:RegisterEvent("DEBUFF_ADDED_SELF")
  tracker:RegisterEvent("DEBUFF_REMOVED_SELF")
  tracker:RegisterEvent("UNIT_DIED")

  tracker:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
      -- Cache player GUID
      if UnitExists then
        local _, guid = UnitExists("player")
        playerGuid = guid
      end
      return
    end

    if event == "UNIT_DIED" then
      -- Clean up dead units
      local guid = arg1
      if guid and myDebuffs[guid] then
        myDebuffs[guid] = nil
      end
      return
    end

    -- DEBUFF events: arg1=guid, arg2=slot, arg3=spellId, arg4=stackCount, arg5=auraLevel
    local guid = arg1
    local slot = arg2
    local spellId = arg3
    local stackCount = arg4
    local auraLevel = arg5

    if not guid or not slot then return end

    if event == "DEBUFF_ADDED_SELF" then
      -- This is YOUR debuff!
      if not myDebuffs[guid] then myDebuffs[guid] = {} end

      -- Get spell info
      local spellName, spellRank, texture
      if SpellInfo then
        spellName, spellRank, texture = SpellInfo(spellId)
      end
      if not spellName then
        spellName, spellRank = SafeGetSpellNameAndRank(spellId)
      end

      if spellName then
        -- Get duration from libdebuff (uses L["debuffs"] table)
        local duration = pfUI.api.libdebuff:GetDuration(spellName, spellRank) or 0

        -- Store debuff data
        myDebuffs[guid][slot] = {
          spellId = spellId,
          name = spellName,
          rank = spellRank,
          texture = texture,
          stacks = stackCount or 1,
          start = GetTime(),
          duration = duration,
          auraLevel = auraLevel
        }
      end

    elseif event == "DEBUFF_REMOVED_SELF" then
      -- Your debuff was removed
      if myDebuffs[guid] and myDebuffs[guid][slot] then
        myDebuffs[guid][slot] = nil
      end
    end
  end)

  -- Public API: Get own debuff by slot number
  -- Returns: name, rank, texture, stacks, dtype, duration, timeleft
  function api:UnitOwnDebuff(unit, id)
    if not UnitExists then return nil end
    
    local exists, guid = UnitExists(unit)
    if not exists or not guid then return nil end

    -- Check if we have any debuffs for this unit
    if not myDebuffs[guid] then return nil end

    -- Find the Nth own debuff (id is the count, not the slot!)
    local count = 0
    for slot = 1, 16 do
      local data = myDebuffs[guid][slot]
      if data then
        -- Check if debuff is still valid
        local timeleft = -1
        if data.duration and data.duration > 0 and data.start then
          timeleft = data.duration + data.start - GetTime()
          if timeleft < 0 then
            -- Expired, clean up
            myDebuffs[guid][slot] = nil
            data = nil
          end
        end

        if data then
          count = count + 1
          if count == id then
            -- Found the Nth own debuff!
            local duration = data.duration
            
            -- Get debuff type from UnitDebuff (we don't track this)
            local _, _, _, dtype = UnitDebuff(unit, slot)
            
            -- Extract rank number
            local rankNum = nil
            if data.rank then
              rankNum = tonumber(string.match(data.rank, "%d+"))
            end

            return data.name, rankNum, data.texture, data.stacks, dtype, duration, timeleft
          end
        end
      end
    end

    return nil
  end

  -- Public API: Check if a specific slot is your debuff
  function api:IsOwnDebuff(unit, slot)
    if not UnitExists then return false end
    
    local exists, guid = UnitExists(unit)
    if not exists or not guid then return false end

    return myDebuffs[guid] and myDebuffs[guid][slot] and true or false
  end

  -- Public API: Get all own debuff slots for a unit
  function api:GetOwnDebuffSlots(unit)
    if not UnitExists then return {} end
    
    local exists, guid = UnitExists(unit)
    if not exists or not guid then return {} end

    local slots = {}
    if myDebuffs[guid] then
      for slot, data in pairs(myDebuffs[guid]) do
        -- Check if still valid
        if data.duration == 0 or (data.start + data.duration) > GetTime() then
          table.insert(slots, slot)
        end
      end
    end
    return slots
  end

  -- Debug command
  SLASH_NPDEBUFFS1 = "/npdebuffs"
  SlashCmdList["NPDEBUFFS"] = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccNampower Debuffs:|r")
    
    if not UnitExists or not UnitExists("target") then
      DEFAULT_CHAT_FRAME:AddMessage("  No target")
      return
    end
    
    local _, guid = UnitExists("target")
    if not guid then
      DEFAULT_CHAT_FRAME:AddMessage("  No GUID")
      return
    end

    if not myDebuffs[guid] then
      DEFAULT_CHAT_FRAME:AddMessage("  No debuffs on target")
      return
    end

    for slot, data in pairs(myDebuffs[guid]) do
      local timeleft = data.duration > 0 and (data.duration + data.start - GetTime()) or 0
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  Slot %d: %s | Duration: %.1f | Timeleft: %.1f", 
        slot, data.name or "unknown", data.duration, timeleft))
    end
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccNampower Debuffs loaded! Use /npdebuffs to debug|r")
end)