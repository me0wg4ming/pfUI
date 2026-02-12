-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libspelldata - Spell Knowledge Database for pfUI ]]--
--
-- Central database for spells where Nampower's AURA_CAST returns durationMs=0
-- or where special duration logic is needed (combopoint abilities, talent mods).
--
-- This library is PURE KNOWLEDGE + lightweight state tracking.
-- It does NOT store debuff timers itself - that remains libdebuff's job.
-- libdebuff calls libspelldata for answers, then stores results in its own tables.
--
-- Handles:
--   1. Forced durations (Judgements etc. where AURA_CAST gives 0)
--   2. Combopoint ability classification (Rip, Rupture, Kidney Shot, Expose Armor)
--      NOTE: CP values are captured by libdebuff at SPELL_CAST_EVENT time
--      (before client consumes them). libspelldata only provides base/perCP data.
--   3. Carnage talent refresh detection (Ferocious Bite → Rip/Rake reset)
--   4. Applicator caster correlation (Judgement SPELL_GO → DEBUFF_ADDED)
--   5. SPELL_GO refresh detection (Judgement procs on melee hit)
--
-- Requires: Nampower 2.27.2+ (SPELL_GO, DEBUFF_ADDED events)
-- Integrates with: libdebuff.lua (called from event handlers)

-- return instantly if not vanilla
if pfUI.client > 11200 then return end

-- Require Nampower
local hasNampower = GetNampowerVersion and true or false
if not hasNampower then return end

pfUI.libspelldata = pfUI.libspelldata or {}
local lib = pfUI.libspelldata

-- ============================================================================
-- SPELL DATABASE: FORCED DURATIONS
-- Spells where AURA_CAST returns durationMs=0 or doesn't fire at all.
-- These need hardcoded durations and refresh tracking.
--
-- Format: ["Spell Name"] = { duration = seconds, refreshOnMelee = bool }
--   refreshOnMelee: if true, every melee hit by the caster refreshes the timer
-- ============================================================================

local forcedDurations = {
  -- PALADIN JUDGEMENTS (10 sec, refreshed by every melee autohit from the caster)
  -- AURA_CAST never fires for these on the target. Timer starts from
  -- Judgement(20271) SPELL_GO, refreshed by caster's melee hits.
  ["Judgement of Wisdom"]       = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of Light"]        = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of the Crusader"] = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of Justice"]      = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },

  -- MAGE PASSIVE PROCS (refreshed by specific Fire spells)
  -- Fire Vulnerability: Applied by Scorch, refreshed by Scorch and Fire Blast
  ["Fire Vulnerability"]        = { duration = 30, refreshOnMelee = false, applicatorSpells = {"Scorch", "Fire Blast"} },
  
  -- Ignite: Applied/refreshed ONLY on crit Fire damage (any Fire spell can crit)
  ["Ignite"]                    = { duration = 4,  refreshOnMelee = false, critBasedRefresh = true },
  
  -- Winter's Chill: Applied/refreshed by Frost spells (NOT Blizzard - vanilla bug)
  ["Winter's Chill"]            = { duration = 15, refreshOnMelee = false, applicatorSpells = {"Frostbolt", "Cone of Cold", "Frost Nova"} },
  
  -- PRIEST PASSIVE PROCS (refreshed by specific Shadow spells)
  -- Shadow Weaving: Applied/refreshed by Shadow DAMAGE spells (not Mana Burn!)
  ["Shadow Weaving"]            = { duration = 15, refreshOnMelee = false, applicatorSpells = {"Mind Blast", "Mind Flay", "Shadow Word: Pain", "Devouring Plague"} },

  -- CHANNELED/AOE DEBUFFS (fixed duration, applied via DEBUFF_ADDED)
  -- These have no AURA_CAST and no targetGuid in SPELL_GO.
  -- Caster is resolved via pendingAoE in libdebuff.
  ["Hurricane"]                 = { duration = 10, refreshOnMelee = false, applicatorSpells = false },
  ["Consecration"]              = { duration = 8,  refreshOnMelee = false, applicatorSpells = false },
  ["Blizzard"]                  = { duration = 8,  refreshOnMelee = false, applicatorSpells = false },
  ["Hellfire"]                  = { duration = 15, refreshOnMelee = false, applicatorSpells = false },
  ["Rain of Fire"]              = { duration = 8,  refreshOnMelee = false, applicatorSpells = false },
  ["Flamestrike"]               = { duration = 8,  refreshOnMelee = false, applicatorSpells = false },

  -- Target spells that return no duration from AURA_CAST and need hardcoded durations.
  -- ["Spell Name"] = { duration = X, refreshOnMelee = true/false, applicatorSpells = {...}/false },
  ["Pain Spike"]                = { duration = 5,  refreshOnMelee = false, applicatorSpells = false },
  ["Pounce Bleed"]              = { duration = 18,  refreshOnMelee = false, applicatorSpells = {"Pounce"} },


}

-- ============================================================================
-- SPELL DATABASE: COMBOPOINT ABILITIES
-- Duration depends on combo points at time of cast.
-- For OUR casts: libdebuff:GetDuration() handles the CP lookup directly
-- For OTHERS' casts: CP unknown → duration = 0 (no timer shown)
--
-- Format: ["Spell Name"] = { base = N, perCP = N }
--   Rogue/Druid CP formula: duration = base + combopoints * perCP
-- ============================================================================

local combopointSpells = {
  -- Druid
  ["Rip"]          = { base = 8,  perCP = 2 },

  -- Rogue
  ["Rupture"]      = { base = 6,  perCP = 2 },
  ["Kidney Shot"]  = { base = 1,  perCP = 1 },
  ["Expose Armor"] = { base = 30, perCP = 0 },  -- fixed 30s
}

-- ============================================================================
-- CARNAGE TALENT (Druid Feral, talent 2/17)
-- Ferocious Bite proc: If Carnage procs, Rip and Rake timers are reset.
-- Detection: Check for combo point gain 50ms after Ferocious Bite lands.
-- ============================================================================

local carnageRefreshable = {
  ["Rip"]  = true,
  ["Rake"] = true,
}

-- ============================================================================
-- SELF-OVERWRITE DEBUFFS
-- Only ONE instance of these debuffs can exist on a target (regardless of caster).
-- When a new caster applies it, the old caster's entry is replaced.
-- ============================================================================

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

-- ============================================================================
-- DEBUFF OVERWRITE PAIRS
-- Variant debuffs that replace each other on the same target.
-- e.g. Faerie Fire overwrites Faerie Fire (Feral) and vice versa.
-- ============================================================================

local debuffOverwritePairs = {
  ["Faerie Fire"] = "Faerie Fire (Feral)",
  ["Faerie Fire (Feral)"] = "Faerie Fire",
  ["Demoralizing Shout"] = "Demoralizing Roar",
  ["Demoralizing Roar"] = "Demoralizing Shout",
}

-- ============================================================================
-- APPLICATOR SPELLS
-- Spells whose SPELL_GO should be stored as pending caster for correlation
-- with the next DEBUFF_ADDED on the same target.
-- Used to identify caster when AURA_CAST doesn't fire.
-- ============================================================================

local applicatorSpells = {
  [20271] = true,   -- Judgement (result depends on active seal)
}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

-- Pending applicator casters: [targetGuid] = { casterGuid, time }
-- Consumed by OnDebuffAdded within 0.5s
local pendingApplicators = {}

-- Carnage state
local _, playerClass = UnitClass("player")
local carnageRank = 0
local carnageState = nil
local carnageCallback = nil  -- registered by libdebuff

-- Player GUID cache
local cachedPlayerGuid = nil
local function GetPlayerGUID()
  if not cachedPlayerGuid and UnitExists then
    local _, guid = UnitExists("player")
    cachedPlayerGuid = guid
  end
  return cachedPlayerGuid
end

-- ============================================================================
-- CARNAGE TALENT TRACKING
-- ============================================================================

local function UpdateCarnageRank()
  if playerClass ~= "DRUID" then return end
  local _, _, _, _, rank = GetTalentInfo(2, 17)
  carnageRank = rank or 0
end

-- Talent update listener (own frame, independent of libdebuff)
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
talentFrame:RegisterEvent("PLAYER_LOGOUT")
talentFrame:SetScript("OnEvent", function()
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    return
  end
  UpdateCarnageRank()
  -- Cache player GUID on login
  if event == "PLAYER_ENTERING_WORLD" then
    GetPlayerGUID()
  end
end)

-- Carnage OnUpdate frame: checks CP 50ms after Ferocious Bite
local carnageFrame = CreateFrame("Frame")
carnageFrame:Hide()
carnageFrame:SetScript("OnUpdate", function()
  if not carnageState then
    this:Hide()
    return
  end
  if GetTime() < carnageState.checkTime then return end

  -- Check if we GAINED combo points (indicates Carnage proc)
  -- Compare current CPs to what we had before the Bite
  local cpNow = GetComboPoints() or 0
  local cpGained = (cpNow - carnageState.cpBefore) > 0

  if cpGained and carnageCallback then
    -- Carnage triggered! Collect affected spell names
    local affected = {}
    local n = 0
    for spellName in pairs(carnageRefreshable) do
      n = n + 1
      affected[n] = spellName
    end
    carnageCallback(carnageState.targetGuid, affected)
  end

  carnageState = nil
  this:Hide()
end)

-- ============================================================================
-- API: SPELL QUERIES
-- ============================================================================

--- Is this a combopoint ability?
function lib:IsComboPointAbility(spellName)
  if not spellName then return false end
  return combopointSpells[spellName] ~= nil
end

--- Get combopoint spell data (base duration and per-CP bonus).
-- @return base, perCP or nil, nil if not a CP ability
function lib:GetComboPointData(spellName)
  if not spellName then return nil, nil end
  local cpData = combopointSpells[spellName]
  if cpData then
    return cpData.base, cpData.perCP
  end
  return nil, nil
end

--- Does this spell have a forced (hardcoded) duration?
function lib:HasForcedDuration(spellName)
  if not spellName then return false end
  return forcedDurations[spellName] ~= nil
end

--- Check if a spell can refresh a debuff via applicatorSpells list
-- @param debuffName  The debuff to check (e.g., "Fire Vulnerability")
-- @param spellName   The spell being cast (e.g., "Scorch", "Fire Blast")
-- @return true if spellName is in debuffName's applicatorSpells list
function lib:IsApplicatorSpell(debuffName, spellName)
  if not debuffName or not spellName then return false end
  
  local data = forcedDurations[debuffName]
  if not data then return false end
  
  -- No applicator spells defined (false or nil)
  if not data.applicatorSpells then return false end
  
  -- Check if spellName is in the applicatorSpells table
  for _, applicator in ipairs(data.applicatorSpells) do
    if applicator == spellName then
      return true
    end
  end
  
  return false
end

--- Check if a debuff requires a critical hit to refresh
-- @param debuffName  The debuff to check (e.g., "Ignite")
-- @param spellName   The spell that dealt damage (optional, for future filtering)
-- @return true if debuff requires crit for refresh
function lib:RequiresCritForRefresh(debuffName, spellName)
  if not debuffName then return false end
  
  local data = forcedDurations[debuffName]
  if not data then return false end
  
  -- Check if critBasedRefresh is true
  return data.critBasedRefresh == true
end

--- Is this a self-overwrite debuff? (only one instance per target)
function lib:IsSelfOverwrite(spellName)
  if not spellName then return false end
  return selfOverwriteDebuffs[spellName] == true
end

--- Get the overwrite pair for a debuff (e.g. Faerie Fire → Faerie Fire (Feral))
-- @return other variant name, or nil if no pair exists
function lib:GetOverwritePair(spellName)
  if not spellName then return nil end
  return debuffOverwritePairs[spellName]
end

--- Get the correct duration for a managed spell.
-- NOTE: For combopoint abilities use GetComboPointData() instead.
-- Duration is calculated by libdebuff using captured CPs from SPELL_CAST_EVENT.
-- @param spellName  The spell name
-- @return duration (number) or nil if not managed / is a CP ability
function lib:GetDuration(spellName)
  if not spellName then return nil end

  -- Forced duration spells (Judgements etc.)
  local forced = forcedDurations[spellName]
  if forced then
    return forced.duration
  end

  -- Combopoint abilities: return nil, libdebuff handles these
  return nil
end

-- ============================================================================
-- API: MELEE REFRESH
-- ============================================================================

--- Get table of melee-refreshable spell names and their durations.
-- Called by libdebuff from AUTO_ATTACK handler to check which debuffs
-- from a given attacker on a given target should be refreshed.
-- @return table of {["spellName"] = duration} for refreshOnMelee spells
local meleeRefreshCache = nil
function lib:GetMeleeRefreshSpells()
  if not meleeRefreshCache then
    meleeRefreshCache = {}
    for spellName, data in pairs(forcedDurations) do
      if data.refreshOnMelee then
        meleeRefreshCache[spellName] = data.duration
      end
    end
  end
  return meleeRefreshCache
end

-- ============================================================================
-- API: CARNAGE
-- ============================================================================

--- Register a callback for Carnage proc events.
-- The callback receives: (targetGuid, affectedSpellNames)
-- where affectedSpellNames is a table like {"Rip", "Rake"}
function lib:SetCarnageCallback(callback)
  carnageCallback = callback
end

--- Should we check for Carnage proc after this SPELL_GO?
-- @return true if Ferocious Bite from player with Carnage talent
function lib:ShouldCheckCarnage(spellName, casterGuid, targetGuid, numHit)
  if playerClass ~= "DRUID" then return false end
  if carnageRank < 1 then return false end
  if spellName ~= "Ferocious Bite" then return false end
  if casterGuid ~= GetPlayerGUID() then return false end
  if not targetGuid or (numHit and numHit == 0) then return false end
  return true
end

--- Schedule the async Carnage check (50ms delay for CP to register).
-- If Carnage procs, the registered callback will fire.
function lib:ScheduleCarnageCheck(targetGuid)
  carnageState = {
    targetGuid = targetGuid,
    checkTime = GetTime() + 0.05,
    cpBefore = GetComboPoints() or 0  -- Track CPs before Bite to detect gain
  }
  carnageFrame:Show()
end

-- ============================================================================
-- API: APPLICATOR TRACKING (SPELL_GO → DEBUFF_ADDED caster correlation)
-- ============================================================================

--- Called from libdebuff's SPELL_GO handler.
-- Stores pending caster info for applicator spells (e.g. Judgement).
function lib:OnSpellGo(spellId, spellName, casterGuid, targetGuid)
  if applicatorSpells[spellId] and targetGuid then
    pendingApplicators[targetGuid] = {
      casterGuid = casterGuid,
      time = GetTime()
    }
  end
end

--- Called from libdebuff's DEBUFF_ADDED handler.
-- Consumes a pending applicator if one exists for this target (within 0.5s).
-- @return casterGuid if an applicator match was found, nil otherwise
function lib:OnDebuffAdded(targetGuid, spellId, spellName)
  if not targetGuid then return nil end

  -- Only consume for spells we manage (forced durations)
  -- This prevents consuming the applicator for unrelated debuffs
  if not forcedDurations[spellName] then return nil end

  local pending = pendingApplicators[targetGuid]
  if pending and (GetTime() - pending.time) < 0.5 then
    pendingApplicators[targetGuid] = nil
    return pending.casterGuid
  end

  return nil
end

--- Called from libdebuff's DEBUFF_REMOVED handler.
-- Currently a no-op; timer data lives in libdebuff's tables.
function lib:OnDebuffRemoved(targetGuid, spellId, spellName)
  -- No internal state to clean up for removed debuffs
end

-- ============================================================================
-- API: CLEANUP
-- ============================================================================

--- Clean up all internal state for a target.
function lib:CleanupUnit(targetGuid)
  pendingApplicators[targetGuid] = nil
end