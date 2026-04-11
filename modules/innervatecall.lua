-- Innervate Callout Module
-- Announces Innervate casts via raid/party/battleground chat
-- Registers AURA_CAST events directly - zero polling, pure event-driven

pfUI:RegisterNewModule("innervatecall", "Innervate Callout", "DRUID")
pfUI:RegisterModule("innervatecall", "vanilla", function ()
  -- Requires Nampower for AURA_CAST events
  if not GetNampowerVersion then return end

  -- Only load for druids
  local _, playerClass = UnitClass("player")
  if playerClass ~= "DRUID" then return end

  local INNERVATE_SPELLID = 29166

  -- Cache player GUID
  local playerGuid = nil
  local function GetPlayerGuid()
    if not playerGuid and GetUnitGUID then
      playerGuid = GetUnitGUID("player")
    end
    return playerGuid
  end

  -- GUID → name resolution for the target
  local function ResolveTargetName(targetGuid)
    if not targetGuid or not GetUnitGUID then return nil end

    -- Check player self-cast
    if GetPlayerGuid() == targetGuid then
      return UnitName("player")
    end

    -- Check current target (most common case for other-cast)
    local curGuid = GetUnitGUID("target")
    if curGuid == targetGuid then
      return UnitName("target")
    end

    -- Scan raid/party for GUID match
    for i = 1, GetNumRaidMembers() do
      local unit = "raid" .. i
      if GetUnitGUID(unit) == targetGuid then
        return UnitName(unit)
      end
    end
    for i = 1, GetNumPartyMembers() do
      local unit = "party" .. i
      if GetUnitGUID(unit) == targetGuid then
        return UnitName(unit)
      end
    end

    return nil
  end

  -- Determine chat channel based on group context
  local function GetAnnounceChannel()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      return "BATTLEGROUND"
    end

    if GetNumRaidMembers() > 0 then
      return "RAID"
    end

    if GetNumPartyMembers() > 0 then
      return "PARTY"
    end

    return nil
  end

  -- Event frame - registers AURA_CAST directly (bypasses libdebuff hooks
  -- which are gated behind ownDebuffs/pendingCasts checks meant for debuffs)
  local frame = CreateFrame("Frame")
  -- AURA_CAST_ON_SELF fires when a buff lands ON the player
  -- AURA_CAST_ON_OTHER fires when a buff lands on someone else
  -- Both needed: self-innervate = ON_SELF, innervate on others = ON_OTHER
  -- casterGuid check prevents announcing other druids' innervates
  frame:RegisterEvent("AURA_CAST_ON_SELF")
  frame:RegisterEvent("AURA_CAST_ON_OTHER")
  frame:RegisterEvent("PLAYER_LOGOUT")
  frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    end

    -- AURA_CAST args: arg1=spellId, arg2=casterGuid, arg3=targetGuid
    local spellId = arg1
    local casterGuid = arg2
    local targetGuid = arg3

    if spellId ~= INNERVATE_SPELLID then return end

    -- Only announce our own casts
    if casterGuid ~= GetPlayerGuid() then return end

    -- Resolve target name from GUID
    local targetName = ResolveTargetName(targetGuid) or "Unknown"

    -- Determine channel
    local channel = GetAnnounceChannel()
    if not channel then return end -- solo, no announcement

    SendChatMessage(">> Innervate casted on " .. targetName .. " <<", channel)

    -- Schedule "ready" announcement when cooldown expires
    -- Use GetSpellIdCooldown for precise remaining time, fallback to 360s
    local cdRemaining = 360
    if GetSpellIdCooldown then
      local cd = GetSpellIdCooldown(INNERVATE_SPELLID)
      if cd and cd.cooldownRemainingMs and cd.cooldownRemainingMs > 0 then
        cdRemaining = cd.cooldownRemainingMs / 1000
      end
    end

    local readyAt = GetTime() + cdRemaining
    frame:SetScript("OnUpdate", function()
      if GetTime() >= readyAt then
        frame:SetScript("OnUpdate", nil)
        local ch = GetAnnounceChannel()
        if ch then
          SendChatMessage(">> Innervate is ready <<", ch)
        end
      end
    end)
  end)
end)