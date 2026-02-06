-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libpredict ]]--
-- A pfUI library that detects, receives and sends heal and resurrection predictions.
-- Healing predictions are done by caching the last known "normal" heal value of the
-- spell when last being used. Those chaches are cleared when new talents are detected.
-- The API provides function calls similar to later WoW expansions such as:
--   UnitGetIncomingHeals(unit)
--   UnitHasIncomingResurrection(unit)
--
-- The library is able to receive and send compatible messages to HealComm
-- including resurrections. It has an option to disable the sending of those
-- messages in case HealComm is already active.
--
-- HOT TRACKING INTEGRATION (NEW):
-- With Nampower enabled, HoT tracking now primarily uses libdebuff's AURA_CAST
-- event system for accurate server-side buff/debuff tracking with full rank
-- protection. GetHotDuration() first checks libdebuff, then falls back to the
-- legacy prediction system for backwards compatibility with non-Nampower clients.
-- This provides:
--   - Accurate duration from server (no prediction needed)
--   - Automatic rank protection (lower ranks won't overwrite higher ranks)
--   - Support for multiple casters of same HoT on one target
--   - Zero event overhead (libdebuff already tracks all auras)

-- return instantly when another libpredict is already active
if pfUI.api.libpredict then return end

-- Check if libdebuff integration is available
local libdebuff_available = (pfUI.api.libdebuff and pfUI.api.libdebuff.GetBestAuraCast) and true or false

-- Check if Nampower is available for SPELL_FAILED events
local hasNampower = GetNampowerVersion ~= nil

local senttarget
local heals, ress, events, hots = {}, {}, {}, {}

local PRAYER_OF_HEALING
do -- Prayer of Healing
  local locales = {
    ["deDE"] = "Gebet der Heilung",
    ["enUS"] = "Prayer of Healing",
    ["esES"] = "Rezo de curación",
    ["frFR"] = "Prière de soins",
    ["koKR"] = "치유의 기원",
    ["ruRU"] = "Молитва исцеления",
    ["zhCN"] = "治疗祷言",
  }

  PRAYER_OF_HEALING = locales[GetLocale()] or locales["enUS"]
end

local REJUVENATION
do -- Rejuvenation
  local locales = {
    ["deDE"] = "Verjüngung",
    ["enUS"] = "Rejuvenation",
    ["esES"] = "Rejuvenecimiento",
    ["frFR"] = "Récupération",
    ["koKR"] = "회복",
    ["ruRU"] = "Омоложение",
    ["zhCN"] = "回春术",
  }

  REJUVENATION = locales[GetLocale()] or locales["enUS"]
end

local RENEW
do -- Renew
  local locales = {
    ["deDE"] = "Erneuerung",
    ["enUS"] = "Renew",
    ["esES"] = "Renovar",
    ["frFR"] = "Rénovation",
    ["koKR"] = "소생",
    ["ruRU"] = "Обновление",
    ["zhCN"] = "恢复",
  }

  RENEW = locales[GetLocale()] or locales["enUS"]
end

local REGROWTH
do -- Regrowth
  local locales = {
    ["deDE"] = "Nachwachsen",
    ["enUS"] = "Regrowth",
    ["esES"] = "Recrecimiento",
    ["frFR"] = "Rétablissement",
    ["koKR"] = "재생",
    ["ruRU"] = "Восстановление",
    ["zhCN"] = "愈合",
  }

  REGROWTH = locales[GetLocale()] or locales["enUS"]
end

-- SuperWoW detection
local superwow_active = SpellInfo ~= nil

-- Spell IDs für UNIT_CASTEVENT (SuperWoW)
local SPELL_IDS = {
  -- Rejuvenation (alle Ränge)
  [774] = "Reju", [1058] = "Reju", [1430] = "Reju", [2090] = "Reju", [2091] = "Reju",
  [3627] = "Reju", [8910] = "Reju", [9839] = "Reju", [9840] = "Reju", [9841] = "Reju",
  [25299] = "Reju", [26981] = "Reju", [26982] = "Reju",
  -- Renew (alle Ränge)
  [139] = "Renew", [6074] = "Renew", [6075] = "Renew", [6076] = "Renew", [6077] = "Renew",
  [6078] = "Renew", [10927] = "Renew", [10928] = "Renew", [10929] = "Renew", [25315] = "Renew",
  [25221] = "Renew", [25222] = "Renew",
}

local libpredict = CreateFrame("Frame")
libpredict:RegisterEvent("UNIT_HEALTH")
libpredict:RegisterEvent("CHAT_MSG_ADDON")
libpredict:RegisterEvent("PLAYER_TARGET_CHANGED")
libpredict:RegisterEvent("PLAYER_LOGOUT")

-- SuperWoW: Registriere UNIT_CASTEVENT für akkurate Instant-HoT Detection
if superwow_active then
  libpredict:RegisterEvent("UNIT_CASTEVENT")
end

libpredict:SetScript("OnEvent", function()
  -- Handle shutdown to prevent crash 132
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    return
  end
  
  if event == "CHAT_MSG_ADDON" and (arg1 == "HealComm" or arg1 == "CTRA") then
    -- Ignore own messages (sender receives own addon messages)
    local playerName = UnitName("player")
    if arg4 == playerName then return end
    
    this:ParseChatMessage(arg4, arg2, arg1)
  elseif event == "UNIT_HEALTH" then
    local name = UnitName(arg1)
    if name and ress[name] and not UnitIsDeadOrGhost(arg1) then
      ress[name] = nil  -- Reuse 'name' variable instead of calling UnitName again
    end
  elseif event == "UNIT_CASTEVENT" and superwow_active then
    -- arg1 = casterGUID, arg2 = targetGUID, arg3 = event type, arg4 = spellId, arg5 = castTime
    local casterGUID, targetGUID, castEvent, spellId = arg1, arg2, arg3, arg4
    
    -- Nur eigene Casts (player)
    local _, playerGUID = UnitExists("player")
    if casterGUID ~= playerGUID then return end
    
    -- Nur "CAST" events (erfolgreiche Instant-Casts)
    if castEvent ~= "CAST" then return end
    
    -- Prüfe ob es ein Instant-HoT ist
    local hotType = SPELL_IDS[spellId]
    if not hotType then return end
    
    -- Finde Target Name
    local targetName
    for i = 1, 40 do
      local unit = "raid" .. i
      if UnitExists(unit) then
        local _, guid = UnitExists(unit)
        if guid == targetGUID then
          targetName = UnitName(unit)
          break
        end
      end
    end
    if not targetName then
      for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
          local _, guid = UnitExists(unit)
          if guid == targetGUID then
            targetName = UnitName(unit)
            break
          end
        end
      end
    end
    if not targetName then
      local _, guid = UnitExists("player")
      if guid == targetGUID then
        targetName = UnitName("player")
      end
    end
    if not targetName then
      local _, guid = UnitExists("target")
      if guid == targetGUID then
        targetName = UnitName("target")
      end
    end
    
    if not targetName then return end
    
    -- Duration bestimmen
    local duration
    if hotType == "Reju" then
      duration = rejuvDuration or 12
    elseif hotType == "Renew" then
      duration = renewDuration or 15
    end
    
    -- Extract rank from spellId (if SpellInfo available)
    local rank = nil
    if SpellInfo then
      local _, rankString = SpellInfo(spellId)
      if rankString and rankString ~= "" then
        rank = tonumber((string.gsub(rankString, "Rank ", ""))) or nil
      end
    end
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[UNIT_CASTEVENT]|r spell=%s target=%s dur=%s rank=%s", 
        hotType, targetName, tostring(duration), tostring(rank or "?")))
    end
    
    -- Sende HoT mit Rank
    local playerName = UnitName("player")
    libpredict:Hot(playerName, targetName, hotType, duration, nil, "UNIT_CASTEVENT", rank)
    
    -- Sende HealComm Nachricht mit Rank (backwards compatible: rank optional)
    -- Use "0" for unknown rank instead of empty string to avoid parsing issues
    local rankStr = rank and tostring(rank) or "0"
    if libpredict.sender and libpredict.sender.SendHealCommMsg then
      libpredict.sender:SendHealCommMsg(hotType .. "/" .. targetName .. "/" .. duration .. "/" .. rankStr .. "/")
    else
      -- Fallback: direkt senden (smart channel selection)
      local msg = hotType .. "/" .. targetName .. "/" .. duration .. "/" .. rankStr .. "/"
      if GetNumRaidMembers() > 0 then
        SendAddonMessage("HealComm", msg, "RAID")
      elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("HealComm", msg, "PARTY")
      end
      -- Note: BATTLEGROUND channel not used (no reliable way to detect BG in Vanilla)
    end
  end
end)

libpredict:SetScript("OnUpdate", function()
  -- throttle cleanup - no need to check every frame
  local now = pfUI.uf.now or GetTime()
  if (this.tick or 0) > now then return end
  this.tick = now + pfUI.throttle:Get("libpredict")  -- Default: Normal (10 FPS)

  -- update on timeout events
  for timestamp, targets in pairs(events) do
    if now >= timestamp then
      events[timestamp] = nil
    end
  end
end)

function libpredict:ParseComm(sender, msg)
  local msgtype, target, heal, time, rank

  if msg == "HealStop" or msg == "GrpHealstop" then
    msgtype = "Stop"
    -- DEBUG: Log when HealStop received
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[libpredict RX]|r HealStop from " .. tostring(sender))
    end
  elseif msg == "Resurrection/stop/" then
    msgtype = "RessStop"
  elseif msg then
    local msgobj = {strsplit("/", msg)}

    if msgobj and msgobj[1] and msgobj[2] then
      -- legacy healcomm object
      if msgobj[1] == "GrpHealdelay" or msgobj[1] == "Healdelay" then
        msgtype, time = "Delay", msgobj[2]
      end

      if msgobj[1] and msgobj[1] == "Resurrection" and msgobj[2] then
        msgtype, target = "Ress", msgobj[2]
      end

      if msgobj[1] == "Heal" and msgobj[2] then
        msgtype, target, heal, time = "Heal", msgobj[2], msgobj[3], msgobj[4]
      end

      if msgobj[1] == "GrpHeal" and msgobj[2] then
        msgtype, target, heal, time = "Heal", {}, msgobj[2], msgobj[3]
        for i=4,8 do
          if msgobj[i] then table.insert(target, msgobj[i]) end
        end
      end

      if msgobj[1] == "Reju" or msgobj[1] == "Renew" or msgobj[1] == "Regr" then --hots
        msgtype, target, heal, time = "Hot", msgobj[2], msgobj[1], msgobj[3]
        -- NEW: Parse rank (optional, backwards compatible)
        -- Format: "Reju/Target/12/10/" where msgobj[3]=duration, msgobj[4]=rank
        -- "0" = unknown rank (for clients without rank extraction)
        local rankStr = msgobj[4]
        if rankStr and rankStr ~= "" and rankStr ~= "/" and rankStr ~= "0" then
          rank = tonumber(rankStr)
        end
      end
    elseif select and UnitCastingInfo then
      -- latest healcomm
      msgtype = tonumber(string.sub(msg, 1, 3))
      if not msgtype then return end

      if msgtype == 0 then
        msgtype = "Heal"
        heal = tonumber(string.sub(msg, 4, 8))
        target = string.sub(msg,9, -1)

        local starttime = select(5, UnitCastingInfo(sender))
        local endtime = select(6, UnitCastingInfo(sender))
        if not starttime or not endtime then return end
        time = endtime - starttime
      elseif msgtype == 1 then
        msgtype = "Stop"
      elseif msgtype == 2 then
        msgtype = "Heal"
        heal = tonumber(string.sub(msg,4, 8))
        target = {strsplit(":", string.sub(msg,9, -1))}
        local starttime = select(5, UnitCastingInfo(sender))
        local endtime = select(6, UnitCastingInfo(sender))
        if not starttime or not endtime then return end
        time = endtime - starttime
      end
    end
  end

  return msgtype, target, heal, time, rank
end

-- Duplikat-Erkennung für HoT Nachrichten
local recentHots = {}
local DUPLICATE_WINDOW = 0.5  -- Ignoriere gleiche Nachricht innerhalb 0.5s

function libpredict:ParseChatMessage(sender, msg, comm)
  local msgtype, target, heal, time, rank

  if comm == "HealComm" then
    msgtype, target, heal, time, rank = libpredict:ParseComm(sender, msg)
  elseif comm == "CTRA" then
    local _, _, cmd, ctratarget = string.find(msg, "(%a+)%s?([^#]*)")
    if cmd and ctratarget and cmd == "RES" and ctratarget ~= "" and ctratarget ~= UNKNOWN then
      msgtype = "Ress"
      target = ctratarget
    end
  end

  if msgtype == "Stop" and sender then
    libpredict:HealStop(sender)
    return
  elseif ( msg == "RessStop" or msg == "RESNO" ) and sender then
    libpredict:RessStop(sender)
    return
  elseif msgtype == "Delay" and time then
    libpredict:HealDelay(sender, time)
  elseif msgtype == "Heal" and target and heal and time then
    if type(target) == "table" then
      for _, name in pairs(target) do
        libpredict:Heal(sender, name, heal, time)
      end
    else
      libpredict:Heal(sender, target, heal, time)
    end
  elseif msgtype == "Ress" then
    libpredict:Ress(sender, target)
  elseif msgtype == "Hot" then
    -- Duplikat-Check: gleicher sender+target+spell innerhalb DUPLICATE_WINDOW ignorieren
    local now = pfUI.uf.now or GetTime()
    local key = sender .. target .. heal
    if recentHots[key] and (now - recentHots[key]) < DUPLICATE_WINDOW then
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DUPLICATE IGNORED]|r " .. key)
      end
      return
    end
    recentHots[key] = now
    
    -- Cleanup alte Einträge (alle 10s)
    if not libpredict.lastCleanup or (now - libpredict.lastCleanup) > 10 then
      for k, v in pairs(recentHots) do
        if (now - v) > DUPLICATE_WINDOW then
          recentHots[k] = nil
        end
      end
      libpredict.lastCleanup = now
    end
    
    -- Für eigene HoTs: Korrigiere die startTime
    if sender == UnitName("player") then
      local existing = hots[target] and hots[target][heal]
      
      -- Wenn bereits ein aktiver Timer existiert, nicht überschreiben
      if existing and (existing.start + existing.duration) > now then
        return
      end
      
      -- Kompensiere HealComm Verzögerung
      local delay = (heal == "Regr") and 0.3 or 0
      local correctedStart = now - delay
      
      libpredict:Hot(sender, target, heal, time, correctedStart, "ParseComm-Self", rank)
      return
    end
    libpredict:Hot(sender, target, heal, time, nil, "ParseComm", rank)
  end
end

function libpredict:AddEvent(time, target)
  events[time] = events[time] or {}
  table.insert(events[time], target)
end

function libpredict:Heal(sender, target, amount, duration)
  if not sender or not target or not amount or not duration then
    return
  end

  local now = pfUI.uf.now or GetTime()
  local timeout = duration/1000 + now
  heals[target] = heals[target] or {}
  heals[target][sender] = { amount, timeout }
  libpredict:AddEvent(timeout, target)
end

-- Debug flag
libpredict.debug = false

function libpredict:Hot(sender, target, spell, duration, startTime, source, rank)
  hots[target] = hots[target] or {}
  hots[target][spell] = hots[target][spell] or {}

  -- Korrigiere Regrowth Duration (Server gibt 21 zurück, sollte aber 20 sein)
  if spell == "Regr" then
    duration = 20
  end
  
  -- Sicherstellen dass duration eine Zahl ist
  duration = tonumber(duration) or duration
  
  -- Rank protection: Don't overwrite higher rank HoT with lower rank
  local existing = hots[target][spell]
  if existing and existing.rank and rank then
    local existingRank = tonumber(existing.rank) or 0
    local newRank = tonumber(rank) or 0
    
    local now = pfUI.uf.now or GetTime()
    local existingTimeleft = (existing.start + existing.duration) - now
    
    -- If existing HoT is still active and has higher rank, don't overwrite
    if existingTimeleft > 0 and newRank > 0 and newRank < existingRank then
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[Hot RANK BLOCK]|r %s Rank %d cannot overwrite Rank %d on %s", 
          spell, newRank, existingRank, target))
      end
      return -- Don't overwrite!
    end
  end

  local now = pfUI.uf.now or GetTime()
  hots[target][spell].duration = duration
  hots[target][spell].start = startTime or now
  hots[target][spell].rank = rank -- Store rank for protection
  
  -- Debug
  if libpredict.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[Hot]|r src=" .. (source or "?") .. 
      " | sender=" .. (sender or "nil") ..
      " | target=" .. (target or "nil") .. 
      " | spell=" .. (spell or "nil") ..
      " | dur=" .. tostring(duration) .. " (" .. type(duration) .. ")" ..
      " | rank=" .. tostring(rank or "?"))
  end

  -- update aura events of relevant unitframes
  if pfUI and pfUI.uf and pfUI.uf.frames then
    for _, frame in pairs(pfUI.uf.frames) do
      if frame.namecache == target then
        frame.update_aura = true
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00-> Frame update triggered for " .. (frame:GetName() or "?") .. "|r")
        end
      end
    end
  end
end

function libpredict:HealStop(sender)
  for ttarget, t in pairs(heals) do
    for tsender in pairs(heals[ttarget]) do
      if sender == tsender then
        heals[ttarget][tsender] = nil
      end
    end
  end
end

function libpredict:HealDelay(sender, delay)
  local delay = delay/1000
  for target, t in pairs(heals) do
    for tsender, amount in pairs(heals[target]) do
      if sender == tsender then
        amount[2] = amount[2] + delay
        libpredict:AddEvent(amount[2], target)
      end
    end
  end
end

function libpredict:Ress(sender, target)
  ress[target] = ress[target] or {}
  ress[target][sender] = true
end

function libpredict:RessStop(sender)
  for ttarget, t in pairs(ress) do
    for tsender in pairs(ress[ttarget]) do
      if sender == tsender then
        ress[ttarget][tsender] = nil
      end
    end
  end
end

function libpredict:UnitGetIncomingHeals(unit)
  if not unit then return 0 end
  local name = UnitName(unit)
  if not name then return 0 end
  if UnitIsDeadOrGhost(unit) then return 0 end

  local sumheal = 0
  if not heals[name] then
    return sumheal
  else
    local now = pfUI.uf.now or GetTime()
    for sender, amount in pairs(heals[name]) do
      if amount[2] <= now then
        heals[name][sender] = nil
      else
        sumheal = sumheal + amount[1]
      end
    end
  end
  return sumheal
end

function libpredict:UnitHasIncomingResurrection(unit)
  if not unit then return nil end
  local name = UnitName(unit)
  if not name then return nil end

  if not ress[name] then
    return nil
  else
    for sender, val in pairs(ress[name]) do
      if val == true then
        return val
      end
    end
  end
  return nil
end

local spell_queue = { "DUMMY", "DUMMYRank 9", "TARGET" }
local realm = GetRealmName()
local player = UnitName("player")
local cache, gear_string = {}, ""
local resetcache = CreateFrame("Frame")
local rejuvDuration, renewDuration = 12, 15 --default durations
local hotsetbonus = libtipscan:GetScanner("hotsetbonus")
resetcache:RegisterEvent("PLAYER_ENTERING_WORLD")
resetcache:RegisterEvent("LEARNED_SPELL_IN_TAB")
resetcache:RegisterEvent("CHARACTER_POINTS_CHANGED")
resetcache:RegisterEvent("UNIT_INVENTORY_CHANGED")
resetcache:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- load and initialize previous caches of spell amounts
    pfUI_cache["prediction"] = pfUI_cache["prediction"] or {}
    pfUI_cache["prediction"][realm] = pfUI_cache["prediction"][realm] or {}
    pfUI_cache["prediction"][realm][player] = pfUI_cache["prediction"][realm][player] or {}
    pfUI_cache["prediction"][realm][player]["heals"] = pfUI_cache["prediction"][realm][player]["heals"] or {}
    cache = pfUI_cache["prediction"][realm][player]["heals"]
  end

  if event == "UNIT_INVENTORY_CHANGED" or "PLAYER_ENTERING_WORLD" then
    -- skip non-player events
    if arg1 and arg1 ~= "player" then return end

    local gear = ""
    for id = 1, 18 do
      gear = gear .. (GetInventoryItemLink("player",id) or "")
    end

    -- abort when inventory didn't change
    if gear == gear_string then return end
    gear_string = gear

    local setBonusCounter
    setBonusCounter = 0
    for i=1,10 do --there is no need to check slots above 10
      hotsetbonus:SetInventoryItem("player", i)
      if hotsetbonus:Find(L["healduration"]["Rejuvenation"]) then setBonusCounter = setBonusCounter + 1 end
    end
    rejuvDuration = setBonusCounter == 8 and 15 or 12
    setBonusCounter = 0
    for i =1,10 do
      hotsetbonus:SetInventoryItem("player", i)
      if hotsetbonus:Find(L["healduration"]["Renew"]) then setBonusCounter = setBonusCounter + 1 end
    end
    renewDuration = setBonusCounter == 5 and 18 or 15
  end

  -- flag all cached heals for renewal
  for k in pairs(cache) do
    if type(cache[k]) == "number" or type(cache[k]) == "string" then
      -- migrate old data
      local oldval = cache[k]
      cache[k] = { [1] = oldval }
    end

    -- flag for reset
    cache[k][2] = true
  end
end)

local function UpdateCache(spell, heal, crit)
  local heal = heal and tonumber(heal)
  if not spell or not heal then return end

  if not cache[spell] or cache[spell][2] then
    -- skills or equipment changed, save whatever is detected
    cache[spell] = cache[spell] or {}
    cache[spell][1] = crit and heal*2/3 or heal
    cache[spell][2] = crit
  elseif not crit and cache[spell][1] < heal then
    -- safe the best heal we can get
    cache[spell][1] = heal
    cache[spell][2] = nil
  end
end

-- Cooldown für lokale Instant-HoT Hooks (verhindert Spam bei Click-to-Cast)
local instantHotCooldown = {}
local INSTANT_HOT_COOLDOWN = 1.0  -- 1 Sekunde Cooldown (GCD ist 1.5s)

-- Pending HoTs Queue - wird nach Delay verifiziert
local pendingHots = {}

-- Hilfsfunktion: Prüfe ob Buff auf Unit vorhanden ist
local function UnitHasBuff(unit, buffName)
  for i = 1, 32 do
    local name = UnitBuff(unit, i)
    if not name then break end
    if name == buffName then return true end
  end
  return false
end

-- Gather Data by User Actions
hooksecurefunc("CastSpell", function(id, bookType)
  if not libpredict.sender.enabled then return end
  local effect, rank = libspell.GetSpellInfo(id, bookType)
  if not effect then return end
  spell_queue[1] = effect
  spell_queue[2] = effect.. ( rank or "" )
  spell_queue[3] = UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")
  
  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end
  
  -- Instant-HoTs: Mit SuperWoW nutzen wir UNIT_CASTEVENT (akkurater)
  -- Ohne SuperWoW: Fallback auf Hook-Methode mit Cooldown
  if superwow_active then return end
  
  if effect == REJUVENATION then
    local target = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. target
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpell REJU INSTANT]|r target=%s rank=%s (Fallback)", target, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, target, "Reju", rejuvDuration, nil, "CastSpell-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..target.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local target = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. target
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpell RENEW INSTANT]|r target=%s rank=%s (Fallback)", target, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, target, "Renew", renewDuration, nil, "CastSpell-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..target.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

hooksecurefunc("CastSpellByName", function(effect, target)
  if not libpredict.sender.enabled then return end
  local effect, rank = libspell.GetSpellInfo(effect)
  if not effect then return end
  local mouseover = pfUI and pfUI.uf and pfUI.uf.mouseover and pfUI.uf.mouseover.unit
  mouseover = mouseover and UnitCanAssist("player", mouseover) and UnitName(mouseover)

  local default = UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")

  target = target and type(target) == "string" and UnitName(target) or target
  target = target and target == true and UnitName("player") or target
  target = target and target == 1 and UnitName("player") or target

  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end

  -- Nur spell_queue überschreiben wenn kein Cast läuft
  -- (verhindert dass Instant-Spam während Regrowth-Cast die Queue zerstört)
  if not libpredict.sender.current_cast then
    spell_queue[1] = effect
    spell_queue[2] = effect.. ( rank or "" )
    spell_queue[3] = target or mouseover or default
  end
  
  -- Instant-HoTs: Mit SuperWoW nutzen wir UNIT_CASTEVENT (akkurater)
  -- Ohne SuperWoW: Fallback auf Hook-Methode mit Cooldown
  if superwow_active then return end
  
  if effect == REJUVENATION then
    local hotTarget = target or mouseover or default
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpellByName REJU INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Reju", rejuvDuration, nil, "CastSpellByName-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..hotTarget.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local hotTarget = target or mouseover or default
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpellByName RENEW INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Renew", renewDuration, nil, "CastSpellByName-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..hotTarget.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

local scanner = libtipscan:GetScanner("prediction")
hooksecurefunc("UseAction", function(slot, target, selfcast)
  if not libpredict.sender.enabled then return end
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  scanner:SetAction(slot)
  local effect, rank = scanner:Line(1)
  if not effect then return end
  spell_queue[1] = effect
  spell_queue[2] = effect.. ( rank or "" )
  spell_queue[3] = selfcast and UnitName("player") or UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")
  
  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end
  
  -- Instant-HoTs: Mit SuperWoW nutzen wir UNIT_CASTEVENT (akkurater)
  -- Ohne SuperWoW: Fallback auf Hook-Methode mit Cooldown
  if superwow_active then return end
  
  if effect == REJUVENATION then
    local hotTarget = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[UseAction REJU INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Reju", rejuvDuration, nil, "UseAction-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..hotTarget.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local hotTarget = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[UseAction RENEW INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Renew", renewDuration, nil, "UseAction-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..hotTarget.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

libpredict.sender = CreateFrame("Frame", "pfPredictionSender", UIParent)
libpredict.sender.enabled = true
libpredict.sender.SendHealCommMsg = function(self, msg)
  -- Smart channel selection: Only send to relevant channel to avoid duplicates
  if GetNumRaidMembers() > 0 then
    -- In raid: Only send to RAID (includes all raid members)
    SendAddonMessage("HealComm", msg, "RAID")
  elseif GetNumPartyMembers() > 0 then
    -- In party: Only send to PARTY
    SendAddonMessage("HealComm", msg, "PARTY")
  end
  -- Note: BATTLEGROUND channel not used (no reliable way to detect BG in Vanilla)
  -- BG groups are handled by RAID channel
end
libpredict.sender.SendResCommMsg = function(self, msg)
  -- Smart channel selection: Only send to relevant channel to avoid duplicates
  if GetNumRaidMembers() > 0 then
    -- In raid: Only send to RAID (includes all raid members)
    SendAddonMessage("CTRA", msg, "RAID")
  elseif GetNumPartyMembers() > 0 then
    -- In party: Only send to PARTY
    SendAddonMessage("CTRA", msg, "PARTY")
  end
  -- Note: BATTLEGROUND channel not used (no reliable way to detect BG in Vanilla)
  -- BG groups are handled by RAID channel
end

libpredict.sender:SetScript("OnUpdate", function()
  -- trigger delayed regrowth timers
  local now = pfUI.uf.now or GetTime()
  if this.regrowth_timer and now > this.regrowth_timer then
    local target = this.regrowth_target or player
    local duration = 20
    local startTime = this.regrowth_start
    local rank = this.regrowth_rank

    libpredict:Hot(player, target, "Regr", duration, startTime, "OnUpdate", rank)
    local rankStr = rank and tostring(rank) or "0"
    libpredict.sender:SendHealCommMsg("Regr/"..target.."/"..duration.."/"..rankStr.."/")
    
    -- Übernehme nächsten Regrowth falls vorhanden
    this.regrowth_target = this.regrowth_target_next
    this.regrowth_start = this.regrowth_start_next
    this.regrowth_rank = this.regrowth_rank_next
    this.regrowth_target_next = nil
    this.regrowth_start_next = nil
    this.regrowth_rank_next = nil
    this.regrowth_timer = nil
  end
end)

libpredict.sender:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
libpredict.sender:RegisterEvent("SPELLCAST_START")
libpredict.sender:RegisterEvent("SPELLCAST_STOP")
libpredict.sender:RegisterEvent("SPELLCAST_FAILED")
libpredict.sender:RegisterEvent("SPELLCAST_INTERRUPTED")
libpredict.sender:RegisterEvent("SPELLCAST_DELAYED")

-- Nampower: Register SPELL_FAILED_SELF for more reliable cast fail detection
if hasNampower then
  libpredict.sender:RegisterEvent("SPELL_FAILED_SELF")
  if libpredict.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[libpredict]|r Nampower detected - SPELL_FAILED_SELF registered")
  end
else
  if libpredict.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libpredict]|r Nampower NOT detected - using vanilla SPELLCAST_FAILED only")
  end
end

-- force cache updates
libpredict.sender:RegisterEvent("UNIT_INVENTORY_CHANGED")
libpredict.sender:RegisterEvent("SKILL_LINES_CHANGED")

libpredict.sender:SetScript("OnEvent", function()
  if event == "CHAT_MSG_SPELL_SELF_BUFF" then -- vanilla
    local spell, _, heal = cmatch(arg1, HEALEDSELFOTHER) -- "Your %s heals %s for %d."
    if spell and heal then
      if spell == spell_queue[1] then UpdateCache(spell_queue[2], heal) end
      return
    end

    local spell, heal = cmatch(arg1, HEALEDSELFSELF) -- "Your %s heals you for %d."
    if spell and heal then
      if spell == spell_queue[1] then UpdateCache(spell_queue[2], heal) end
      return
    end

    local spell, heal = cmatch(arg1, HEALEDCRITSELFOTHER) -- "Your %s critically heals %s for %d."
    if spell and heal then
      if spell == spell_queue[1] then UpdateCache(spell_queue[2], heal, true) end
      return
    end

    local spell, _, heal = cmatch(arg1, HEALEDCRITSELFSELF) -- "Your %s critically heals you for %d."
    if spell and heal then
      if spell == spell_queue[1] then UpdateCache(spell_queue[2], heal, true) end
      return
    end
  elseif event == "SPELLCAST_START" then
    local spell, time = arg1, arg2
    
    -- Speichere aktuellen Cast (wird nicht von Instant-Hooks überschrieben)
    this.current_cast = spell
    this.current_cast_target = senttarget or spell_queue[3]

    if spell_queue[1] == spell and cache[spell_queue[2]] then
      local sender = player
      local target = senttarget or spell_queue[3]
      local amount = cache[spell_queue[2]][1]
      local casttime = time

      if spell == REGROWTH then
        -- Extract rank from spell_queue[2] which contains "spell + rank"
        local fullSpell = spell_queue[2]
        local rankStr = fullSpell and string.match(fullSpell, "Rank (%d+)") or nil
        local rankNum = rankStr and tonumber(rankStr) or nil
        
        if this.regrowth_timer then
          this.regrowth_target_next = spell_queue[3]
          this.regrowth_rank_next = rankNum
        else
          this.regrowth_target = spell_queue[3]
          this.regrowth_rank = rankNum
        end
      end

      if spell == PRAYER_OF_HEALING then
        target = sender

        for i=1,4 do
          if CheckInteractDistance("party"..i, 4) then
            libpredict:Heal(player, UnitName("party"..i), amount, casttime)
            libpredict.sender:SendHealCommMsg("Heal/" .. UnitName("party"..i) .. "/" .. amount .. "/" .. casttime .. "/")
            libpredict.sender.healing = true
          end
        end
      end

      libpredict:Heal(player, target, amount, casttime)
      libpredict.sender:SendHealCommMsg("Heal/" .. target .. "/" .. amount .. "/" .. casttime .. "/")
      libpredict.sender.healing = true

    elseif spell_queue[1] == spell and L["resurrections"][spell] then
      local target = senttarget or spell_queue[3]
      libpredict:Ress(player, target)
      libpredict.sender:SendHealCommMsg("Resurrection/" .. target .. "/start/")
      libpredict.sender:SendResCommMsg("RES " .. target)
      libpredict.sender.resurrecting = true
    end
  elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
    if libpredict.sender.healing then
      libpredict:HealStop(player)
      
      -- DEBUG: Log when sending HealStop
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[libpredict TX]|r Sending HealStop (via " .. event .. ") to group")
      end
      libpredict.sender:SendHealCommMsg("HealStop")
      libpredict.sender.healing = nil
    elseif libpredict.sender.resurrecting then
      local target = senttarget or spell_queue[3]
      libpredict:RessStop(player)
      libpredict.sender:SendHealCommMsg("Resurrection/stop/")
      libpredict.sender:SendResCommMsg("RESNO " .. target)
      libpredict.sender.resurrecting = nil
    end
    -- Nutze current_cast für Regrowth cleanup
    if this.current_cast == REGROWTH then
      this.regrowth_timer = nil
      this.regrowth_start = nil
      this.regrowth_target_next = nil
      this.regrowth_start_next = nil
    end
    -- Cleanup
    this.current_cast = nil
    this.current_cast_target = nil
  elseif event == "SPELL_FAILED_SELF" then
    -- Nampower SPELL_FAILED_SELF: More reliable than vanilla SPELLCAST_FAILED
    -- Same cleanup as SPELLCAST_FAILED
    if libpredict.sender.healing then
      libpredict:HealStop(player)
      
      -- DEBUG: Log when sending HealStop
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[libpredict TX]|r Sending HealStop to group (SPELL_FAILED_SELF)")
      end
      libpredict.sender:SendHealCommMsg("HealStop")
      libpredict.sender.healing = nil
    elseif libpredict.sender.resurrecting then
      local target = senttarget or spell_queue[3]
      libpredict:RessStop(player)
      libpredict.sender:SendHealCommMsg("Resurrection/stop/")
      libpredict.sender:SendResCommMsg("RESNO " .. target)
      libpredict.sender.resurrecting = nil
    end
    -- Regrowth cleanup
    if this.current_cast == REGROWTH then
      this.regrowth_timer = nil
      this.regrowth_start = nil
      this.regrowth_target_next = nil
      this.regrowth_start_next = nil
    end
    -- Cleanup
    this.current_cast = nil
    this.current_cast_target = nil
  elseif event == "SPELLCAST_DELAYED" then
    if libpredict.sender.healing then
      libpredict:HealDelay(player, arg1)
      libpredict.sender:SendHealCommMsg("Healdelay/" .. arg1 .. "/")
    end
  elseif event == "SPELLCAST_STOP" then
    libpredict:HealStop(player)
    
    -- Nur Regrowth wird hier verarbeitet (hat Cast-Zeit)
    -- Nutze this.current_cast (wird bei SPELLCAST_START gesetzt, nicht von Instant-Hooks überschrieben)
    if this.current_cast == REGROWTH then
      local now = pfUI.uf.now or GetTime()
      if this.regrowth_timer then
        -- Bereits ein Regrowth aktiv, speichere für den nächsten
        this.regrowth_start_next = now
      else
        this.regrowth_start = now
      end
      this.regrowth_timer = now + 0.1
    end
    
    -- Cleanup
    this.current_cast = nil
    this.current_cast_target = nil
  end
end)

function libpredict:GetHotDuration(unit, spell)
  if unit == UNKNOWNOBJECT or unit == UNKOWNBEING then return end
  
  -- NEW: Try libdebuff first (Nampower AURA_CAST events)
  if pfUI.api.libdebuff and pfUI.api.libdebuff.GetBestAuraCast then
    local _, guid = UnitExists(unit)  -- FIX: Get GUID, not exists boolean!
    if guid then
      -- Get the best (highest rank) aura cast for this spell
      local spellName = spell
      
      -- Map short spell codes to full names
      if spell == "Reju" then
        spellName = REJUVENATION
      elseif spell == "Regr" then
        spellName = REGROWTH
      elseif spell == "Renew" then
        spellName = RENEW
      end
      
      local start, duration, timeleft, rank, casterGuid = pfUI.api.libdebuff:GetBestAuraCast(guid, spellName)
      
      if start and duration and timeleft then
        -- SUCCESS: libdebuff has accurate server-side data!
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[GetHotDuration]|r %s on %s via libdebuff: dur=%.1fs timeleft=%.1fs rank=%d", 
            spell, unit, duration, timeleft, rank or 0))
        end
        return start, duration, timeleft
      end
    end
  end
  
  -- FALLBACK: Use old prediction system (for non-Nampower clients or no AURA_CAST data)
  local start, duration, timeleft
  local now = pfUI.uf.now or GetTime()
  
  local unitName = UnitName(unit)
  local unitdata = hots[unitName]
  
  if unitdata and unitdata[spell] then
    local spellData = unitdata[spell]
    if spellData.start and spellData.duration then
      local endTime = spellData.start + spellData.duration
      if endTime > now - 1 then
        start = spellData.start
        duration = spellData.duration
        timeleft = endTime - now
        
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[GetHotDuration]|r %s on %s via prediction: dur=%.1fs timeleft=%.1fs", 
            spell, unit, duration, timeleft))
        end
      end
    end
  end

  return start, duration, timeleft
end

-- Debug command: /hotdebug - Show HoT tracking status
_G.SLASH_HOTDEBUG1 = "/hotdebug"
_G.SlashCmdList.HOTDEBUG = function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[HoT Tracking Debug]|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  
  -- Check libdebuff availability
  local libdebuff_now = (pfUI.api.libdebuff and pfUI.api.libdebuff.GetBestAuraCast) and true or false
  
  if libdebuff_now then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PRIMARY]|r libdebuff integration: ACTIVE")
    DEFAULT_CHAT_FRAME:AddMessage("  Using AURA_CAST events for server-side tracking")
    DEFAULT_CHAT_FRAME:AddMessage("  Rank protection: ENABLED")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[PRIMARY]|r libdebuff integration: NOT AVAILABLE")
    DEFAULT_CHAT_FRAME:AddMessage("  Reason: Nampower not enabled or libdebuff outdated")
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[FALLBACK]|r Legacy prediction system: ACTIVE")
  DEFAULT_CHAT_FRAME:AddMessage("  Using UNIT_CASTEVENT + HealComm messages")
  
  -- Show active HoTs in tracking
  local hotCount = 0
  for target, spells in pairs(hots) do
    for spell, data in pairs(spells) do
      hotCount = hotCount + 1
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[TRACKED]|r %d HoTs in legacy system", hotCount))
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  DEFAULT_CHAT_FRAME:AddMessage("Tip: /libpredict.debug = true for verbose logging")
end

pfUI.api.libpredict = libpredict
