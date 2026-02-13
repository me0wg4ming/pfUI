-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff - GetUnitField Edition ]]--
-- A pfUI library that detects and saves all ongoing debuffs of players, NPCs and enemies.
-- 
-- MAJOR REWRITE: Now uses GetUnitField for slot mapping instead of manual shifting.
-- Key insight: GetUnitField returns STABLE aura slots (33-48 in 1-based Lua arrays) that 
-- DON'T shift when debuffs expire. Only the display slots (UnitDebuff returns 1,2,3...) 
-- are compacted.
--
-- This eliminates ~400 lines of error-prone shift logic while maintaining full
-- multi-caster tracking support.
--
-- PERFORMANCE OPTIMIZATION (Nampower 2.29+):
-- Uses arg6 (auraSlot) parameter from DEBUFF_ADDED/REMOVED events to eliminate
-- GetDebuffSlotMap() lookups. NOTE: arg6 is 0-based (32-47) but GetUnitField arrays 
-- are 1-based (33-48), so we convert with +1. Falls back to GetUnitField if unavailable.
--
--  libdebuff:UnitDebuff(unit, id)
--    Returns debuff informations on the given effect of the specified unit.
--    name, rank, texture, stacks, dtype, duration, timeleft, caster

-- return instantly if we're not on a vanilla client
if pfUI.client > 11200 then return end

-- return instantly when another libdebuff is already active
if pfUI.api.libdebuff then return end

-- fix a typo (missing $) in ruRU capture index
if GetLocale() == "ruRU" then
  SPELLREFLECTSELFOTHER = gsub(SPELLREFLECTSELFOTHER, "%%2s", "%%2%$s")
end

local libdebuff = CreateFrame("Frame", "pfdebuffsScanner", UIParent)
local scanner = libtipscan:GetScanner("libdebuff")
local _, class = UnitClass("player")
local lastspell

-- GetSpellNameAndRank wrapper: Use GetSpellRec (Nampower/Turtle WoW)
-- Returns: name, rank, texture
local function GetSpellNameAndRank(spellId)
  if not spellId then return nil, nil, nil end
  
  if GetSpellRec then
    local data = GetSpellRec(spellId)
    if data and data.name then
      local texture = nil
      -- Get texture from spellIconID if available
      if data.spellIconID and GetSpellIconTexture then
        texture = GetSpellIconTexture(data.spellIconID)
        -- GetSpellIconTexture may return short name, needs full path
        if texture and not string.find(texture, "\\") then
          texture = "Interface\\Icons\\" .. texture
        end
      end
      return data.name, data.rank, texture
    end
  end
  
  return nil, nil, nil
end

-- Nampower Support
local hasNampower = false

-- Set hasNampower immediately for functionality
if GetNampowerVersion then
  local major, minor, patch = GetNampowerVersion()
  patch = patch or 0
  -- Minimum required version: 2.31.0 (SPELL_FAILED_OTHER fix)
  if major > 2 or (major == 2 and minor > 31) or (major == 2 and minor == 31 and patch >= 0) then
    hasNampower = true
  end
end

-- Delayed Nampower version check (5 seconds after PLAYER_ENTERING_WORLD)
local nampowerCheckFrame = CreateFrame("Frame")
local nampowerCheckTimer = 0
local nampowerCheckDone = false
nampowerCheckFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
nampowerCheckFrame:RegisterEvent("PLAYER_LOGOUT")
nampowerCheckFrame:SetScript("OnEvent", function()
  -- Handle shutdown to prevent crash 132
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    this:SetScript("OnUpdate", nil)
    return
  end
  
  nampowerCheckFrame:SetScript("OnUpdate", function()
    nampowerCheckTimer = nampowerCheckTimer + arg1
    if nampowerCheckTimer >= 5 and not nampowerCheckDone then
      nampowerCheckDone = true
      
      if GetNampowerVersion then
        local major, minor, patch = GetNampowerVersion()
        patch = patch or 0
        local versionString = major .. "." .. minor .. "." .. patch
        
        if major > 2 or (major == 2 and minor > 31) or (major == 2 and minor == 31 and patch >= 0) then
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Nampower v" .. versionString .. " detected - GetUnitField mode enabled!")
          
          -- Enable required Nampower CVars
          if SetCVar and GetCVar then
            local cvarsToEnable = {
              "NP_EnableSpellStartEvents",
              "NP_EnableSpellGoEvents", 
              "NP_EnableAuraCastEvents",
              "NP_EnableAutoAttackEvents",
            }
            
            local totalCvars = table.getn(cvarsToEnable)
            local enabledCount = 0
            local alreadyEnabledCount = 0
            local failedCount = 0
            
            for _, cvar in ipairs(cvarsToEnable) do
              local success, currentValue = pcall(GetCVar, cvar)
              if success and currentValue then
                if currentValue == "1" then
                  alreadyEnabledCount = alreadyEnabledCount + 1
                else
                  local setSuccess = pcall(SetCVar, cvar, "1")
                  if setSuccess then
                    enabledCount = enabledCount + 1
                  else
                    failedCount = failedCount + 1
                  end
                end
              else
                failedCount = failedCount + 1
              end
            end
            
            if enabledCount > 0 then
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Enabled " .. enabledCount .. " Nampower CVars")
            end
            
            if alreadyEnabledCount == totalCvars then
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r All required Nampower CVars already enabled")
            elseif alreadyEnabledCount > 0 then
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r " .. alreadyEnabledCount .. " CVars were already enabled")
            end
            
            if failedCount > 0 then
              DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff]|r Warning: Could not check/set " .. failedCount .. " CVars")
            end
          end
          
        elseif major == 2 and minor == 31 and patch == 0 then
          DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff] WARNING: Nampower v2.31.0 detected!|r")
          DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff] Please update to v2.31.0 or higher!|r")
          StaticPopup_Show("LIBDEBUFF_NAMPOWER_UPDATE", versionString)
        else
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] Debuff tracking disabled! Please update Nampower to v2.31.0 or higher.|r")
          StaticPopup_Show("LIBDEBUFF_NAMPOWER_UPDATE", versionString)
        end
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] Nampower not found! Debuff tracking disabled.|r")
        StaticPopup_Show("LIBDEBUFF_NAMPOWER_MISSING")
      end
      
      nampowerCheckFrame:SetScript("OnUpdate", nil)
    end
  end)
end)

-- ============================================================================
-- DATA STRUCTURES (Simplified - no more manual slot tracking!)
-- ============================================================================

-- ownDebuffs: [targetGUID][spellName] = {startTime, duration, texture, rank}
-- Timer data for OUR debuffs only
pfUI.libdebuff_own = pfUI.libdebuff_own or {}
local ownDebuffs = pfUI.libdebuff_own

-- allAuraCasts: [targetGUID][spellName][casterGuid] = {startTime, duration, rank}
-- Timer data for ALL debuffs (multi-caster support)
pfUI.libdebuff_all_auras = pfUI.libdebuff_all_auras or {}
local allAuraCasts = pfUI.libdebuff_all_auras

-- slotOwnership: [targetGUID][auraSlot] = {casterGuid, spellName, spellId}
-- Maps REAL aura slots (33-48) to caster info - NO SHIFTING NEEDED!
pfUI.libdebuff_slot_ownership = pfUI.libdebuff_slot_ownership or {}
local slotOwnership = pfUI.libdebuff_slot_ownership

-- displayToAura: [targetGUID][displaySlot] = auraSlot
-- Maps DISPLAY slots (1-16) to REAL aura slots (33-48) for DEBUFF_REMOVED correlation
pfUI.libdebuff_display_to_aura = pfUI.libdebuff_display_to_aura or {}
local displayToAura = pfUI.libdebuff_display_to_aura

-- pendingCasts: [targetGUID][spellName] = {casterGuid, rank, time}
-- Temporary storage from SPELL_GO to correlate with DEBUFF_ADDED
pfUI.libdebuff_pending = pfUI.libdebuff_pending or {}
local pendingCasts = pfUI.libdebuff_pending

-- pendingAoE: [spellName] = {casterGuid, rank, time}
-- AoE spells (Hurricane, Consecration) have no targetGuid in SPELL_GO
local pendingAoE = {}

-- pendingApplicators: [targetGuid] = {spell, time}
-- Tracks when player casts spells that apply passive proc debuffs (e.g., Scorch → Fire Vulnerability)
-- Used to assign ownership when debuff appears without casterGuid in SPELL_GO
local pendingApplicators = {}

-- Spell Icon Cache: [spellId] = texture
pfUI.libdebuff_icon_cache = pfUI.libdebuff_icon_cache or {}
local iconCache = pfUI.libdebuff_icon_cache

-- Cast Tracking: [casterGuid] = {spellID, spellName, icon, startTime, duration, endTime}
-- Shared with nameplates for cast-bar display
pfUI.libdebuff_casts = pfUI.libdebuff_casts or {}
pfUI.libdebuff_item_icons = pfUI.libdebuff_item_icons or {}  -- [casterGuid] = icon (persists across SPELL_GO)

-- Cleveroids API: [targetGUID][spellID] = {start, duration, caster, stacks}
pfUI.libdebuff_objects_guid = pfUI.libdebuff_objects_guid or {}
local objectsByGuid = pfUI.libdebuff_objects_guid

-- LEGACY: Keep these for backwards compatibility (external modules might check them)
pfUI.libdebuff_own_slots = pfUI.libdebuff_own_slots or {}
pfUI.libdebuff_all_slots = pfUI.libdebuff_all_slots or {}

-- Deduplication: Track recent AURA_CAST events to ignore duplicates
-- [targetGuid][spellName][casterGuid] = timestamp
pfUI.libdebuff_recent_casts = pfUI.libdebuff_recent_casts or {}
local recentCasts = pfUI.libdebuff_recent_casts
local AURA_CAST_DEDUPE_WINDOW = 0.1  -- Ignore duplicates within 100ms

-- Hit tracking: Track successful spell hits for applicator refresh validation
-- [targetGuid][spellName] = timestamp (only tracks player's spells)
pfUI.libdebuff_recent_hits = pfUI.libdebuff_recent_hits or {}
local recentHits = pfUI.libdebuff_recent_hits
local HIT_TRACKING_WINDOW = 0.1  -- Track hits within 100ms (AURA_CAST validation)

-- ============================================================================
-- STATIC POPUP DIALOGS
-- ============================================================================

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_UPDATE"] = {
  text = "Nampower Update Required!\n\nYour current version: %s\nRequired version: 2.31.0+\n\nPlease update Nampower!",
  button1 = "OK",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
  OnAccept = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Download: https://gitea.com/avitasia/nampower/releases/tag/v2.31.0")
  end,
}

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_MISSING"] = {
  text = "Nampower Not Found!\n\nNampower 2.31.0+ is required for pfUI Enhanced debuff tracking.\n\nPlease install Nampower.",
  button1 = "OK",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
}

-- ============================================================================
-- SPELL DATA TABLES
-- ============================================================================

-- Self-overwrite debuffs and overwrite pairs moved to libspelldata.lua
-- Accessed via libspelldata:IsSelfOverwrite() and libspelldata:GetOverwritePair()

-- Combopoint abilities and Carnage refresh logic moved to libspelldata.lua
-- libspelldata is queried from AURA_CAST and SPELL_GO handlers below

-- Captured combo points from SPELL_CAST_EVENT (before client consumes them)
-- SPELL_CAST_EVENT fires before the spell is sent to the server,
-- so GetComboPoints() still returns the correct value at that point.
-- By SPELL_GO and AURA_CAST, CPs are already 0.
local capturedCP = nil

-- Cached melee-refreshable spells from libspelldata (populated on first use)
local meleeRefreshSpells = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Player GUID Cache
local playerGuid = nil
local function GetPlayerGuid()
  -- Always try to fetch if we don't have it yet
  if not playerGuid and UnitExists then
    local exists, guid = UnitExists("player")
    if exists and guid then
      playerGuid = guid
    end
  end
  return playerGuid
end

-- Debug Stats
pfUI.libdebuff_debugstats = pfUI.libdebuff_debugstats or {
  enabled = false,
  trackAllUnits = false,
  aura_cast = 0,
  debuff_added = 0,
  debuff_removed = 0,
  getunitfield_calls = 0,
}
local debugStats = pfUI.libdebuff_debugstats

local function DebugGuid(guid)
  if not guid then return "nil" end
  local str = tostring(guid)
  if string.len(str) > 4 then
    return string.sub(str, -4)
  end
  return str
end

local function IsCurrentTarget(guid)
  if debugStats.trackAllUnits then return true end
  if not guid or not UnitExists then return false end
  local _, targetGuid = UnitExists("target")
  return targetGuid == guid
end

local function GetDebugTimestamp()
  return string.format("[%.3f]", GetTime())
end

-- Refresh passive proc debuffs when applicator spells hit
-- Used by SPELL_DAMAGE_EVENT_SELF, SPELL_GO, and AURA_CAST
local function RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
  local libspelldata = pfUI.libspelldata  -- Get reference in function scope
  
  if not libspelldata or not allAuraCasts[targetGuid] or not targetGuid or not spellName or not myGuid then
    return false
  end
  
  local now = GetTime()
  local refreshed = false
  
  for debuffName, casterData in pairs(allAuraCasts[targetGuid]) do
    -- Check if we own this debuff AND spell is in applicatorSpells list
    if casterData[myGuid] and libspelldata:IsApplicatorSpell(debuffName, spellName) then
      local data = casterData[myGuid]
      local duration = libspelldata:GetDuration(debuffName)
      
      if duration then
        -- Deduplication: Skip if already refreshed very recently (within 50ms)
        -- This prevents duplicate refreshes from SPELL_DAMAGE_EVENT + SPELL_GO + AURA_CAST
        local shouldRefresh = true
        if data.startTime and (now - data.startTime) < 0.05 then
          -- Already refreshed by another event, skip
          shouldRefresh = false
        end
        
        if shouldRefresh then
          -- Refresh the timer
          data.startTime = now
          data.duration = duration
          refreshed = true
          
          -- Also refresh ownDebuffs
          if ownDebuffs[targetGuid] and ownDebuffs[targetGuid][debuffName] then
            ownDebuffs[targetGuid][debuffName].startTime = now
            ownDebuffs[targetGuid][debuffName].duration = duration
          end
          
          if debugStats.enabled and IsCurrentTarget(targetGuid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[APPLICATOR REFRESH]|r %s via %s (%.1fs)", 
              GetDebugTimestamp(), debuffName, spellName, duration))
          end
        end
      end
    end
  end
  
  -- Force UI update if something was refreshed
  if refreshed then
    if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
      pfUI.nameplates:OnAuraUpdate(targetGuid, true)
    end
    
    if UnitExists("target") then
      local _, currentTargetGuid = UnitExists("target")
      if currentTargetGuid == targetGuid then
        if pfTarget then pfTarget.update_aura = true end
        libdebuff:UpdateUnits()
      end
    end
  end
  
  return refreshed
end

-- Speichert die Ranks der zuletzt gecasteten Spells
pfUI.libdebuff_lastranks = pfUI.libdebuff_lastranks or {}
local lastCastRanks = pfUI.libdebuff_lastranks

-- Speichert Spells die gefailed sind
pfUI.libdebuff_lastfailed = pfUI.libdebuff_lastfailed or {}
local lastFailedSpells = pfUI.libdebuff_lastfailed

-- Get spell icon texture (with caching)
function libdebuff:GetSpellIcon(spellId)
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  
  if iconCache[spellId] then
    return iconCache[spellId]
  end
  
  local texture = nil
  
  if GetSpellRecField and GetSpellIconTexture then
    local spellIconId = GetSpellRecField(spellId, "spellIconID")
    if spellIconId and type(spellIconId) == "number" and spellIconId > 0 then
      texture = GetSpellIconTexture(spellIconId)
      -- GetSpellIconTexture may return short name OR full path
      -- Only add prefix if it's a short name (no backslash)
      if texture and not string.find(texture, "\\") then
        texture = "Interface\\Icons\\" .. texture
      end
    end
  end
  
  if not texture then
    local _, _, spellTexture = GetSpellNameAndRank(spellId)
    texture = spellTexture
  end
  
  if not texture then
    texture = "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  
  iconCache[spellId] = texture
  return texture
end

pfUI.libdebuff_GetSpellIcon = function(spellId)
  return libdebuff:GetSpellIcon(spellId)
end

function libdebuff:DidSpellFail(spell)
  if not spell then return false end
  local data = lastFailedSpells[spell]
  if data and (GetTime() - data.time) < 1 then
    return true
  end
  return false
end

-- ============================================================================
-- CORE: GetUnitField-based Slot Mapping (THE KEY INNOVATION!)
-- ============================================================================

-- Cache for GetDebuffSlotMap to reduce GetUnitField calls
-- [guid] = {map, timestamp}
local slotMapCache = {}
local SLOT_MAP_CACHE_DURATION = 0.05  -- 50ms cache (1-2 frames)

-- Dispel type mapping: SpellRec.dispel index -> Blizzard DebuffTypeColor key
local dispelTypeMap = {
  [1] = "Magic",
  [2] = "Curse",
  [3] = "Disease",
  [4] = "Poison",
}

-- Get current buff state directly from WoW via GetUnitField
-- Returns: { [displaySlot] = {auraSlot, spellId, spellName, stacks, texture} }
local function GetBuffSlotMap(guid)
  if not guid or not GetUnitField then
    return nil
  end
  
  -- Check cache first
  local now = GetTime()
  local cached = slotMapCache[guid]
  if cached and cached.buffMap and (now - cached.timestamp) < SLOT_MAP_CACHE_DURATION then
    return cached.buffMap
  end
  
  local auras = GetUnitField(guid, "aura")
  if not auras then return nil end
  
  -- Fetch stacks array
  local auraApps = GetUnitField(guid, "auraApplications")
  
  if debugStats.enabled then
    debugStats.getunitfield_calls = debugStats.getunitfield_calls + 1
  end
  
  local map = {}
  local displaySlot = 0
  
  -- Buff aura slots are 1-32
  for auraSlot = 1, 32 do
    local spellId = auras[auraSlot]
    if spellId and spellId > 0 then
      -- Get texture via GetSpellIcon (uses DBC when possible, works out of range!)
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Get spell name: Try DBC first (works out of range!), using GetSpellRec
      local spellName = nil
      if GetSpellRecField then
        spellName = GetSpellRecField(spellId, "name")
        -- Empty string = not found, treat as nil
        if spellName == "" then
          spellName = nil
        end
      end
      if not spellName then
        spellName = GetSpellNameAndRank(spellId)
      end
      
      -- Skip "?" icons (unknown spells)
      -- Only add if we have a real texture (not the question mark fallback)
      if texture then
        displaySlot = displaySlot + 1
        
        -- Get stacks from auraApplications (0-indexed, so +1 for display)
        local stacks = (auraApps and auraApps[auraSlot] or 0) + 1
        
        map[displaySlot] = {
          auraSlot = auraSlot,
          spellId = spellId,
          spellName = spellName or "Unknown",
          stacks = stacks,
          texture = texture
        }
      end
    end
  end
  
  -- Cache the result (always cache, even if some buffs were skipped)
  if not slotMapCache[guid] then
    slotMapCache[guid] = { timestamp = now }
  end
  slotMapCache[guid].buffMap = map
  slotMapCache[guid].timestamp = now
  
  return map
end

-- Get current debuff state directly from WoW via GetUnitField
-- Returns: { [displaySlot] = {auraSlot, spellId, spellName, stacks, texture, dtype} }
local function GetDebuffSlotMap(guidOrUnit)
  if not guidOrUnit or not GetUnitField then
    return nil
  end
  
  -- Handle case where GUID is passed as table (old Nampower format or bug)
  if type(guidOrUnit) == "table" then
    -- Cannot process table GUIDs - silently return nil
    return nil
  end
  
  -- Determine if we got a GUID or a unitToken
  -- With new Nampower: GUIDs are strings starting with "0x" (e.g., "0xF13000...")
  -- unitTokens are strings like "target", "player", "pet"
  local guid = guidOrUnit
  local unitToken = nil
  
  -- Check if it's a unitToken (common unit strings)
  local knownUnits = { target=true, player=true, pet=true, focus=true, mouseover=true }
  if knownUnits[guidOrUnit] or (type(guidOrUnit) == "string" and not string.find(guidOrUnit, "^0x")) then
    -- It's a unitToken like "target" - get the GUID from it
    unitToken = guidOrUnit
    if UnitExists and UnitExists(unitToken) then
      local _, unitGuid = UnitExists(unitToken)
      guid = unitGuid
    else
      return nil
    end
  else
    -- It's a GUID (string starting with "0x")
    -- CRITICAL FIX: Use the GUID directly as unitToken!
    -- Nampower's UnitExists() and GetUnitField() accept GUID strings directly
    unitToken = guid
  end
  
  -- Check cache first (use GUID as key for consistency across calls)
  local now = GetTime()
  local cached = slotMapCache[guid]
  if cached and cached.map and (now - cached.timestamp) < SLOT_MAP_CACHE_DURATION then
    return cached.map
  end
  
  -- GetUnitField needs unitToken, not GUID!
  local auras = GetUnitField(unitToken, "aura")
  if not auras then 
    return nil 
  end
  
  -- Fetch stacks array (reusable reference - extract values immediately)
  local auraApps = GetUnitField(unitToken, "auraApplications")
  
  if debugStats.enabled then
    debugStats.getunitfield_calls = debugStats.getunitfield_calls + 1
  end
  
  local map = {}
  local displaySlot = 0
  
  -- Debuff aura slots are 33-48
  for auraSlot = 33, 48 do
    local spellId = auras[auraSlot]
    if spellId and spellId > 0 then
      -- Get texture via GetSpellIcon (uses DBC when possible, works out of range!)
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Get spell name: Try DBC first (works out of range!), using GetSpellRec
      local spellName = nil
      if GetSpellRecField then
        spellName = GetSpellRecField(spellId, "name")
        -- Empty string = not found, treat as nil
        if spellName == "" then
          spellName = nil
        end
      end
      if not spellName then
        spellName = GetSpellNameAndRank(spellId)
      end
      
      -- Get debuff type from SpellRec DBC (always works)
      local dtype = nil
      if GetSpellRecField then
        local dispelId = GetSpellRecField(spellId, "dispel")
        if dispelId and dispelId > 0 then
          dtype = dispelTypeMap[dispelId]
        end
      end
      
      -- Skip "?" icons (unknown spells)
      -- Only add if we have a real texture (not the question mark fallback)
      if texture then
        displaySlot = displaySlot + 1
        
        -- Get stacks from auraApplications (0-indexed, so +1 for display)
        local rawStacks = auraApps and auraApps[auraSlot]
        local stacks = (rawStacks or 0) + 1
        
        map[displaySlot] = {
          auraSlot = auraSlot,
          spellId = spellId,
          spellName = spellName or "Unknown",
          stacks = stacks,
          texture = texture,
          dtype = dtype
        }
      end
    end
  end
  
  -- Cache the result (always cache, even if some debuffs were skipped)
  slotMapCache[guid] = {
    map = map,
    timestamp = now
  }
  
  return map
end

-- Get caster info for a specific aura slot
local function GetSlotCaster(guid, auraSlot, spellName)
  -- First check our ownership tracking
  if slotOwnership[guid] and slotOwnership[guid][auraSlot] then
    local ownership = slotOwnership[guid][auraSlot]
    -- Verify spell name matches (slot might have been reused)
    if ownership.spellName == spellName then
      return ownership.casterGuid, ownership.isOurs
    end
  end
  
  -- Fallback: Check ownDebuffs
  local myGuid = GetPlayerGuid()
  if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
    return myGuid, true
  end
  
  -- Fallback: Check allAuraCasts for any caster
  if allAuraCasts[guid] and allAuraCasts[guid][spellName] then
    for casterGuid, data in pairs(allAuraCasts[guid][spellName]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > 0 then
        return casterGuid, (casterGuid == myGuid)
      end
    end
  end
  
  return nil, false
end

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

local lastRangeCheck = 0

-- Recycled buffers for cleanup (avoids table creation per call)
local _cleanupBuf1 = {}
local _cleanupBuf2 = {}

local function CleanupUnit(guid)
  if not guid then return false end
  
  local cleaned = false
  
  -- Notify libspelldata
  if pfUI.libspelldata then
    pfUI.libspelldata:CleanupUnit(guid)
  end
  
  if ownDebuffs[guid] then
    ownDebuffs[guid] = nil
    cleaned = true
  end
  
  if slotOwnership[guid] then
    slotOwnership[guid] = nil
    cleaned = true
  end
  
  if allAuraCasts[guid] then
    allAuraCasts[guid] = nil
    cleaned = true
  end
  
  if objectsByGuid[guid] then
    objectsByGuid[guid] = nil
    cleaned = true
  end
  
  if pendingCasts[guid] then
    pendingCasts[guid] = nil
    cleaned = true
  end
  
  if debugStats.enabled and cleaned and IsCurrentTarget(guid) then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[CLEANUP]|r GUID %s", DebugGuid(guid)))
  end
  
  return cleaned
end

local function CleanupExpiredTimers(guid)
  local now = GetTime()
  
  -- Cleanup ownDebuffs
  if ownDebuffs[guid] then
    local n = 0
    for spellName, data in pairs(ownDebuffs[guid]) do
      local timeleft = (data.startTime + data.duration) - now
      if timeleft < -2 then -- Grace period
        n = n + 1
        _cleanupBuf1[n] = spellName
      end
    end
    for i = 1, n do
      ownDebuffs[guid][_cleanupBuf1[i]] = nil
      _cleanupBuf1[i] = nil
    end
  end
  
  -- Cleanup allAuraCasts
  if allAuraCasts[guid] then
    for spellName, casterTable in pairs(allAuraCasts[guid]) do
      local n2 = 0
      for casterGuid, data in pairs(casterTable) do
        local timeleft = (data.startTime + data.duration) - now
        if timeleft < -2 then
          n2 = n2 + 1
          _cleanupBuf2[n2] = casterGuid
        end
      end
      for i = 1, n2 do
        allAuraCasts[guid][spellName][_cleanupBuf2[i]] = nil
        _cleanupBuf2[i] = nil
      end
      -- Remove empty spell tables
      local hasCasters = false
      for _ in pairs(allAuraCasts[guid][spellName]) do
        hasCasters = true
        break
      end
      if not hasCasters then
        allAuraCasts[guid][spellName] = nil
      end
    end
  end
end

local function CleanupOutOfRangeUnits()
  local now = GetTime()
  if now - lastRangeCheck < 10 then return end
  lastRangeCheck = now
  
  local allGuids = {}
  for guid in pairs(ownDebuffs) do allGuids[guid] = true end
  for guid in pairs(slotOwnership) do allGuids[guid] = true end
  for guid in pairs(allAuraCasts) do allGuids[guid] = true end
  for guid in pairs(objectsByGuid) do allGuids[guid] = true end
  for guid in pairs(pendingCasts) do allGuids[guid] = true end
  
  for guid in pairs(allGuids) do
    local exists = UnitExists and UnitExists(guid)
    local isDead = UnitIsDead and UnitIsDead(guid)
    
    if not exists or isDead then
      CleanupUnit(guid)
    end
  end
  
  -- Cleanup old lastCastRanks
  for spell, data in pairs(lastCastRanks) do
    if now - data.time > 3 then
      lastCastRanks[spell] = nil
    end
  end
  
  -- Cleanup old lastFailedSpells
  for spell, data in pairs(lastFailedSpells) do
    if now - data.time > 2 then
      lastFailedSpells[spell] = nil
    end
  end
  
  -- Cleanup old pendingCasts
  for guid, spells in pairs(pendingCasts) do
    for spell, data in pairs(spells) do
      if now - data.time > 1 then
        pendingCasts[guid][spell] = nil
      end
    end
    local isEmpty = true
    for _ in pairs(pendingCasts[guid]) do
      isEmpty = false
      break
    end
    if isEmpty then
      pendingCasts[guid] = nil
    end
  end
  
  -- Cleanup old pendingAoE (now supports multiple casters per spell)
  for spell, casters in pairs(pendingAoE) do
    for casterGuid, data in pairs(casters) do
      if now - data.time > 12 then  -- AoE channels can last up to 10s
        pendingAoE[spell][casterGuid] = nil
      end
    end
    -- Remove empty spell entries
    if next(pendingAoE[spell]) == nil then
      pendingAoE[spell] = nil
    end
  end
end

-- ============================================================================
-- DURATION FUNCTIONS
-- ============================================================================

function libdebuff:GetDuration(effect, rank)
  if L["debuffs"][effect] then
    local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
    local rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
    local duration = L["debuffs"][effect][rank]

    -- Talent-modified durations (non-CP spells)
    if effect == L["dyndebuffs"]["Demoralizing Shout"] then
      local _,_,_,_,count = GetTalentInfo(2,1)
      if count and count > 0 then duration = duration + ( duration / 100 * (count*10)) end
    elseif effect == L["dyndebuffs"]["Shadow Word: Pain"] then
      local _,_,_,_,count = GetTalentInfo(3,4)
      if count and count > 0 then duration = duration + count * 3 end
    elseif effect == L["dyndebuffs"]["Frostbolt"] then
      local _,_,_,_,count = GetTalentInfo(3,7)
      if count and count > 0 then duration = duration + count end
    elseif effect == L["dyndebuffs"]["Gouge"] then
      local _,_,_,_,count = GetTalentInfo(3,3)
      if count and count > 0 then duration = duration + (count*.5) end
    end
    return duration
  else
    return 0
  end
end

function libdebuff:GetMaxRank(effect)
  local max = 0
  for id in pairs(L["debuffs"][effect]) do
    if id > max then max = id end
  end
  return max
end

function libdebuff:UpdateDuration(unit, unitlevel, effect, duration)
  if not unit or not effect or not duration then return end
  unitlevel = unitlevel or 0

  if libdebuff.objects[unit] and libdebuff.objects[unit][unitlevel] and libdebuff.objects[unit][unitlevel][effect] then
    libdebuff.objects[unit][unitlevel][effect].duration = duration
  end
end

function libdebuff:UpdateUnits()
  if not pfUI.uf or not pfUI.uf.target then return end
  pfUI.uf:RefreshUnit(pfUI.uf.target, "aura")
end

-- ============================================================================
-- LEGACY API (for turtle-wow.lua compatibility)
-- ============================================================================

libdebuff.pending = {}
libdebuff.objects = {}

function libdebuff:AddPending(unit, unitlevel, effect, duration, caster, rank)
  if not unit or duration <= 0 then return end
  if not L["debuffs"][effect] then return end
  if libdebuff.pending[3] then return end

  libdebuff.pending[1] = unit
  libdebuff.pending[2] = unitlevel or 0
  libdebuff.pending[3] = effect
  libdebuff.pending[4] = duration
  libdebuff.pending[5] = caster
  libdebuff.pending[6] = rank

  QueueFunction(libdebuff.PersistPending)
end

function libdebuff:RemovePending()
  libdebuff.pending[1] = nil
  libdebuff.pending[2] = nil
  libdebuff.pending[3] = nil
  libdebuff.pending[4] = nil
  libdebuff.pending[5] = nil
  libdebuff.pending[6] = nil
end

function libdebuff:PersistPending(effect)
  if not libdebuff.pending[3] then return end

  if libdebuff.pending[3] == effect or ( effect == nil and libdebuff.pending[3] ) then
    local p1, p2, p3, p4, p5, p6 = libdebuff.pending[1], libdebuff.pending[2], libdebuff.pending[3], libdebuff.pending[4], libdebuff.pending[5], libdebuff.pending[6]
    libdebuff.AddEffect(libdebuff, p1, p2, p3, p4, p5, p6)
  end

  libdebuff:RemovePending()
end

function libdebuff:AddEffect(unit, unitlevel, effect, duration, caster, rank)
  if not rank and caster == "player" and effect then
    if libdebuff.pending[3] == effect and libdebuff.pending[6] then
      rank = libdebuff.pending[6]
    elseif lastCastRanks[effect] and (GetTime() - lastCastRanks[effect].time) < 2 then
      rank = lastCastRanks[effect].rank
    end
  end
  
  if not unit then return end
  unitlevel = unitlevel or 0
  
  -- Create tables if needed
  libdebuff.objects[unit] = libdebuff.objects[unit] or {}
  libdebuff.objects[unit][unitlevel] = libdebuff.objects[unit][unitlevel] or {}
  
  -- Get duration from spell database if not provided
  if not duration or duration == 0 then
    duration = libdebuff:GetDuration(effect, rank)
  end
  
  -- Store/update effect
  local now = GetTime()
  local existing = libdebuff.objects[unit][unitlevel][effect]
  
  if existing then
    existing.start = now
    existing.duration = duration
    existing.caster = caster
    existing.rank = rank
  else
    libdebuff.objects[unit][unitlevel][effect] = {
      start = now,
      duration = duration,
      caster = caster,
      rank = rank
    }
  end
  
  lastspell = libdebuff.objects[unit][unitlevel][effect]
end

-- ============================================================================
-- MAIN API: UnitDebuff (GetUnitField-based)
-- ============================================================================

local cache = {}

-- ============================================================================
-- API: UnitDebuff
-- ============================================================================

function libdebuff:UnitDebuff(unit, displaySlot)
  local unitname = UnitName(unit)
  local unitlevel = UnitLevel(unit)
  local duration, timeleft = nil, -1
  local rank = nil
  local caster = nil
  local effect = nil
  local texture = nil
  local stacks = 0
  local dtype = nil

  -- Nampower: Use GetUnitField for ALL debuff data (no Blizzard UnitDebuff needed)
  if hasNampower and UnitExists then
    local _, guid = UnitExists(unit)
    
    if not guid then
      -- Safety fallback: no GUID available (should not happen with Nampower)
      local bTexture, bStacks, bDtype = UnitDebuff(unit, displaySlot)
      if bTexture then
        scanner:SetUnitDebuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
      end
      return effect, rank, bTexture, bStacks, bDtype, duration, timeleft, caster
    end
    
    -- HYBRID: Check if unit is in range
    local inRange = UnitIsVisible and UnitIsVisible(unit)
    
    if not inRange then
      -- OUT OF RANGE: Use vanilla Blizzard API (slow but works!)
      local bTexture, bStacks, bDtype = UnitDebuff(unit, displaySlot)
      if bTexture then
        scanner:SetUnitDebuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
        return effect, rank, bTexture, bStacks, bDtype, duration, timeleft, caster
      end
      return nil
    end
    
    -- IN RANGE: Get current slot map from GetUnitField (cached 50ms)
    -- CRITICAL: Pass unitToken, not GUID! GetDebuffSlotMap needs unitToken for GetUnitField calls
    local slotMap = GetDebuffSlotMap(unit)
    
    if not slotMap or not slotMap[displaySlot] then
      return nil
    end
    
    local slotData = slotMap[displaySlot]
    effect = slotData.spellName                                  
    texture = slotData.texture                                   
    stacks = slotData.stacks                                     
    dtype = slotData.dtype                                       
    local auraSlot = slotData.auraSlot
    local spellId = slotData.spellId
    
    -- Get caster info for this slot
    local slotCasterGuid, isOurs = GetSlotCaster(guid, auraSlot, effect)
    
    if isOurs then
      -- OUR debuff - get timer from ownDebuffs
      if ownDebuffs[guid] and ownDebuffs[guid][effect] then
        local data = ownDebuffs[guid][effect]
        local remaining = (data.startTime + data.duration) - GetTime()
        if remaining > 0 then
          duration = data.duration
          timeleft = remaining
          caster = slotCasterGuid or "player"  -- Return actual GUID, fallback to "player"
          rank = data.rank
        elseif remaining > -1 then
          -- Grace period - show 0 timeleft
          duration = data.duration
          timeleft = 0
          caster = slotCasterGuid or "player"  -- Return actual GUID, fallback to "player"
          rank = data.rank
        end
      end
    else
      -- OTHER player's debuff - get timer from allAuraCasts
      if slotCasterGuid and allAuraCasts[guid] and allAuraCasts[guid][effect] then
        local data = allAuraCasts[guid][effect][slotCasterGuid]
        if data then
          local remaining = (data.startTime + data.duration) - GetTime()
          if remaining > 0 and data.duration > 0 then
            duration = data.duration
            timeleft = remaining
            caster = slotCasterGuid  -- Return actual caster GUID
            rank = data.rank
          elseif data.duration == 0 then
            -- Combo-point ability from other player: no duration known, but return caster
            caster = slotCasterGuid
          end
        end
      end
      
      -- If we have slotCasterGuid but no data in allAuraCasts, still return it
      -- (Happens for combo-point abilities from other players that just landed)
      if slotCasterGuid and not caster then
        caster = slotCasterGuid
      end
      
      -- Fallback: Search all casters if we still don't have one
      if not caster and allAuraCasts[guid] and allAuraCasts[guid][effect] then
        for anyCasterGuid, data in pairs(allAuraCasts[guid][effect]) do
          local remaining = (data.startTime + data.duration) - GetTime()
          if remaining > 0 and data.duration > 0 then
            duration = data.duration
            timeleft = remaining
            caster = anyCasterGuid  -- Return actual caster GUID
            rank = data.rank
            break
          elseif data.duration == 0 then
            -- Combo-point ability: no duration but return caster
            caster = anyCasterGuid
            break
          end
        end
      end
    end
    
    return effect, rank, texture, stacks, dtype, duration, timeleft, caster, spellId
  end

  -- ============================================================================
  -- FALLBACK: Legacy (non-Nampower) system
  -- ============================================================================
  
  local bTexture, bStacks, bDtype = UnitDebuff(unit, displaySlot)
  texture = bTexture
  stacks = bStacks
  dtype = bDtype
  
  if texture then
    scanner:SetUnitDebuff(unit, displaySlot)
    effect = scanner:Line(1) or ""
  end
  
  if effect and libdebuff.objects[unitname] then
    for level, effects in pairs(libdebuff.objects[unitname]) do
      if effects[effect] and effects[effect].duration then
        local timeleft = effects[effect].start and
          effects[effect].start + effects[effect].duration - GetTime()

        if timeleft and timeleft > 0 then
          return effect, effects[effect].rank, texture, stacks, dtype,
            effects[effect].duration, timeleft, effects[effect].caster
        end
      end
    end
  end

  return effect, rank, texture, stacks, dtype, duration, timeleft, caster
end

-- ============================================================================
-- API: UnitBuff (buffs from aura slots 1-32)
-- ============================================================================

function libdebuff:UnitBuff(unit, displaySlot)
  local unitname = UnitName(unit)
  local duration, timeleft = nil, -1
  local rank = nil
  local caster = nil
  local effect = nil
  local texture = nil
  local stacks = 0

  -- Nampower: Use GetUnitField for ALL buff data
  if hasNampower and UnitExists then
    local _, guid = UnitExists(unit)
    if not guid then
      -- Safety fallback: no GUID available
      local bTexture, bStacks = UnitBuff(unit, displaySlot)
      if bTexture then
        scanner:SetUnitBuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
      end
      return effect, rank, bTexture, bStacks, duration, timeleft, caster
    end
    
    -- For "player" ONLY: vanilla UnitBuff works perfectly
    if unit == "player" then
      local bTexture, bStacks = UnitBuff(unit, displaySlot)
      texture = bTexture
      stacks = bStacks
      
      if texture then
        scanner:SetUnitBuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
      end
      
      return effect, rank, texture, stacks, duration, timeleft, caster
    end
    
    -- HYBRID: Check if unit is in range
    local inRange = UnitIsVisible and UnitIsVisible(unit)
    
    if not inRange then
      -- OUT OF RANGE: Use vanilla Blizzard API (slow but works!)
      local bTexture, bStacks = UnitBuff(unit, displaySlot)
      if bTexture then
        scanner:SetUnitBuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
        return effect, rank, bTexture, bStacks, duration, timeleft, caster
      end
      return nil
    end
    
    -- IN RANGE: Use GetBuffSlotMap (fast Nampower method with cache!)
    local slotMap = GetBuffSlotMap(guid)
    if not slotMap or not slotMap[displaySlot] then
      return nil
    end
    
    local slotData = slotMap[displaySlot]
    effect = slotData.spellName
    texture = slotData.texture
    stacks = slotData.stacks
    local spellId = slotData.spellId
    
    return effect, rank, texture, stacks, duration, timeleft, caster, spellId
  end
  
  -- ============================================================================
  -- FALLBACK: Legacy (non-Nampower) system
  -- ============================================================================
  
  local bTexture, bStacks = UnitBuff(unit, displaySlot)
  texture = bTexture
  stacks = bStacks
  
  if texture then
    scanner:SetUnitBuff(unit, displaySlot)
    effect = scanner:Line(1) or ""
  end
  
  return effect, rank, texture, stacks, duration, timeleft, caster
end

-- ============================================================================
-- API: UnitOwnDebuff (only OUR debuffs)
-- ============================================================================

-- Pre-defined sort function for UnitOwnDebuff (sort by startTime, then spellId for stability)
local _ownDebuffSortFunc = function(a, b)
  if a.data.startTime == b.data.startTime then
    -- Use spellId as tiebreaker instead of name (more stable)
    local aId = a.data.spellId or 0
    local bId = b.data.spellId or 0
    return aId < bId
  end
  return a.data.startTime < b.data.startTime
end

function libdebuff:UnitOwnDebuff(unit, id)
  if hasNampower and UnitExists then
    local _, guid = UnitExists(unit)
    if guid and ownDebuffs[guid] then
      -- Get GetDebuffSlotMap to verify which spells are actually in debuff slots (Bit 3 check)
      -- CRITICAL: Pass unitToken (e.g. "target"), not GUID! GetDebuffSlotMap needs unitToken for GetUnitField calls
      local debuffSlotMap = GetDebuffSlotMap(unit)
      local debuffSpellNames = {}
      if debuffSlotMap then
        for _, slotData in pairs(debuffSlotMap) do
          debuffSpellNames[slotData.spellName] = true
        end
      end
      
      -- Build sorted list of our active debuffs (only those that pass Bit 3 check)
      local sortedDebuffs = {}
      local now = GetTime()
      
      for spellName, data in pairs(ownDebuffs[guid]) do
        local timeleft = (data.startTime + data.duration) - now
        if timeleft > -1 then  -- Grace period
          -- FIX: Include spells that are in debuff slots OR are Ground AoE spells (Consecration, Hurricane, etc.)
          -- Ground AoE spells don't appear in debuff slots but are still valid debuffs that should be shown
          local isGroundAoE = libspelldata and libspelldata:HasForcedDuration(spellName)
          if debuffSpellNames[spellName] or isGroundAoE then
            local count = table.getn(sortedDebuffs) + 1
            sortedDebuffs[count] = {
              spellName = spellName,
              data = data,
              timeleft = timeleft
            }
          end
        end
      end
      
      -- Sort by startTime (oldest first), then by spellId for stable ordering
      table.sort(sortedDebuffs, _ownDebuffSortFunc)
      
      -- Return debuff at position 'id'
      if sortedDebuffs[id] then
        local entry = sortedDebuffs[id]
        local texture = entry.data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
        local displayTimeleft = entry.timeleft > 0 and entry.timeleft or 0
        
        -- Get dtype from SpellRec DBC via stored spellId
        local entryDtype = nil
        if entry.data.spellId and GetSpellRecField then
          local dispelId = GetSpellRecField(entry.data.spellId, "dispel")
          if dispelId and dispelId > 0 then
            entryDtype = dispelTypeMap[dispelId]
          end
        end
        
        return entry.spellName, entry.data.rank, texture, 1, entryDtype, entry.data.duration, displayTimeleft, "player"
      end
    end
    -- Don't return nil here - fall through to fallback scan
  end
  
  -- Fallback: Iterate through all debuffs and filter by caster="player"
  -- This is used when ownDebuffs cache is empty (e.g., after /reload)
  for k in pairs(cache) do cache[k] = nil end
  local count = 1
  for i=1,16 do
    local effect, rank, texture, stacks, dtype, duration, timeleft, caster = libdebuff:UnitDebuff(unit, i)
    if effect and not cache[effect] and caster and caster == "player" then
      cache[effect] = true
      if count == id then
        return effect, rank, texture, stacks, dtype, duration, timeleft, caster
      else
        count = count + 1
      end
    end
  end
end

-- ============================================================================
-- API: GetBestAuraCast (for libpredict HoT tracking)
-- ============================================================================

function libdebuff:GetBestAuraCast(guid, spellName)
  if not guid or not spellName then return nil end
  
  -- Check ownDebuffs first (for our casts)
  if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
    local data = ownDebuffs[guid][spellName]
    local timeleft = (data.startTime + data.duration) - GetTime()
    if timeleft > 0 then
      return data.startTime, data.duration, timeleft, data.rank, GetPlayerGuid()
    end
  end
  
  -- Check allAuraCasts (for any caster)
  if allAuraCasts[guid] and allAuraCasts[guid][spellName] then
    local bestData = nil
    local bestCaster = nil
    local bestTimeleft = 0
    
    for casterGuid, data in pairs(allAuraCasts[guid][spellName]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > bestTimeleft then
        bestTimeleft = timeleft
        bestData = data
        bestCaster = casterGuid
      end
    end
    
    if bestData and bestTimeleft > 0 then
      return bestData.startTime, bestData.duration, bestTimeleft, bestData.rank, bestCaster
    end
  end
  
  return nil
end

-- ============================================================================
-- API: GetEnhancedDebuffs (for external modules)
-- ============================================================================

function libdebuff:GetEnhancedDebuffs(targetGUID)
  if not targetGUID then return nil end
  local result = {}
  
  if ownDebuffs[targetGUID] then
    local myGuid = GetPlayerGuid()
    for spellName, data in pairs(ownDebuffs[targetGUID]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > 0 then
        result[spellName] = result[spellName] or {}
        result[spellName][myGuid] = {
          startTime = data.startTime,
          duration = data.duration,
          texture = data.texture,
          rank = data.rank
        }
      end
    end
  end
  
  return result
end

-- ============================================================================
-- Cache Management
-- ============================================================================

-- Invalidate slot map cache for a specific GUID
-- Called when unit goes in/out of range to force fresh data fetch
function libdebuff:InvalidateCache(guid)
  if guid and slotMapCache[guid] then
    slotMapCache[guid] = nil
  end
end

-- ============================================================================
-- NAMPOWER EVENT HANDLING
-- ============================================================================

if hasNampower then
  -- libspelldata reference (for forced durations, CP abilities, Carnage, applicators)
  local libspelldata = pfUI.libspelldata
  
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_LOGOUT")
  frame:RegisterEvent("SPELL_START_SELF")
  frame:RegisterEvent("SPELL_START_OTHER")
  frame:RegisterEvent("SPELL_GO_SELF")
  frame:RegisterEvent("SPELL_GO_OTHER")
  frame:RegisterEvent("SPELL_CAST_EVENT")
  frame:RegisterEvent("AUTO_ATTACK_SELF")
  frame:RegisterEvent("AUTO_ATTACK_OTHER")
  frame:RegisterEvent("SPELL_FAILED_SELF")
  frame:RegisterEvent("SPELL_FAILED_OTHER")
  frame:RegisterEvent("AURA_CAST_ON_SELF")
  frame:RegisterEvent("AURA_CAST_ON_OTHER")
  frame:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")  -- For Ignite (crit-based refresh)
  frame:RegisterEvent("DEBUFF_ADDED_OTHER")
  frame:RegisterEvent("DEBUFF_REMOVED_OTHER")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UNIT_HEALTH")
  
  -- Register Carnage callback with libspelldata
  -- When Carnage procs (Ferocious Bite → CP gain), refresh Rip/Rake timers
  if libspelldata then
    libspelldata:SetCarnageCallback(function(targetGuid, affectedSpells)
      local refreshTime = GetTime()
      local myGuid = GetPlayerGuid()
      
      if debugStats.enabled then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[CARNAGE CALLBACK]|r targetGuid=%s affected=%d", 
          DebugGuid(targetGuid), table.getn(affectedSpells)))
      end
      
      for _, spellName in ipairs(affectedSpells) do
        -- Refresh in ownDebuffs
        if ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
          local duration = ownDebuffs[targetGuid][spellName].duration or 0
          ownDebuffs[targetGuid][spellName].startTime = refreshTime
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE]|r " .. spellName .. " refreshed (Carnage triggered - " .. duration .. "s)")
          end
        elseif debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[CARNAGE SKIP]|r %s not found in ownDebuffs (guid=%s exists=%s)", 
            spellName, DebugGuid(targetGuid), tostring(ownDebuffs[targetGuid] ~= nil)))
        end
        
        -- Refresh in allAuraCasts
        if allAuraCasts[targetGuid] and allAuraCasts[targetGuid][spellName] 
           and allAuraCasts[targetGuid][spellName][myGuid] then
          allAuraCasts[targetGuid][spellName][myGuid].startTime = refreshTime
        end
      end
      
      -- NO cache invalidation! Slots don't change during refresh.
      -- Slot mappings (displayToAura, slotOwnership) remain valid.
      -- This matches the old version's behavior.
      
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(targetGuid, true)  -- forceRefresh = true
      end
      
      if UnitExists("target") then
        local _, currentTargetGuid = UnitExists("target")
        if currentTargetGuid == targetGuid then
          if pfTarget then pfTarget.update_aura = true end
          libdebuff:UpdateUnits()
        end
      end
    end)
  end
  
  frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
      
    elseif event == "PLAYER_ENTERING_WORLD" then
      GetPlayerGuid()
      
    elseif event == "UNIT_HEALTH" then
      local guid = arg1
      if guid and UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
      end
      
    elseif event == "SPELL_CAST_EVENT" then
      -- Fires BEFORE spell is sent to server - CPs still available!
      -- By SPELL_GO/AURA_CAST time, CPs are already consumed (=0).
      local spellId = arg2
      if spellId and libspelldata then
        local spellName = GetSpellNameAndRank(spellId)
        if spellName and libspelldata:IsComboPointAbility(spellName) then
          capturedCP = GetComboPoints() or 0
        end
      end
      
    elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
      -- Melee autohit: refresh Judgement debuffs from this attacker on the target
      local attackerGuid = arg1
      local targetGuid = arg2
      local totalDamage = arg3
      local hitInfo = arg4
      local victimState = arg5
      
      -- Only refresh on actual hits (not dodge/parry/miss)
      if not targetGuid or not attackerGuid then return end
      if victimState and (victimState == 0 or victimState == 2 or victimState == 3 or victimState == 6 or victimState == 7) then
        return  -- UNAFFECTED(miss), DODGE, PARRY, EVADE, IMMUNE
      end
      
      -- Check if this attacker has any melee-refreshable debuffs on this target
      if libspelldata and allAuraCasts[targetGuid] then
        if not meleeRefreshSpells then
          meleeRefreshSpells = libspelldata:GetMeleeRefreshSpells()
        end
        local now = GetTime()
        local myGuid = GetPlayerGuid()
        local isOurs = (attackerGuid == myGuid)
        local refreshed = false
        for spellName, refreshDur in pairs(meleeRefreshSpells) do
          if allAuraCasts[targetGuid][spellName] and allAuraCasts[targetGuid][spellName][attackerGuid] then
            local data = allAuraCasts[targetGuid][spellName][attackerGuid]
            -- Refresh timer
            data.startTime = now
            data.duration = refreshDur
            refreshed = true
            
            -- Refresh ownDebuffs if it's our debuff
            if isOurs and ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
              ownDebuffs[targetGuid][spellName].startTime = now
              ownDebuffs[targetGuid][spellName].duration = refreshDur
            end
            
            if debugStats.enabled and IsCurrentTarget(targetGuid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[MELEE REFRESH]|r %s on %s by %s", 
                GetDebugTimestamp(), spellName, DebugGuid(targetGuid), DebugGuid(attackerGuid)))
            end
          end
        end
        
        -- Only update UI when something was actually refreshed
        if refreshed then
          -- NO cache invalidation needed - slots don't change during timer refresh
          
          -- Force nameplate cooldown refresh (bypasses 0.5s threshold)
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid, true)  -- forceRefresh = true
          end
          
          if UnitExists("target") then
            local _, currentTargetGuid = UnitExists("target")
            if currentTargetGuid == targetGuid then
              if pfTarget then pfTarget.update_aura = true end
              libdebuff:UpdateUnits()
            end
          end
        end
      end
      
    elseif event == "SPELL_DAMAGE_EVENT_SELF" then
      -- Spell damage: Track hits for applicator refresh
      -- Filters out DoT ticks (periodic damage) using effectAuraStr
      local targetGuid = arg1
      local casterGuid = arg2
      local spellId = arg3
      local amount = arg4
      local mitigationStr = arg5
      local hitInfo = arg6
      local spellSchool = arg7
      local effectAuraStr = arg8  -- "effect1,effect2,effect3,auraType"
      
      if not targetGuid or not casterGuid or not spellId then return end
      
      local myGuid = GetPlayerGuid()
      if casterGuid ~= myGuid then return end  -- Only our damage
      
      local spellName = GetSpellNameAndRank(spellId)
      if not spellName then return end
      
      -- Check if this is periodic damage (DoT tick) by checking effectAuraStr
      -- Aura types: 3=SPELL_AURA_PERIODIC_DAMAGE, 89=SPELL_AURA_PERIODIC_DAMAGE_PERCENT
      local isPeriodicDamage = false
      if effectAuraStr and type(effectAuraStr) == "string" then
        -- Parse comma-separated string: "effect1,effect2,effect3,auraType"
        local _, _, e1, e2, e3, auraType = string.find(effectAuraStr, "^([^,]*),([^,]*),([^,]*),([^,]*)$")
        if auraType and auraType ~= "" then
          local auraTypeNum = tonumber(auraType)
          if auraTypeNum == 3 or auraTypeNum == 89 then
            isPeriodicDamage = true
          end
        end
      end
      
      -- ADDITIONAL CHECK: If no recent SPELL_GO/AURA_CAST, it's likely a DoT tick
      -- This filters DoT ticks from hybrid spells where effectAuraStr doesn't have auraType
      -- DoT ticks happen WITHOUT SPELL_GO or AURA_CAST events
      local hadRecentCast = false
      if recentHits[targetGuid] and recentHits[targetGuid][spellName] then
        local timeSinceCast = GetTime() - recentHits[targetGuid][spellName]
        if timeSinceCast < 1.0 then  -- 1 second window (DoT ticks are typically 3s intervals)
          hadRecentCast = true
        end
      end
      
      -- If no recent cast AND damage event fires → it's a DoT tick!
      local isDotTick = isPeriodicDamage or not hadRecentCast
      
      -- APPLICATOR REFRESH: Track successful hit for AURA_CAST validation
      -- But ONLY for initial/direct damage, NOT for DoT ticks!
      if not isDotTick then
        recentHits[targetGuid] = recentHits[targetGuid] or {}
        recentHits[targetGuid][spellName] = GetTime()
        
        -- APPLICATOR REFRESH: Immediately refresh passive proc debuffs when applicator spells hit
        RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
      -- Removed DOT TICK SKIPPED spam
      -- else
      --   if debugStats.enabled and IsCurrentTarget(targetGuid) then
      --     local reason = isPeriodicDamage and "periodic damage (auraType)" or "no recent cast (DoT tick)"
      --     DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff8888[DOT TICK SKIPPED]|r %s (%s)", 
      --       GetDebugTimestamp(), spellName, reason))
      --   end
      end
      
      -- CRIT-BASED REFRESH (Ignite etc.)
      if not hitInfo then return end
      
      -- Check if this was a critical hit
      local isCrit = (tonumber(hitInfo) == 2)
      if not isCrit then return end  -- Only process crits for crit-based refresh
      
      -- Check all debuffs we have on this target for crit-based refresh
      if libspelldata and allAuraCasts[targetGuid] then
        local now = GetTime()
        local refreshed = false
        
        for debuffName, casterData in pairs(allAuraCasts[targetGuid]) do
          -- Check if we own this debuff and it requires crit for refresh
          if casterData[myGuid] and libspelldata:RequiresCritForRefresh(debuffName, spellName) then
            local data = casterData[myGuid]
            local duration = libspelldata:GetDuration(debuffName)
            
            if duration then
              -- Refresh the timer
              data.startTime = now
              data.duration = duration
              refreshed = true
              
              -- Also refresh ownDebuffs
              if ownDebuffs[targetGuid] and ownDebuffs[targetGuid][debuffName] then
                ownDebuffs[targetGuid][debuffName].startTime = now
                ownDebuffs[targetGuid][debuffName].duration = duration
              end
              
              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff0000[CRIT REFRESH]|r %s via %s crit (%.1fs)", 
                  GetDebugTimestamp(), debuffName, spellName, duration))
              end
            end
          end
        end
        
        -- Force UI update if something was refreshed
        if refreshed then
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid, true)
          end
          
          if UnitExists("target") then
            local _, currentTargetGuid = UnitExists("target")
            if currentTargetGuid == targetGuid then
              if pfTarget then pfTarget.update_aura = true end
              libdebuff:UpdateUnits()
            end
          end
        end
      end
      
    elseif event == "SPELL_FAILED_SELF" then
      -- Clear captured CPs on failed cast
      capturedCP = nil
      
    elseif event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local castTime = arg6
      
      if not casterGuid or not spellId then return end
      
      local spellName = GetSpellNameAndRank(spellId) or nil
      local icon = libdebuff:GetSpellIcon(spellId)
      
      -- Use item icon for item-triggered casts
      if itemId and itemId > 0 and GetItemStatsField and GetItemIconTexture then
        local displayInfoId = GetItemStatsField(itemId, "displayInfoID")
        if displayInfoId then
          local itemIcon = GetItemIconTexture(displayInfoId)
          if itemIcon then
            -- GetItemIconTexture returns short name (e.g. "INV_Gizmo_08"), needs full path
            if not string.find(itemIcon, "\\") then
              itemIcon = "Interface\\Icons\\" .. itemIcon
            end
            icon = itemIcon
          end
        end
        -- Store in persistent item icon cache (survives SPELL_GO clearing libdebuff_casts)
        pfUI.libdebuff_item_icons[casterGuid] = {
          icon = icon,
          name = GetItemStatsField and GetItemStatsField(itemId, "displayName") or nil
        }
      else
        pfUI.libdebuff_item_icons[casterGuid] = nil
      end
      
      pfUI.libdebuff_casts[casterGuid] = {
        spellID = spellId,
        itemID = itemId and itemId > 0 and itemId or nil,
        spellName = spellName,
        icon = icon,
        startTime = GetTime(),
        duration = castTime and castTime / 1000 or 0,
        endTime = castTime and (GetTime() + castTime / 1000) or nil,
        event = "START"
      }
      
    elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local targetGuid = arg4
      local numHit = arg6 or 0
      local numMissed = arg7 or 0
      
      if debugStats.enabled then
        local spellName = GetSpellNameAndRank(spellId)
        local myGuid = GetPlayerGuid()
        -- Log if: current target OR player cast (for AoE without targetGuid)
        if spellName and (IsCurrentTarget(targetGuid or casterGuid) or (casterGuid == myGuid and not targetGuid)) then
          local itemStr = (itemId and itemId > 0) and string.format(" itemId=%d", itemId) or ""
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ccff[SPELL_GO]|r %s%s caster=%s target=%s numHit=%d numMissed=%d", 
            GetDebugTimestamp(), spellName, itemStr, DebugGuid(casterGuid), DebugGuid(targetGuid), numHit, numMissed))
        end
      end
      
      -- Clear cast bar only if SPELL_GO matches the active cast
      -- (Reactive procs like Frost Armor trigger SPELL_GO but shouldn't clear the castbar)
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        if pfUI.libdebuff_casts[casterGuid].spellID == spellId then
          pfUI.libdebuff_casts[casterGuid] = nil
        end
      end
      
      -- AoE spells with forced durations: store pendingAoE regardless of hit count.
      -- Ground AoEs (Flamestrike) may report numHit>0, channeled AoEs (Hurricane,
      -- Consecration) report Hit:0 Miss:0. Both need pendingAoE for DEBUFF_ADDED
      -- correlation since casterGuid is absent in that event.
      if numMissed == 0 and libspelldata then
        local aoeName = GetSpellNameAndRank(spellId)
        if aoeName and libspelldata:HasForcedDuration(aoeName) then
          local aoeRank = 0
          local _, aoeRankStr = GetSpellNameAndRank(spellId)
          if aoeRankStr and aoeRankStr ~= "" then
            aoeRank = tonumber((string.gsub(aoeRankStr, "Rank ", ""))) or 0
          end
          
          -- Support multiple casters: pendingAoE[spellName] = {[casterGuid] = {rank, time}}
          pendingAoE[aoeName] = pendingAoE[aoeName] or {}
          pendingAoE[aoeName][casterGuid] = {
            rank = aoeRank,
            time = GetTime()
          }
          
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff00cc[PENDING AOE]|r %s stored caster=%s (hit=%d)", 
              GetDebugTimestamp(), aoeName, DebugGuid(casterGuid), numHit))
          end
          
          -- If this AoE spell is already active, refresh it immediately!
          -- Handles recast scenarios (e.g. casting Consecration while one is already running)
          local refreshedTargets = 0
          for guid, spellTable in pairs(allAuraCasts) do
            if spellTable[aoeName] and spellTable[aoeName][casterGuid] then
              local data = spellTable[aoeName][casterGuid]
              local timeleft = (data.startTime + data.duration) - GetTime()
              
              if timeleft > -1 then
                local forcedDur = libspelldata:GetDuration(aoeName)
                if forcedDur and forcedDur > 0 then
                  local now = GetTime()
                  data.startTime = now
                  data.duration = forcedDur
                  refreshedTargets = refreshedTargets + 1
                  
                  local myGuid = GetPlayerGuid()
                  if casterGuid == myGuid and ownDebuffs[guid] and ownDebuffs[guid][aoeName] then
                    ownDebuffs[guid][aoeName].startTime = now
                    ownDebuffs[guid][aoeName].duration = forcedDur
                  end
                  
                  if debugStats.enabled and IsCurrentTarget(guid) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[AOE REFRESH]|r %s on %s refreshed by SPELL_GO", 
                      GetDebugTimestamp(), aoeName, DebugGuid(guid)))
                  end
                  
                  if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
                    pfUI.nameplates:OnAuraUpdate(guid, true)
                  end
                end
              end
            end
          end
          
          if debugStats.enabled and refreshedTargets > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[AOE REFRESH]|r %s refreshed %d target(s)", 
              GetDebugTimestamp(), aoeName, refreshedTargets))
          end
        end
      end
      
      -- APPLICATOR TRACKING: Track when PLAYER casts spells that apply passive proc debuffs
      -- (e.g., Scorch → Fire Vulnerability)
      -- NOTE: For AoE spells, we track via AURA_CAST instead since SPELL_GO has no targetGuid
      local myGuid = GetPlayerGuid()
      if myGuid and casterGuid == myGuid and targetGuid and numHit > 0 then
        local spellName = GetSpellNameAndRank(spellId)
        if spellName then
          -- Track successful hit for applicator refresh validation in AURA_CAST
          recentHits[targetGuid] = recentHits[targetGuid] or {}
          recentHits[targetGuid][spellName] = GetTime()
          
          -- Store that we just cast this spell on this target
          pendingApplicators[targetGuid] = {
            spell = spellName,
            time = GetTime()
          }
          
          -- APPLICATOR REFRESH: Check if this spell refreshes any passive proc debuffs
          -- (e.g., Scorch/Fire Blast → Fire Vulnerability)
          -- NOTE: This is a fallback - SPELL_DAMAGE_EVENT_SELF handles this faster/better
          RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
          
          if debugStats.enabled and IsCurrentTarget(targetGuid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff888888[APPLICATOR]|r %s → %s (pending)", 
              GetDebugTimestamp(), spellName, DebugGuid(targetGuid)))
          end
        end
      end
      
      if numMissed > 0 or numHit == 0 then
        -- Clear captured CPs on miss/dodge/parry
        local myGuid = GetPlayerGuid()
        if casterGuid == myGuid then
          capturedCP = nil
        end
        return
      end
      -- SpellInfo check removed (using GetSpellRec wrapper)
      
      local spellName, spellRankString = GetSpellNameAndRank(spellId)
      if not spellName then return end
      
      local castRank = 0
      if spellRankString and spellRankString ~= "" then
        castRank = tonumber((string.gsub(spellRankString, "Rank ", ""))) or 0
      end
      
      -- Store in pendingCasts for DEBUFF_ADDED correlation
      if targetGuid then
        pendingCasts[targetGuid] = pendingCasts[targetGuid] or {}
        pendingCasts[targetGuid][spellName] = {
          casterGuid = casterGuid,
          rank = castRank,
          time = GetTime()
        }
      end
      
      -- Store rank for our casts
      local myGuid = GetPlayerGuid()
      if casterGuid == myGuid then
        lastCastRanks[spellName] = {
          rank = castRank,
          time = GetTime()
        }
      end
      
      -- ========== libspelldata integration ==========
      
      if libspelldata then
        -- 1. Applicator tracking (Judgement SPELL_GO → DEBUFF_ADDED caster correlation)
        libspelldata:OnSpellGo(spellId, spellName, casterGuid, targetGuid)
        
        -- 2. Carnage: Ferocious Bite → check for CP gain → refresh Rip/Rake
        if libspelldata:ShouldCheckCarnage(spellName, casterGuid, targetGuid, numHit) then
          libspelldata:ScheduleCarnageCheck(targetGuid)
        end
      end
      
    elseif event == "SPELL_FAILED_OTHER" then
      local casterGuid = arg1
      
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        pfUI.libdebuff_casts[casterGuid] = nil
      end
      
    elseif event == "AURA_CAST_ON_SELF" or event == "AURA_CAST_ON_OTHER" then
      local spellId = arg1
      local casterGuid = arg2
      local targetGuid = arg3
      local effect = arg4
      local effectAuraName = arg5
      local effectAmplitude = arg6
      local effectMiscValue = arg7
      local durationMs = arg8
      local auraCapStatus = arg9
      
      if not spellId then return end
      if not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000" then return end
      
      local spellName = GetSpellNameAndRank(spellId)
      if not spellName then return end
      
      -- Deduplicate: Ignore if we processed this exact cast recently (within 100ms)
      -- Nampower fires multiple AURA_CAST events for multi-effect spells (e.g. Faerie Fire has 3 effects)
      recentCasts[targetGuid] = recentCasts[targetGuid] or {}
      recentCasts[targetGuid][spellName] = recentCasts[targetGuid][spellName] or {}
      
      local now = GetTime()
      local lastCastTime = recentCasts[targetGuid][spellName][casterGuid]
      
      if lastCastTime and (now - lastCastTime) < AURA_CAST_DEDUPE_WINDOW then
        return  -- Duplicate event, ignore
      end
      
      recentCasts[targetGuid][spellName][casterGuid] = now
      
      -- Get player GUID early for tracking
      local myGuid = GetPlayerGuid()
      local isOurs = (myGuid and casterGuid == myGuid)
      
      -- Track cast in recentHits for SPELL_DAMAGE_EVENT DoT detection
      -- If our spell: track it so SPELL_DAMAGE can distinguish initial hit from DoT tick
      if isOurs and targetGuid then
        recentHits[targetGuid] = recentHits[targetGuid] or {}
        recentHits[targetGuid][spellName] = now
      end
      
      -- Rank aus spellId ermitteln
      local rankNum = 0
      local rankString = GetSpellRecField(spellId, "rank")
      if rankString and rankString ~= "" then
        rankNum = tonumber((string.gsub(rankString, "Rank ", ""))) or 0
      end
      
      local duration = durationMs and (durationMs / 1000) or 0
      local startTime = GetTime()
      
      if debugStats.enabled and isOurs then
        debugStats.aura_cast = debugStats.aura_cast + 1
      end
      
      -- libspelldata: Duration override logic
      local usedCP = nil  -- for debug output
      if libspelldata then
        if libspelldata:IsComboPointAbility(spellName) then
          -- CP abilities: AURA_CAST returns durationMs=0, must calculate ourselves
          if isOurs then
            -- OWN casts: use captured CPs from SPELL_CAST_EVENT
            local cp = capturedCP or 0
            usedCP = cp
            local base, perCP = libspelldata:GetComboPointData(spellName)
            if base and perCP then
              duration = base + cp * perCP
            else
              -- Fallback to legacy database
              duration = libdebuff:GetDuration(spellName, rankNum)
            end
            capturedCP = nil  -- consumed
          else
            -- OTHER players: CP unknown, no timer (except Expose Armor = fixed 30s)
            local base, perCP = libspelldata:GetComboPointData(spellName)
            if perCP and perCP == 0 and base then
              duration = base  -- fixed duration (Expose Armor)
            else
              duration = 0
            end
          end
        elseif duration == 0 then
          -- Non-CP managed spells (Judgements etc.): only when AURA_CAST returned 0
          local spellDuration = libspelldata:GetDuration(spellName)
          if spellDuration ~= nil then
            duration = spellDuration
          end
        end
      end
      
      -- Fallback: If duration is still 0 and we have a legacy database entry, use that
      if duration == 0 and isOurs then
        local legacyDur = libdebuff:GetDuration(spellName, rankNum)
        if legacyDur and legacyDur > 0 then
          duration = legacyDur
        end
      end
      
      -- Store in allAuraCasts
      if targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        allAuraCasts[targetGuid] = allAuraCasts[targetGuid] or {}
        allAuraCasts[targetGuid][spellName] = allAuraCasts[targetGuid][spellName] or {}
        
        -- Cache spell classification from libspelldata (checked multiple times below)
        local isSelfOverwrite = libspelldata and libspelldata:IsSelfOverwrite(spellName)
        local overwritePair = libspelldata and libspelldata:GetOverwritePair(spellName)
        
        -- Downrank Protection: Check BEFORE clearing old casters!
        -- For selfOverwrite debuffs, check ALL existing casters
        if isSelfOverwrite then
          for otherCaster, existingData in pairs(allAuraCasts[targetGuid][spellName]) do
            if existingData.rank and rankNum and rankNum > 0 then
              local existingTimeleft = (existingData.startTime + existingData.duration) - GetTime()
              if existingTimeleft > 0 and rankNum < existingData.rank then
                -- Lower rank cannot overwrite higher rank - block the update
                if debugStats.enabled then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d from %s cannot overwrite Rank %d from %s (%.1fs left)", 
                    spellName, rankNum, DebugGuid(casterGuid), existingData.rank, DebugGuid(otherCaster), existingTimeleft))
                end
                return
              end
            end
          end
        else
          -- For non-selfOverwrite: Check only same caster
          local existingData = allAuraCasts[targetGuid][spellName][casterGuid]
          if existingData and existingData.rank and rankNum and rankNum > 0 then
            local existingTimeleft = (existingData.startTime + existingData.duration) - GetTime()
            if existingTimeleft > 0 and rankNum < existingData.rank then
              if debugStats.enabled and isOurs then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)", 
                  spellName, rankNum, existingData.rank, existingTimeleft))
              end
              return
            end
          end
        end
        
        -- Handle self-overwrite debuffs (clear other casters)
        if isSelfOverwrite then
          local n = 0
          for otherCaster in pairs(allAuraCasts[targetGuid][spellName]) do
            if otherCaster ~= casterGuid then
              n = n + 1
              _cleanupBuf1[n] = otherCaster
            end
          end
          for i = 1, n do
            allAuraCasts[targetGuid][spellName][_cleanupBuf1[i]] = nil
            _cleanupBuf1[i] = nil
          end
          
          -- Clear from ownDebuffs if we're being overwritten
          if not isOurs and ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
            ownDebuffs[targetGuid][spellName] = nil
          end
        end
        
        -- Handle variant pairs (Faerie Fire <-> Faerie Fire (Feral))
        if overwritePair then
          if allAuraCasts[targetGuid][overwritePair] and allAuraCasts[targetGuid][overwritePair][casterGuid] then
            allAuraCasts[targetGuid][overwritePair][casterGuid] = nil
          end
        end
        
        -- Store timer data
        allAuraCasts[targetGuid][spellName][casterGuid] = {
          startTime = startTime,
          duration = duration,
          rank = rankNum
        }
        
        -- UPDATE slotOwnership for selfOverwrite refreshes
        -- (DEBUFF_ADDED doesn't fire on refresh, so we must update here!)
        if isSelfOverwrite and slotOwnership[targetGuid] then
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName then
              -- Update the casterGuid and isOurs for this slot
              ownership.casterGuid = casterGuid
              ownership.isOurs = isOurs
              
              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[SLOT UPDATED]|r aura=%d %s newCaster=%s isOurs=%s", 
                  auraSlot, spellName, DebugGuid(casterGuid), tostring(isOurs)))
              end
              break
            end
          end
        end
        
        if debugStats.enabled and IsCurrentTarget(targetGuid) then
          local cpInfo = usedCP and string.format(" cp=%d", usedCP) or ""
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[AURA_CAST]|r %s target=%s caster=%s isOurs=%s dur=%.1fs%s", 
            GetDebugTimestamp(), spellName, DebugGuid(targetGuid), DebugGuid(casterGuid), tostring(isOurs), duration, cpInfo))
        end
      end
      
      -- Notify nameplates
        if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
          pfUI.nameplates:OnAuraUpdate(targetGuid)
        end
        
        -- Notify unitframes of debuff updates (UNIT_AURA doesn't fire on refreshes!)
        -- Check player
        if UnitExists("player") then
          local _, playerGuid = UnitExists("player")
          if playerGuid == targetGuid and pfPlayer then
            pfPlayer.update_aura = true
          end
        end
        
        -- Check target
        if UnitExists("target") then
          local _, targetUnitGuid = UnitExists("target")
          if targetUnitGuid == targetGuid and pfTarget then
            pfTarget.update_aura = true
          end
        end
      
      -- APPLICATOR REFRESH IN AURA_CAST (with hit validation):
      -- Refresh passive proc debuffs when applicator spells hit
      -- Only refresh if we have confirmed the spell actually hit (via SPELL_GO/SPELL_DAMAGE tracking)
      if isOurs and targetGuid then
        -- Check if this spell hit recently (tracked from SPELL_GO or SPELL_DAMAGE_EVENT)
        local hasRecentHit = false
        if recentHits[targetGuid] and recentHits[targetGuid][spellName] then
          local timeSinceHit = now - recentHits[targetGuid][spellName]
          if timeSinceHit < HIT_TRACKING_WINDOW then
            hasRecentHit = true
          end
        end
        
        -- Only refresh if we confirmed the spell hit
        if hasRecentHit then
          RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
        end
      end
      
      -- Only track in ownDebuffs if it's OUR debuff
      if not isOurs then return end
      if targetGuid == myGuid then return end  -- Skip self-buffs
      if not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000" then return end
      
      -- Get texture
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Store in ownDebuffs
      ownDebuffs[targetGuid] = ownDebuffs[targetGuid] or {}
      
      if not ownDebuffs[targetGuid][spellName] then
        ownDebuffs[targetGuid][spellName] = {}
      end
      
      local data = ownDebuffs[targetGuid][spellName]
      
      -- Downrank Protection: Check if existing debuff is still active and has higher rank
      if data.startTime and data.duration and data.rank and rankNum > 0 then
        local existingTimeleft = (data.startTime + data.duration) - GetTime()
        if existingTimeleft > 0 then
          -- Existing debuff is still active
          if rankNum < data.rank then
            -- Lower rank cannot overwrite higher rank - block the update
            if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)", 
                spellName, rankNum, data.rank, existingTimeleft))
            end
            return
          end
        end
      end
      
      data.startTime = startTime
      data.duration = duration
      data.texture = texture
      data.rank = rankNum
      data.spellId = spellId
      
      -- Handle variant pairs for ownDebuffs
      local ownOverwritePair = libspelldata and libspelldata:GetOverwritePair(spellName)
      if ownOverwritePair then
        if ownDebuffs[targetGuid][ownOverwritePair] then
          ownDebuffs[targetGuid][ownOverwritePair] = nil
        end
      end
      
      -- Store for Cleveroids API
      objectsByGuid[targetGuid] = objectsByGuid[targetGuid] or {}
      objectsByGuid[targetGuid][spellId] = {
        start = startTime,
        duration = duration,
        caster = "player",
        stacks = 1
      }
      
    elseif event == "DEBUFF_ADDED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- Display slot (1-16), compacted
      local spellId = arg3
      local stacks = arg4
      local auraLevel = arg5
      local auraSlot_0based = arg6  -- NEW! Raw slot 0-based (32-47) from Nampower
      
      -- Convert 0-based (Nampower event) to 1-based (Lua GetUnitField array)
      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil
      
      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = GetSpellNameAndRank(spellId)
      if not spellName then return end
      
      if debugStats.enabled then
        debugStats.debuff_added = debugStats.debuff_added + 1
      end
      
      -- If unit is dead, cleanup and skip
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- Get auraSlot from event parameter (Nampower 2.29+)
      -- Fallback to GetUnitField lookup if not available
      if not auraSlot then
        local slotMap = GetDebuffSlotMap(guid)
        if slotMap and slotMap[displaySlot] then
          auraSlot = slotMap[displaySlot].auraSlot
        end
      end
      
      -- Final fallback: Calculate from displaySlot
      -- (Assumes no gaps - not always true, but better than nothing)
      if not auraSlot then
        auraSlot = 32 + displaySlot
      end
      
      -- Get caster from pendingCasts (SPELL_GO correlation)
      local casterGuid = nil
      if pendingCasts[guid] and pendingCasts[guid][spellName] then
        local pending = pendingCasts[guid][spellName]
        if GetTime() - pending.time < 0.5 then
          casterGuid = pending.casterGuid
          pendingCasts[guid][spellName] = nil
        end
      end
      
      -- AoE spells (Hurricane, Consecration): no targetGuid in SPELL_GO
      if not casterGuid and pendingAoE[spellName] then
        -- Search through all pending casters for this AoE spell (supports multiple simultaneous casts)
        local bestMatch = nil
        local bestAge = 999
        
        for pendingCasterGuid, pending in pairs(pendingAoE[spellName]) do
          local age = GetTime() - pending.time
          if age < 0.05 and age < bestAge then  -- 50ms window - find most recent
            bestMatch = pendingCasterGuid
            bestAge = age
          end
        end
        
        if bestMatch then
          casterGuid = bestMatch
          
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff00cc[AOE CASTER FOUND]|r %s from pendingAoE caster=%s age=%.2fs", 
              GetDebugTimestamp(), spellName, DebugGuid(casterGuid), bestAge))
          end
        elseif debugStats.enabled and IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff0000[AOE EXPIRED]|r %s pendingAoE too old", 
            GetDebugTimestamp(), spellName))
        end
      elseif not casterGuid and debugStats.enabled and IsCurrentTarget(guid) and libspelldata and libspelldata:HasForcedDuration(spellName) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff0000[CASTER UNKNOWN]|r %s no pendingAoE entry found!", 
          GetDebugTimestamp(), spellName))
      end
      
      -- Fallback for forced-duration spells: Check if we already have a timer for this spell
      -- This handles: 1) AoE ticks after pendingAoE expired, 2) Passive procs (Fire Vulnerability)
      if not casterGuid and libspelldata and libspelldata:HasForcedDuration(spellName) then
        if allAuraCasts[guid] and allAuraCasts[guid][spellName] then
          -- Find the most recent active caster for this spell
          local mostRecentTime = 0
          local mostRecentCaster = nil
          for casterId, data in pairs(allAuraCasts[guid][spellName]) do
            local timeleft = (data.startTime + data.duration) - GetTime()
            if timeleft > -1 and data.startTime > mostRecentTime then  -- grace period
              mostRecentTime = data.startTime
              mostRecentCaster = casterId
            end
          end
          
          if mostRecentCaster then
            casterGuid = mostRecentCaster
            
            -- Check if it's ours
            local myGuid = GetPlayerGuid()
            if myGuid and casterGuid == myGuid then
              isOurs = true
            end
            
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[CASTER RESOLVED]|r %s found existing caster=%s isOurs=%s", 
                GetDebugTimestamp(), spellName, DebugGuid(casterGuid), tostring(isOurs)))
            end
          end
        end
      end
      
      -- libspelldata: Check applicator tracking (e.g. Judgement → JoW caster)
      if not casterGuid and libspelldata then
        casterGuid = libspelldata:OnDebuffAdded(guid, spellId, spellName)
      end
      
      -- pendingApplicators: Track passive proc debuffs (e.g., Scorch → Fire Vulnerability)
      -- Only assigns ownership if PLAYER cast the applicator spell recently
      if not casterGuid and libspelldata and libspelldata:HasForcedDuration(spellName) then
        if pendingApplicators[guid] then
          local timeSinceCast = GetTime() - pendingApplicators[guid].time
          if timeSinceCast < 0.5 then
            -- Player cast spell on this target very recently - assign ownership
            local myGuid = GetPlayerGuid()
            if myGuid then
              casterGuid = myGuid
              isOurs = true
              
              if debugStats.enabled and IsCurrentTarget(guid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[APPLICATOR]|r %s applied by player's %s (%.2fs ago)", 
                  GetDebugTimestamp(), spellName, pendingApplicators[guid].spell, timeSinceCast))
              end
            end
            
            -- Clear pending applicator
            pendingApplicators[guid] = nil
          end
        end
      end
      
      -- Fallback: Check allAuraCasts for most recent caster
      if not casterGuid and allAuraCasts[guid] and allAuraCasts[guid][spellName] then
        local mostRecent = nil
        local mostRecentTime = 0
        for casterId, data in pairs(allAuraCasts[guid][spellName]) do
          if data.startTime > mostRecentTime then
            mostRecentTime = data.startTime
            mostRecent = casterId
          end
        end
        if mostRecent then
          casterGuid = mostRecent
        end
      end
      
      local myGuid = GetPlayerGuid()
      local isOurs = (myGuid and casterGuid == myGuid)
      
      -- Fallback: Check ownDebuffs timing
      if not isOurs and not casterGuid then
        if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
          local age = GetTime() - ownDebuffs[guid][spellName].startTime
          if age < 0.5 then
            isOurs = true
            casterGuid = myGuid
          end
        end
      end
      
      -- libspelldata: Create timer for forced-duration spells (no AURA_CAST fires)
      -- e.g. Judgement of Wisdom: DEBUFF_ADDED is the only event, create timer here
      -- Also handles passive talent procs like Fire Vulnerability (no caster detected)
      if libspelldata and libspelldata:HasForcedDuration(spellName) then
        -- If no caster detected, assume it's ours (passive talent procs)
        if not casterGuid then
          casterGuid = GetPlayerGuid()
          isOurs = true
          
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[PASSIVE PROC]|r %s assumed ours (no caster)", 
              spellName))
          end
        end
      end
      
      -- Store slot ownership (KEY: auraSlot is STABLE, no shifting needed!)
      -- Must be AFTER passive proc detection so we have correct casterGuid/isOurs
      slotOwnership[guid] = slotOwnership[guid] or {}
      slotOwnership[guid][auraSlot] = {
        casterGuid = casterGuid,
        spellName = spellName,
        spellId = spellId,
        isOurs = isOurs
      }
      
      -- Store displaySlot → auraSlot mapping for DEBUFF_REMOVED
      displayToAura[guid] = displayToAura[guid] or {}
      displayToAura[guid][displaySlot] = auraSlot
      
      if debugStats.enabled then
        local stackStr = stacks and stacks > 1 and string.format(" x%d", stacks) or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[DEBUFF_ADDED]|r display=%d aura=%d %s%s caster=%s isOurs=%s guid=%s", 
          GetDebugTimestamp(), displaySlot, auraSlot, spellName, stackStr, DebugGuid(casterGuid), tostring(isOurs), DebugGuid(guid)))
      end
      
      -- libspelldata: Create timer for forced-duration spells (now that we have casterGuid from passive proc detection)
      if libspelldata and libspelldata:HasForcedDuration(spellName) and casterGuid then
        local hasExistingTimer = false
        if allAuraCasts[guid] and allAuraCasts[guid][spellName] and allAuraCasts[guid][spellName][casterGuid] then
          local existingData = allAuraCasts[guid][spellName][casterGuid]
          local existingTimeleft = (existingData.startTime + existingData.duration) - GetTime()
          
          -- Check if this was refreshed by an applicator spell
          local wasRefreshedByApplicator = false
          if pendingApplicators[guid] then
            local timeSinceCast = GetTime() - pendingApplicators[guid].time
            if timeSinceCast < 1.0 and libspelldata:IsApplicatorSpell(spellName, pendingApplicators[guid].spell) then
              wasRefreshedByApplicator = true
            end
          end
          
          -- If timer is still valid AND (was refreshed by applicator OR recently created), use it
          if existingTimeleft > 0 and (wasRefreshedByApplicator or (GetTime() - existingData.startTime) < 10) then
            hasExistingTimer = true
            
            if debugStats.enabled and IsCurrentTarget(guid) then
              local reason = wasRefreshedByApplicator and "refreshed by applicator" or "recently created"
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[TIMER EXISTS]|r %s using existing timer (%.1fs left, %s)", 
                spellName, existingTimeleft, reason))
            end
          end
        end
        
        -- Only create new timer if we don't have one already
        if not hasExistingTimer then
          local forcedDur = libspelldata:GetDuration(spellName)
          if forcedDur and forcedDur > 0 then
            local now = GetTime()
            local texture = libdebuff:GetSpellIcon(spellId)
            
            -- Store in allAuraCasts
            allAuraCasts[guid] = allAuraCasts[guid] or {}
            allAuraCasts[guid][spellName] = allAuraCasts[guid][spellName] or {}
            allAuraCasts[guid][spellName][casterGuid] = {
              startTime = now,
              duration = forcedDur,
              rank = 0
            }
            
            -- Store in ownDebuffs if ours
            if isOurs then
              ownDebuffs[guid] = ownDebuffs[guid] or {}
              ownDebuffs[guid][spellName] = {
                startTime = now,
                duration = forcedDur,
                texture = texture,
                rank = 0,
                spellId = spellId
              }
            end
            
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[FORCED TIMER]|r %s dur=%.1f caster=%s", 
                spellName, forcedDur, DebugGuid(casterGuid)))
            end
          end
        end
      end
      
      -- CRITICAL FIX: Update ownDebuffs here too for refresh timing!
      -- This prevents the gap between DEBUFF_REMOVED and AURA_CAST where buffwatch shows nothing
      if isOurs and casterGuid then
        local myGuid = GetPlayerGuid()
        if myGuid and casterGuid == myGuid then
          -- Check if we have timer data from allAuraCasts
          if allAuraCasts[guid] and allAuraCasts[guid][spellName] and allAuraCasts[guid][spellName][casterGuid] then
            local auraData = allAuraCasts[guid][spellName][casterGuid]
            local texture = libdebuff:GetSpellIcon(spellId)
            
            ownDebuffs[guid] = ownDebuffs[guid] or {}
            ownDebuffs[guid][spellName] = {
              startTime = auraData.startTime,
              duration = auraData.duration,
              texture = texture,
              rank = auraData.rank or 0,
              spellId = spellId
            }
            
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[OWNDEBUFF SYNC]|r %s from DEBUFF_ADDED", spellName))
              DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff888888└ startTime=%.1f duration=%.1f texture=%s|r", auraData.startTime, auraData.duration, tostring(texture ~= nil)))
            end
          end
        end
      end
      
      -- Cleanup expired timers
      CleanupExpiredTimers(guid)
      
      -- Notify nameplates
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
      
      -- Notify buffwatch (CRITICAL for non-SuperWoW clients!)
      -- UNIT_AURA doesn't fire reliably without SuperWoW, so we must manually notify
      if pfUI.buffwatch and pfUI.buffwatch.OnAuraUpdate then
        pfUI.buffwatch:OnAuraUpdate(guid)
      end
      
    elseif event == "DEBUFF_REMOVED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- Display slot (1-16), compacted
      local spellId = arg3
      local stacks = arg4
      local auraLevel = arg5
      local auraSlot_0based = arg6  -- NEW! Raw slot 0-based (32-47) from Nampower
      
      -- Convert 0-based (Nampower event) to 1-based (Lua GetUnitField array)
      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil
      
      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = GetSpellNameAndRank(spellId) or "?"
      
      -- Notify libspelldata
      if libspelldata then
        libspelldata:OnDebuffRemoved(guid, spellId, spellName)
      end
      
      if debugStats.enabled then
        debugStats.debuff_removed = debugStats.debuff_removed + 1
        if IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[DEBUFF_REMOVED]|r display=%d aura=%d (0based=%d) %s", 
            GetDebugTimestamp(), displaySlot, auraSlot or -1, auraSlot_0based or -1, spellName))
        end
      end
      
      -- If unit is dead, cleanup all
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- Get auraSlot from event parameter (Nampower 2.29+)
      -- Fallback to displayToAura mapping if not available
      local foundAuraSlot = auraSlot
      if not foundAuraSlot and displayToAura[guid] and displayToAura[guid][displaySlot] then
        foundAuraSlot = displayToAura[guid][displaySlot]
      end
      
      local wasOurs = false
      local removedCasterGuid = nil
      
      if foundAuraSlot then
        -- Get ownership info for this specific slot
        if slotOwnership[guid] and slotOwnership[guid][foundAuraSlot] then
          local ownership = slotOwnership[guid][foundAuraSlot]
          wasOurs = ownership.isOurs
          removedCasterGuid = ownership.casterGuid
        end
        
        -- Clear both mappings (with nil-checks)
        if slotOwnership[guid] then
          slotOwnership[guid][foundAuraSlot] = nil
        end
        if displayToAura[guid] then
          displayToAura[guid][displaySlot] = nil
        end
        
        if debugStats.enabled and IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[SLOT CLEARED]|r aura=%d [arg6] %s wasOurs=%s caster=%s", 
            GetDebugTimestamp(), foundAuraSlot, spellName, tostring(wasOurs), DebugGuid(removedCasterGuid)))
        end
      end
      
      -- Remove from ownDebuffs if it was ours
      if wasOurs and ownDebuffs[guid] and ownDebuffs[guid][spellName] then
        local age = GetTime() - ownDebuffs[guid][spellName].startTime
        -- Only delete if not recently renewed
        if age > 1 then
          ownDebuffs[guid][spellName] = nil
        end
      end
      
      -- Remove from allAuraCasts
      if removedCasterGuid and allAuraCasts[guid] and allAuraCasts[guid][spellName] then
        if allAuraCasts[guid][spellName][removedCasterGuid] then
          local auraData = allAuraCasts[guid][spellName][removedCasterGuid]
          local age = GetTime() - auraData.startTime
          
          -- CRITICAL: Don't delete if this is an AoE spell with pending recast
          -- This prevents timer loss during the DEBUFF_REMOVED → DEBUFF_ADDED gap
          local isPendingRecast = false
          if libspelldata and libspelldata:HasForcedDuration(spellName) and pendingAoE[spellName] then
            -- Check if this specific caster has a pending recast
            if pendingAoE[spellName][removedCasterGuid] then
              local pending = pendingAoE[spellName][removedCasterGuid]
              -- Check if pending is recent (within last 10s)
              if (GetTime() - pending.time) < 10 then
                isPendingRecast = true
                
                if debugStats.enabled and IsCurrentTarget(guid) then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[AOE RECAST]|r %s timer preserved (pending recast detected)", 
                    GetDebugTimestamp(), spellName))
                end
              end
            end
          end
          
          -- Only delete if not recently refreshed AND no pending recast
          if age > 1 and not isPendingRecast then
            allAuraCasts[guid][spellName][removedCasterGuid] = nil
          end
        end
      end
      
      -- Cleanup expired timers
      CleanupExpiredTimers(guid)
      
      -- Notify nameplates
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
      
      -- Notify buffwatch (CRITICAL for non-SuperWoW clients!)
      if pfUI.buffwatch and pfUI.buffwatch.OnAuraUpdate then
        pfUI.buffwatch:OnAuraUpdate(guid)
      end
      
    elseif event == "PLAYER_TARGET_CHANGED" then
      if not UnitExists then return end
      local _, targetGuid = UnitExists("target")
      
      if targetGuid and targetGuid ~= "" then
        -- Invalidate slot map cache on retarget
        -- Prevents stale slot mappings after untarget/retarget cycles
        slotMapCache[targetGuid] = nil
        
        -- Cleanup expired timers for new target
        CleanupExpiredTimers(targetGuid)
        
        -- Force nameplate refresh on retarget
        -- Without this, nameplates show stale timer data after untarget/retarget cycles
        if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
          pfUI.nameplates:OnAuraUpdate(targetGuid, true)
          
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[TARGET_CHANGE]|r OnAuraUpdate called for %s", DebugGuid(targetGuid)))
            
            -- Show what's in ownDebuffs for this target
            if ownDebuffs[targetGuid] then
              for spell, data in pairs(ownDebuffs[targetGuid]) do
                local timeleft = (data.startTime + data.duration) - GetTime()
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  └ ownDebuffs['%s'] timeleft=%.1fs", spell, timeleft))
              end
            else
              DEFAULT_CHAT_FRAME:AddMessage("  └ ownDebuffs[guid] is nil")
            end
          end
        end
      end
    end
    
    -- Periodic cleanup
    CleanupOutOfRangeUnits()
  end)
  
  -- Cleveroids API
  if CleveRoids then
    CleveRoids.libdebuff = libdebuff
    libdebuff.objects = objectsByGuid
  end
end

-- add libdebuff to pfUI API
pfUI.api.libdebuff = libdebuff

-- Export GetDebuffSlotMap for external use (e.g., buffwatch for stable slot IDs)
libdebuff.GetDebuffSlotMap = GetDebuffSlotMap

-- Expose debugStats for external access
libdebuff.debugStats = debugStats

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

_G.SLASH_LIBDEBUGSTATS1 = "/libdebugstats"
_G.SlashCmdList["LIBDEBUGSTATS"] = function(msg)
  msg = string.lower(msg or "")
  
  if msg == "start" then
    debugStats.enabled = true
    debugStats.trackAllUnits = false
    debugStats.aura_cast = 0
    debugStats.debuff_added = 0
    debugStats.debuff_removed = 0
    debugStats.getunitfield_calls = 0
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[libdebuff]|r Debug tracking STARTED")
    
  elseif msg == "stop" then
    debugStats.enabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r Debug tracking STOPPED")
    
  elseif msg == "stats" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== LIBDEBUFF STATS (GetUnitField Edition) ===|r")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("AURA_CAST events: %d", debugStats.aura_cast))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("DEBUFF_ADDED events: %d", debugStats.debuff_added))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("DEBUFF_REMOVED events: %d", debugStats.debuff_removed))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GetUnitField calls: %d", debugStats.getunitfield_calls))
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00No manual slot shifting needed!|r")
    
  elseif msg == "target" then
    if not UnitExists("target") then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff]|r No target!")
      return
    end
    
    local _, guid = UnitExists("target")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== TARGET DEBUFF STATE ===|r")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GUID: %s", tostring(guid)))
    
    -- Show GetUnitField slot map
    local slotMap = GetDebuffSlotMap(guid)
    if slotMap then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GetUnitField Slots:|r")
      for displaySlot, data in pairs(slotMap) do
        local casterGuid, isOurs = GetSlotCaster(guid, data.auraSlot, data.spellName)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Display %d (aura %d): %s [caster=%s, ours=%s]", 
          displaySlot, data.auraSlot, data.spellName, DebugGuid(casterGuid), tostring(isOurs)))
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900No debuffs via GetUnitField|r")
    end
    
    -- Show ownDebuffs
    if ownDebuffs[guid] then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ownDebuffs:|r")
      for spell, data in pairs(ownDebuffs[guid]) do
        local timeleft = (data.startTime + data.duration) - GetTime()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: dur=%.1f left=%.1f", spell, data.duration, timeleft))
      end
    end
    
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[libdebuff] GetUnitField Edition - Commands:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats start - Start debug tracking")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats stop  - Stop debug tracking")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats stats - Show statistics")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats target - Show target debuff state")
  end
end

_G.SLASH_MEMCHECK1 = "/memcheck"
_G.SlashCmdList["MEMCHECK"] = function()
  local function countTable(t)
    local count = 0
    if not t then return 0 end
    for _ in pairs(t) do count = count + 1 end
    return count
  end
  
  local function countNestedEntries(t)
    local total = 0
    if not t then return 0 end
    for _, nested in pairs(t) do
      if type(nested) == "table" then
        total = total + countTable(nested)
      end
    end
    return total
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========== LIBDEBUFF MEMORY (GetUnitField Edition) ==========|r")
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00Primary Tables:|r"))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  ownDebuffs: %d GUIDs, %d debuffs", countTable(ownDebuffs), countNestedEntries(ownDebuffs)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  slotOwnership: %d GUIDs, %d slots", countTable(slotOwnership), countNestedEntries(slotOwnership)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  allAuraCasts: %d GUIDs", countTable(allAuraCasts)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  pendingCasts: %d GUIDs", countTable(pendingCasts)))
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00No ownSlots/allSlots (eliminated by GetUnitField approach!)|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff============================================================|r")
end

-- ============================================================================
-- Initialize ownDebuffs cache from current game state (for /reload scenarios)
-- ============================================================================
function libdebuff:InitializeOwnDebuffsCache(guid)
  if not guid or not GetUnitField then return end
  
  local debuffSlotMap = GetDebuffSlotMap(guid)
  if not debuffSlotMap then return end
  
  local now = GetTime()
  
  -- Scan all debuffs and add those where we are the caster to ownDebuffs
  for displaySlot, slotData in pairs(debuffSlotMap) do
    local auraSlot = slotData.auraSlot
    local spellName = slotData.spellName
    
    -- Get caster info
    local slotCasterGuid, isOurs = GetSlotCaster(guid, auraSlot, spellName)
    
    if isOurs then
      -- We are the caster - add to ownDebuffs cache
      if not ownDebuffs[guid] then
        ownDebuffs[guid] = {}
      end
      
      -- Only add if not already tracked
      if not ownDebuffs[guid][spellName] then
        ownDebuffs[guid][spellName] = {
          spellId = slotData.spellId,
          rank = nil,  -- Unknown after /reload
          texture = slotData.texture,
          duration = 0,  -- Unknown after /reload
          startTime = now,  -- Assume just applied
        }
      end
    end
  end
end

-- Delayed load message (after pfUI is fully loaded)
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function()
  this:UnregisterEvent("PLAYER_ENTERING_WORLD")
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r GetUnitField Edition loaded! UnitBuff() and UnitDebuff() available.")
end)