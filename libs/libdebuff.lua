-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff ]]--
-- A pfUI library that detects and saves all ongoing debuffs of players, NPCs and enemies.
-- The functions UnitDebuff is exposed to the modules which allows to query debuffs like you
-- would on later expansions.
--
--  libdebuff:UnitDebuff(unit, id)
--    Returns debuff informations on the given effect of the specified unit.
--    name, rank, texture, stacks, dtype, duration, timeleft

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

-- Speichert die Ranks der zuletzt gecasteten Spells (bleibt länger als pending)
local lastCastRanks = {}

-- Speichert Spells die gefailed sind (miss/dodge/parry/etc.) für 1 Sekunde
local lastFailedSpells = {}

-- Combo Points Tracking
local currentComboPoints = 0
local lastSpentComboPoints = 0
local lastSpentTime = 0

-- Prüft ob ein Spell kürzlich gefailed ist (öffentliche Funktion für andere Module)
function libdebuff:DidSpellFail(spell)
  if not spell then return false end
  local data = lastFailedSpells[spell]
  if data and (GetTime() - data.time) < 1 then
    return true
  end
  return false
end

-- Gibt die zuletzt ausgegebenen Combo Points zurück (innerhalb 1 Sekunde)
local function GetStoredComboPoints()
  if lastSpentComboPoints > 0 and (GetTime() - lastSpentTime) < 1 then
    return lastSpentComboPoints
  end
  return 0
end

-- Shared Debuffs: Diese werden von allen Spielern geteilt (nur einer kann drauf sein)
-- Timer darf von anderen Spielern aktualisiert werden
local sharedDebuffs = {
  -- Warrior
  ["Sunder Armor"] = true,
  ["Demoralizing Shout"] = true,
  ["Thunder Clap"] = true,
  
  -- Rogue
  ["Expose Armor"] = true,
  
  -- Druid
  ["Faerie Fire"] = true,
  ["Faerie Fire (Feral)"] = true,
  
  -- Hunter
  ["Hunter's Mark"] = true,
  
  -- Warlock Curses (nur eine pro Typ kann auf Target sein)
  ["Curse of Weakness"] = true,
  ["Curse of Recklessness"] = true,
  ["Curse of the Elements"] = true,
  ["Curse of Shadow"] = true,
  ["Curse of Tongues"] = true,
  ["Curse of Exhaustion"] = true,
  -- NICHT: Curse of Agony, Curse of Doom (jeder Warlock hat seinen eigenen!)
  
  -- Priest
  ["Shadow Weaving"] = true,
  
  -- Mage
  ["Winter's Chill"] = true,
  
  -- Paladin Judgements
  ["Judgement of Wisdom"] = true,
  ["Judgement of Light"] = true,
  ["Judgement of the Crusader"] = true,
  ["Judgement of Justice"] = true,
}

function libdebuff:GetDuration(effect, rank)
  if L["debuffs"][effect] then
    local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
    local rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
    local duration = L["debuffs"][effect][rank]

    if effect == L["dyndebuffs"]["Rupture"] then
      -- Rupture: +2 sec per combo point
      local cp = GetComboPoints() or 0
      if cp == 0 then cp = GetStoredComboPoints() end
      duration = duration + cp*2
    elseif effect == L["dyndebuffs"]["Kidney Shot"] then
      -- Kidney Shot: +1 sec per combo point
      local cp = GetComboPoints() or 0
      if cp == 0 then cp = GetStoredComboPoints() end
      duration = duration + cp*1
    elseif effect == "Rip" or effect == L["dyndebuffs"]["Rip"] then
      -- Rip (Turtle WoW): 10s base + 2s per additional combo point
      -- Base in table is 8, so: 8 + CP*2 = 10/12/14/16/18
      local cp = GetComboPoints() or 0
      if cp == 0 then cp = GetStoredComboPoints() end
      duration = 8 + cp*2
    elseif effect == L["dyndebuffs"]["Demoralizing Shout"] then
      -- Booming Voice: 10% per talent
      local _,_,_,_,count = GetTalentInfo(2,1)
      if count and count > 0 then duration = duration + ( duration / 100 * (count*10)) end
    elseif effect == L["dyndebuffs"]["Shadow Word: Pain"] then
      -- Improved Shadow Word: Pain: +3s per talent
      local _,_,_,_,count = GetTalentInfo(3,4)
      if count and count > 0 then duration = duration + count * 3 end
    elseif effect == L["dyndebuffs"]["Frostbolt"] then
      -- Permafrost: +1s per talent
      local _,_,_,_,count = GetTalentInfo(3,7)
      if count and count > 0 then duration = duration + count end
    elseif effect == L["dyndebuffs"]["Gouge"] then
      -- Improved Gouge: +.5s per talent
      local _,_,_,_,count = GetTalentInfo(3,3)
      if count and count > 0 then duration = duration + (count*.5) end
    end
    return duration
  else
    return 0
  end
end

function libdebuff:UpdateDuration(unit, unitlevel, effect, duration)
  if not unit or not effect or not duration then return end
  unitlevel = unitlevel or 0

  if libdebuff.objects[unit] and libdebuff.objects[unit][unitlevel] and libdebuff.objects[unit][unitlevel][effect] then
    libdebuff.objects[unit][unitlevel][effect].duration = duration
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
  if not pfUI.uf or not pfUI.uf.target then return end
  pfUI.uf:RefreshUnit(pfUI.uf.target, "aura")
end

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

function libdebuff:RevertLastAction()
  if lastspell and lastspell.effect then
  end
  lastspell.start = lastspell.start_old
  lastspell.start_old = nil
  libdebuff:UpdateUnits()
end

function libdebuff:AddEffect(unit, unitlevel, effect, duration, caster, rank)
  -- WORKAROUND: Wenn rank nil ist und wir einen eigenen Cast haben, hole rank aus lastCastRanks
  if not rank and caster == "player" and effect then
    -- Erst aus pending versuchen
    if libdebuff.pending[3] == effect and libdebuff.pending[6] then
      rank = libdebuff.pending[6]
    -- Dann aus lastCastRanks (bleibt länger)
    elseif lastCastRanks[effect] and (GetTime() - lastCastRanks[effect].time) < 2 then
      rank = lastCastRanks[effect].rank
    end
  end
  
  if not unit or not effect then return end
  
  -- SCHUTZ: Wenn der Spell gerade gefailed ist (miss/dodge/parry/etc.), nicht anwenden
  -- Nur für eigene Spells prüfen, nicht für andere Spieler
  if caster == "player" and libdebuff:DidSpellFail(effect) then
    return  -- Spell hat nicht getroffen, keinen Timer setzen
  end
  
  unitlevel = unitlevel or 0
  if not libdebuff.objects[unit] then libdebuff.objects[unit] = {} end
  if not libdebuff.objects[unit][unitlevel] then libdebuff.objects[unit][unitlevel] = {} end
  if not libdebuff.objects[unit][unitlevel][effect] then libdebuff.objects[unit][unitlevel][effect] = {} end

  local existing = libdebuff.objects[unit][unitlevel][effect]
  local now = GetTime()
  
  -- Wenn kein Caster übergeben wurde, behalte den existierenden (wichtig für Refresh-Mechaniken wie Ferocious Bite)
  if not caster and existing.caster then
    caster = existing.caster
  end
  
  -- Wenn kein Rank übergeben wurde, behalte den existierenden
  if not rank and existing.rank then
    rank = existing.rank
  end
  
  -- Prüfe ob ein existierender Debuff noch aktiv ist
  local existingIsActive = existing.start and existing.duration and (existing.start + existing.duration) > now
  
  -- SCHUTZ: Wenn MEIN Debuff aktiv ist, darf ein anderer Spieler ihn NICHT überschreiben
  -- AUSNAHME: Shared Debuffs (Sunder Armor, Curses, etc.) dürfen aktualisiert werden
  if existingIsActive and existing.caster == "player" and caster ~= "player" then
    if not sharedDebuffs[effect] then
      return  -- Blockiere das Update
    end
  end
  
  -- Rank-Prüfung wenn beide vom Player sind und beide Ranks bekannt sind
  if existingIsActive and existing.rank and rank and existing.caster == "player" and caster == "player" then
    -- Niedrigerer Rank darf höheren NICHT überschreiben
    if rank < existing.rank then
      return  -- Blockiere das Update
    end
    -- Gleicher oder höherer Rank darf überschreiben (Timer erneuern)
  end

  -- save current effect as lastspell
  lastspell = existing

  existing.effect = effect
  existing.start_old = existing.start
  existing.start = now
  existing.duration = duration or libdebuff:GetDuration(effect)
  existing.caster = caster
  existing.rank = rank

  libdebuff:UpdateUnits()
end

-- scan for debuff application
libdebuff:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
libdebuff:RegisterEvent("PLAYER_TARGET_CHANGED")
libdebuff:RegisterEvent("SPELLCAST_STOP")
libdebuff:RegisterEvent("UNIT_AURA")

-- register combo points tracking for Druids and Rogues
if class == "DRUID" or class == "ROGUE" then
  libdebuff:RegisterEvent("PLAYER_COMBO_POINTS")
end

-- register seal handler
if class == "PALADIN" then
  libdebuff:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
end

-- Remove Pending
libdebuff.rp = { SPELLIMMUNESELFOTHER, IMMUNEDAMAGECLASSSELFOTHER,
  SPELLMISSSELFOTHER, SPELLRESISTSELFOTHER, SPELLEVADEDSELFOTHER,
  SPELLDODGEDSELFOTHER, SPELLDEFLECTEDSELFOTHER, SPELLREFLECTSELFOTHER,
  SPELLPARRIEDSELFOTHER, SPELLLOGABSORBSELFOTHER, SPELLFAILCASTSELF }

libdebuff.objects = {}
libdebuff.pending = {}

-- Gather Data by Events
libdebuff:SetScript("OnEvent", function()
  -- paladin seal refresh
  if event == "CHAT_MSG_COMBAT_SELF_HITS" then
    local hit = cmatch(arg1, COMBATHITSELFOTHER)
    local crit = cmatch(arg1, COMBATHITCRITSELFOTHER)
    if hit or crit then
      for seal in L["judgements"] do
        local name = UnitName("target")
        local level = UnitLevel("target")
        if name and libdebuff.objects[name] then
          if level and libdebuff.objects[name][level] and libdebuff.objects[name][level][seal] then
            libdebuff:AddEffect(name, level, seal)
          elseif libdebuff.objects[name][0] and libdebuff.objects[name][0][seal] then
            libdebuff:AddEffect(name, 0, seal)
          end
        end
      end
    end

  -- Add Combat Log
  elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
    local unit, effect = cmatch(arg1, AURAADDEDOTHERHARMFUL)
    if unit and effect then
      local unitlevel = UnitName("target") == unit and UnitLevel("target") or 0
      if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
        libdebuff:AddEffect(unit, unitlevel, effect, nil, nil, nil)  -- Explizit nil für rank
      end
    end

  -- Add Missing Buffs by Iteration
  elseif ( event == "UNIT_AURA" and arg1 == "target" ) or event == "PLAYER_TARGET_CHANGED" then
    for i=1, 16 do
      local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff("target", i)

      -- abort when no further debuff was found
      if not texture then return end

      if texture and effect and effect ~= "" then
        -- don't overwrite existing timers
        local unitlevel = UnitLevel("target") or 0
        local unit = UnitName("target")
        if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
          libdebuff:AddEffect(unit, unitlevel, effect, nil, nil, nil)  -- Explizit nil für rank
        end
      end
    end

  -- Update Pending Spells und tracke failed spells
  elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    -- Prüfe ob ein Spell gefailed ist und speichere ihn
    for _, msg in pairs(libdebuff.rp) do
      local effect = cmatch(arg1, msg)
      if effect then
        -- Speichere den failed spell für 1 Sekunde
        lastFailedSpells[effect] = { time = GetTime() }
        
        -- Bestehende Logik: Remove pending spell
        if libdebuff.pending[3] == effect then
          libdebuff:RemovePending()
          return
        elseif lastspell and lastspell.start_old and lastspell.effect == effect then
          -- late removal of debuffs (e.g hunter arrows as they hit late)
          libdebuff:RevertLastAction()
          return
        end
      end
    end
  elseif event == "SPELLCAST_STOP" then
    libdebuff:PersistPending()
  elseif event == "PLAYER_COMBO_POINTS" then
    -- Track combo points for Druid AND Rogue (both use CP-based abilities)
    if class ~= "DRUID" and class ~= "ROGUE" then return end
    local current = GetComboPoints("player", "target") or 0
    if current < currentComboPoints then
      -- Combo points were spent!
      lastSpentComboPoints = currentComboPoints
      lastSpentTime = GetTime()
    end
    currentComboPoints = current
  end
end)

-- Gather Data by User Actions
hooksecurefunc("CastSpell", function(id, bookType)
  local rawEffect, rank = libspell.GetSpellInfo(id, bookType)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  local rankNum = 0
  if rank then
    local _, _, num = string.find(rank, "(%d+)")
    rankNum = num and tonumber(num) or 0
  end
  
  -- Speichere rank für später (bleibt 2 Sekunden)
  if rawEffect and rankNum > 0 then
    lastCastRanks[rawEffect] = { rank = rankNum, time = GetTime() }
  end
  
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player", rankNum)
end)

hooksecurefunc("CastSpellByName", function(effect, target)
  local rawEffect, rank = libspell.GetSpellInfo(effect)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  local rankNum = 0
  if rank then
    local _, _, num = string.find(rank, "(%d+)")
    rankNum = num and tonumber(num) or 0
  end
  
  -- Speichere rank für später (bleibt 2 Sekunden)
  if rawEffect and rankNum > 0 then
    lastCastRanks[rawEffect] = { rank = rankNum, time = GetTime() }
  end
  
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player", rankNum)
end)

hooksecurefunc("UseAction", function(slot, target, button)
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  scanner:SetAction(slot)
  local rawEffect, rank = scanner:Line(1)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  local rankNum = 0
  if rank then
    local _, _, num = string.find(rank, "(%d+)")
    rankNum = num and tonumber(num) or 0
  end
  
  -- Speichere rank für später (bleibt 2 Sekunden)
  if rawEffect and rankNum > 0 then
    lastCastRanks[rawEffect] = { rank = rankNum, time = GetTime() }
  end
  
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player", rankNum)
end)

function libdebuff:UnitDebuff(unit, id)
  local unitname = UnitName(unit)
  local unitlevel = UnitLevel(unit)
  local texture, stacks, dtype = UnitDebuff(unit, id)
  local duration, timeleft = nil, -1
  local rank = nil -- no backport
  local caster = nil -- experimental
  local effect

  if texture then
    scanner:SetUnitDebuff(unit, id)
    effect = scanner:Line(1) or ""
  end

  -- read level based debuff table
  local data = libdebuff.objects[unitname] and libdebuff.objects[unitname][unitlevel]
  data = data or libdebuff.objects[unitname] and libdebuff.objects[unitname][0]

  if data and data[effect] then
    if data[effect].duration and data[effect].start and data[effect].duration + data[effect].start > GetTime() then
      -- read valid debuff data
      duration = data[effect].duration
      timeleft = duration + data[effect].start - GetTime()
      caster = data[effect].caster
    else
      -- clean up invalid values
      data[effect] = nil
    end
  end

  return effect, rank, texture, stacks, dtype, duration, timeleft, caster
end

local cache = {}
function libdebuff:UnitOwnDebuff(unit, id)
  -- clean cache
  for k, v in pairs(cache) do cache[k] = nil end

  -- detect own debuffs
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

-- add libdebuff to pfUI API
pfUI.api.libdebuff = libdebuff