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

-- Nampower Support

-- Minimum required Nampower version -- update this single value when requirements change
local NAMPOWER_MIN_MAJOR = 4
local NAMPOWER_MIN_MINOR = 1
local NAMPOWER_MIN_PATCH = 0
local NAMPOWER_MIN_VERSION = NAMPOWER_MIN_MAJOR .. "." .. NAMPOWER_MIN_MINOR .. "." .. NAMPOWER_MIN_PATCH

-- Nampower startup check: show version info and ensure CVars are set.
-- Runs on first OnUpdate after PLAYER_ENTERING_WORLD to give Nampower time to initialize.
local nampowerCheckFrame = CreateFrame("Frame")
nampowerCheckFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
nampowerCheckFrame:SetScript("OnEvent", function()
  -- Defer to next frame so Nampower is fully initialized
  this:SetScript("OnUpdate", function()
    this:SetScript("OnUpdate", nil)
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)

    if GetNampowerVersion then
      local major, minor, patch = GetNampowerVersion()
      patch = patch or 0
      local versionString = major .. "." .. minor .. "." .. patch

      if major > NAMPOWER_MIN_MAJOR or (major == NAMPOWER_MIN_MAJOR and minor > NAMPOWER_MIN_MINOR) or (major == NAMPOWER_MIN_MAJOR and minor == NAMPOWER_MIN_MINOR and patch >= NAMPOWER_MIN_PATCH) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Nampower v" .. versionString .. " detected - GetUnitField mode enabled!")

        if SetCVar and GetCVar then
          local cvarsToEnable = {
            "NP_EnableSpellStartEvents",
            "NP_EnableSpellGoEvents",
            "NP_EnableAuraCastEvents",
            "NP_EnableAutoAttackEvents",
            "NP_EnableSpellHealEvents", 
          }
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
                if setSuccess then enabledCount = enabledCount + 1
                else failedCount = failedCount + 1 end
              end
            else
              failedCount = failedCount + 1
            end
          end

          if enabledCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r Enabled " .. enabledCount .. " Nampower CVars")
          elseif alreadyEnabledCount == table.getn(cvarsToEnable) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r All required Nampower CVars already enabled")
          end
          if failedCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff]|r Warning: Could not check/set " .. failedCount .. " CVars")
          end
        end

      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] Debuff tracking disabled! Please update Nampower to v" .. NAMPOWER_MIN_VERSION .. " or higher.|r")
        StaticPopup_Show("LIBDEBUFF_NAMPOWER_UPDATE", versionString)
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] Nampower not found! Debuff tracking disabled.|r")
      StaticPopup_Show("LIBDEBUFF_NAMPOWER_MISSING")
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

-- slotTimers: [targetGUID][auraSlot] = {startTime, duration}
-- Timer data keyed by stable Nampower auraSlot - no casterGuid needed
pfUI.libdebuff_slot_timers = pfUI.libdebuff_slot_timers or {}
local slotTimers = pfUI.libdebuff_slot_timers

-- pendingSlotTimer: [targetGUID][spellName] = {startTime, duration, rank}
-- Temporary: correlates AURA_CAST (has duration) with DEBUFF_ADDED (has auraSlot)
pfUI.libdebuff_pending_slot_timer = pfUI.libdebuff_pending_slot_timer or {}
local pendingSlotTimer = pfUI.libdebuff_pending_slot_timer

-- pfUI.libdebuff_sharedoverwrite_timers: [targetGUID][spellName] = {startTime, duration}
-- Persistent timer for sharedOverwrite debuffs in spillover slots (no DEBUFF_ADDED fires)
-- Written by AURA_CAST, read by IterDebuffs PASS 2, cleared by DEBUFF_REMOVED
pfUI.libdebuff_sharedoverwrite_timers = pfUI.libdebuff_sharedoverwrite_timers or {}

-- slotOwnership: [targetGUID][auraSlot] = {casterGuid, spellName, spellId}
-- Maps REAL aura slots (33-48) to caster info - NO SHIFTING NEEDED!
pfUI.libdebuff_slot_ownership = pfUI.libdebuff_slot_ownership or {}
local slotOwnership = pfUI.libdebuff_slot_ownership

-- displayToAura: [targetGUID][displaySlot] = auraSlot
-- Maps DISPLAY slots (1-16) to REAL aura slots (33-48) for DEBUFF_REMOVED correlation
pfUI.libdebuff_display_to_aura = pfUI.libdebuff_display_to_aura or {}
local displayToAura = pfUI.libdebuff_display_to_aura

-- spilloverSlots: [targetGUID][auraSlot] = true
-- Tracks which buff-region slots (1-32) currently hold spillover debuffs.
-- Populated by IterDebuffs PASS 2 when debuffSlotCount >= 16, then re-checked
-- on subsequent calls even if debuffSlotCount drops below 16.
-- Entries are removed when the slot is empty or no longer flagged as debuff.
-- Cleared on CleanupUnit (unit dies, out of range, etc.)
pfUI.libdebuff_spillover_slots = pfUI.libdebuff_spillover_slots or {}
local spilloverSlots = pfUI.libdebuff_spillover_slots

-- pendingCasts: [targetGUID][spellName] = {casterGuid, rank, time}
-- Temporary storage from SPELL_GO to correlate with DEBUFF_ADDED
pfUI.libdebuff_pending = pfUI.libdebuff_pending or {}
local pendingCasts = pfUI.libdebuff_pending

-- pendingAoE: [spellName] = {[casterGuid] = {time}}
-- AoE spells (Hurricane, Consecration) have no targetGuid in SPELL_GO
pfUI.libdebuff_pending_aoe = pfUI.libdebuff_pending_aoe or {}
local pendingAoE = pfUI.libdebuff_pending_aoe

-- pendingApplicators: [targetGuid] = {spell, time}
-- Tracks when player casts spells that apply passive proc debuffs
pfUI.libdebuff_pending_applicators = pfUI.libdebuff_pending_applicators or {}
local pendingApplicators = pfUI.libdebuff_pending_applicators

-- Hit tracking: Track successful spell hits for applicator refresh validation
-- [targetGuid][spellName] = timestamp
pfUI.libdebuff_recent_hits = pfUI.libdebuff_recent_hits or {}
local recentHits = pfUI.libdebuff_recent_hits

-- allAuraCasts: compatibility stub for external addons (SuperCleveRoidMacros etc.)
-- libdebuff uses slotOwnership/slotTimers instead, but keep this table so external
-- addons that index pfUI.libdebuff_all_auras don't crash
pfUI.libdebuff_all_auras = pfUI.libdebuff_all_auras or {}
local allAuraCasts = pfUI.libdebuff_all_auras

-- maxRankSeen: [targetGUID][spellName] = rankNum
-- Tracks highest rank we've ever applied per target - survives slot clear/re-apply cycles
-- Used by downrank protection so Rank 9 can't overwrite Rank 10 even after re-cast
pfUI.libdebuff_max_rank_seen = pfUI.libdebuff_max_rank_seen or {}
local maxRankSeen = pfUI.libdebuff_max_rank_seen

-- Cached melee-refreshable spells from libspelldata() (populated on first use)
local meleeRefreshSpells = nil

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

-- Callbacks fired after SPELL_GO_SELF is processed: fn(spellId, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
pfUI.libdebuff_spell_go_hooks = pfUI.libdebuff_spell_go_hooks or {}

-- Callbacks fired after SPELL_GO_OTHER is processed: fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_spell_go_other_hooks = pfUI.libdebuff_spell_go_other_hooks or {}

-- Callbacks fired after SPELL_START_SELF is processed: fn(spellId, casterGuid, targetGuid, castTime)
pfUI.libdebuff_spell_start_self_hooks = pfUI.libdebuff_spell_start_self_hooks or {}

-- Callbacks fired after SPELL_START_OTHER is processed: fn(spellId, casterGuid, targetGuid, castTime)
pfUI.libdebuff_spell_start_other_hooks = pfUI.libdebuff_spell_start_other_hooks or {}

-- Callbacks fired after SPELL_FAILED_OTHER is processed: fn(casterGuid, spellId)
pfUI.libdebuff_spell_failed_other_hooks = pfUI.libdebuff_spell_failed_other_hooks or {}

-- Callbacks fired after AURA_CAST_ON_SELF is processed: fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_aura_cast_on_self_hooks = pfUI.libdebuff_aura_cast_on_self_hooks or {}

-- Callbacks fired after AURA_CAST_ON_OTHER is processed: fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_aura_cast_on_other_hooks = pfUI.libdebuff_aura_cast_on_other_hooks or {}

-- Callbacks fired after DEBUFF_ADDED_OTHER is processed: fn(guid, luaSlot, spellId, stackCount)
pfUI.libdebuff_debuff_added_other_hooks = pfUI.libdebuff_debuff_added_other_hooks or {}

-- Callbacks fired after melee refresh updates slotTimers: fn(targetGuid)
pfUI.libdebuff_melee_refresh_hooks = pfUI.libdebuff_melee_refresh_hooks or {}

-- Callbacks fired after DEBUFF_REMOVED_OTHER is processed: fn(guid, luaSlot, spellId, stackCount)
pfUI.libdebuff_debuff_removed_other_hooks = pfUI.libdebuff_debuff_removed_other_hooks or {}

-- Generic signal: fired when target debuff state changes (AURA_CAST, DEBUFF_ADDED, DEBUFF_REMOVED, melee refresh)
-- fn(guid)
pfUI.libdebuff_target_updated_hooks = pfUI.libdebuff_target_updated_hooks or {}

-- Generic signal: fired specifically when timer data for a unit changes (slotTimers written or cleared)
-- fn(guid) - consumers: buffwatch, nameplates, unitframes
pfUI.libdebuff_on_unit_updated = pfUI.libdebuff_on_unit_updated or {}

-- Multi-tracking: Slot-to-caster mapping for accurate timer display
-- [guid][displaySlot] = { spellName, casterGuid }
-- Rebuilt on DEBUFF_ADDED/DEBUFF_REMOVED from Blizzard UnitDebuff + allAuraCasts

-- Callbacks fired after UNIT_HEALTH is processed: fn(unitToken)
pfUI.libdebuff_unit_health_hooks = pfUI.libdebuff_unit_health_hooks or {}

-- Callbacks fired after PLAYER_TARGET_CHANGED is processed: fn()
pfUI.libdebuff_player_target_changed_hooks = pfUI.libdebuff_player_target_changed_hooks or {}

-- Callbacks fired after UNIT_DIED is processed: fn(guid)
pfUI.libdebuff_unit_died_hooks = pfUI.libdebuff_unit_died_hooks or {}

-- Callbacks fired after SPELL_CAST_EVENT is processed: fn(success, spellId, castType, targetGuid)
pfUI.libdebuff_spell_cast_hooks = pfUI.libdebuff_spell_cast_hooks or {}
-- Overflow buffs: buffs that exist server-side but have no client aura slot
-- because all 32 buff slots are occupied. Tracked via AURA_CAST_ON_SELF.
-- [spellId] = { startTime, duration, texture, spellName }
pfUI.libdebuff_overflow_buffs = pfUI.libdebuff_overflow_buffs or {}
local overflowBuffs = pfUI.libdebuff_overflow_buffs

-- Forced no-timer SpellIDs (server reports wrong duration, hardcoded fix)
pfUI.libdebuff_forced_no_timer = pfUI.libdebuff_forced_no_timer or {
  [30200] = true,  -- Scythe of the Unborn (item equip buff, server stores wrong duration)
}
local forcedNoTimer = pfUI.libdebuff_forced_no_timer

-- Captured combo points from SPELL_CAST_EVENT (before client consumes them)
-- SPELL_CAST_EVENT fires BEFORE UnitAura updates, so GetComboPoints() still works
local capturedCP = nil

-- Pending cast info for libpredict (heal prediction target tracking)
-- SPELL_CAST_EVENT fires with targetGuid BEFORE SPELLCAST_START,
-- which allows libpredict to know the correct target for queued casts.
-- Fields: { spellId, spellName, targetGuid, time }
pfUI.libpredict_pending_cast = pfUI.libpredict_pending_cast or {}

-- ============================================================================
-- STATIC POPUP DIALOGS
-- ============================================================================

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_UPDATE"] = {
  text = "|cffff0000!!!WARNING!!!|r\n\nNampower Update Required!\n\nYour current version: %s\nRequired version: " .. NAMPOWER_MIN_VERSION .. "+\n\nPlease update Nampower to continue using pfUI!",
  button1 = "Show Download",
  button2 = "Dismiss",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0,
  preferredIndex = 3,
  OnAccept = function()
    pfUI.chat.urlcopy.CopyText("https://github.com/me0wg4ming/pfUI/wiki/How-to-install-nampower")
  end,
}

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_MISSING"] = {
  text = "|cffff0000!!!WARNING!!!|r\n\nNampower Not Found!\n\nNampower " .. NAMPOWER_MIN_VERSION .. "+ is required for pfUI to function correctly.\n\nPlease install Nampower!",
  button1 = "Show Download",
  button2 = "Dismiss",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0,
  preferredIndex = 3,
  OnAccept = function()
    pfUI.chat.urlcopy.CopyText("https://github.com/me0wg4ming/pfUI/wiki/How-to-install-nampower")
  end,
}

-- ============================================================================
-- SPELL DATA (via libspelldata())
-- ============================================================================

-- All spell knowledge tables (sharedOverwrite, overwritePairs, combopointAbilities,
-- forcedDurations, applicators) are now centralized in libspelldata().lua.
-- libdebuff queries libspelldata() via its API methods.
local _libspelldata = nil
local function libspelldata()
  if not _libspelldata then _libspelldata = pfUI.libspelldata end
  return _libspelldata
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Check if spell is a combo-point ability (delegates to libspelldata())
local function IsComboPointAbility(spellName)
  if libspelldata() then
    return libspelldata():IsComboPointAbility(spellName)
  end
  return false
end

-- Get combo-point spell data (delegates to libspelldata())
local function GetComboPointData(spellName)
  if libspelldata() then
    return libspelldata():GetComboPointData(spellName)
  end
  return nil, nil
end

-- Player GUID Cache
local playerGUID = nil
local function GetPlayerGUID()
  if not playerGUID and GetUnitGUID then
    local guid = GetUnitGUID("player")
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
  if not guid or not GetUnitGUID then return false end
  local targetGuid = GetUnitGUID("target")
  return targetGuid == guid
end

pfUI.libdebuff_fire_unit_updated = function(guid)
  if not guid or not pfUI.libdebuff_on_unit_updated then return end
  for _, fn in pairs(pfUI.libdebuff_on_unit_updated) do
    fn(guid)
  end
end

-- Batch dispatcher: deduplicates multiple queueUnitUpdated calls for the same
-- GUID within a single event cycle. Fires on the next OnUpdate frame.
-- Uses pfUI table instead of locals to stay within Lua 5.0 upvalue limit (32).
pfUI.libdebuff_pending_updates = pfUI.libdebuff_pending_updates or {}
pfUI.libdebuff_has_pending = false

local batchFrame = CreateFrame("Frame", "pfLibdebuffBatch", UIParent)
batchFrame:SetScript("OnUpdate", function()
  if not pfUI.libdebuff_has_pending then return end
  pfUI.libdebuff_has_pending = false
  local pending = pfUI.libdebuff_pending_updates
  for guid in pairs(pending) do
    pfUI.libdebuff_fire_unit_updated(guid)
    pending[guid] = nil
  end
end)

pfUI.libdebuff_queue_update = function(guid)
  if guid then
    pfUI.libdebuff_pending_updates[guid] = true
    pfUI.libdebuff_has_pending = true
  end
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
pfUI.libdebuff_slotmapcache = pfUI.libdebuff_slotmapcache or {}
local slotMapCache = pfUI.libdebuff_slotmapcache

-- auraFC: per-tick deduplication cache for GetUnitField("aura"/"auraApplications"/"auraFlags").
-- Single table to stay within Lua 5.0 upvalue limit (32).
-- First call per guid per tick always calls GetUnitField normally.
-- Second+ call returns cached result, saving redundant Nampower calls when
-- unitframes + nameplates + buffwatch all react to the same fire_unit_updated.
local auraFC = {}

local function GetCachedAuraField(guid)
  local now = GetTime()
  local c = auraFC[guid]
  if c and c[4] == now and c[5] then
    return c[1], c[2], c[3]
  end
  local auras     = GetUnitField(guid, "aura")
  local auraApps  = GetUnitField(guid, "auraApplications")
  local auraFlags = GetUnitField(guid, "auraFlags")
  if not auraFC[guid] then auraFC[guid] = {} end
  local e = auraFC[guid]
  e[1], e[2], e[3], e[4], e[5] = auras, auraApps, auraFlags, now, true
  return auras, auraApps, auraFlags
end

local function GetCachedAuraFlags(guid)
  if not guid or not GetUnitField then return nil end
  local _, _, auraFlags = GetCachedAuraField(guid)
  return auraFlags
end

-- PERF: knownUnits as upvalue (not re-created per call)
local _knownUnits = { target=true, player=true, pet=true, focus=true, mouseover=true }

-- Dispel type mapping: SpellRec.dispel index -> Blizzard DebuffTypeColor key
local dispelTypeMap = {
  [1] = "Magic",
  [2] = "Curse",
  [3] = "Disease",
  [4] = "Poison",
}

-- Get current debuff state directly from WoW via GetUnitField
-- Returns: { [displaySlot] = {auraSlot, spellId, spellName, stacks, texture, dtype} }
local function GetDebuffSlotMap(guidOrUnit)
  if not guidOrUnit or not GetUnitField then
    return nil
  end
  
  -- Handle case where GUID is passed as table (old Nampower format or bug)
  if type(guidOrUnit) == "table" then
    return nil
  end
  
  -- Determine if we got a GUID or a unitToken
  -- PERF: string.sub instead of string.find pattern matching
  local guid = guidOrUnit
  if _knownUnits[guidOrUnit] or (type(guidOrUnit) == "string" and string.sub(guidOrUnit, 1, 2) ~= "0x") then
    if UnitExists and UnitExists(guidOrUnit) then
      local _, unitGuid = UnitExists(guidOrUnit)
      guid = unitGuid
    else
      return nil
    end
  end

  -- Check cache first (use GUID as key)
  local now = GetTime()
  local cached = slotMapCache[guid]
  if cached and cached.map and (now - cached.timestamp) < 0.05 then
    return cached.map
  end

  local auras = GetUnitField(guid, "aura")
  if not auras then
    return nil
  end
  
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
      -- Check hidelist
      local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
      
      if not isHidden then
        local texture = libdebuff:GetSpellIcon(spellId)
        
        local spellName = nil
        if GetSpellRecField then
          spellName = GetSpellRecField(spellId, "name")
          if spellName == "" then spellName = nil end
        end
        if not spellName then
          spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId)
        end
        
        local dtype = nil
        if GetSpellRecField then
          local dispelId = GetSpellRecField(spellId, "dispel")
          if dispelId and dispelId > 0 then
            dtype = dispelTypeMap[dispelId]
          end
        end
        
        if texture then
          displaySlot = displaySlot + 1
          
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
  end
  
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
  
  -- Fallback: check slotOwnership by spellName
  if slotOwnership[guid] then
    for auraSlot, ownership in pairs(slotOwnership[guid]) do
      if ownership.spellName == spellName then
        return ownership.casterGuid, ownership.isOurs
      end
    end
  end
  
  return nil, false
end

-- Register as pfUI functions so event handler can call via pfUI.* (avoids upvalue slots)
pfUI.libdebuff_get_slot_map    = GetDebuffSlotMap
pfUI.libdebuff_get_slot_caster = GetSlotCaster

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

local lastRangeCheck = 0

-- Recycled buffers for cleanup (avoids table creation per call)
pfUI.libdebuff_cleanupbuf = pfUI.libdebuff_cleanupbuf or { {}, {} }
local _cleanupBuf1 = pfUI.libdebuff_cleanupbuf[1]
local _cleanupBuf2 = pfUI.libdebuff_cleanupbuf[2]

local function CleanupUnit(guid)
  if not guid then return false end
  
  local cleaned = false
  
  -- Notify libspelldata()
  if libspelldata() then
    libspelldata():CleanupUnit(guid)
  end
  
  if ownDebuffs[guid] then
    ownDebuffs[guid] = nil
    cleaned = true
  end
  
  if slotOwnership[guid] then
    slotOwnership[guid] = nil
    cleaned = true
  end

  if slotTimers[guid] then
    slotTimers[guid] = nil
    cleaned = true
  end

  if pendingSlotTimer[guid] then
    pendingSlotTimer[guid] = nil
  end
  
  if objectsByGuid[guid] then
    objectsByGuid[guid] = nil
    cleaned = true
  end
  
  if pendingCasts[guid] then
    pendingCasts[guid] = nil
    cleaned = true
  end

  if displayToAura[guid] then
    displayToAura[guid] = nil
  end

  if spilloverSlots[guid] then
    if debugStats.enabled then
      local count = 0
      for _ in pairs(spilloverSlots[guid]) do count = count + 1 end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r CleanupUnit: removed spilloverSlots for %s (%d slots)", DebugGuid(guid), count))
    end
    spilloverSlots[guid] = nil
  end

  if slotMapCache[guid] then
    slotMapCache[guid] = nil
  end

  if recentHits[guid] then
    recentHits[guid] = nil
  end

  if pendingApplicators[guid] then
    pendingApplicators[guid] = nil
  end

  if pfUI.libdebuff_sharedoverwrite_timers[guid] then
    pfUI.libdebuff_sharedoverwrite_timers[guid] = nil
  end

  if recentCasts[guid] then
    recentCasts[guid] = nil
  end

  if auraFC[guid] then
    auraFC[guid] = nil
  end

  if maxRankSeen[guid] then
    maxRankSeen[guid] = nil
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
  
  -- Cleanup slotTimers (expired slots)
  if slotTimers[guid] then
    local n2 = 0
    for auraSlot, data in pairs(slotTimers[guid]) do
      local timeleft = (data.startTime + data.duration) - now
      if timeleft < -2 then
        n2 = n2 + 1
        _cleanupBuf2[n2] = auraSlot
      end
    end
    for i = 1, n2 do
      slotTimers[guid][_cleanupBuf2[i]] = nil
      _cleanupBuf2[i] = nil
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
  for guid in pairs(slotTimers) do allGuids[guid] = true end
  for guid in pairs(objectsByGuid) do allGuids[guid] = true end
  for guid in pairs(pendingCasts) do allGuids[guid] = true end
  for guid in pairs(displayToAura) do allGuids[guid] = true end
  for guid in pairs(recentHits) do allGuids[guid] = true end
  for guid in pairs(recentCasts) do allGuids[guid] = true end
  
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
  
  -- Cleanup old pendingAoE
  for spell, casters in pairs(pendingAoE) do
    for casterGuid, data in pairs(casters) do
      if now - data.time > 12 then  -- AoE channels can last up to 10s
        pendingAoE[spell][casterGuid] = nil
      end
    end
    if next(pendingAoE[spell]) == nil then
      pendingAoE[spell] = nil
    end
  end
end

-- ============================================================================
-- APPLICATOR REFRESH HELPER
-- ============================================================================

-- Refresh passive proc debuffs when applicator spells hit
local function RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
  if not libspelldata() or not slotOwnership[targetGuid] or not targetGuid or not spellName or not myGuid then
    return false
  end

  local now = GetTime()
  local refreshed = false

  -- Iterate all owned slots to find applicator targets
  for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
    local debuffName = ownership.spellName
    if debuffName and libspelldata():IsApplicatorSpell(debuffName, spellName) then
      local isShared = libspelldata():IsSharedOverwrite(debuffName)
      local isOurs = ownership.isOurs
      if isOurs or isShared then
        local duration = libspelldata():GetDuration(debuffName)
        if duration and slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot] then
          local data = slotTimers[targetGuid][auraSlot]
          -- Deduplication: skip if refreshed very recently
          if not data.startTime or (now - data.startTime) >= 0.05 then
            data.startTime = now
            data.duration = duration
            refreshed = true
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
  end

  if refreshed then
    pfUI.libdebuff_queue_update(targetGuid)
    if GetUnitGUID("target") then
      local currentTargetGuid = GetUnitGUID("target")
      if currentTargetGuid == targetGuid then
        libdebuff:UpdateUnits()
      end
    end
  end

  return refreshed
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

function libdebuff:UpdateUnits()
  -- Replaced by pfUI.libdebuff_fire_unit_updated hook system
  -- Kept as stub for external compat
end

-- libdebuff.objects kept as empty stub for external compat
libdebuff.objects = {}



-- ============================================================================
-- MAIN API: IterDebuffs + UnitDebuff
-- Directly iterates stable aura slots (33-48) from GetUnitField.
-- No UnitDebuff() call, no tooltip scanner, no RebuildDebuffSlots needed.
-- ============================================================================

-- IterDebuffs: iterate all debuffs on a unit by stable aura slot.
-- Callback fn(auraSlot, spellId, spellName, texture, stacks, dtype, duration, timeleft, caster, isOurs)
-- Returns number of debuffs found.
-- Helper: Extract 4-bit aura flag for a specific slot (1-48)
-- auraFlags is an array of 6 UINT32 values, each holding 8 slots × 4 bits
-- auraFlags[1] = slots 1-8, [2] = 9-16, [3] = 17-24, [4] = 25-32, [5] = 33-40, [6] = 41-48
local function GetAuraFlag(auraFlags, slot)
  if not auraFlags then return nil end
  local arrayIndex = math.ceil(slot / 8)
  local bitOffset = math.mod(slot - 1, 8) * 4
  local flags = auraFlags[arrayIndex]
  if not flags then return nil end
  return bit.band(bit.rshift(flags, bitOffset), 15)  -- extract 4-bit nibble
end

-- Check if an aura slot is a debuff via bit 3 (0x8) of its auraFlag
local function IsDebuffByFlag(auraFlags, slot)
  local flag = GetAuraFlag(auraFlags, slot)
  if not flag then return false end
  return bit.band(flag, 8) ~= 0
end

function libdebuff:IterDebuffs(unit, fn)
  if not fn or not GetUnitGUID or not GetUnitField then return 0 end

  local guid = GetUnitGUID(unit)
  if not guid then
    if debugStats.enabled then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[IterDebuffs] NO GUID for: "..(unit or "nil").."|r")
    end
    return 0
  end

  local auras, auraApps, auraFlagsCache = GetCachedAuraField(guid)
  if not auras then
    return 0
  end

  local myGuid = GetPlayerGUID()
  local now = GetTime()
  local count = 0
  local debuffSlotCount = 0
  local ls = libspelldata()  -- cache once per call, not per slot iteration

  -- ============================================================
  -- PASS 1: Normal debuff slots (33-48)
  -- ============================================================
  for auraSlot = 33, 48 do
    local spellId = auras[auraSlot]
    if spellId and spellId ~= 0 then
      debuffSlotCount = debuffSlotCount + 1
      local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
      if not isHidden then
        local texture = libdebuff:GetSpellIcon(spellId)
        if texture then
          local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
          if not spellName or spellName == "" then
            spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId) or "Unknown"
          end

          local rawStacks = auraApps and auraApps[auraSlot]
          local stacks = rawStacks and (rawStacks + 1) or 1

          local dtype = nil
          if GetSpellRecField then
            local dispelId = GetSpellRecField(spellId, "dispel")
            if dispelId and dispelId > 0 then
              dtype = dispelTypeMap[dispelId]
            end
          end

          -- Timer lookup: slotTimers keyed by auraSlot (stable with Nampower)
          local duration, timeleft, caster, isOurs = nil, -1, nil, false
          local ownership = slotOwnership[guid] and slotOwnership[guid][auraSlot]
          if ownership then
            isOurs = ownership.isOurs
          end
          caster = isOurs and "player" or "other"

          local st = slotTimers[guid] and slotTimers[guid][auraSlot]
          if st and st.duration and st.duration > 0 then
            local remaining = (st.startTime + st.duration) - now
            if remaining > -1 then
              duration = st.duration
              timeleft = remaining > 0 and remaining or 0
            end
          end

          -- Fallback: ownDebuffs for own spells when slotTimers missing
          -- For sharedOverwrite debuffs: also use ownDebuffs even if not ours (only 1 instance exists)
          local isSelfOverwrite = ls and ls:IsSharedOverwrite(spellName)
          if not duration and (isOurs or isSelfOverwrite) and ownDebuffs[guid] and ownDebuffs[guid][spellName] then
            local d = ownDebuffs[guid][spellName]
            local remaining = (d.startTime + d.duration) - now
            if remaining > -1 then
              duration = d.duration
              timeleft = remaining > 0 and remaining or 0
            end
          end

          count = count + 1
          fn(auraSlot, spellId, spellName, texture, stacks, dtype, duration, timeleft, caster, isOurs)
        end
      end
    end
  end

  -- ============================================================
  -- PASS 2: Spillover debuffs in buff slots (1-32)
  -- Icon + tooltip only, no timer except for sharedOverwrite debuffs
  --
  -- Full scan (slots 1-32) only when debuffSlotCount >= 16.
  -- Once spillover slots are found, they are cached in spilloverSlots[guid].
  -- Cached slots are re-checked on every call even if debuffSlotCount drops
  -- below 16 (Nampower does not move them back to 33-48).
  -- Slots are removed from cache when the spell is gone or no longer a debuff.
  -- ============================================================
  local hasKnownSpillovers = spilloverSlots[guid] and next(spilloverSlots[guid])
  if pfUI_config and pfUI_config.buffs and pfUI_config.buffs.showspillover == "0" then
    return count
  end
  if debuffSlotCount >= 16 or hasKnownSpillovers then
    local auraFlags = auraFlagsCache or GetCachedAuraFlags(guid)
    if auraFlags then
      -- Determine scan range: full 1-32 when slots are full, only cached slots otherwise
      local fullScan = debuffSlotCount >= 16

      if fullScan then
        -- Full scan: check all buff-region slots for spillover debuffs
        for auraSlot = 1, 32 do
          local spellId = auras[auraSlot]
          if spellId and spellId ~= 0 and IsDebuffByFlag(auraFlags, auraSlot) then
            -- Found spillover debuff - cache it and display (store spellId for debug/removal)
            spilloverSlots[guid] = spilloverSlots[guid] or {}
            spilloverSlots[guid][auraSlot] = spellId

            local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
            if not isHidden then
              local texture = libdebuff:GetSpellIcon(spellId)
              if texture then
                local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
                if not spellName or spellName == "" then
                  spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId) or "Unknown"
                end
                local rawStacks = auraApps and auraApps[auraSlot]
                local stacks = rawStacks and (rawStacks + 1) or 1

                local duration, timeleft = nil, -1
                if ls and ls:IsSharedOverwrite(spellName) then
                  local st = slotTimers[guid] and slotTimers[guid][auraSlot]
                  if st and st.duration and st.duration > 0 then
                    local remaining = (st.startTime + st.duration) - now
                    if remaining > -1 then
                      duration = st.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                  if not duration and pfUI.libdebuff_sharedoverwrite_timers[guid] and pfUI.libdebuff_sharedoverwrite_timers[guid][spellName] then
                    local d = pfUI.libdebuff_sharedoverwrite_timers[guid][spellName]
                    local remaining = (d.startTime + d.duration) - now
                    if remaining > -1 then
                      duration = d.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                  if not duration and ownDebuffs[guid] and ownDebuffs[guid][spellName] then
                    local d = ownDebuffs[guid][spellName]
                    local remaining = (d.startTime + d.duration) - now
                    if remaining > -1 then
                      duration = d.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                end

                local isOursSpillover = false
                if ls and ls:IsSharedOverwrite(spellName) then
                  local sot = pfUI.libdebuff_sharedoverwrite_timers[guid] and pfUI.libdebuff_sharedoverwrite_timers[guid][spellName]
                  isOursSpillover = sot and sot.isOurs or false
                end

                count = count + 1
                fn(auraSlot, spellId, spellName, texture, stacks, nil, duration, timeleft, isOursSpillover and "player" or nil, isOursSpillover)
              end
            end
          else
            -- Slot empty or no longer a debuff - remove from cache
            if spilloverSlots[guid] and spilloverSlots[guid][auraSlot] then
              if debugStats.enabled and IsCurrentTarget(guid) then
                local prevSpellId = spilloverSlots[guid][auraSlot]
                local prevSpellName = GetSpellRecField and GetSpellRecField(prevSpellId, "name") or "?"
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r Spillover REMOVED (full-scan): slot=%d spellId=%s name=%s guid=%s", auraSlot, tostring(prevSpellId), prevSpellName, DebugGuid(guid)))
              end
              spilloverSlots[guid][auraSlot] = nil
            end
          end
        end
      else
        -- Cached-only scan: only re-check slots we previously found spillovers in
        for auraSlot in pairs(spilloverSlots[guid]) do
          local spellId = auras[auraSlot]
          if spellId and spellId ~= 0 and IsDebuffByFlag(auraFlags, auraSlot) then
            -- Still a spillover debuff - display it
            local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
            if not isHidden then
              local texture = libdebuff:GetSpellIcon(spellId)
              if texture then
                local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
                if not spellName or spellName == "" then
                  spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId) or "Unknown"
                end
                local rawStacks = auraApps and auraApps[auraSlot]
                local stacks = rawStacks and (rawStacks + 1) or 1

                local duration, timeleft = nil, -1
                if ls and ls:IsSharedOverwrite(spellName) then
                  local st = slotTimers[guid] and slotTimers[guid][auraSlot]
                  if st and st.duration and st.duration > 0 then
                    local remaining = (st.startTime + st.duration) - now
                    if remaining > -1 then
                      duration = st.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                  if not duration and pfUI.libdebuff_sharedoverwrite_timers[guid] and pfUI.libdebuff_sharedoverwrite_timers[guid][spellName] then
                    local d = pfUI.libdebuff_sharedoverwrite_timers[guid][spellName]
                    local remaining = (d.startTime + d.duration) - now
                    if remaining > -1 then
                      duration = d.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                  if not duration and ownDebuffs[guid] and ownDebuffs[guid][spellName] then
                    local d = ownDebuffs[guid][spellName]
                    local remaining = (d.startTime + d.duration) - now
                    if remaining > -1 then
                      duration = d.duration
                      timeleft = remaining > 0 and remaining or 0
                    end
                  end
                end

                local isOursSpillover = false
                if ls and ls:IsSharedOverwrite(spellName) then
                  local sot = pfUI.libdebuff_sharedoverwrite_timers[guid] and pfUI.libdebuff_sharedoverwrite_timers[guid][spellName]
                  isOursSpillover = sot and sot.isOurs or false
                end

                count = count + 1
                fn(auraSlot, spellId, spellName, texture, stacks, nil, duration, timeleft, isOursSpillover and "player" or nil, isOursSpillover)
              end
            end
          else
            -- Slot empty or no longer a debuff - remove from cache
            if debugStats.enabled and IsCurrentTarget(guid) then
              local prevSpellId = spilloverSlots[guid][auraSlot]
              local prevSpellName = GetSpellRecField and GetSpellRecField(prevSpellId, "name") or "?"
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r Spillover REMOVED (cached-scan): slot=%d spellId=%s name=%s guid=%s", auraSlot, tostring(prevSpellId), prevSpellName, DebugGuid(guid)))
            end
            spilloverSlots[guid][auraSlot] = nil
          end
        end
        -- Clean up empty cache entry
        if not next(spilloverSlots[guid]) then
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r Spillover cache cleared (all slots gone) for %s", DebugGuid(guid)))
          end
          spilloverSlots[guid] = nil
        end
      end
    end -- if auraFlags
  end -- if debuffSlotCount >= 16 or hasKnownSpillovers

  return count
end

-- ============================================================================
-- IterBuffs: Iterate over real buffs only (filters spillover debuffs)
-- Callback: fn(auraSlot, spellId, spellName, texture, stacks, timeleft, duration)
-- For player: timer from GetPlayerAuraDuration
-- For others: no native buff timer (timeleft = nil)
-- Also detects buff-spillover into debuff slots (33-48) when 32 buff slots are full
-- ============================================================================
function libdebuff:IterBuffs(unit, fn)
  if not fn or not GetUnitGUID or not GetUnitField then return 0 end

  local guid = GetUnitGUID(unit)
  if not guid then return 0 end

  local auras, auraApps, auraFlags = GetCachedAuraField(guid)
  if not auras then return 0 end

  local isPlayer = (unit == "player")
  local hasPlayerAuraDuration = isPlayer and GetPlayerAuraDuration

  -- auraFlags already fetched via GetCachedAuraField above

  local count = 0
  local buffSlotCount = 0

  -- PASS 1: Normal buff slots (1-32)
  for auraSlot = 1, 32 do
    local spellId = auras[auraSlot]
    if spellId and spellId ~= 0 then
      buffSlotCount = buffSlotCount + 1
      -- Skip if this slot is a spillover debuff
      if auraFlags and IsDebuffByFlag(auraFlags, auraSlot) then
        -- Spillover debuff — skip for buff display
      else
        local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
        if not isHidden then
          local texture = libdebuff:GetSpellIcon(spellId)
          if texture then
            local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
            if not spellName or spellName == "" then
              spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId) or "Unknown"
            end

            local rawStacks = auraApps and auraApps[auraSlot]
            local stacks = rawStacks and (rawStacks + 1) or 1

            -- Timer: player only via GetPlayerAuraDuration (0-based)
            local timeleft, duration = nil, nil
            if hasPlayerAuraDuration and not forcedNoTimer[spellId] then
              local durSpellId, remainingMs = GetPlayerAuraDuration(auraSlot - 1)
              -- Verify spellId match to avoid desync
              if durSpellId == spellId and remainingMs and remainingMs > 0 then
                timeleft = remainingMs / 1000
              end
            end

            count = count + 1
            fn(auraSlot, spellId, spellName, texture, stacks, timeleft, duration)
          end
        end
      end
    end
  end

  -- PASS 2: Buff-spillover into debuff slots (33-48)
  -- Only when all 32 buff slots are occupied
  if pfUI_config and pfUI_config.buffs and pfUI_config.buffs.showoverflow == "0" then
    return count
  end
  if buffSlotCount >= 32 and auraFlags then
    for auraSlot = 33, 48 do
      local spellId = auras[auraSlot]
      if spellId and spellId ~= 0 then
        -- Check auraFlags: bit 3 NOT set = buff in debuff slot
        if not IsDebuffByFlag(auraFlags, auraSlot) then
          local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
          if not isHidden then
            local texture = libdebuff:GetSpellIcon(spellId)
            if texture then
              local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
              if not spellName or spellName == "" then
                spellName = GetSpellNameAndRank and GetSpellNameAndRank(spellId) or "Unknown"
              end

              local rawStacks = auraApps and auraApps[auraSlot]
              local stacks = rawStacks and (rawStacks + 1) or 1

              local timeleft, duration = nil, nil
              if hasPlayerAuraDuration and not forcedNoTimer[spellId] then
                local durSpellId, remainingMs = GetPlayerAuraDuration(auraSlot - 1)
                if durSpellId == spellId and remainingMs and remainingMs > 0 then
                  timeleft = remainingMs / 1000
                end
              end

              count = count + 1
              fn(auraSlot, spellId, spellName, texture, stacks, timeleft, duration)
            end
          end
        end
      end
    end
  end

  -- ============================================================
  -- PASS 3: Overflow buffs (no client aura slot, tracked by AURA_CAST)
  -- Only for player unit
  -- ============================================================
  if isPlayer and next(overflowBuffs) then
    local now = GetTime()
    for sid, data in pairs(overflowBuffs) do
      local remaining = (data.startTime + data.duration) - now
      if remaining > 0 then
        local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[sid]
        if not isHidden and data.texture then
          count = count + 1
          -- auraSlot = -1 signals overflow (no real aura slot)
          fn(-1, sid, data.spellName or "Unknown", data.texture, 1, remaining, data.duration)
        end
      else
        -- Expired, clean up
        overflowBuffs[sid] = nil
      end
    end
  end

  return count
end
-- unitframes.lua should migrate to IterDebuffs directly for best performance.
function libdebuff:UnitDebuff(unit, displaySlot)
  if not GetUnitGUID then return nil end

  local idx = 0
  local result = nil
  libdebuff:IterDebuffs(unit, function(auraSlot, spellId, spellName, texture, stacks, dtype, duration, timeleft, caster, isOurs)
    idx = idx + 1
    if idx == displaySlot and not result then
      result = { spellName, nil, texture, stacks, dtype, duration, timeleft, caster }
    end
  end)

  if result then
    return result[1], result[2], result[3], result[4], result[5], result[6], result[7], result[8]
  end
  return nil
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
  if GetUnitGUID then
    local guid = GetUnitGUID(unit)
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
        
        return entry.spellName, entry.data.rank, texture, entry.data.stacks or 1, entryDtype, entry.data.duration, displayTimeleft, "player"
      end
    end
    return nil
  end
  return nil
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
  
  -- Fallback: find slot by spellName in slotOwnership, return its timer
  if slotOwnership[guid] and slotTimers[guid] then
    local bestStart, bestDur, bestLeft = nil, nil, 0
    for auraSlot, ownership in pairs(slotOwnership[guid]) do
      if ownership.spellName == spellName then
        local st = slotTimers[guid][auraSlot]
        if st and st.duration and st.duration > 0 then
          local timeleft = (st.startTime + st.duration) - GetTime()
          if timeleft > bestLeft then
            bestLeft = timeleft
            bestStart = st.startTime
            bestDur = st.duration
          end
        end
      end
    end
    if bestStart then
      return bestStart, bestDur, bestLeft, nil, nil
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

  -- Register Carnage callback with libspelldata()
  if libspelldata() then
    libspelldata():SetCarnageCallback(function(targetGuid, affectedSpells)
      local refreshTime = GetTime()
      local myGuid = GetPlayerGUID()
      
      if debugStats.enabled then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[CARNAGE CALLBACK]|r targetGuid=%s affected=%d", 
          DebugGuid(targetGuid), table.getn(affectedSpells)))
      end
      
      for _, spellName in ipairs(affectedSpells) do
        if ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
          ownDebuffs[targetGuid][spellName].startTime = refreshTime
          if debugStats.enabled then
            local d = ownDebuffs[targetGuid][spellName]
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
              "|cff00ffff[CARNAGE]|r ownDebuffs[%s] refreshed startTime=%.3f dur=%.1f",
              spellName, refreshTime, d.duration or 0))
          end
        elseif debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ffff[CARNAGE]|r ownDebuffs[%s] NOT FOUND - skip", spellName))
        end

        -- Carnage: refresh slotTimers for our slot of this spellName
        if slotOwnership[targetGuid] and slotTimers[targetGuid] then
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName and ownership.isOurs then
              local st = slotTimers[targetGuid][auraSlot]
              if st then
                st.startTime = refreshTime
                if debugStats.enabled then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cff00ffff[CARNAGE slotTimers]|r aura=%d %s refreshed dur=%.1f",
                    auraSlot, spellName, st.duration or 0))
                end
              end
              break
            end
          end
        end

        -- Show slotOwnership state for this spellName
        if debugStats.enabled and slotOwnership[targetGuid] then
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName then
              DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ffff[CARNAGE slotOwnership]|r aura=%d %s caster=%s isOurs=%s",
                auraSlot, spellName, DebugGuid(ownership.casterGuid), tostring(ownership.isOurs)))
            end
          end
        end
      end
      
      pfUI.libdebuff_queue_update(targetGuid)
      
      if GetUnitGUID("target") then
        local currentTargetGuid = GetUnitGUID("target")
        if currentTargetGuid == targetGuid then
          libdebuff:UpdateUnits()
          -- One-shot snapshot of all active slots after Carnage
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE SNAPSHOT]|r --- slot state after refresh ---")
            libdebuff:IterDebuffs("target", function(auraSlot, spellId, spellName, tex, st, dt, dur, tl, caster, isOurs)
              DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ffff[CARNAGE SNAPSHOT]|r slot=%d %s isOurs=%s dur=%s tl=%s",
                auraSlot, spellName, tostring(isOurs),
                dur and string.format("%.1f", dur) or "nil",
                tl and string.format("%.1f", tl) or "nil"))
            end)
          end
        end
      end
    end)
  end
  
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_TALENT_UPDATE")
  frame:RegisterEvent("PLAYER_LOGOUT")
  frame:RegisterEvent("SPELL_START_SELF")
  frame:RegisterEvent("SPELL_START_OTHER")
  frame:RegisterEvent("SPELL_GO_SELF")
  frame:RegisterEvent("SPELL_GO_OTHER")
  frame:RegisterEvent("SPELL_FAILED_SELF")
  frame:RegisterEvent("SPELL_MISS_SELF")
  frame:RegisterEvent("SPELL_FAILED_OTHER")
  frame:RegisterEvent("UNIT_DIED")
  frame:RegisterEvent("SPELL_CAST_EVENT")
  -- AUTO_ATTACK events only needed for Paladin (Judgement melee-refresh)
  -- In a 40-man raid AUTO_ATTACK_OTHER fires hundreds of times per second - skip for non-Paladins
  if class == "PALADIN" then
    frame:RegisterEvent("AUTO_ATTACK_SELF")
    frame:RegisterEvent("AUTO_ATTACK_OTHER")
  end
  frame:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
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
      -- Clear overflow buffs (death, instance change, login)
      for k in pairs(overflowBuffs) do overflowBuffs[k] = nil end
      -- Clear auraFieldCache
      for k in pairs(auraFC) do auraFC[k] = nil end
      
    elseif event == "PLAYER_TALENT_UPDATE" then
      -- Talent changes handled dynamically (no cached talent checks needed)
      
    elseif event == "UNIT_HEALTH" then
      local guid = arg1
      if guid and UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
      end
      if pfUI.libdebuff_unit_health_hooks then
        for _, fn in pairs(pfUI.libdebuff_unit_health_hooks) do
          fn(arg1)
        end
      end

    elseif event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local spellType = arg8 or 0  -- 0=Normal, 1=Channel, 2=Autorepeating
      -- arg6=castTime, arg7=channel duration
      -- prefer arg6 if present - some spells (e.g. Volley post-rework) still send
      -- arg8=1 but now have a real cast time in arg6, so we only fall back to arg7
      -- when arg6 is nil (true channels like Blizzard)
      -- arg6=0 means "no cast time" (channel), arg6=nil also means channel (e.g. Blizzard)
      -- In Lua, 0 is truthy so we must check for nil OR zero explicitly
      local castTime = (arg6 and arg6 > 0 and arg6) or arg7
      local isChannel = spellType == 1 and (not arg6 or arg6 == 0)
      
      if not casterGuid or not spellId then return end
      
      -- Get spell name via Nampower
      local spellName = nil
      if GetSpellRec then
        local rec = GetSpellRec(spellId)
        spellName = rec and rec.name or nil
      end

      
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
        event = isChannel and "CHANNEL" or "START"
      }

      if event == "SPELL_START_SELF" and pfUI.libdebuff_spell_start_self_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_start_self_hooks) do
          fn(spellId, casterGuid, arg4, castTime)
        end
      elseif event == "SPELL_START_OTHER" and pfUI.libdebuff_spell_start_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_start_other_hooks) do
          fn(spellId, casterGuid, arg4, castTime)
        end
      end

    elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local targetGuid = arg4
      local numHit = arg6 or 0
      local numMissed = arg7 or 0
      
      -- Clear cast bar only if SPELL_GO matches the active cast
      -- (Reactive procs like Frost Armor trigger SPELL_GO but shouldn't clear the castbar)
      -- Don't clear channels on SPELL_GO - channels persist until duration expires or SPELL_FAILED
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        if pfUI.libdebuff_casts[casterGuid].spellID == spellId and pfUI.libdebuff_casts[casterGuid].event ~= "CHANNEL" then
          pfUI.libdebuff_casts[casterGuid] = nil
        end
      end
      
      -- AoE channel spells (Hurricane, Consecration) report numHit=0 in SPELL_GO
      -- because hits arrive later via SPELL_DAMAGE_EVENT during the channel.
      -- We must register pendingAoE BEFORE the numHit guard so the caster is known.
      -- Fire registered SPELL_GO_SELF hooks BEFORE the spellName guard.
      -- Item-use spells (e.g. Brilliant Mana Oil) may have no entry in GetSpellRecField
      -- so spellName comes back nil and the guard below returns early -- hooks must
      -- fire here so bag/inventory consumers see every item-triggered SPELL_GO_SELF.
      if event == "SPELL_GO_SELF" and pfUI.libdebuff_spell_go_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_go_hooks) do
          fn(spellId, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        end
      end

      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      local spellRankString
      if not spellName then return end

      local isNullTarget = (not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000")
      if isNullTarget and casterGuid and libspelldata() and libspelldata():HasForcedDuration(spellName) then
        pendingAoE[spellName] = pendingAoE[spellName] or {}
        pendingAoE[spellName][casterGuid] = { time = GetTime() }

      end

      if numMissed > 0 or numHit == 0 then return end

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
      -- Track hit for applicator refresh (own casts only)
      if targetGuid and casterGuid == myGuid then
        recentHits[targetGuid] = recentHits[targetGuid] or {}
        recentHits[targetGuid][spellName] = GetTime()
      end
      if casterGuid == myGuid then
        -- Track pending applicator (Judgement etc.) for passive proc correlation
        if targetGuid and libspelldata() then
          pendingApplicators[targetGuid] = { spell = spellName, time = GetTime(), casterGuid = casterGuid }
          libspelldata():OnSpellGo(spellId, spellName, casterGuid, targetGuid)

          -- Refresh shared debuffs on SPELL_GO for own casts too
          -- AURA_CAST only fires on new application, not server-side refresh (e.g. max stacks)
          if libspelldata():IsAnyApplicatorSpell(spellName) then
            RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
          end
        end
      end
      
      -- CARNAGE TALENT via libspelldata()
      if libspelldata() and libspelldata():ShouldCheckCarnage(spellName, casterGuid, targetGuid, numHit) then
        libspelldata():ScheduleCarnageCheck(targetGuid)
      end

      -- Track pending applicator for OTHER players (e.g. Judgement from other Paladins)
      -- Ensures DEBUFF_ADDED can resolve real casterGuid via libspelldata():OnDebuffAdded
      if event == "SPELL_GO_OTHER" and targetGuid and casterGuid and libspelldata() then
        libspelldata():OnSpellGo(spellId, spellName, casterGuid, targetGuid)
      end

      -- Fire registered SPELL_GO_OTHER hooks
      if event == "SPELL_GO_OTHER" and pfUI.libdebuff_spell_go_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_go_other_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      end

    elseif event == "UNIT_DIED" then
      local diedGuid = arg1
      if diedGuid then
        CleanupUnit(diedGuid)
      end
      if pfUI.libdebuff_unit_died_hooks then
        for _, fn in pairs(pfUI.libdebuff_unit_died_hooks) do
          fn(diedGuid)
        end
      end

    elseif event == "SPELL_FAILED_OTHER" then
      local casterGuid = arg1
      
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        pfUI.libdebuff_casts[casterGuid] = nil
      end
      if pfUI.libdebuff_spell_failed_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_failed_other_hooks) do
          fn(casterGuid, arg2)
        end
      end

    elseif event == "SPELL_MISS_SELF" then
      -- arg1=casterGuid, arg2=targetGuid, arg3=spellId, arg4=missType
      local targetGuid = arg2
      local spellId = arg3
      if not spellId or not targetGuid then return end
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      if not spellName then return end
      -- Clear pendingSlotTimer so miss doesn't get committed on a future DEBUFF_ADDED
      if pendingSlotTimer[targetGuid] and pendingSlotTimer[targetGuid][spellName] then
        pendingSlotTimer[targetGuid][spellName] = nil
      end
      -- Only clear ownDebuffs/objectsByGuid if no active slot exists
      -- (if debuff already on target, keep existing timers intact)
      local slotExists = false
      if slotOwnership[targetGuid] then
        for _, ownership in pairs(slotOwnership[targetGuid]) do
          if ownership.spellName == spellName and ownership.isOurs then
            slotExists = true
            break
          end
        end
      end
      if not slotExists and ownDebuffs[targetGuid] then
        ownDebuffs[targetGuid][spellName] = nil
      end
      if not slotExists and objectsByGuid[targetGuid] then
        objectsByGuid[targetGuid][spellId] = nil
      end
      if debugStats.enabled then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff4400[SPELL MISSED]|r %s on %s missType=%s slotExists=%s",
          GetDebugTimestamp(), spellName, DebugGuid(targetGuid), tostring(arg4), tostring(slotExists)))
      end

    elseif event == "SPELL_FAILED_SELF" then
      -- Clear captured CPs on failed cast
      capturedCP = nil

    elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
      -- PERF: Early exit if no melee-refresh spells configured (avoids processing hundreds of events/sec in raids)
      if not libspelldata() then return end
      if not meleeRefreshSpells then
        meleeRefreshSpells = libspelldata():GetMeleeRefreshSpells()
      end
      if not meleeRefreshSpells or not next(meleeRefreshSpells) then return end
      -- Melee autohit: refresh Judgement debuffs from this attacker on the target
      local attackerGuid = arg1
      local targetGuid = arg2
      local victimState = arg5

      if not targetGuid or not attackerGuid then return end
      -- PERF: Skip if no tracked debuffs on this target at all
      if not slotOwnership[targetGuid] then return end
      -- Only refresh on actual hits (not dodge/parry/miss)
      if victimState and (victimState == 0 or victimState == 2 or victimState == 3 or victimState == 6 or victimState == 7) then
        return  -- UNAFFECTED(miss), DODGE, PARRY, EVADE, IMMUNE
      end

      if slotOwnership[targetGuid] then
        if not meleeRefreshSpells then
          meleeRefreshSpells = libspelldata():GetMeleeRefreshSpells()
        end
        local now = GetTime()
        local myGuid = GetPlayerGUID()
        local isOurs = (attackerGuid == myGuid)
        local refreshed = false
        for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
          local spellName = ownership.spellName
          local refreshDur = spellName and meleeRefreshSpells[spellName]
          if refreshDur and (ownership.isOurs or (isOurs)) then
            local st = slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot]
            if st then
              st.startTime = now
              st.duration = refreshDur
              refreshed = true

              if ownership.isOurs and ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
                ownDebuffs[targetGuid][spellName].startTime = now
                ownDebuffs[targetGuid][spellName].duration = refreshDur
              end

              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[MELEE REFRESH]|r %s aura=%d on %s",
                  GetDebugTimestamp(), spellName, auraSlot, DebugGuid(targetGuid)))
              end
            end
          end
        end
        
        if refreshed then
          pfUI.libdebuff_queue_update(targetGuid)
          if GetUnitGUID("target") then
            local currentTargetGuid = GetUnitGUID("target")
            if currentTargetGuid == targetGuid then
              libdebuff:UpdateUnits()
              -- Notify buffwatch (UNIT_AURA doesn't fire on melee refresh)
              if pfUI.libdebuff_melee_refresh_hooks then
                for _, fn in pairs(pfUI.libdebuff_melee_refresh_hooks) do
                  fn(targetGuid)
                end
              end
              if pfUI.libdebuff_target_updated_hooks then
                for _, fn in pairs(pfUI.libdebuff_target_updated_hooks) do
                  fn(targetGuid)
                end
              end
            end
          end
        end
      end

    elseif event == "SPELL_DAMAGE_EVENT_SELF" then
      -- Spell damage: Track hits for applicator refresh + crit-based refresh (Ignite)
      local targetGuid = arg1
      local casterGuid = arg2
      local spellId = arg3
      local hitInfo = arg6
      local effectAuraStr = arg8
      
      if not targetGuid or not casterGuid or not spellId then return end
      
      local myGuid = GetPlayerGUID()
      if casterGuid ~= myGuid then return end  -- Only our damage
      
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      if not spellName then return end
      
      -- Check if this is periodic damage (DoT tick)
      local isPeriodicDamage = false
      if effectAuraStr and type(effectAuraStr) == "string" then
        local _, _, _, _, _, auraType = string.find(effectAuraStr, "^([^,]*),([^,]*),([^,]*),([^,]*)$")
        if auraType and auraType ~= "" then
          local auraTypeNum = tonumber(auraType)
          if auraTypeNum == 3 or auraTypeNum == 89 then
            isPeriodicDamage = true
          end
        end
      end
      
      -- Additional check: If no recent SPELL_GO, it's likely a DoT tick
      local hadRecentCast = false
      if recentHits[targetGuid] and recentHits[targetGuid][spellName] then
        if (GetTime() - recentHits[targetGuid][spellName]) < 1.0 then
          hadRecentCast = true
        end
      end
      
      local isDotTick = isPeriodicDamage or not hadRecentCast
      
      -- Track successful hit for applicator refresh validation (not DoT ticks)
      if not isDotTick then
        recentHits[targetGuid] = recentHits[targetGuid] or {}
        recentHits[targetGuid][spellName] = GetTime()
        RefreshApplicatorDebuffs(targetGuid, spellName, myGuid)
      end
      
      -- CRIT-BASED REFRESH (Ignite etc.)
      if not hitInfo then return end
      local isCrit = (tonumber(hitInfo) == 2)
      if not isCrit then return end
      
      if libspelldata() and slotOwnership[targetGuid] then
        local now = GetTime()
        local refreshed = false

        for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
          if ownership.isOurs then
            local debuffName = ownership.spellName
            if debuffName and libspelldata():RequiresCritForRefresh(debuffName, spellName) then
              local duration = libspelldata():GetDuration(debuffName)
              if duration then
                local st = slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot]
                if st then
                  st.startTime = now
                  st.duration = duration
                  refreshed = true

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
          end
        end
        
        if refreshed then
          pfUI.libdebuff_queue_update(targetGuid)
          if GetUnitGUID("target") then
            local currentTargetGuid = GetUnitGUID("target")
            if currentTargetGuid == targetGuid then
              libdebuff:UpdateUnits()
            end
          end
        end
      end

    elseif event == "SPELL_CAST_EVENT" then
      -- Capture combo points BEFORE they're consumed
      -- This event fires when YOU cast a spell (before server processes it)
      local success = arg1
      local spellId = arg2
      local castType = arg3
      local targetGuid = arg4
      
      if success ~= 1 or not spellId then return end
      
      -- Get spell name
      local spellName = nil
      if GetSpellRec then
        local rec = GetSpellRec(spellId)
        spellName = rec and rec.name or nil
      end

      
      -- Store pending cast info for libpredict (heal prediction target tracking)
      -- This allows libpredict to resolve the correct target for Nampower queued casts,
      -- where CastSpellByName hook fires while current_cast is set and spell_queue
      -- cannot be updated. SPELL_CAST_EVENT fires right before SPELLCAST_START.
      if spellName and targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        pfUI.libpredict_pending_cast.spellId = spellId
        pfUI.libpredict_pending_cast.spellName = spellName
        pfUI.libpredict_pending_cast.targetGuid = targetGuid
        pfUI.libpredict_pending_cast.time = GetTime()
      else
        -- No explicit target - clear pending so libpredict falls back to spell_queue
        pfUI.libpredict_pending_cast.spellId = nil
        pfUI.libpredict_pending_cast.spellName = nil
        pfUI.libpredict_pending_cast.targetGuid = nil
        pfUI.libpredict_pending_cast.time = nil
      end
      
      -- Only capture CPs for combo-point abilities
      if spellName and IsComboPointAbility(spellName) then
        capturedCP = GetComboPoints() or 0
      end

      -- Fire registered SPELL_CAST_EVENT hooks
      if pfUI.libdebuff_spell_cast_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_cast_hooks) do
          fn(success, spellId, castType, targetGuid)
        end
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
      
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      if not spellName then return end
      
      -- Deduplicate: Ignore if we processed this exact cast recently (within 100ms)
      -- Nampower fires multiple AURA_CAST events for multi-effect spells (e.g. Faerie Fire has 3 effects)
      recentCasts[targetGuid] = recentCasts[targetGuid] or {}
      recentCasts[targetGuid][spellName] = recentCasts[targetGuid][spellName] or {}
      
      local now = GetTime()
      local lastCastTime = recentCasts[targetGuid][spellName][casterGuid]
      
      if lastCastTime and (now - lastCastTime) < 0.1 then
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
      
      -- ================================================================
      -- OVERFLOW BUFF DETECTION (player only, AURA_CAST_ON_SELF)
      -- When buff slots are full, new buffs have no client aura slot.
      -- Track them separately so IterBuffs can display them.
      -- ================================================================
      if event == "AURA_CAST_ON_SELF" and duration > 0 then
        if debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa[OVF DBG]|r %s capStatus=%s dur=%.1f", 
            spellName, tostring(auraCapStatus), duration))
        end
        
        local buffCapped = false
        if auraCapStatus then
          buffCapped = bit.band(auraCapStatus, 1) ~= 0
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa[OVF DBG]|r buffCapped=%s", tostring(buffCapped)))
          end
        
          if buffCapped and GetPlayerAuraDuration then
            -- Check if this spell is a debuff (in slots 32-47)
            local isDebuff = false
            for slot = 32, 47 do
              local sid = GetPlayerAuraDuration(slot)
              if sid and sid == spellId then
                isDebuff = true
                break
              end
            end
          
            if not isDebuff then
              -- Check if this buff already has a visible slot (0-31)
              local inVisibleSlot = false
              for slot = 0, 31 do
                local sid = GetPlayerAuraDuration(slot)
                if sid and sid == spellId then
                  inVisibleSlot = true
                  break
                end
              end
              
              if debugStats.enabled then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa[OVF DBG]|r isDebuff=%s inVisible=%s", 
                  tostring(isDebuff), tostring(inVisibleSlot)))
              end
            
              if not inVisibleSlot then
                -- Overflow buff: no client aura slot
                local texture = libdebuff:GetSpellIcon(spellId)
                overflowBuffs[spellId] = {
                  startTime = startTime,
                  duration = duration,
                  texture = texture,
                  spellName = spellName,
                  spellId = spellId
                }
                if debugStats.enabled then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[OVERFLOW BUFF TRACKED]|r %s (ID:%d) dur=%.1fs tex=%s", 
                    spellName, spellId, duration, tostring(texture)))
                end
                -- Notify buff frames to refresh (no PLAYER_AURAS_CHANGED fires for overflow)
                if pfUI.buff and pfUI.buff:GetScript("OnEvent") then
                  pfUI.buff:GetScript("OnEvent")()
                end
                -- Also notify player unitframe
              end
            end
          else
            if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa[OVF DBG]|r %s is a debuff, skip", spellName))
            end
          end
        else
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[OVF DBG]|r auraCapStatus is nil")
          end
        end
        
        -- Cleanup: if no longer buff-capped, check if overflow buffs got real slots
        if not buffCapped and next(overflowBuffs) and GetPlayerAuraDuration then
          for sid in pairs(overflowBuffs) do
            local gotSlot = false
            for slot = 0, 31 do
              local checkId = GetPlayerAuraDuration(slot)
              if checkId and checkId == sid then
                gotSlot = true
                break
              end
            end
            if gotSlot then
              overflowBuffs[sid] = nil
            end
          end
        end
      end
      
      -- Cleanup expired overflow buffs
      if next(overflowBuffs) then
        local now = GetTime()
        for sid, data in pairs(overflowBuffs) do
          if (data.startTime + data.duration) < now then
            overflowBuffs[sid] = nil
          end
        end
      end
      
      if debugStats.enabled and isOurs then
        debugStats.aura_cast = debugStats.aura_cast + 1
      end
      
      -- Combo-point abilities: Calculate duration based on CPs used
      if IsComboPointAbility(spellName) then
        if isOurs then
          -- OWN casts: use captured CPs from SPELL_CAST_EVENT (if available)
          local cp = capturedCP or 0
          local base, perCP = GetComboPointData(spellName)
          if base and perCP then
            duration = base + cp * perCP
          else
            -- Fallback to spell duration database
            duration = libdebuff:GetDuration(spellName, rankNum)
          end
          capturedCP = nil  -- consumed
        else
          -- OTHER players: CP unknown, no timer (except Expose Armor = fixed 30s)
          local base, perCP = GetComboPointData(spellName)
          if perCP and perCP == 0 and base then
            duration = base  -- fixed duration (Expose Armor)
          else
            duration = 0  -- CP unknown for other players
          end
        end
      elseif duration == 0 then
        -- Non-CP managed spells: check libspelldata() first, then spell duration database
        if libspelldata() then
          local spellDuration = libspelldata():GetDuration(spellName, nil, casterGuid)
          if spellDuration then
            duration = spellDuration
          end
        end
        if duration == 0 then
          duration = libdebuff:GetDuration(spellName, rankNum) or 0
        end
      end
      
      -- Downrank Protection for own spells: check slotOwnership for existing higher-rank slot
      if isOurs and rankNum > 0 then
        -- First check: active slot with higher rank still ticking
        if slotOwnership[targetGuid] then
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName and ownership.isOurs then
              local st = slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot]
              if st and st.rank and st.rank > rankNum then
                local existingTimeleft = (st.startTime + st.duration) - GetTime()
                -- Only block if genuinely still ticking (>0.5s guards against float near-zero)
                -- If timer is near expiry, let the cast through so DEBUFF_ADDED can update tracking
                if existingTimeleft > 0.5 then
                  if debugStats.enabled and IsCurrentTarget(targetGuid) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)",
                      spellName, rankNum, st.rank, existingTimeleft))
                  end
                  return
                end
              end
              break
            end
          end
        end
        -- Second check: maxRankSeen - protects the brief window between slot cleared and new DEBUFF_ADDED
        -- where slotOwnership is nil but a higher-rank debuff was just re-applied
        if maxRankSeen[targetGuid] and maxRankSeen[targetGuid][spellName] then
          -- Check if maxRankSeen has expired (2s after removal, no re-apply happened)
          local clearedAt = maxRankSeen[targetGuid][spellName .. "_cleared"]
          if clearedAt and (GetTime() - clearedAt) > 2.0 then
            maxRankSeen[targetGuid][spellName] = nil
            maxRankSeen[targetGuid][spellName .. "_cleared"] = nil
          end
        end
        if maxRankSeen[targetGuid] and maxRankSeen[targetGuid][spellName] then
          local seenRank = maxRankSeen[targetGuid][spellName]
          if seenRank > rankNum then
            local freshSlot = false
            if slotOwnership[targetGuid] then
              for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
                if ownership.spellName == spellName and ownership.isOurs then
                  local st = slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot]
                  -- Only block if the slot ACTUALLY contains the higher rank and is fresh
                  -- If slot has a lower rank (e.g. Rank 9 just landed), don't block
                  if st and st.rank and st.rank >= seenRank and (GetTime() - st.startTime) < 2.0 then
                    freshSlot = true
                    if debugStats.enabled and IsCurrentTarget(targetGuid) then
                      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (fresh re-apply)",
                        spellName, rankNum, seenRank))
                    end
                  end
                  break
                end
              end
            end
            if freshSlot then return end
          end
        end
      end

      -- Early debug: log ALL AURA_CAST events before any gates
      if debugStats.enabled and IsCurrentTarget(targetGuid) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff888888[AURA_CAST RAW]|r %s rank=%d isOurs=%s dur=%.1fs caster=%s",
          GetDebugTimestamp(), spellName, rankNum, tostring(isOurs), duration, DebugGuid(casterGuid)))
      end

      -- Store timer in pendingSlotTimer[targetGuid][spellName]
      -- DEBUFF_ADDED will pick this up and key it by auraSlot
      if targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" and duration > 0 then
        pendingSlotTimer[targetGuid] = pendingSlotTimer[targetGuid] or {}
        pendingSlotTimer[targetGuid][spellName] = {
          startTime = startTime,
          duration  = duration,
          isOurs    = isOurs,
          rank      = rankNum,
          time      = startTime  -- for stale-entry detection
        }

        -- sharedOverwrite: also store persistently for spillover display (no DEBUFF_ADDED fires in buff slots)
        if libspelldata() and libspelldata():IsSharedOverwrite(spellName) then
          pfUI.libdebuff_sharedoverwrite_timers[targetGuid] = pfUI.libdebuff_sharedoverwrite_timers[targetGuid] or {}
          local existing = pfUI.libdebuff_sharedoverwrite_timers[targetGuid][spellName]
          -- Downrank check: don't overwrite a higher-rank timer that is still ticking
          local blocked = false
          if existing and existing.rank and rankNum > 0 and existing.rank > rankNum then
            local existingTimeleft = (existing.startTime + existing.duration) - GetTime()
            if existingTimeleft > 0.5 then
              blocked = true
              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[SPILLOVER DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)",
                  spellName, rankNum, existing.rank, existingTimeleft))
              end
            end
          end
          if not blocked then
            pfUI.libdebuff_sharedoverwrite_timers[targetGuid][spellName] = { startTime = startTime, duration = duration, isOurs = isOurs, rank = rankNum }
            pfUI.libdebuff_queue_update(targetGuid)
          end
        end

        -- On refresh DEBUFF_ADDED doesn't fire - update slotTimers directly.
        -- KEY: Match by BOTH spellName AND casterGuid so each caster only updates their own slot.
        -- Fallback: if casterGuid is nil (SPELL_GO not correlated), match by spellName only
        -- when there is exactly one slot for this spell (safe for single-caster debuffs).
        if slotOwnership[targetGuid] then
          local matchSlot, matchCount = nil, 0
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName then
              -- Match if: casterGuid unknown, OR ownership casterGuid unknown, OR exact match
              if casterGuid == nil or ownership.casterGuid == nil or ownership.casterGuid == casterGuid then
                matchSlot = auraSlot
              end
              matchCount = matchCount + 1
            end
          end
          -- Use match if found (exact or unknown-caster fallback)
          if matchSlot then
            local ownership = slotOwnership[targetGuid][matchSlot]
            local auraSlot = matchSlot
            -- Downrank protection: skip refresh only if a HIGHER rank is still genuinely ticking
            local st = slotTimers[targetGuid] and slotTimers[targetGuid][auraSlot]
            if st and st.rank and st.rank > 0 and rankNum > 0 and rankNum < st.rank then
              local existingTimeleft = (st.startTime + st.duration) - GetTime()
              if existingTimeleft > 0.5 then
                if debugStats.enabled and IsCurrentTarget(targetGuid) then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)",
                    spellName, rankNum, st.rank, existingTimeleft))
                end
                return -- skip refresh for this slot
              else
                -- Timer effectively expired (<=0.5s): proactively clear objectsByGuid now
                -- so Conditionals doesn't wait for DEBUFF_REMOVED (can lag 100-500ms behind)
                if spellId and objectsByGuid[targetGuid] and objectsByGuid[targetGuid][spellId] then
                  objectsByGuid[targetGuid][spellId] = nil
                  if debugStats.enabled and IsCurrentTarget(targetGuid) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4400[->ADDON]|r objectsByGuid[%s][%d] PRE-CLEARED (timer %.3fs, DEBUFF_REMOVED pending)",
                      DebugGuid(targetGuid), spellId, existingTimeleft))
                  end
                end
                -- Also clear by name in case spellId differs across ranks (Moonfire R9 vs R10)
                if ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
                  local ownRec = ownDebuffs[targetGuid][spellName]
                  local ownSpellId = ownRec.spellId
                  if ownSpellId and ownSpellId ~= spellId and objectsByGuid[targetGuid] and objectsByGuid[targetGuid][ownSpellId] then
                    objectsByGuid[targetGuid][ownSpellId] = nil
                    if debugStats.enabled and IsCurrentTarget(targetGuid) then
                      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4400[->ADDON]|r objectsByGuid[%s][%d] PRE-CLEARED by name match (%s)",
                        DebugGuid(targetGuid), ownSpellId, spellName))
                    end
                  end
                end
              end
            end
            -- Refresh the slot timer (same rank, higher rank after expiry, or no existing timer)
            ownership.isOurs = isOurs
            slotTimers[targetGuid] = slotTimers[targetGuid] or {}
            -- Preserve highest rank ever written to this slot
            local existingRank = slotTimers[targetGuid][auraSlot] and slotTimers[targetGuid][auraSlot].rank or 0
            local writeRank = (rankNum > existingRank) and rankNum or existingRank
            slotTimers[targetGuid][auraSlot] = { startTime = startTime, duration = duration, rank = writeRank, isOurs = isOurs }
            pfUI.libdebuff_queue_update(targetGuid)
            -- Sync ownDebuffs for our refreshes (only if entry already exists = confirmed hit)
            if isOurs and ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
              ownDebuffs[targetGuid][spellName].startTime = startTime
              ownDebuffs[targetGuid][spellName].duration = duration
            end
            -- Sync objectsByGuid for CleveRoids API (slot exists = confirmed hit, not a miss)
            if isOurs and spellId then
              objectsByGuid[targetGuid] = objectsByGuid[targetGuid] or {}
              objectsByGuid[targetGuid][spellId] = {
                start    = startTime,
                duration = duration,
                caster   = "player",
                stacks   = objectsByGuid[targetGuid][spellId] and objectsByGuid[targetGuid][spellId].stacks or 1
              }
              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[->ADDON]|r objectsByGuid[%s][%d] REFRESHED start=%.2f dur=%.1f",
                  DebugGuid(targetGuid), spellId, startTime, duration))
              end
            elseif debugStats.enabled and IsCurrentTarget(targetGuid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4400[->ADDON SKIP]|r REFRESH not written: isOurs=%s spellId=%s",
                tostring(isOurs), tostring(spellId)))
            end
            if debugStats.enabled and IsCurrentTarget(targetGuid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[SLOT REFRESHED]|r aura=%d %s rank=%d caster=%s isOurs=%s dur=%.1f",
                auraSlot, spellName, writeRank, DebugGuid(casterGuid), tostring(isOurs), duration))
            end
          end -- matchSlot
        end

        if debugStats.enabled and IsCurrentTarget(targetGuid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[AURA_CAST]|r %s rank=%d target=%s isOurs=%s dur=%.1fs",
            GetDebugTimestamp(), spellName, rankNum, DebugGuid(targetGuid), tostring(isOurs), duration))
        end
      end
      
      
      -- APPLICATOR REFRESH: Refresh passive proc debuffs when applicator spells hit
      -- Run for ALL casters (not just isOurs) - RefreshApplicatorDebuffs internally
      -- filters to only refresh debuffs that belong to us (myGuid or shared)
      if targetGuid and libspelldata() then
        local now = GetTime()
        local hasRecentHit = false
        if recentHits[targetGuid] and recentHits[targetGuid][spellName] then
          if (now - recentHits[targetGuid][spellName]) < 0.1 then
            hasRecentHit = true
          end
        end
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

      -- AURA_CAST fires on both hit AND miss - only update ownDebuffs if entry already exists
      -- (meaning DEBUFF_ADDED previously confirmed a hit). Never create a new entry here.
      if not ownDebuffs[targetGuid] or not ownDebuffs[targetGuid][spellName] then return end

      local data = ownDebuffs[targetGuid][spellName]
      if not data then return end  -- race condition: cleared by DEBUFF_REMOVED between init and use

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
      data.stacks = data.stacks or 1

      -- Handle variant pairs for ownDebuffs
      local ownOverwritePair = libspelldata() and libspelldata():GetOverwritePair(spellName)
      if ownOverwritePair then
        if ownDebuffs[targetGuid][ownOverwritePair] then
          ownDebuffs[targetGuid][ownOverwritePair] = nil
        end
      end
      -- NOTE: objectsByGuid is written only in DEBUFF_ADDED (confirmed hit) and
      -- the refresh path above (slot exists = confirmed). Never here (AURA_CAST fires on miss too).

      if event == "AURA_CAST_ON_SELF" and pfUI.libdebuff_aura_cast_on_self_hooks then
        for _, fn in pairs(pfUI.libdebuff_aura_cast_on_self_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      elseif event == "AURA_CAST_ON_OTHER" and pfUI.libdebuff_aura_cast_on_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_aura_cast_on_other_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      end
      if targetGuid and pfUI.libdebuff_target_updated_hooks then
        for _, fn in pairs(pfUI.libdebuff_target_updated_hooks) do
          fn(targetGuid)
        end
      end

    elseif event == "DEBUFF_ADDED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- Display slot (1-16), compacted
      local spellId = arg3
      local stacks = arg4
      local auraSlot_0based = arg6  -- Nampower 2.29+: debuff aura slot, 0-based (32-47). GetUnitField uses 1-based (33-48), so we add +1 below.

      -- Convert Nampower 0-based slot (32-47) to GetUnitField 1-based slot (33-48)
      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil

      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
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
        local slotMap = pfUI.libdebuff_get_slot_map(guid)
        if slotMap and slotMap[displaySlot] then
          auraSlot = slotMap[displaySlot].auraSlot
        end
      end
      
      -- Last resort fallback: derive 1-based aura slot from display slot.
      -- displaySlot is 1-based (1-16), debuff aura slots start at 33, so: 32 + displaySlot.
      -- Unreliable if there are gaps in the aura array (removed debuffs leave holes).
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
      -- Use wider window (0.5s) since server-client latency can exceed 50ms.
      -- FIFO: pick the OLDEST pending entry (first cast = first debuff applied).

      if not casterGuid and pendingAoE[spellName] then
        local bestMatch = nil
        local bestAge = -1  -- we want the largest age (oldest)
        for pendingCasterGuid, pending in pairs(pendingAoE[spellName]) do
          local age = GetTime() - pending.time
          if age < 0.5 and age > bestAge then
            bestMatch = pendingCasterGuid
            bestAge = age
          end
        end
        if bestMatch then
          casterGuid = bestMatch
          pendingAoE[spellName][bestMatch] = nil  -- consume so next DEBUFF_ADDED gets next caster
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff00cc[AOE CASTER FOUND]|r %s from pendingAoE caster=%s (age=%.3fs)", 
              GetDebugTimestamp(), spellName, DebugGuid(casterGuid), bestAge))
          end
        end
      end
      
      -- Fallback for forced-duration spells: Check if we already have a timer
      -- Skip for AoE spells: pendingAoE is the only reliable source for those.
      -- Using allAuraCasts here would pick up stale entries from previous casts by us.
      local isAoESpell = libspelldata() and libspelldata():IsAoEChannel(spellName)

      -- forcedDuration casterGuid fallback no longer needed:
      -- slotTimers are keyed by auraSlot, not casterGuid
      

      
      -- libspelldata(): Check applicator tracking (e.g. Judgement → JoW caster)
      if not casterGuid and libspelldata() then
        casterGuid = libspelldata():OnDebuffAdded(guid, spellId, spellName)
      end
      
      -- pendingApplicators: Track passive proc debuffs (e.g., Scorch → Fire Vulnerability, Frostbolt → Winter's Chill)
      -- Only assigns ownership if PLAYER cast the applicator spell recently
      if not casterGuid and libspelldata() and libspelldata():HasForcedDuration(spellName) then
        if pendingApplicators[guid] then
          local timeSinceCast = GetTime() - pendingApplicators[guid].time
          if timeSinceCast < 0.5 then
            -- Use the actual caster of the applicator spell (may be foreign player)
            casterGuid = pendingApplicators[guid].casterGuid or GetPlayerGUID()
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[APPLICATOR]|r %s applied by %s's %s (%.2fs ago)",
                GetDebugTimestamp(), spellName, DebugGuid(casterGuid), pendingApplicators[guid].spell, timeSinceCast))
            end
            pendingApplicators[guid] = nil
          end
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
      
      -- For forced-duration spells: If still no caster, assume ours (passive talent procs)
      -- IMPORTANT: Skip this fallback for AoE spells (pendingAoE key present means spell has a known caster
      -- that just missed the timing window -- do NOT falsely claim ownership)
      local isAoESpell2 = libspelldata() and libspelldata():IsAoEChannel(spellName)
      if not casterGuid and not isAoESpell2 and libspelldata() and libspelldata():HasForcedDuration(spellName) then
        casterGuid = GetPlayerGUID()
        isOurs = true
        if debugStats.enabled and IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[PASSIVE PROC]|r %s assumed ours (no caster)", spellName))
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
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[DEBUFF_ADDED]|r display=%d aura=%d %s rank=%d caster=%s isOurs=%s",
          GetDebugTimestamp(), displaySlot, auraSlot, spellName, (pendingSlotTimer[guid] and pendingSlotTimer[guid][spellName] and pendingSlotTimer[guid][spellName].rank or 0), DebugGuid(casterGuid), tostring(isOurs)))
      end
      
      -- Resolve pendingSlotTimer → slotTimers for this auraSlot
      -- AURA_CAST fires slightly before DEBUFF_ADDED, so pending entry should be here
      local now = GetTime()
      slotTimers[guid] = slotTimers[guid] or {}
      local pending = pendingSlotTimer[guid] and pendingSlotTimer[guid][spellName]
      if pending and (now - pending.time) < 2.0 then
        -- Fresh pending timer from AURA_CAST - commit to slot, preserving highest rank
        -- Only preserve rank if the existing slot entry is for the SAME spell (prevents
        -- stale rank from a different spell that held this slot bleeding into the new entry)
        local existingEntry = slotTimers[guid][auraSlot]
        local existingRank = (existingEntry and existingEntry.spellName == spellName and existingEntry.rank) or 0
        local writeRank = ((pending.rank or 0) > existingRank) and (pending.rank or 0) or existingRank
        slotTimers[guid][auraSlot] = { startTime = pending.startTime, duration = pending.duration, rank = writeRank, isOurs = pending.isOurs or false, spellName = spellName }
        pfUI.libdebuff_queue_update(guid)
        pendingSlotTimer[guid][spellName] = nil
        if debugStats.enabled and IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[SLOT TIMER]|r aura=%d %s rank=%d start=%.2f dur=%.1f",
            auraSlot, spellName, writeRank, pending.startTime, pending.duration))
        end
      elseif isOurs then
        -- No pendingSlotTimer (e.g. AURA_CAST was downrank-blocked but spell still landed)
        -- Build timer from libspelldata() or spell duration DB so Conditionals tracks ownership
        local fallbackDur = 0
        if libspelldata() then
          fallbackDur = libspelldata():GetDuration(spellName) or 0
        end
        if fallbackDur == 0 then
          fallbackDur = libdebuff:GetDuration(spellName, nil) or 0
        end
        if fallbackDur > 0 then
          local existingRank = slotTimers[guid][auraSlot] and slotTimers[guid][auraSlot].rank or 0
          slotTimers[guid][auraSlot] = { startTime = now, duration = fallbackDur, rank = existingRank, isOurs = true }
          pfUI.libdebuff_queue_update(guid)
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[SLOT TIMER FALLBACK]|r aura=%d %s dur=%.1f (no pending, own spell)",
              auraSlot, spellName, fallbackDur))
          end
        end
      elseif libspelldata() and libspelldata():HasForcedDuration(spellName) then
        -- No AURA_CAST for this spell (passive proc) - create timer from libspelldata()
        local existingST = slotTimers[guid][auraSlot]
        local hasExistingTimer = existingST and ((existingST.startTime + existingST.duration) - now) > 0
        if not hasExistingTimer then
          local forcedDur = libspelldata():GetDuration(spellName)
          if forcedDur and forcedDur > 0 then
            slotTimers[guid][auraSlot] = { startTime = now, duration = forcedDur, rank = 0, isOurs = isOurs }
            pfUI.libdebuff_queue_update(guid)
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[FORCED TIMER]|r aura=%d %s dur=%.1f",
                auraSlot, spellName, forcedDur))
            end
          end
        end
      end

      -- Sync ownDebuffs from slotTimers for our own debuffs
      -- Prevents gap between DEBUFF_REMOVED and AURA_CAST where buffwatch shows nothing
      if isOurs then
        local st = slotTimers[guid][auraSlot]
        if st then
          local texture = libdebuff:GetSpellIcon(spellId)
          ownDebuffs[guid] = ownDebuffs[guid] or {}
          ownDebuffs[guid][spellName] = {
            startTime = st.startTime,
            duration  = st.duration,
            texture   = texture,
            rank      = st.rank or 0,
            spellId   = spellId,
            stacks    = stacks or 1
          }
          -- Store for CleveRoids API - only on confirmed hit (DEBUFF_ADDED = server confirmed)
          -- Never write on AURA_CAST (fires on miss too)
          objectsByGuid[guid] = objectsByGuid[guid] or {}
          objectsByGuid[guid][spellId] = {
            start    = st.startTime,
            duration = st.duration,
            caster   = "player",
            stacks   = stacks or 1
          }
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[OWNDEBUFF SYNC]|r %s rank=%d from DEBUFF_ADDED", spellName, st.rank or 0))
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[->ADDON]|r objectsByGuid[%s][%d] SET start=%.2f dur=%.1f caster=player",
              DebugGuid(guid), spellId, st.startTime, st.duration))
          end
        end
      end

      auraFC[guid] = nil
      
      -- Cleanup expired timers
      CleanupExpiredTimers(guid)
      
      -- Rebuild slot-to-caster mapping for multi-tracking
      local currentTargetGuid = GetUnitGUID("target")
      if currentTargetGuid and currentTargetGuid == guid then
      end
      
      if pfUI.libdebuff_debuff_added_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_debuff_added_other_hooks) do
          fn(arg1, arg2, arg3, arg4)
        end
      end
      if guid and pfUI.libdebuff_target_updated_hooks then
        for _, fn in pairs(pfUI.libdebuff_target_updated_hooks) do
          fn(guid)
        end
      end

    elseif event == "DEBUFF_REMOVED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- Display slot (1-16), compacted
      local spellId = arg3
      local auraSlot_0based = arg6  -- Nampower 2.29+: debuff aura slot, 0-based (32-47). GetUnitField uses 1-based (33-48), so we add +1 below.

      -- Convert Nampower 0-based slot (32-47) to GetUnitField 1-based slot (33-48)
      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil

      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = (GetSpellRecField and GetSpellRecField(spellId, "name")) or "?"
      
      -- Notify libspelldata()
      if libspelldata() then
        libspelldata():OnDebuffRemoved(guid, spellId, spellName)
      end
      
      if debugStats.enabled then
        debugStats.debuff_removed = debugStats.debuff_removed + 1
        if IsCurrentTarget(guid) and spellName and spellName ~= "" and spellName ~= "?" then
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

      -- Check if debuff is still present (stack change, not full removal)
      -- If the spell is still in aura slots, this was a stack decrement - keep timer data
      local isStillPresent = false
      if GetUnitField then
        local auras = GetUnitField(guid, "aura")
        if auras then
          for checkSlot = 33, 48 do
            if auras[checkSlot] and auras[checkSlot] == spellId then
              isStillPresent = true
              break
            end
          end
        end
      end

      local wasOurs = false
      local removedCasterGuid = nil

      if foundAuraSlot then
        -- Get ownership info for this specific slot
        if slotOwnership[guid] and slotOwnership[guid][foundAuraSlot] then
          local ownership = slotOwnership[guid][foundAuraSlot]
          -- Sanity check: slot name must match event spellName to avoid stale mapping
          -- (e.g. displayToAura still pointing to Shadow Weaving's auraSlot after Mind Flay shift)
          if ownership.spellName and spellName ~= "?" and ownership.spellName ~= spellName then
            -- Stale mapping - this auraSlot belongs to a different spell, skip clear
            if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff4400[SLOT MISMATCH]|r aura=%d event=%s but slot has %s - skipping clear",
                GetDebugTimestamp(), foundAuraSlot, spellName, ownership.spellName))
            end
            foundAuraSlot = nil
          else
            wasOurs = ownership.isOurs
            removedCasterGuid = ownership.casterGuid
          end
        end
        
        -- Clear both mappings (with nil-checks) - but NOT if still present (stack change)
        if foundAuraSlot and not isStillPresent then
          if slotOwnership[guid] then
            slotOwnership[guid][foundAuraSlot] = nil
          end
          if displayToAura[guid] then
            displayToAura[guid][displaySlot] = nil
          end
        end
        
        if debugStats.enabled and IsCurrentTarget(guid) and spellName and spellName ~= "" and spellName ~= "?" then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[SLOT CLEARED]|r aura=%d [arg6] %s wasOurs=%s caster=%s stillPresent=%s", 
            GetDebugTimestamp(), foundAuraSlot, spellName, tostring(wasOurs), DebugGuid(removedCasterGuid), tostring(isStillPresent)))
        end
      end
      
      -- sharedOverwrite: clear persistent timer on removal (fires regardless of wasOurs)
      if not isStillPresent and pfUI.libdebuff_sharedoverwrite_timers[guid] and pfUI.libdebuff_sharedoverwrite_timers[guid][spellName] then
        pfUI.libdebuff_sharedoverwrite_timers[guid][spellName] = nil
      end

      if not isStillPresent and wasOurs then
        -- Always clear ownDebuffs and objectsByGuid so Conditionals sees the debuff as gone
        if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
          ownDebuffs[guid][spellName] = nil
        end
        if spellId and objectsByGuid[guid] and objectsByGuid[guid][spellId] then
          objectsByGuid[guid][spellId] = nil
          if debugStats.enabled and IsCurrentTarget(guid) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4400[->ADDON]|r objectsByGuid[%s][%d] CLEARED (%s removed)",
              DebugGuid(guid), spellId, spellName))
          end
        end

        -- Clear slotTimers only if not recently refreshed (age > 1s protects against
        -- DEBUFF_REMOVED firing during a refresh cycle before new DEBUFF_ADDED arrives)
        if foundAuraSlot and slotTimers[guid] and slotTimers[guid][foundAuraSlot] then
          local st = slotTimers[guid][foundAuraSlot]
          local age = GetTime() - st.startTime
          if age > 1 then
            -- Save rank to maxRankSeen only briefly (for the re-apply window).
            -- Also clear it now - it will be re-set if a higher rank truly re-applies.
            -- This prevents stale high-rank entries from blocking lower ranks indefinitely.
            if st.rank and st.rank > 0 then
              maxRankSeen[guid] = maxRankSeen[guid] or {}
              local current = maxRankSeen[guid][spellName] or 0
              if st.rank > current then
                maxRankSeen[guid][spellName] = st.rank
              end
            end
            slotTimers[guid][foundAuraSlot] = nil
            pfUI.libdebuff_queue_update(guid)
            -- Schedule maxRankSeen clear after 2s (re-apply window expires)
            -- We do this by storing the removal time; checked in AURA_CAST
            if maxRankSeen[guid] and maxRankSeen[guid][spellName] then
              maxRankSeen[guid][spellName .. "_cleared"] = GetTime()
            end
          end
        end
      end

      auraFC[guid] = nil
      
      -- Cleanup expired timers
      CleanupExpiredTimers(guid)
      
      -- Rebuild slot-to-caster mapping for multi-tracking
      local currentTargetGuid = GetUnitGUID("target")
      if currentTargetGuid and currentTargetGuid == guid then
      end
      
      -- Notify nameplates
      if pfUI.libdebuff_debuff_removed_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_debuff_removed_other_hooks) do
          fn(arg1, arg2, arg3, arg4)
        end
      end
      if guid and pfUI.libdebuff_target_updated_hooks then
        for _, fn in pairs(pfUI.libdebuff_target_updated_hooks) do
          fn(guid)
        end
      end
      pfUI.libdebuff_queue_update(guid)

    elseif event == "PLAYER_TARGET_CHANGED" then
      if not GetUnitGUID then return end
      local targetGuid = GetUnitGUID("target")
      
      if targetGuid and targetGuid ~= "" then
        -- Invalidate slot map cache on retarget
        slotMapCache[targetGuid] = nil
        auraFC[targetGuid] = nil
        -- Cleanup expired timers for new target
        CleanupExpiredTimers(targetGuid)
      end
      if pfUI.libdebuff_player_target_changed_hooks then
        for _, fn in pairs(pfUI.libdebuff_player_target_changed_hooks) do
          fn()
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
    if not GetUnitGUID("target") then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff]|r No target!")
      return
    end
    
    local guid = GetUnitGUID("target")
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
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  slotTimers: %d GUIDs", countTable(slotTimers)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  pendingCasts: %d GUIDs", countTable(pendingCasts)))
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00No ownSlots/allSlots (eliminated by GetUnitField approach!)|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff============================================================|r")
end

-- Clear buff slot map cache and rebuild HiddenBuffsLookup (call after hidelist changes)
function libdebuff:ClearBuffCache()
  slotMapCache = {}
  playerBuffMapCache = { map = nil, timestamp = 0 }
  playerDebuffMapCache = { map = nil, timestamp = 0 }
  pfUI_HiddenBuffsLookup = {}
  pfUI_HiddenBuffNames = {}
  local hidelist = pfUI_config and pfUI_config.buffs and pfUI_config.buffs.hidelist
  if hidelist and hidelist ~= "" then
    for id in string.gfind(hidelist, "([^#]+)") do
      local sid = tonumber(id)
      if sid then
        pfUI_HiddenBuffsLookup[sid] = true
        local sname = GetSpellRecField and GetSpellRecField(sid, "name")
        if sname and sname ~= "" then
          pfUI_HiddenBuffNames[sname] = true
        end
      end
    end
  end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r GetUnitField Edition loaded!")