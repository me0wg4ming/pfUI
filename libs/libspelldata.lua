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
--   1. Self-overwrite debuffs (only one instance per target)
--   2. Debuff overwrite pairs (Faerie Fire <-> Faerie Fire (Feral))
--   3. Combopoint ability classification (Rip, Rupture, Kidney Shot, Expose Armor)
--   4. Forced durations (Judgements, AoE channels, passive procs)
--   5. Melee-hit refresh (Judgement timers refreshed by autoattacks)
--   6. Applicator caster correlation (Judgement SPELL_GO -> DEBUFF_ADDED)
--   7. Crit-based refresh (Ignite)
--   8. Carnage talent refresh detection (Ferocious Bite -> Rip/Rake reset)
--
-- Requires: Nampower 3.0.0+
-- Integrates with: libdebuff.lua (called from event handlers)

-- return instantly if not vanilla
if pfUI.client > 11200 then return end

-- Require Nampower
if not GetNampowerVersion then return end

pfUI.libspelldata = pfUI.libspelldata or {}
local lib = pfUI.libspelldata

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
  ["Fire Vulnerability"] = true,
}

-- ============================================================================
-- DEBUFF OVERWRITE PAIRS
-- Variant debuffs that replace each other on the same target.
-- ============================================================================

local debuffOverwritePairs = {
  ["Faerie Fire"] = "Faerie Fire (Feral)",
  ["Faerie Fire (Feral)"] = "Faerie Fire",
  ["Demoralizing Shout"] = "Demoralizing Roar",
  ["Demoralizing Roar"] = "Demoralizing Shout",
}

-- ============================================================================
-- COMBOPOINT ABILITIES
-- Duration depends on combo points at time of cast.
-- For OUR casts: CPs captured at SPELL_CAST_EVENT time by libdebuff.
-- For OTHERS' casts: CP unknown -> duration = 0 (no timer shown)
--
-- Format: ["Spell Name"] = { base = N, perCP = N }
--   duration = base + combopoints * perCP
-- ============================================================================

local combopointSpells = {
  -- Druid
  ["Rip"]            = { base = 8,  perCP = 2 },

  -- Rogue
  ["Rupture"]        = { base = 6,  perCP = 2 },
  ["Kidney Shot"]    = { base = 1,  perCP = 1 },
  ["Expose Armor"]   = { base = 30, perCP = 0 },  -- fixed 30s
}

-- ============================================================================
-- FORCED DURATIONS
-- Spells where AURA_CAST returns durationMs=0 or doesn't fire at all.
--
-- Format: ["Spell Name"] = { duration = seconds, refreshOnMelee = bool, ... }
--   refreshOnMelee: if true, every melee hit by the caster refreshes the timer
--   applicatorSpells: table of spell names that refresh this debuff, or false
--   critBasedRefresh: if true, any crit from triggering spells refreshes
-- ============================================================================

local forcedDurations = {
  -- PALADIN JUDGEMENTS (10 sec, refreshed by every melee autohit from the caster)
  ["Judgement of Wisdom"]       = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of Light"]        = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of the Crusader"] = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },
  ["Judgement of Justice"]      = { duration = 10, refreshOnMelee = true,  applicatorSpells = false },

  -- MAGE PASSIVE PROCS
  ["Fire Vulnerability"]        = { duration = 30, refreshOnMelee = false, applicatorSpells = {"Scorch", "Fire Blast", "Fireball", "Pyroblast", "Flamestrike", "Fire Blast", "Blast Wave", "Dragon's Breath", "Arcane Explosion"} },
  ["Ignite"]                    = { duration = 4,  refreshOnMelee = false, critBasedRefresh = true },
  ["Winter's Chill"]            = { duration = 15, refreshOnMelee = false, applicatorSpells = {"Frostbolt", "Cone of Cold", "Frost Nova"} },

  -- PRIEST PASSIVE PROCS
  ["Shadow Weaving"]            = { duration = 15, refreshOnMelee = false, applicatorSpells = {"Mind Blast", "Mind Flay", "Shadow Word: Pain", "Devouring Plague"} },

  -- CHANNELED/AOE DEBUFFS (no AURA_CAST, no targetGuid in SPELL_GO)
  -- isAoEChannel: timer should NOT be refreshed on subsequent ticks
  ["Hurricane"]                 = { duration = 10, isAoEChannel = true },
  ["Consecration"]              = { duration = 8,  isAoEChannel = true },
  ["Blizzard"]                  = { duration = 8,  isAoEChannel = true },
  ["Rain of Fire"]              = { duration = 8,  isAoEChannel = true },
  ["Frost Trap Aura"]           = { duration = 30,  isAoEChannel = true },
  ["Explosive Trap Effect"]     = { duration = 20,  isAoEChannel = true },
  ["Flamestrike"]               = { duration = 8,  isAoEChannel = true },
  ["Garrote"]                   = { duration = 18,  isAoEChannel = false },
  ["Piercing Shots"]            = { duration = 8,  isAoEChannel = false },

  -- Other spells with no duration from AURA_CAST
  ["Pain Spike"]                = { duration = 5,  refreshOnMelee = false, applicatorSpells = false },
  ["Pounce Bleed"]              = { duration = 18, refreshOnMelee = false, applicatorSpells = {"Pounce"} },
}

-- ============================================================================
-- APPLICATOR SPELLS (spellId -> true)
-- Spells whose SPELL_GO should be stored as pending caster for correlation
-- with the next DEBUFF_ADDED on the same target.
-- ============================================================================

local applicatorSpells = {
  [20271] = true,   -- Judgement (result depends on active seal)
}

-- ============================================================================
-- CARNAGE TALENT (Druid Feral, talent 2/17)
-- Ferocious Bite proc: If Carnage procs, Rip and Rake timers are reset.
-- ============================================================================

local carnageRefreshable = {
  ["Rip"]  = true,
  ["Rake"] = true,
}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

-- Pending applicator casters: [targetGuid] = { casterGuid, time }
local pendingApplicators = {}

-- Carnage state
local _, playerClass = UnitClass("player")
local carnageState = nil
local carnageCallback = nil

-- Player GUID cache
local cachedPlayerGuid = nil
local function GetPlayerGuid()
  if not cachedPlayerGuid and GetUnitGUID then
    cachedPlayerGuid = GetUnitGUID("player")
  end
  return cachedPlayerGuid
end

-- ============================================================================
-- CARNAGE TALENT TRACKING
-- ============================================================================

-- No talent check needed: If Druid uses Ferocious Bite and gets +1 CP,
-- Carnage procced. The CP check in OnUpdate handles detection.

-- Persistent Carnage check frame
local carnageFrame = CreateFrame("Frame")
carnageFrame:Hide()
carnageFrame:SetScript("OnUpdate", function()
  if not carnageState then
    this:Hide()
    return
  end
  if GetTime() < carnageState.checkTime then return end

  -- Check if we gained a combo point (indicates Carnage proc)
  local cp = GetComboPoints() or 0

  if cp > 0 and carnageCallback then
    local affectedSpells = {}
    for spellName in pairs(carnageRefreshable) do
      table.insert(affectedSpells, spellName)
    end
    carnageCallback(carnageState.targetGuid, affectedSpells)
  end

  carnageState = nil
  this:Hide()
end)

-- ============================================================================
-- API: SPELL QUERIES
-- ============================================================================

function lib:IsSelfOverwrite(spellName)
  if not spellName then return false end
  return selfOverwriteDebuffs[spellName] == true
end

function lib:GetOverwritePair(spellName)
  if not spellName then return nil end
  return debuffOverwritePairs[spellName]
end

function lib:IsComboPointAbility(spellName)
  if not spellName then return false end
  return combopointSpells[spellName] ~= nil
end

function lib:GetComboPointData(spellName)
  if not spellName then return nil, nil end
  local cpData = combopointSpells[spellName]
  if cpData then
    return cpData.base, cpData.perCP
  end
  return nil, nil
end

function lib:HasForcedDuration(spellName)
  if not spellName then return false end
  return forcedDurations[spellName] ~= nil
end

function lib:IsAoEChannel(spellName)
  if not spellName then return false end
  local data = forcedDurations[spellName]
  return data and data.isAoEChannel or false
end

function lib:IsAnyApplicatorSpell(spellName)
  if not spellName then return false end
  for _, data in pairs(forcedDurations) do
    if data.applicatorSpells then
      for _, applicator in ipairs(data.applicatorSpells) do
        if applicator == spellName then return true end
      end
    end
  end
  return false
end

function lib:IsApplicatorSpell(debuffName, spellName)
  if not debuffName or not spellName then return false end
  local data = forcedDurations[debuffName]
  if not data or not data.applicatorSpells then return false end
  for _, applicator in ipairs(data.applicatorSpells) do
    if applicator == spellName then
      return true
    end
  end
  return false
end

function lib:RequiresCritForRefresh(debuffName, spellName)
  if not debuffName then return false end
  local data = forcedDurations[debuffName]
  if not data then return false end
  return data.critBasedRefresh == true
end

--- Get the correct duration for a managed spell.
-- For combopoint abilities use GetComboPointData() instead.
function lib:GetDuration(spellName, rank, casterGuid)
  if not spellName then return nil end
  local forced = forcedDurations[spellName]
  if forced then
    return forced.duration
  end
  return nil
end

-- ============================================================================
-- API: MELEE REFRESH
-- ============================================================================

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

function lib:SetCarnageCallback(callback)
  carnageCallback = callback
end

function lib:ShouldCheckCarnage(spellName, casterGuid, targetGuid, numHit)
  if playerClass ~= "DRUID" then return false end
  if spellName ~= "Ferocious Bite" then return false end
  if casterGuid ~= GetPlayerGuid() then return false end
  if not targetGuid or (numHit and numHit == 0) then return false end
  return true
end

function lib:ScheduleCarnageCheck(targetGuid)
  carnageState = {
    targetGuid = targetGuid,
    checkTime = GetTime() + 0.05,
  }
  carnageFrame:Show()
end

-- ============================================================================
-- API: APPLICATOR TRACKING (SPELL_GO -> DEBUFF_ADDED caster correlation)
-- ============================================================================

function lib:OnSpellGo(spellId, spellName, casterGuid, targetGuid)
  if applicatorSpells[spellId] and targetGuid then
    pendingApplicators[targetGuid] = {
      casterGuid = casterGuid,
      time = GetTime()
    }
  end
end

function lib:OnDebuffAdded(targetGuid, spellId, spellName)
  if not targetGuid then return nil end
  if not forcedDurations[spellName] then return nil end
  local pending = pendingApplicators[targetGuid]
  if pending and (GetTime() - pending.time) < 0.5 then
    pendingApplicators[targetGuid] = nil
    return pending.casterGuid
  end
  return nil
end

function lib:OnDebuffRemoved(targetGuid, spellId, spellName)
  -- No internal state to clean up
end

-- ============================================================================
-- API: CLEANUP
-- ============================================================================

function lib:CleanupUnit(targetGuid)
  pendingApplicators[targetGuid] = nil
end
