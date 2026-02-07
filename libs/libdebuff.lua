-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff - GetUnitField Edition ]]--
-- A pfUI library that detects and saves all ongoing debuffs of players, NPCs and enemies.
-- 
-- MAJOR REWRITE: Now uses GetUnitField for slot mapping instead of manual shifting.
-- Key insight: GetUnitField returns STABLE aura slots (33-48) that DON'T shift when 
-- debuffs expire. Only the display slots (UnitDebuff returns 1,2,3...) are compacted.
--
-- This eliminates ~400 lines of error-prone shift logic while maintaining full
-- multi-caster tracking support.
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

-- Nampower Support
local hasNampower = false

-- Set hasNampower immediately for functionality
if GetNampowerVersion then
  local major, minor, patch = GetNampowerVersion()
  patch = patch or 0
  -- Minimum required version: 2.27.2 (SPELL_FAILED_OTHER fix)
  if major > 2 or (major == 2 and minor > 27) or (major == 2 and minor == 27 and patch >= 2) then
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
        
        if major > 2 or (major == 2 and minor > 27) or (major == 2 and minor == 27 and patch >= 2) then
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Nampower v" .. versionString .. " detected - GetUnitField mode enabled!")
          
          -- Enable required Nampower CVars
          if SetCVar and GetCVar then
            local cvarsToEnable = {
              "NP_EnableSpellStartEvents",
              "NP_EnableSpellGoEvents", 
              "NP_EnableAuraCastEvents",
              "NP_EnableAutoAttackEvents"
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
          
        elseif major == 2 and minor == 27 and patch == 1 then
          DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff] WARNING: Nampower v2.27.1 detected!|r")
          DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff] Please update to v2.27.2 or higher!|r")
          StaticPopup_Show("LIBDEBUFF_NAMPOWER_UPDATE", versionString)
        else
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] Debuff tracking disabled! Please update Nampower to v2.27.2 or higher.|r")
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

-- ============================================================================
-- STATIC POPUP DIALOGS
-- ============================================================================

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_UPDATE"] = {
  text = "Nampower Update Required!\n\nYour current version: %s\nRequired version: 2.27.2+\n\nPlease update Nampower!",
  button1 = "OK",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
  OnAccept = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Download: https://gitea.com/avitasia/nampower/releases/tag/v2.27.2")
  end,
}

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_MISSING"] = {
  text = "Nampower Not Found!\n\nNampower 2.27.2+ is required for pfUI Enhanced debuff tracking.\n\nPlease install Nampower.",
  button1 = "OK",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
}

-- ============================================================================
-- SPELL DATA TABLES
-- ============================================================================

-- Debuffs that only ONE player can have on target (overwrites other casters)
local selfOverwriteDebuffs = {
  ["Faerie Fire"] = true,
  ["Faerie Fire (Feral)"] = true,
  ["Demoralizing Shout"] = true,
  ["Demoralizing Roar"] = true,
  ["Hunter's Mark"] = true,
  ["Sunder Armor"] = true,
  ["Thunder Clap"] = true,
  ["Expose Armor"] = true,
  ["Curse of Weakness"] = true,
  ["Curse of Recklessness"] = true,
  ["Curse of the Elements"] = true,
  ["Curse of Shadow"] = true,
  ["Curse of Tongues"] = true,
  ["Curse of Exhaustion"] = true,
  ["Judgement of Wisdom"] = true,
  ["Judgement of Light"] = true,
  ["Judgement of the Crusader"] = true,
  ["Judgement of Justice"] = true,
  ["Shadow Weaving"] = true,
  ["Winter's Chill"] = true,
}

-- Debuff pairs that overwrite each other
local debuffOverwritePairs = {
  ["Faerie Fire"] = "Faerie Fire (Feral)",
  ["Faerie Fire (Feral)"] = "Faerie Fire",
  ["Demoralizing Shout"] = "Demoralizing Roar",
  ["Demoralizing Roar"] = "Demoralizing Shout",
}

-- Combopoint-based abilities: Only show timers for OUR casts
local combopointAbilities = {
  ["Rip"] = true,
  ["Rupture"] = true,
  ["Kidney Shot"] = true,
  ["Slice and Dice"] = true,
  ["Expose Armor"] = true,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Player GUID Cache
local playerGUID = nil
local function GetPlayerGUID()
  if not playerGUID and UnitExists then
    local _, guid = UnitExists("player")
    playerGUID = guid
  end
  return playerGUID
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
      -- GetSpellIconTexture may return short name, needs full path for SetTexture
      if texture and not string.find(texture, "\\") then
        texture = "Interface\\Icons\\" .. texture
      end
    end
  end
  
  if not texture and SpellInfo then
    local _, _, spellTexture = SpellInfo(spellId)
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

-- Get current debuff state directly from WoW via GetUnitField
-- Returns: { [displaySlot] = {auraSlot, spellId, spellName, stacks, texture, dtype} }
local function GetDebuffSlotMap(guid)
  if not guid or not GetUnitField or not SpellInfo then
    return nil
  end
  
  -- Check cache first
  local now = GetTime()
  local cached = slotMapCache[guid]
  if cached and (now - cached.timestamp) < SLOT_MAP_CACHE_DURATION then
    return cached.map
  end
  
  local auras = GetUnitField(guid, "aura")
  if not auras then return nil end
  
  -- Fetch stacks array (reusable reference - extract values immediately)
  local auraApps = GetUnitField(guid, "auraApplications")
  
  if debugStats.enabled then
    debugStats.getunitfield_calls = debugStats.getunitfield_calls + 1
  end
  
  local map = {}
  local displaySlot = 0
  
  -- Debuff aura slots are 33-48
  for auraSlot = 33, 48 do
    local spellId = auras[auraSlot]
    if spellId and spellId > 0 then
      displaySlot = displaySlot + 1
      local spellName = SpellInfo(spellId)
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Get stacks from auraApplications (extract immediately - reusable table)
      local stacks = auraApps and auraApps[auraSlot] or 0
      if stacks == 0 then stacks = 1 end  -- 0 means 1 stack (no stacking)
      
      -- Get debuff type from SpellRec DBC
      local dtype = nil
      if GetSpellRecField then
        local dispelId = GetSpellRecField(spellId, "dispel")
        if dispelId and dispelId > 0 then
          dtype = dispelTypeMap[dispelId]
        end
      end
      
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
  
  -- Cache the result
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
  local myGuid = GetPlayerGUID()
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
end

-- ============================================================================
-- DURATION FUNCTIONS
-- ============================================================================

function libdebuff:GetDuration(effect, rank)
  if L["debuffs"][effect] then
    local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
    local rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
    local duration = L["debuffs"][effect][rank]

    if effect == L["dyndebuffs"]["Rupture"] then
      local cp = GetComboPoints() or 0
      duration = duration + cp*2
    elseif effect == L["dyndebuffs"]["Kidney Shot"] then
      local cp = GetComboPoints() or 0
      duration = duration + cp*1
    elseif effect == "Rip" or effect == L["dyndebuffs"]["Rip"] then
      local cp = GetComboPoints() or 0
      duration = 8 + cp*2
    elseif effect == L["dyndebuffs"]["Demoralizing Shout"] then
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
    
    -- Get current slot map from GetUnitField (cached 50ms)
    local slotMap = GetDebuffSlotMap(guid)
    if not slotMap or not slotMap[displaySlot] then
      return nil
    end
    
    local slotData = slotMap[displaySlot]
    effect = slotData.spellName
    texture = slotData.texture
    stacks = slotData.stacks
    dtype = slotData.dtype
    local auraSlot = slotData.auraSlot
    
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
          caster = "player"
          rank = data.rank
        elseif remaining > -1 then
          -- Grace period - show 0 timeleft
          duration = data.duration
          timeleft = 0
          caster = "player"
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
            caster = "other"
            rank = data.rank
          end
        end
      end
      
      -- Fallback: Search all casters if specific one not found
      if not duration and allAuraCasts[guid] and allAuraCasts[guid][effect] then
        for anyCasterGuid, data in pairs(allAuraCasts[guid][effect]) do
          local remaining = (data.startTime + data.duration) - GetTime()
          if remaining > 0 and data.duration > 0 then
            duration = data.duration
            timeleft = remaining
            caster = "other"
            rank = data.rank
            break
          end
        end
      end
    end
    
    return effect, rank, texture, stacks, dtype, duration, timeleft, caster
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
-- API: UnitOwnDebuff (only OUR debuffs)
-- ============================================================================

-- Pre-defined sort function for UnitOwnDebuff (avoids closure creation per call)
local _ownDebuffSortFunc = function(a, b)
  if a.data.startTime == b.data.startTime then
    return a.spellName < b.spellName
  end
  return a.data.startTime < b.data.startTime
end

function libdebuff:UnitOwnDebuff(unit, id)
  if hasNampower and UnitExists then
    local _, guid = UnitExists(unit)
    if guid and ownDebuffs[guid] then
      -- Build sorted list of our active debuffs
      local sortedDebuffs = {}
      local now = GetTime()
      
      for spellName, data in pairs(ownDebuffs[guid]) do
        local timeleft = (data.startTime + data.duration) - now
        if timeleft > -1 then  -- Grace period
          local count = table.getn(sortedDebuffs) + 1
          sortedDebuffs[count] = {
            spellName = spellName,
            data = data,
            timeleft = timeleft
          }
        end
      end
      
      -- Sort by startTime (oldest first = lowest display slot)
      -- If startTime is equal (e.g. after Carnage refresh), use spellName for stable sorting
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
    return nil
  end
  
  -- Fallback: Iterate through all debuffs and filter
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
      return data.startTime, data.duration, timeleft, data.rank, GetPlayerGUID()
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
    local myGuid = GetPlayerGUID()
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
-- NAMPOWER EVENT HANDLING
-- ============================================================================

if hasNampower then
  -- Carnage Talent Rank
  local carnageRank = 0
  local function UpdateCarnageRank()
    if class ~= "DRUID" then return end
    local _, _, _, _, rank = GetTalentInfo(2, 17)
    carnageRank = rank or 0
  end
  
  -- Persistent Carnage check frame (reused instead of CreateFrame per Bite)
  local carnageState = nil  -- {targetGuid, checkTime}
  local carnageCheckFrame = CreateFrame("Frame")
  carnageCheckFrame:Hide()
  carnageCheckFrame:SetScript("OnUpdate", function()
    if not carnageState then
      this:Hide()
      return
    end
    if GetTime() < carnageState.checkTime then return end
    
    -- Check if we gained a combo point (indicates Carnage proc)
    local cp = GetComboPoints() or 0
    
    if cp > 0 then
      -- Carnage triggered! Refresh Rip & Rake
      local guid = carnageState.targetGuid
      local refreshTime = GetTime()
      local myGuid = GetPlayerGUID()
      
      -- Refresh in ownDebuffs
      if ownDebuffs[guid] then
        if ownDebuffs[guid]["Rip"] then
          ownDebuffs[guid]["Rip"].startTime = refreshTime
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE]|r Rip refreshed (CP detected)")
          end
        end
        if ownDebuffs[guid]["Rake"] then
          ownDebuffs[guid]["Rake"].startTime = refreshTime
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE]|r Rake refreshed (CP detected)")
          end
        end
      end
      
      -- Refresh in allAuraCasts
      if allAuraCasts[guid] then
        if allAuraCasts[guid]["Rip"] and allAuraCasts[guid]["Rip"][myGuid] then
          allAuraCasts[guid]["Rip"][myGuid].startTime = refreshTime
        end
        if allAuraCasts[guid]["Rake"] and allAuraCasts[guid]["Rake"][myGuid] then
          allAuraCasts[guid]["Rake"][myGuid].startTime = refreshTime
        end
      end
      
      -- Trigger UI updates
      if pfTarget and UnitExists("target") then
        local _, currentTargetGuid = UnitExists("target")
        if currentTargetGuid == guid then
          pfTarget.update_aura = true
        end
      end
      
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
    end
    
    carnageState = nil
    this:Hide()
  end)
  
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_TALENT_UPDATE")
  frame:RegisterEvent("PLAYER_LOGOUT")
  frame:RegisterEvent("SPELL_START_SELF")
  frame:RegisterEvent("SPELL_START_OTHER")
  frame:RegisterEvent("SPELL_GO_SELF")
  frame:RegisterEvent("SPELL_GO_OTHER")
  frame:RegisterEvent("SPELL_FAILED_OTHER")
  frame:RegisterEvent("AURA_CAST_ON_SELF")
  frame:RegisterEvent("AURA_CAST_ON_OTHER")
  frame:RegisterEvent("DEBUFF_ADDED_OTHER")
  frame:RegisterEvent("DEBUFF_REMOVED_OTHER")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UNIT_HEALTH")
  
  frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
      
    elseif event == "PLAYER_ENTERING_WORLD" then
      GetPlayerGUID()
      UpdateCarnageRank()
      
    elseif event == "PLAYER_TALENT_UPDATE" then
      UpdateCarnageRank()
      
    elseif event == "UNIT_HEALTH" then
      local guid = arg1
      if guid and UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
      end
      
    elseif event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local castTime = arg6
      
      if not casterGuid or not spellId then return end
      
      local spellName = SpellInfo and SpellInfo(spellId) or nil
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
      
      -- Clear cast bar only if SPELL_GO matches the active cast
      -- (Reactive procs like Frost Armor trigger SPELL_GO but shouldn't clear the castbar)
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        if pfUI.libdebuff_casts[casterGuid].spellID == spellId then
          pfUI.libdebuff_casts[casterGuid] = nil
        end
      end
      
      if numMissed > 0 or numHit == 0 then return end
      if not SpellInfo then return end
      
      local spellName, spellRankString = SpellInfo(spellId)
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
      local myGuid = GetPlayerGUID()
      if casterGuid == myGuid then
        lastCastRanks[spellName] = {
          rank = castRank,
          time = GetTime()
        }
      end
      
      -- CARNAGE TALENT: Ferocious Bite refreshes Rip & Rake
      -- Check for combo point gain after Bite (indicates Carnage proc)
      -- Carnage gives +1 CP immediately after Bite if it procs
      if class == "DRUID" and carnageRank >= 1 and spellName == "Ferocious Bite" and casterGuid == myGuid then
        if targetGuid and numHit > 0 then
          -- Schedule delayed check (50ms to allow CP to register)
          carnageState = {
            targetGuid = targetGuid,
            checkTime = GetTime() + 0.05
          }
          carnageCheckFrame:Show()
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
      
      if not SpellInfo or not spellId then return end
      if not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000" then return end
      
      local spellName = SpellInfo(spellId)
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
      
      -- Rank aus spellId ermitteln
      local rankNum = 0
      local rankString = GetSpellRecField(spellId, "rank")
      if rankString and rankString ~= "" then
        rankNum = tonumber((string.gsub(rankString, "Rank ", ""))) or 0
      end
      
      local duration = durationMs and (durationMs / 1000) or 0
      local startTime = GetTime()
      local myGuid = GetPlayerGUID()
      local isOurs = (myGuid and casterGuid == myGuid)
      
      if debugStats.enabled and isOurs then
        debugStats.aura_cast = debugStats.aura_cast + 1
      end
      
      -- CP-based spells: Use GetDuration for our casts
      if isOurs and combopointAbilities[spellName] then
        duration = libdebuff:GetDuration(spellName, rankNum)
      end
      
      -- CP-based spells: Force duration=0 for others (unknown!)
      if not isOurs and combopointAbilities[spellName] then
        if spellName == "Expose Armor" then
          duration = 30  -- Fixed duration for Expose Armor
        else
          duration = 0
        end
      end
      
      -- Store in allAuraCasts
      if targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        allAuraCasts[targetGuid] = allAuraCasts[targetGuid] or {}
        allAuraCasts[targetGuid][spellName] = allAuraCasts[targetGuid][spellName] or {}
        
        -- Downrank Protection: Check BEFORE clearing old casters!
        -- For selfOverwrite debuffs, check ALL existing casters
        if selfOverwriteDebuffs[spellName] then
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
        if selfOverwriteDebuffs[spellName] then
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
        if debuffOverwritePairs[spellName] then
          local otherVariant = debuffOverwritePairs[spellName]
          if allAuraCasts[targetGuid][otherVariant] and allAuraCasts[targetGuid][otherVariant][casterGuid] then
            allAuraCasts[targetGuid][otherVariant][casterGuid] = nil
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
        if selfOverwriteDebuffs[spellName] and slotOwnership[targetGuid] then
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
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[AURA_CAST]|r %s target=%s caster=%s isOurs=%s dur=%.1fs", 
            GetDebugTimestamp(), spellName, DebugGuid(targetGuid), DebugGuid(casterGuid), tostring(isOurs), duration))
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
      if debuffOverwritePairs[spellName] then
        local otherVariant = debuffOverwritePairs[spellName]
        if ownDebuffs[targetGuid][otherVariant] then
          ownDebuffs[targetGuid][otherVariant] = nil
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
      local displaySlot = arg2  -- This is DISPLAY slot (1-16), NOT aura slot!
      local spellId = arg3
      local stacks = arg4
      
      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = SpellInfo and SpellInfo(spellId)
      if not spellName then return end
      
      if debugStats.enabled then
        debugStats.debuff_added = debugStats.debuff_added + 1
      end
      
      -- If unit is dead, cleanup and skip
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- Find the REAL aura slot (33-48) via GetUnitField
      local auraSlot = nil
      local slotMap = GetDebuffSlotMap(guid)
      if slotMap and slotMap[displaySlot] then
        auraSlot = slotMap[displaySlot].auraSlot
      end
      
      -- Fallback: Calculate aura slot if GetUnitField didn't work
      -- (This assumes no gaps, which isn't always true, but better than nothing)
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
      
      local myGuid = GetPlayerGUID()
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
      
      -- Store slot ownership (KEY: auraSlot is STABLE, no shifting needed!)
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
      
      if debugStats.enabled and IsCurrentTarget(guid) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[DEBUFF_ADDED]|r display=%d aura=%d %s caster=%s isOurs=%s", 
          GetDebugTimestamp(), displaySlot, auraSlot, spellName, DebugGuid(casterGuid), tostring(isOurs)))
      end
      
      -- CRITICAL FIX: Update ownDebuffs here too for refresh timing!
      -- This prevents the gap between DEBUFF_REMOVED and AURA_CAST where buffwatch shows nothing
      if isOurs and casterGuid then
        local myGuid = GetPlayerGUID()
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
      
    elseif event == "DEBUFF_REMOVED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- This is DISPLAY slot (1-16), NOT aura slot!
      local spellId = arg3
      
      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = SpellInfo and SpellInfo(spellId) or "?"
      
      if debugStats.enabled then
        debugStats.debuff_removed = debugStats.debuff_removed + 1
        if IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[DEBUFF_REMOVED]|r display=%d %s", 
            GetDebugTimestamp(), displaySlot, spellName))
        end
      end
      
      -- If unit is dead, cleanup all
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- Find the auraSlot using displaySlot mapping
      local wasOurs = false
      local removedCasterGuid = nil
      local foundAuraSlot = nil
      
      -- Use displayToAura mapping to find the correct auraSlot
      if displayToAura[guid] and displayToAura[guid][displaySlot] then
        foundAuraSlot = displayToAura[guid][displaySlot]
        
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
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[SLOT CLEARED]|r aura=%d %s wasOurs=%s caster=%s", 
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
          -- Only delete if not recently refreshed
          if age > 1 then
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
      
    elseif event == "PLAYER_TARGET_CHANGED" then
      -- Nothing special needed - GetUnitField will get fresh data on next query
      if not UnitExists then return end
      local _, targetGuid = UnitExists("target")
      
      if targetGuid and targetGuid ~= "" then
        -- Cleanup expired timers for new target
        CleanupExpiredTimers(targetGuid)
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

DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r GetUnitField Edition loaded!")