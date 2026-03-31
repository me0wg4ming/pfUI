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


local sharedOverwriteDebuffs = {
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

function lib:IsSharedOverwrite(spellName)
  if not spellName then return false end
  return sharedOverwriteDebuffs[spellName] == true
end

function lib:GetOverwritePair(spellName)
  if not spellName then return nil end
  return debuffOverwritePairs[spellName]
end


-- ============================================================================
-- SpellID-based debuff lookup (from Cursive addon data)
-- Used by SPELL_GO_SELF to get duration without locales database fallback
-- combopointAbility = true means duration is calculated from combo points
-- ============================================================================
-- SpellID-based debuff duration lookup
-- Source: Cursive addon (https://github.com/TurtleWoW/Cursive)
-- Used by SPELL_GO_SELF to get duration without relying on locales database
-- combopointAbility = true means duration is calculated from combo points (see combopointSpells)
local spellIdDebuffs = {
  -- DRUID
  -- Entangling Roots
  [339]   = { name = "Entangling Roots",  duration = 12 },
  [1062]  = { name = "Entangling Roots",  duration = 15 },
  [5195]  = { name = "Entangling Roots",  duration = 18 },
  [5196]  = { name = "Entangling Roots",  duration = 21 },
  [9852]  = { name = "Entangling Roots",  duration = 24 },
  [9853]  = { name = "Entangling Roots",  duration = 27 },
  -- Hibernate
  [2637]  = { name = "Hibernate",         duration = 20 },
  [18657] = { name = "Hibernate",         duration = 30 },
  [18658] = { name = "Hibernate",         duration = 40 },
  -- Faerie Fire
  [770]   = { name = "Faerie Fire",       duration = 40 },
  [778]   = { name = "Faerie Fire",       duration = 40 },
  [9749]  = { name = "Faerie Fire",       duration = 40 },
  [9907]  = { name = "Faerie Fire",       duration = 40 },
  [16855] = { name = "Faerie Fire",       duration = 40 },
  [17387] = { name = "Faerie Fire",       duration = 40 },
  [17388] = { name = "Faerie Fire",       duration = 40 },
  [17389] = { name = "Faerie Fire",       duration = 40 },
  [16857] = { name = "Faerie Fire",       duration = 40 },
  [17390] = { name = "Faerie Fire",       duration = 40 },
  [17391] = { name = "Faerie Fire",       duration = 40 },
  [17392] = { name = "Faerie Fire",       duration = 40 },
  -- Insect Swarm
  [5570]  = { name = "Insect Swarm",      duration = 12 },
  [24974] = { name = "Insect Swarm",      duration = 12 },
  [24975] = { name = "Insect Swarm",      duration = 12 },
  [24976] = { name = "Insect Swarm",      duration = 18 },
  [24977] = { name = "Insect Swarm",      duration = 18 },
  -- Moonfire
  [8921]  = { name = "Moonfire",          duration = 9  },
  [8924]  = { name = "Moonfire",          duration = 12 },
  [8925]  = { name = "Moonfire",          duration = 12 },
  [8926]  = { name = "Moonfire",          duration = 12 },
  [8927]  = { name = "Moonfire",          duration = 12 },
  [8928]  = { name = "Moonfire",          duration = 12 },
  [8929]  = { name = "Moonfire",          duration = 12 },
  [9833]  = { name = "Moonfire",          duration = 12 },
  [9834]  = { name = "Moonfire",          duration = 12 },
  [9835]  = { name = "Moonfire",          duration = 12 },
  -- Rake
  [1822]  = { name = "Rake",              duration = 9,  combopointAbility = true },
  [1823]  = { name = "Rake",              duration = 9,  combopointAbility = true },
  [1824]  = { name = "Rake",              duration = 9,  combopointAbility = true },
  [9904]  = { name = "Rake",              duration = 9,  combopointAbility = true },
  -- Rip
  [1079]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  [9492]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  [9493]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  [9752]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  [9894]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  [9896]  = { name = "Rip",              duration = 8,  combopointAbility = true },
  -- Bash
  [5211]  = { name = "Bash",             duration = 2  },
  [6798]  = { name = "Bash",             duration = 3  },
  [8983]  = { name = "Bash",             duration = 4  },
  -- Demoralizing Roar
  [99]    = { name = "Demoralizing Roar", duration = 30 },
  [1735]  = { name = "Demoralizing Roar", duration = 30 },
  [9490]  = { name = "Demoralizing Roar", duration = 30 },
  [9747]  = { name = "Demoralizing Roar", duration = 30 },
  [9898]  = { name = "Demoralizing Roar", duration = 30 },

  -- WARLOCK
  -- Corruption
  [172]   = { name = "Corruption",        duration = 12 },
  [6222]  = { name = "Corruption",        duration = 15 },
  [6223]  = { name = "Corruption",        duration = 18 },
  [7648]  = { name = "Corruption",        duration = 18 },
  [11671] = { name = "Corruption",        duration = 18 },
  [11672] = { name = "Corruption",        duration = 18 },
  [25311] = { name = "Corruption",        duration = 18 },
  -- Curse of Agony
  [980]   = { name = "Curse of Agony",    duration = 24 },
  [1014]  = { name = "Curse of Agony",    duration = 24 },
  [6217]  = { name = "Curse of Agony",    duration = 24 },
  [11711] = { name = "Curse of Agony",    duration = 24 },
  [11712] = { name = "Curse of Agony",    duration = 24 },
  [11713] = { name = "Curse of Agony",    duration = 24 },
  -- Siphon Life
  [18265] = { name = "Siphon Life",       duration = 30 },
  [18879] = { name = "Siphon Life",       duration = 30 },
  [18880] = { name = "Siphon Life",       duration = 30 },
  [18881] = { name = "Siphon Life",       duration = 30 },
  -- Curse of Doom
  [603]   = { name = "Curse of Doom",     duration = 60 },
  -- Curse of Recklessness
  [704]   = { name = "Curse of Recklessness", duration = 120 },
  [7658]  = { name = "Curse of Recklessness", duration = 120 },
  [7659]  = { name = "Curse of Recklessness", duration = 120 },
  [11717] = { name = "Curse of Recklessness", duration = 120 },
  -- Curse of Shadow
  [17862] = { name = "Curse of Shadow",   duration = 300 },
  [17937] = { name = "Curse of Shadow",   duration = 300 },
  -- Curse of the Elements
  [1490]  = { name = "Curse of the Elements", duration = 300 },
  [11721] = { name = "Curse of the Elements", duration = 300 },
  [11722] = { name = "Curse of the Elements", duration = 300 },
  -- Curse of Tongues
  [1714]  = { name = "Curse of Tongues",  duration = 30 },
  [11719] = { name = "Curse of Tongues",  duration = 30 },
  -- Curse of Weakness
  [702]   = { name = "Curse of Weakness", duration = 120 },
  [1108]  = { name = "Curse of Weakness", duration = 120 },
  [6205]  = { name = "Curse of Weakness", duration = 120 },
  [7646]  = { name = "Curse of Weakness", duration = 120 },
  [11707] = { name = "Curse of Weakness", duration = 120 },
  [11708] = { name = "Curse of Weakness", duration = 120 },
  -- Curse of Exhaustion
  [18223] = { name = "Curse of Exhaustion", duration = 12 },
  -- Immolate
  [348]   = { name = "Immolate",          duration = 15 },
  [707]   = { name = "Immolate",          duration = 15 },
  [1094]  = { name = "Immolate",          duration = 15 },
  [2941]  = { name = "Immolate",          duration = 15 },
  [11665] = { name = "Immolate",          duration = 15 },
  [11667] = { name = "Immolate",          duration = 15 },
  [11668] = { name = "Immolate",          duration = 15 },
  [25309] = { name = "Immolate",          duration = 15 },
  -- Fear
  [5782]  = { name = "Fear",              duration = 10 },
  [6213]  = { name = "Fear",              duration = 15 },
  [6215]  = { name = "Fear",              duration = 20 },
  -- Banish
  [710]   = { name = "Banish",            duration = 20 },
  [18647] = { name = "Banish",            duration = 30 },

  -- PRIEST
  -- Shadow Word: Pain
  [589]   = { name = "Shadow Word: Pain", duration = 24 },
  [594]   = { name = "Shadow Word: Pain", duration = 24 },
  [970]   = { name = "Shadow Word: Pain", duration = 24 },
  [992]   = { name = "Shadow Word: Pain", duration = 24 },
  [2767]  = { name = "Shadow Word: Pain", duration = 24 },
  [10892] = { name = "Shadow Word: Pain", duration = 24 },
  [10893] = { name = "Shadow Word: Pain", duration = 24 },
  [10894] = { name = "Shadow Word: Pain", duration = 24 },
  -- Devouring Plague
  [2944]  = { name = "Devouring Plague",  duration = 24 },
  [19276] = { name = "Devouring Plague",  duration = 24 },
  [19277] = { name = "Devouring Plague",  duration = 24 },
  [19278] = { name = "Devouring Plague",  duration = 24 },
  [19279] = { name = "Devouring Plague",  duration = 24 },
  [19280] = { name = "Devouring Plague",  duration = 24 },
  -- Mind Control
  [605]   = { name = "Mind Control",      duration = 60 },
  [10911] = { name = "Mind Control",      duration = 30 },
  [10912] = { name = "Mind Control",      duration = 30 },
  -- Vampiric Embrace
  [15286] = { name = "Vampiric Embrace",  duration = 60 },

  -- ROGUE
  -- Garrote
  [703]   = { name = "Garrote",           duration = 18 },
  [8631]  = { name = "Garrote",           duration = 18 },
  [8632]  = { name = "Garrote",           duration = 18 },
  [8633]  = { name = "Garrote",           duration = 18 },
  [11289] = { name = "Garrote",           duration = 18 },
  [11290] = { name = "Garrote",           duration = 18 },
  -- Rupture
  [1943]  = { name = "Rupture",           duration = 6,  combopointAbility = true },
  [8639]  = { name = "Rupture",           duration = 8,  combopointAbility = true },
  [8640]  = { name = "Rupture",           duration = 10, combopointAbility = true },
  [11273] = { name = "Rupture",           duration = 12, combopointAbility = true },
  [11274] = { name = "Rupture",           duration = 14, combopointAbility = true },
  [11275] = { name = "Rupture",           duration = 16, combopointAbility = true },
  -- Kidney Shot
  [408]   = { name = "Kidney Shot",       duration = 2,  combopointAbility = true },
  [8643]  = { name = "Kidney Shot",       duration = 2,  combopointAbility = true },
  -- Deadly Poison
  [2818]  = { name = "Deadly Poison",     duration = 12 },
  [2819]  = { name = "Deadly Poison",     duration = 12 },
  [11353] = { name = "Deadly Poison",     duration = 12 },
  [11354] = { name = "Deadly Poison",     duration = 12 },
  [25349] = { name = "Deadly Poison",     duration = 12 },
  -- Hemorrhage
  [16511] = { name = "Hemorrhage",        duration = 15 },
  -- Blind
  [2094]  = { name = "Blind",             duration = 10 },
  [21060] = { name = "Blind",             duration = 10 },
  -- Sap
  [6770]  = { name = "Sap",               duration = 25 },
  [2070]  = { name = "Sap",               duration = 35 },
  [11297] = { name = "Sap",               duration = 45 },

  -- SHAMAN
  -- Flame Shock
  [8050]  = { name = "Flame Shock",       duration = 12 },
  [8052]  = { name = "Flame Shock",       duration = 12 },
  [8053]  = { name = "Flame Shock",       duration = 12 },
  [10447] = { name = "Flame Shock",       duration = 12 },
  [10448] = { name = "Flame Shock",       duration = 12 },
  [29228] = { name = "Flame Shock",       duration = 12 },

  -- WARRIOR
  -- Rend
  [772]   = { name = "Rend",              duration = 9  },
  [6546]  = { name = "Rend",              duration = 12 },
  [6547]  = { name = "Rend",              duration = 15 },
  [6548]  = { name = "Rend",              duration = 18 },
  [11572] = { name = "Rend",              duration = 21 },
  [11573] = { name = "Rend",              duration = 21 },
  [11574] = { name = "Rend",              duration = 21 },

  -- HUNTER
  -- Serpent Sting
  [1978]  = { name = "Serpent Sting",     duration = 15 },
  [13549] = { name = "Serpent Sting",     duration = 15 },
  [13550] = { name = "Serpent Sting",     duration = 15 },
  [13551] = { name = "Serpent Sting",     duration = 15 },
  [13552] = { name = "Serpent Sting",     duration = 15 },
  [13553] = { name = "Serpent Sting",     duration = 15 },
  [13554] = { name = "Serpent Sting",     duration = 15 },
  [13555] = { name = "Serpent Sting",     duration = 15 },
  [25295] = { name = "Serpent Sting",     duration = 15 },
  -- Scorpid Sting
  [3043]  = { name = "Scorpid Sting",     duration = 20 },
  [14275] = { name = "Scorpid Sting",     duration = 20 },
  [14276] = { name = "Scorpid Sting",     duration = 20 },
  [14277] = { name = "Scorpid Sting",     duration = 20 },
  -- Viper Sting
  [3034]  = { name = "Viper Sting",       duration = 8  },
  [14279] = { name = "Viper Sting",       duration = 8  },
  [14280] = { name = "Viper Sting",       duration = 8  },
  -- Wyvern Sting
  [19386] = { name = "Wyvern Sting",      duration = 12 },
  [24132] = { name = "Wyvern Sting",      duration = 12 },
  [24133] = { name = "Wyvern Sting",      duration = 12 },
  -- Concussive Shot
  [5116]  = { name = "Concussive Shot",   duration = 4  },
  -- Hunter's Mark
  [1130]  = { name = "Hunter's Mark",     duration = 120 },
  [14323] = { name = "Hunter's Mark",     duration = 120 },
  [14324] = { name = "Hunter's Mark",     duration = 120 },
  [14325] = { name = "Hunter's Mark",     duration = 120 },
  -- Wing Clip
  [2974]  = { name = "Wing Clip",         duration = 10 },
  [14267] = { name = "Wing Clip",         duration = 10 },
  [14268] = { name = "Wing Clip",         duration = 10 },
}

function lib:GetDurationBySpellId(spellId, capturedCP)
  local data = spellIdDebuffs[spellId]
  if not data then return nil end
  local duration = data.duration
  if data.combopointAbility then
    local cp = capturedCP or GetComboPoints() or 0
    local cpData = combopointSpells[data.name]
    if cpData then
      duration = cpData.base + cp * cpData.perCP
    end
  end
  return duration, data.name
end

function lib:IsTrackedDebuffSpell(spellId)
  return spellIdDebuffs[spellId] ~= nil
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

-- Returns a list of debuff names that the given spell applies as a passive proc.
-- e.g. GetDebuffsForApplicator("Scorch") -> {"Fire Vulnerability"}
function lib:GetDebuffsForApplicator(spellName)
  if not spellName then return nil end
  local result = nil
  for debuffName, data in pairs(forcedDurations) do
    if data.applicatorSpells then
      for _, applicator in ipairs(data.applicatorSpells) do
        if applicator == spellName then
          result = result or {}
          result[table.getn(result) + 1] = debuffName
          break
        end
      end
    end
  end
  return result
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