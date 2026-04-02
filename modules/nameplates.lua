pfUI:RegisterModule("nameplates", "vanilla", function ()
  -- disable original castbars
  pcall(SetCVar, "ShowVKeyCastbar", 0)


  -- Local function references for performance
  local pfGetCastInfo = pfGetCastInfo  -- provided by libcast for vanilla
  local pfGetChannelInfo = pfGetChannelInfo  -- provided by libcast for vanilla
  local GetTime = GetTime
  local UnitExists = UnitExists
  local UnitName = UnitName
  local UnitClass = UnitClass
  local UnitLevel = UnitLevel
  local UnitIsPlayer = UnitIsPlayer
  local UnitIsDead = UnitIsDead
  local UnitAffectingCombat = UnitAffectingCombat
  local UnitIsUnit = UnitIsUnit
  local UnitCanAssist = UnitCanAssist
  local UnitHealth = UnitHealth
  local UnitHealthMax = UnitHealthMax
  local UnitMana = UnitMana
  local UnitManaMax = UnitManaMax
  local pairs = pairs
  local tonumber = tonumber
  local strlower = strlower
  local strfind = strfind
  local strlen = strlen
  local floor = floor
  local ceil = ceil
  local abs = abs
  local mathmod = math.mod

  local unitcolors = {
    ["ENEMY_NPC"] = { .9, .2, .3, .8 },
    ["NEUTRAL_NPC"] = { 1, 1, .3, .8 },
    ["FRIENDLY_NPC"] = { .6, 1, 0, .8 },
    ["ENEMY_PLAYER"] = { .9, .2, .3, .8 },
    ["FRIENDLY_PLAYER"] = { .2, .6, 1, .8 }
  }

  local offtanks = {}

  local combatstate = {
    -- gets overwritten by user config
    ["OFFTANK"]  = { r = .7, g = .4, b = .2, a = 1 },
    ["NOTHREAT"] = { r = .7, g = .7, b = .2, a = 1 },
    ["THREAT"]   = { r = .7, g = .2, b = .2, a = 1 },
    ["CASTING"]  = { r = .7, g = .2, b = .7, a = 1 },
    ["STUN"]     = { r = .2, g = .7, b = .7, a = 1 },
    ["NONE"]     = { r = .2, g = .2, b = .2, a = 1 },
  }

  local elitestrings = {
    ["elite"] = "+",
    ["rareelite"] = "R+",
    ["rare"] = "R",
    ["boss"] = "B"
  }

  -- catch all nameplates
  local childs = {}
  local regions, plate
  local initialized = 0

  -- Friendly zone nameplate disable state
  local savedHostileState = nil
  local savedFriendlyState = nil
  local inFriendlyZone = false
  local parentcount = 0
  local platecount = 0
  local registry = {}

  -- ============================================================================
  -- OPTIMIZATION: GUID-based registries for O(1) lookups
  -- ============================================================================
  local guidRegistry = {}   -- guid -> plate (for direct event routing)
  local raidGuidCache = {}  -- guid -> name (rebuilt on RAID_ROSTER_UPDATE/PARTY_MEMBERS_CHANGED)

  -- Helper function to safely access libdebuff cast data
  local function GetCastInfo(guid)
    return pfUI.libdebuff_casts and pfUI.libdebuff_casts[guid]
  end

  local debuffCache = {}    -- guid -> { [spellID] = { start, duration } }
  local threatMemory = {}   -- guid -> true if mob had player targeted

  -- PERF (Nampower): Reusable per-plate debuff display buffer — avoids GC churn
  -- from per-call table creation. Module-level, cleared before each use.
  local debuffDisplayBuf = {}
  for i = 1, 16 do debuffDisplayBuf[i] = {} end

  -- PERF (Nampower): Module-level IterDebuffs callback — avoids closure allocation per call
  local _iterDebuffCount = 0
  local function iterDebuffCallback(auraSlot, spellId, effect, texture, stacks, dtype, duration, timeleft)
    if not texture or string.find(texture, "QuestionMark") then return end
    _iterDebuffCount = _iterDebuffCount + 1
    if _iterDebuffCount > 16 then return end
    local b = debuffDisplayBuf[_iterDebuffCount]
    b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
  end

  -- PERF: Track visible plate count for adaptive throttling
  local visiblePlateCount = 0
  local lastVisibleCheck = 0

  -- wipe polyfill
  local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

  -- Player GUID for filtering
  local PlayerGUID = GetUnitGUID("player")

  -- ============================================================================
  -- OPTIMIZATION: Config caching
  -- ============================================================================
  local cfg = {}
  local function CacheConfig()
    cfg.showcastbar = C.nameplates["showcastbar"] == "1"
    cfg.targetcastbar = C.nameplates["targetcastbar"] == "1"
    cfg.notargalpha = tonumber(C.nameplates.notargalpha) or 0.5
    if cfg.notargalpha > 1 then cfg.notargalpha = cfg.notargalpha / 100 end
    -- Clamp to 0.99 so non-target plates never reach 1.0 (used for target detection)
    if cfg.notargalpha > 0.99 then cfg.notargalpha = 0.99 end
    cfg.namefightcolor = C.nameplates.namefightcolor == "1"
    cfg.spellname = C.nameplates.spellname == "1"
    cfg.showhp = C.nameplates.showhp == "1"
    cfg.showdebuffs = C.nameplates["showdebuffs"] == "1"
    cfg.showdebuffs_hostile = C.nameplates["showdebuffs_hostile"] == "1"
    cfg.showdebuffs_friendly = C.nameplates["showdebuffs_friendly"] == "1"
    cfg.targetzoom = C.nameplates.targetzoom == "1"
    cfg.zoomval = (tonumber(C.nameplates.targetzoomval) or 0.4) + 1
    cfg.zoominstant = C.nameplates.targetzoominstant == "1"
    cfg.width = tonumber(C.nameplates.width) or 120
    cfg.heighthealth = tonumber(C.nameplates.heighthealth) or 8
    cfg.targetglow = C.nameplates.targetglow == "1"
    cfg.targethighlight = C.nameplates.targethighlight == "1"
    cfg.outcombatstate = C.nameplates.outcombatstate == "1"
    cfg.barcombatstate = C.nameplates.barcombatstate == "1"
    cfg.ccombatcasting = C.nameplates.ccombatcasting == "1"
    cfg.ccombatthreat = C.nameplates.ccombatthreat == "1"
    cfg.ccombatnothreat = C.nameplates.ccombatnothreat == "1"
    cfg.ccombatstun = C.nameplates.ccombatstun == "1"
    cfg.ccombatofftank = C.nameplates.ccombatofftank == "1"
    cfg.use_unitfonts = C.nameplates.use_unitfonts == "1"
    cfg.font_size = cfg.use_unitfonts and C.global.font_unit_size or C.global.font_size
    cfg.hptextformat = C.nameplates.hptextformat
    cfg.debufftimers = C.nameplates.debufftimers == "1"
    cfg.debuffanim = tonumber(C.nameplates.debuffanim) or 0
    cfg.debufftext = tonumber(C.nameplates.debufftext) or 1

  end

  local function RebuildOfftanks()
    offtanks = {}
    for k, v in pairs({strsplit("#", C.nameplates.combatofftanks)}) do
      if v ~= "" then offtanks[string.lower(v)] = true end
    end
  end
  RebuildOfftanks()

  -- ============================================================================
  -- OPTIMIZATION: Frame state cache
  -- ============================================================================
  local frameState = {
    now = 0,
    hasTarget = false,
    targetGuid = nil,
    hasMouseover = false,
  }

  -- cache default border color
  local er, eg, eb, ea = GetStringColor(pfUI_config.appearance.border.color)

  -- ============================================================================
  -- PERF (Nampower): Bitwise flag helper (Lua 5.0 compatible)
  -- ============================================================================
  local function HasFlag(flags, flag)
    return math.mod(math.floor(flags / flag), 2) ~= 0
  end

  local UNIT_FLAG_IN_COMBAT = 524288  -- 0x00080000
  local NULL_GUID           = "0x0000000000000000"

  -- ============================================================================
  -- PERF (Nampower): raidGuidCache for O(1) offtank target-name lookup
  -- ============================================================================
  local function RebuildRaidGuidCache()
    for k in pairs(raidGuidCache) do raidGuidCache[k] = nil end
    for i = 1, GetNumRaidMembers() do
      local g = GetUnitGUID("raid"..i)
      if g then raidGuidCache[g] = UnitName("raid"..i) end
    end
    for i = 1, GetNumPartyMembers() do
      local g = GetUnitGUID("party"..i)
      if g then raidGuidCache[g] = UnitName("party"..i) end
    end
    local pg = GetUnitGUID("player")
    if pg then raidGuidCache[pg] = UnitName("player") end
  end

  -- ============================================================================
  -- PERF (Nampower): combatColorCache throttles GetCombatStateColor to 0.2s/guid.
  -- Uses GetUnitField(flags) instead of UnitAffectingCombat(guid) and
  -- raidGuidCache instead of UnitName(target) for O(1) offtank detection.
  -- ============================================================================
  local combatColorCache = {}  -- guid -> { color, expires }

  local function GetCombatStateColor(guid)
    if not UnitAffectingCombat("player") then return false end
    if UnitCanAssist("player", guid) then return false end

    -- PERF: 0.2s throttle per guid
    local now = frameState.now
    local cached = combatColorCache[guid]
    if cached and cached.expires > now then
      return cached.color
    end

    -- PERF (Nampower): GetUnitField flags instead of UnitAffectingCombat(guid)
    local flags = GetUnitField and GetUnitField(guid, "flags")
    if not flags then return false end
    if not HasFlag(flags, UNIT_FLAG_IN_COMBAT) then return false end

    local mobTargetGuid = GetUnitField and GetUnitField(guid, "target")
    local hasTarget = mobTargetGuid and mobTargetGuid ~= NULL_GUID

    local target = guid.."target"
    local color = false

    local castInfo = GetCastInfo(guid)
    local isCasting = castInfo and castInfo.endTime and now < castInfo.endTime
    local targetingPlayer = hasTarget and UnitIsUnit(target, "player")

    if targetingPlayer then
      threatMemory[guid] = true
    elseif hasTarget and not isCasting then
      threatMemory[guid] = nil
    end

    -- PERF (Nampower): O(1) GUID lookup via raidGuidCache
    local targetName = hasTarget and (UnitName(target) or raidGuidCache[mobTargetGuid])

    if cfg.ccombatcasting and isCasting then
      color = combatstate.CASTING
    elseif cfg.ccombatthreat and (targetingPlayer or threatMemory[guid]) then
      color = combatstate.THREAT
    elseif cfg.ccombatofftank and targetName and offtanks[strlower(targetName)] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatofftank and pfUI.uf and pfUI.uf.raid and targetName and pfUI.uf.raid.tankrole[targetName] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatnothreat and hasTarget then
      color = combatstate.NOTHREAT
    elseif cfg.ccombatstun and not hasTarget then
      color = combatstate.STUN
    end

    combatColorCache[guid] = combatColorCache[guid] or {}
    combatColorCache[guid].color = color
    combatColorCache[guid].expires = now + 0.2

    return color
  end

  local function DoNothing()
    return
  end

  local function wipe(table)
    if type(table) ~= "table" then return end
    for k in pairs(table) do table[k] = nil end
  end

  local function IsNamePlate(frame)
    if frame:GetObjectType() ~= NAMEPLATE_FRAMETYPE then return nil end
    regions = plate:GetRegions()
    if not regions then return nil end
    if not regions.GetObjectType then return nil end
    if not regions.GetTexture then return nil end
    if regions:GetObjectType() ~= "Texture" then return nil end
    return regions:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" or nil
  end

  local function DisableObject(object)
    if not object then return end
    if not object.GetObjectType then return end
    local otype = object:GetObjectType()
    if otype == "Texture" then
      object:SetTexture("")
      object:SetTexCoord(0, 0, 0, 0)
    elseif otype == "FontString" then
      object:SetWidth(0.001)
    elseif otype == "StatusBar" then
      object:SetStatusBarTexture("")
    end
  end

  local function TotemPlate(name)
    if C.nameplates.totemicons == "1" then
      for totem, icon in pairs(L["totems"]) do
        if string.find(name, totem) then return icon end
      end
    end
  end

  local function HidePlate(unittype, name, fullhp, target)
    if C.nameplates.fullhealth == "1" and not fullhp then return nil end
    if C.nameplates.target == "1" and target then return nil end
    if C.nameplates.enemynpc == "1" and unittype == "ENEMY_NPC" then return true
    elseif C.nameplates.enemyplayer == "1" and unittype == "ENEMY_PLAYER" then return true
    elseif C.nameplates.neutralnpc == "1" and unittype == "NEUTRAL_NPC" then return true
    elseif C.nameplates.friendlynpc == "1" and unittype == "FRIENDLY_NPC" then return true
    elseif C.nameplates.friendlyplayer == "1" and unittype == "FRIENDLY_PLAYER" then return true
    elseif C.nameplates.critters == "1" and unittype == "NEUTRAL_NPC" then
      for i, critter in pairs(L["critters"]) do
        if string.lower(name) == string.lower(critter) then return true end
      end
    elseif C.nameplates.totems == "1" then
      for totem in pairs(L["totems"]) do
        if string.find(name, totem) then return true end
      end
    end
    return nil
  end

  local function abbrevname(t)
    return string.sub(t,1,1)..". "
  end

  local function GetNameString(name)
    local abbrev = pfUI_config.unitframes.abbrevname == "1" or nil
    local size = 20
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "^(%S+) ", abbrevname)
    end
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "(%S+) ", abbrevname)
    end
    return name
  end

  local function GetUnitType(red, green, blue)
    if red > .9 and green < .2 and blue < .2 then return "ENEMY_NPC"
    elseif red > .9 and green > .9 and blue < .2 then return "NEUTRAL_NPC"
    elseif red < .2 and green < .2 and blue > 0.9 then return "FRIENDLY_PLAYER"
    elseif red < .2 and green > .9 and blue < .2 then return "FRIENDLY_NPC"
    end
  end

  local filter, list, cache
  local function DebuffFilterPopulate()
    filter = C.nameplates["debuffs"]["filter"]
    if filter == "none" then return end
    list = C.nameplates["debuffs"][filter]
    cache = {}
    for _, val in pairs({strsplit("#", list)}) do
      cache[strlower(val)] = true
    end
  end

  local function DebuffFilter(effect)
    if filter == "none" then return true end
    if not cache then DebuffFilterPopulate() end
    if filter == "blacklist" and cache[strlower(effect)] then return nil
    elseif filter == "blacklist" then return true
    elseif filter == "whitelist" and cache[strlower(effect)] then return true
    elseif filter == "whitelist" then return nil
    end
  end

  local function PlateCacheDebuffs(self, unitstr, verify)
    if not self.debuffcache then self.debuffcache = {} end
    if not libdebuff then return end
    local now = GetTime()
    for id = 1, 16 do
      if self.debuffcache[id] then self.debuffcache[id].empty = true end
    end
    -- PERF (Nampower): Use IterDebuffs if available, else fall back to slot loop
    if unitstr and libdebuff.IterDebuffs and GetUnitGUID then
      local id = 0
      libdebuff:IterDebuffs(unitstr, function(auraSlot, spellId, effect, texture, stacks, dtype, duration, timeleft)
        if not effect or not texture then return end
        id = id + 1
        if id > 16 then return end
        local stop = (timeleft and timeleft > 0) and (now + timeleft) or nil
        local start = stop and (stop - (duration or 0)) or now
        self.debuffcache[id] = self.debuffcache[id] or {}
        self.debuffcache[id].effect = effect
        self.debuffcache[id].texture = texture
        self.debuffcache[id].stacks = stacks
        self.debuffcache[id].duration = duration or 0
        self.debuffcache[id].start = start
        self.debuffcache[id].stop = stop
        self.debuffcache[id].empty = nil
      end)
    else
      for id = 1, 16 do
        local effect, _, texture, stacks, dtype, duration, timeleft
        effect, _, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff(unitstr, id)
        if effect and texture then
          local stop = (timeleft and timeleft > 0) and (now + timeleft) or nil
          local start = stop and (stop - (duration or 0)) or now
          self.debuffcache[id] = self.debuffcache[id] or {}
          self.debuffcache[id].effect = effect
          self.debuffcache[id].texture = texture
          self.debuffcache[id].stacks = stacks
          self.debuffcache[id].duration = duration or 0
          self.debuffcache[id].start = start
          self.debuffcache[id].stop = stop
          self.debuffcache[id].empty = nil
        end
      end
    end
    self.verify = verify
  end

  local function PlateUnitDebuff(self, id)
    if not self.debuffcache then return end
    if not self.debuffcache[id] then return end
    if not self.debuffcache[id].stop then return end
    if self.debuffcache[id].empty then return end
    if self.debuffcache[id].stop < GetTime() then return end
    local c = self.debuffcache[id]
    return c.effect, c.rank, c.texture, c.stacks, c.dtype, c.duration, (c.stop - GetTime())
  end

  local function CreateDebuffIcon(plate, index)
    plate.debuffs[index] = CreateFrame("Frame", plate.platename.."Debuff"..index, plate)
    plate.debuffs[index]:Hide()
    plate.debuffs[index]:SetFrameLevel(4)

    plate.debuffs[index].icon = plate.debuffs[index]:CreateTexture(nil, "BACKGROUND")
    plate.debuffs[index].icon:SetTexture(.3,1,.8,1)
    plate.debuffs[index].icon:SetAllPoints(plate.debuffs[index])

    plate.debuffs[index].stacks = plate.debuffs[index]:CreateFontString(nil, "OVERLAY")
    plate.debuffs[index].stacks:SetAllPoints(plate.debuffs[index])
    plate.debuffs[index].stacks:SetJustifyH("RIGHT")
    plate.debuffs[index].stacks:SetJustifyV("BOTTOM")
    plate.debuffs[index].stacks:SetTextColor(1,1,0)

    -- PERF: Use lightweight fake cooldown frame when animation disabled
    if pfUI.client <= 11200 and cfg.debuffanim ~= 1 then
      plate.debuffs[index].cd = CreateFrame("Frame", plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index])
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
      plate.debuffs[index].cd:SetScript("OnUpdate", CooldownFrame_OnUpdateModel)
      plate.debuffs[index].cd.AdvanceTime = DoNothing
      plate.debuffs[index].cd.SetSequence = DoNothing
      plate.debuffs[index].cd.SetSequenceTime = DoNothing
    else
      plate.debuffs[index].cd = CreateFrame(COOLDOWN_FRAME_TYPE, plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index], "CooldownFrameTemplate")
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
    end

    plate.debuffs[index].cd.pfCooldownStyleAnimation = cfg.debuffanim
    plate.debuffs[index].cd.pfCooldownStyleText = cfg.debufftext
    plate.debuffs[index].cd.pfCooldownType = "ALL"
  end

  local function UpdateDebuffConfig(nameplate, i)
    if not nameplate.debuffs[i] then return end
    local width = tonumber(C.nameplates.width)
    local debuffsize = tonumber(C.nameplates.debuffsize)
    local debuffoffset = tonumber(C.nameplates.debuffoffset)
    local limit = floor(width / debuffsize)
    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle
    local aligna, alignb, offs, space
    if C.nameplates.debuffs["position"] == "BOTTOM" then
      aligna, alignb, offs, space = "TOPLEFT", "BOTTOMLEFT", -debuffoffset, -1
    else
      aligna, alignb, offs, space = "BOTTOMLEFT", "TOPLEFT", debuffoffset, 1
    end
    nameplate.debuffs[i].stacks:SetFont(font, font_size, font_style)
    nameplate.debuffs[i]:ClearAllPoints()
    if i == 1 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.health, alignb, 0, offs)
    elseif i <= limit then
      nameplate.debuffs[i]:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", 1, 0)
    elseif i > limit and limit > 0 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.debuffs[i-limit], alignb, 0, space)
    end
    nameplate.debuffs[i]:SetWidth(tonumber(C.nameplates.debuffsize))
    nameplate.debuffs[i]:SetHeight(tonumber(C.nameplates.debuffsize))
    if nameplate.debuffs[i].cd then
      nameplate.debuffs[i].cd.pfCooldownStyleText = tonumber(C.nameplates.debufftext) or 1
      nameplate.debuffs[i].cd.pfCooldownStyleAnimation = tonumber(C.nameplates.debuffanim) or 0
      if pfUI.client > 11200 then
        nameplate.debuffs[i].cd:SetScale(debuffsize / 32)
      end
    end
  end

  -- create nameplate core
  local nameplates = CreateFrame("Frame", "pfNameplates", UIParent)
  nameplates:RegisterEvent("PLAYER_ENTERING_WORLD")
  nameplates:RegisterEvent("PLAYER_TARGET_CHANGED")
  nameplates:RegisterEvent("PLAYER_LOGOUT")
  nameplates:RegisterEvent("UNIT_COMBO_POINTS")
  nameplates:RegisterEvent("PLAYER_COMBO_POINTS")
  nameplates:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  nameplates:RegisterEvent("RAID_ROSTER_UPDATE")
  nameplates:RegisterEvent("PARTY_MEMBERS_CHANGED")
  -- PERF (Nampower): UNIT_FLAGS_GUID fires instantly on flag changes (stun, combat)
  if GetUnitField then
    nameplates:RegisterEvent("UNIT_FLAGS_GUID")
  end

  -- Callback from libdebuff when auras change (GUID-based, event-driven)
  nameplates.OnAuraUpdate = function(self, guid)
    if not guid then return end
    local plate = guidRegistry[guid]
    if plate and plate.nameplate then
      plate.nameplate.auraUpdate = true
      return
    end
    -- Fallback: plate visible but GUID not yet registered
    for _, frame in pairs(registry) do
      if frame.nameplate then
        local frameGuid = frame:GetName(1)
        if frameGuid == guid then
          frame.nameplate.cachedGuid = frameGuid
          guidRegistry[guid] = frame
          frame.nameplate.auraUpdate = true
          return
        end
      end
    end
  end

  -- Hook into libdebuff timer signal (fires when slotTimers written or cleared)
  pfUI.libdebuff_on_unit_updated = pfUI.libdebuff_on_unit_updated or {}
  table.insert(pfUI.libdebuff_on_unit_updated, function(guid)
    local plate = guidRegistry[guid]
    if plate and plate.nameplate then
      plate.nameplate.auraUpdate = true
    end
  end)

  nameplates:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
      if nameplates.mouselook then
        nameplates.mouselook:SetScript("OnUpdate", nil)
      end
      return

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
      if event == "PLAYER_ENTERING_WORLD" then
        _, PlayerGUID = UnitExists("player")
        CacheConfig()
        this:SetGameVariables()
        RebuildRaidGuidCache()
      end

      local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
      local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"

      if disableHostile or disableFriendly then
        local pvpType = GetZonePVPInfo()
        local nowFriendly = (pvpType == "friendly")

        if nowFriendly and not inFriendlyZone then
          inFriendlyZone = true
          savedHostileState = C.nameplates["showhostile"]
          savedFriendlyState = C.nameplates["showfriendly"]
          if disableHostile then _G.NAMEPLATES_ON = nil; HideNameplates() end
          if disableFriendly then _G.FRIENDNAMEPLATES_ON = nil; HideFriendNameplates() end
        elseif not nowFriendly and inFriendlyZone then
          inFriendlyZone = false
          if savedHostileState == "1" then _G.NAMEPLATES_ON = true; ShowNameplates() end
          if savedFriendlyState == "1" then _G.FRIENDNAMEPLATES_ON = true; ShowFriendNameplates() end
          savedHostileState = nil
          savedFriendlyState = nil
        end
      end

    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
      RebuildRaidGuidCache()

    elseif event == "UNIT_FLAGS_GUID" then
      -- PERF (Nampower): Instant flag change notification — bypass throttle
      local plate = guidRegistry[arg1]
      if plate and plate.nameplate then
        plate.nameplate.eventcache = true
      end

    elseif event == "PLAYER_TARGET_CHANGED" then
      local targetGuid = GetUnitGUID("target")
      if targetGuid then
        local plate = guidRegistry[targetGuid]
        if plate and plate.nameplate then
          plate.nameplate.targetUpdate = true
        end
      end
      this.eventcache = true

    elseif event == "PLAYER_COMBO_POINTS" or event == "UNIT_COMBO_POINTS" then
      local targetGuid = GetUnitGUID("target")
      if targetGuid then
        local plate = guidRegistry[targetGuid]
        if plate and plate.nameplate then
          plate.nameplate.comboUpdate = true
        end
      end
    else
      this.eventcache = true
    end
  end)

  nameplates:SetScript("OnUpdate", function()
    local now = GetTime()
    if (this.frameTick or 0) + 0.01 > now then return end
    this.frameTick = now

    frameState.now = now
    frameState.hasTarget, frameState.targetGuid = UnitExists("target")
    frameState.hasMouseover = UnitExists("mouseover")

    if this.eventcache then
      this.eventcache = nil
      for plate in pairs(registry) do plate.eventcache = true end
    end

    if frameState.now - lastVisibleCheck > 0.5 then
      lastVisibleCheck = frameState.now
      local count = 0
      for plate in pairs(registry) do
        if plate:IsVisible() then count = count + 1 end
      end
      visiblePlateCount = count
    end

    local scanThrottle = nameplates.combat and nameplates.combat.inCombat and 0.1 or 0.05
    if (this.tick or 0) <= frameState.now then
      this.tick = frameState.now + scanThrottle
      parentcount = WorldFrame:GetNumChildren()
      if initialized < parentcount then
        for i = table.getn(childs), 1, -1 do childs[i] = nil end
        local tmp = { WorldFrame:GetChildren() }
        for i = 1, parentcount do childs[i] = tmp[i] end
        for i = initialized + 1, parentcount do
          plate = childs[i]
          if IsNamePlate(plate) and not registry[plate] then
            nameplates.OnCreate(plate)
            registry[plate] = plate
          end
        end
        initialized = parentcount
      end
    end

    for plate in pairs(registry) do
      if plate:IsVisible() then
        nameplates.OnUpdate(plate, frameState)
      else
        local guid = plate.nameplate and plate.nameplate.cachedGuid
        if guid then
          if guidRegistry[guid] == plate then guidRegistry[guid] = nil end
          local castInfo = GetCastInfo(guid)
          if castInfo and castInfo.endTime and castInfo.endTime < frameState.now then
            if pfUI.libdebuff_casts then pfUI.libdebuff_casts[guid] = nil end
          end
          if debuffCache[guid] then debuffCache[guid] = nil end
          if threatMemory[guid] then threatMemory[guid] = nil end
          -- PERF (Nampower): Also clean combatColorCache for hidden plates
          if combatColorCache[guid] then combatColorCache[guid] = nil end
        end
      end
    end
  end)

  -- combat tracker
  nameplates.combat = CreateFrame("Frame")
  nameplates.combat:RegisterEvent("PLAYER_ENTER_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LEAVE_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LOGOUT")
  nameplates.combat:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    elseif event == "PLAYER_ENTER_COMBAT" then
      this.inCombat = 1
      if PlayerFrame then PlayerFrame.inCombat = 1 end
    elseif event == "PLAYER_LEAVE_COMBAT" then
      this.inCombat = nil
      if PlayerFrame then PlayerFrame.inCombat = nil end
      for k in pairs(threatMemory) do threatMemory[k] = nil end
      for k in pairs(combatColorCache) do combatColorCache[k] = nil end
    end
  end)

  nameplates.OnCreate = function(frame)
    local parent = frame or this
    platecount = platecount + 1
    platename = "pfNamePlate" .. platecount

    local nameplate = CreateFrame("Button", platename, parent)
    nameplate.platename = platename
    nameplate:EnableMouse(0)
    nameplate.parent = parent
    nameplate.cache = {}
    nameplate.UnitDebuff = PlateUnitDebuff
    nameplate.CacheDebuffs = PlateCacheDebuffs
    nameplate.original = {}

    nameplate.original.healthbar, nameplate.original.castbar = parent:GetChildren()
    DisableObject(nameplate.original.healthbar)
    DisableObject(nameplate.original.castbar)

    for i, object in pairs({parent:GetRegions()}) do
      if NAMEPLATE_OBJECTORDER[i] and NAMEPLATE_OBJECTORDER[i] == "raidicon" then
        nameplate[NAMEPLATE_OBJECTORDER[i]] = object
      elseif NAMEPLATE_OBJECTORDER[i] then
        nameplate.original[NAMEPLATE_OBJECTORDER[i]] = object
        DisableObject(object)
      else
        DisableObject(object)
      end
    end

    HookScript(nameplate.original.healthbar, "OnValueChanged", nameplates.OnValueChanged)

    nameplate:SetScale(UIParent:GetScale())

    nameplate.health = CreateFrame("StatusBar", nil, nameplate)
    nameplate.health:SetFrameLevel(4)
    nameplate.health.text = nameplate.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameplate.health.text:SetAllPoints()
    nameplate.health.text:SetTextColor(1,1,1,1)

    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetPoint("TOP", nameplate, "TOP", 0, 0)

    nameplate.glow = nameplate:CreateTexture(nil, "BACKGROUND")
    nameplate.glow:SetPoint("CENTER", nameplate.health, "CENTER", 0, 0)
    nameplate.glow:SetTexture(pfUI.media["img:dot"])
    nameplate.glow:Hide()

    nameplate.guild = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.guild:SetPoint("BOTTOM", nameplate.health, "BOTTOM", 0, 0)

    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.level:SetPoint("RIGHT", nameplate.health, "LEFT", -3, 0)

    nameplate.raidicon:SetParent(nameplate.health)
    nameplate.raidicon:SetDrawLayer("OVERLAY", 7)
    if C.unitframes.blizzard_raidicons ~= "1" then
      nameplate.raidicon:SetTexture(pfUI.media["img:raidicons"])
    end

    nameplate.totem = CreateFrame("Frame", nil, nameplate)
    nameplate.totem:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    nameplate.totem:SetHeight(32)
    nameplate.totem:SetWidth(32)
    nameplate.totem.icon = nameplate.totem:CreateTexture(nil, "OVERLAY")
    nameplate.totem.icon:SetTexCoord(.078, .92, .079, .937)
    nameplate.totem.icon:SetAllPoints()
    CreateBackdrop(nameplate.totem)

    do -- debuffs
      nameplate.debuffs = {}
      CreateDebuffIcon(nameplate, 1)
    end

    do -- combopoints
      local combopoints = { }
      for i = 1, 5 do
        combopoints[i] = CreateFrame("Frame", nil, nameplate)
        combopoints[i]:Hide()
        combopoints[i]:SetFrameLevel(8)
        combopoints[i].tex = combopoints[i]:CreateTexture("OVERLAY")
        combopoints[i].tex:SetAllPoints()
        if i < 3 then combopoints[i].tex:SetTexture(1, .3, .3, .75)
        elseif i < 4 then combopoints[i].tex:SetTexture(1, 1, .3, .75)
        else combopoints[i].tex:SetTexture(.3, 1, .3, .75)
        end
      end
      nameplate.combopoints = combopoints
    end

    do -- castbar
      local castbar = CreateFrame("StatusBar", nil, nameplate.health)
      castbar:Hide()

      castbar:SetScript("OnShow", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar:SetScript("OnHide", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this:GetParent(), "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar.text = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.text:SetPoint("RIGHT", castbar, "LEFT", -4, 0)
      castbar.text:SetNonSpaceWrap(false)
      castbar.text:SetTextColor(1,1,1,.5)

      castbar.spell = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.spell:SetPoint("CENTER", castbar, "CENTER")
      castbar.spell:SetNonSpaceWrap(false)
      castbar.spell:SetTextColor(1,1,1,1)

      castbar.icon = CreateFrame("Frame", nil, castbar)
      castbar.icon.tex = castbar.icon:CreateTexture(nil, "BORDER")
      castbar.icon.tex:SetAllPoints()

      nameplate.castbar = castbar
    end

    nameplate.tick = GetTime() + mathmod(platecount, 10) * 0.05

    parent.nameplate = nameplate
    HookScript(parent, "OnShow", nameplates.OnShow)
    parent:SetScript("OnUpdate", nil)

    nameplates.OnConfigChange(parent)
    nameplates.OnShow(parent)
  end

  nameplates.OnConfigChange = function(frame)
    local parent = frame
    local nameplate = frame.nameplate

    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle
    local glowr, glowg, glowb, glowa = GetStringColor(C.nameplates.glowcolor)
    local hlr, hlg, hlb, hla = GetStringColor(C.nameplates.highlightcolor)
    local hptexture = pfUI.media[C.nameplates.healthtexture]
    local rawborder, default_border = GetBorderSize("nameplates")
    local plate_width = C.nameplates.width + 50
    local plate_height = C.nameplates.heighthealth + font_size + 5
    local combo_size = 5
    local healthoffset = tonumber(C.nameplates.health.offset)
    local orientation = C.nameplates.verticalhealth == "1" and "VERTICAL" or "HORIZONTAL"

    local c = combatstate
    c.CASTING.r, c.CASTING.g, c.CASTING.b, c.CASTING.a = GetStringColor(C.nameplates.combatcasting)
    c.THREAT.r, c.THREAT.g, c.THREAT.b, c.THREAT.a = GetStringColor(C.nameplates.combatthreat)
    c.NOTHREAT.r, c.NOTHREAT.g, c.NOTHREAT.b, c.NOTHREAT.a = GetStringColor(C.nameplates.combatnothreat)
    c.OFFTANK.r, c.OFFTANK.g, c.OFFTANK.b, c.OFFTANK.a = GetStringColor(C.nameplates.combatofftank)
    c.STUN.r, c.STUN.g, c.STUN.b, c.STUN.a = GetStringColor(C.nameplates.combatstun)

    nameplate:SetWidth(plate_width)
    nameplate:SetHeight(plate_height)
    nameplate:SetPoint("TOP", parent, "TOP", 0, 0)
    nameplate.name:SetFont(font, font_size, font_style)
    nameplate.health:SetOrientation(orientation)
    nameplate.health:SetPoint("TOP", nameplate.name, "BOTTOM", 0, healthoffset)
    nameplate.health:SetStatusBarTexture(hptexture)
    nameplate.health:SetWidth(C.nameplates.width)
    nameplate.health:SetHeight(C.nameplates.heighthealth)
    nameplate.health.hlr, nameplate.health.hlg, nameplate.health.hlb, nameplate.health.hla = hlr, hlg, hlb, hla
    CreateBackdrop(nameplate.health, default_border)
    nameplate.health.text:SetFont(font, font_size - 2, "OUTLINE")
    nameplate.health.text:SetJustifyH(C.nameplates.hptextpos)
    nameplate.guild:SetFont(font, font_size, font_style)
    nameplate.glow:SetWidth(C.nameplates.width + 60)
    nameplate.glow:SetHeight(C.nameplates.heighthealth + 30)
    nameplate.glow:SetVertexColor(glowr, glowg, glowb, glowa)
    nameplate.raidicon:ClearAllPoints()
    nameplate.raidicon:SetPoint("BOTTOM", nameplate.health, "TOP", C.nameplates.raidiconoffx, C.nameplates.raidiconoffy)
    nameplate.level:SetFont(font, font_size, font_style)
    nameplate.raidicon:SetWidth(C.nameplates.raidiconsize)
    nameplate.raidicon:SetHeight(C.nameplates.raidiconsize)

    for i=1,16 do UpdateDebuffConfig(nameplate, i) end

    for i=1,5 do
      nameplate.combopoints[i]:SetWidth(combo_size)
      nameplate.combopoints[i]:SetHeight(combo_size)
      nameplate.combopoints[i]:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", -(i-1)*(combo_size+default_border*3), -default_border*3)
      CreateBackdrop(nameplate.combopoints[i], default_border)
    end

    nameplate.castbar:SetPoint("TOPLEFT", nameplate.health, "BOTTOMLEFT", 0, -default_border*3)
    nameplate.castbar:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", 0, -default_border*3)
    nameplate.castbar:SetHeight(C.nameplates.heightcast)
    local cbtexture = pfUI.media[C.appearance.castbar.texture]
    nameplate.castbar:SetStatusBarTexture(cbtexture or hptexture)
    local cbr, cbg, cbb, cba = strsplit(",", C.appearance.castbar.castbarcolor)
    nameplate.castbar:SetStatusBarColor(cbr, cbg, cbb, cba)
    nameplate.castbar.lastEndTime = nil
    CreateBackdrop(nameplate.castbar, default_border)
    nameplate.castbar.text:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.spell:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.icon:SetPoint("BOTTOMLEFT", nameplate.castbar, "BOTTOMRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetWidth(C.nameplates.heightcast + default_border*3 + C.nameplates.heighthealth)
    CreateBackdrop(nameplate.castbar.icon, default_border)

    nameplates:OnDataChanged(nameplate)
  end

  -- ============================================================================
  -- PERF (ShaguPlates): OnValueChanged only syncs bar values — never triggers
  -- the expensive OnDataChanged. HP text updates happen inside OnDataChanged
  -- when the hp/hpmax cache detects an actual change.
  -- ============================================================================
  nameplates.OnValueChanged = function()
    local plate = this:GetParent().nameplate
    if plate and plate.health then
      plate.health:SetMinMaxValues(plate.original.healthbar:GetMinMaxValues())
      plate.health:SetValue(plate.original.healthbar:GetValue())
    end
  end

  nameplates.OnDataChanged = function(self, plate)
    local visible = plate:IsVisible()
    local hp = plate.original.healthbar:GetValue()
    local hpmin, hpmax = plate.original.healthbar:GetMinMaxValues()
    local name = plate.original.name:GetText()
    local level = plate.original.level:IsShown() and plate.original.level:GetObjectType() == "FontString" and tonumber(plate.original.level:GetText()) or "??"
    local class, ulevel, elite, player, guild = GetUnitData(name, true)

    local levelFromDB = false
    if level == "??" and ulevel and ulevel > 0 then
      level = ulevel
      levelFromDB = true
    end

    local target = plate.istarget
    local mouseover = UnitExists("mouseover") and plate.original.glow:IsShown() or nil
    local unitstr = target and "target" or mouseover and "mouseover" or nil
    local red, green, blue = plate.original.healthbar:GetStatusBarColor()
    local unittype = GetUnitType(red, green, blue) or "ENEMY_NPC"
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size

    if not unitstr then unitstr = plate.parent:GetName(1) end

    if ulevel and ulevel > (level == "??" and -1 or level) then player = nil end

    if plate.cache.name ~= name then
      plate.cache.name = name
      plate.cache.player = nil
      plate.cdCache = nil
    end

    if plate.cache.player then
      player = plate.cache.player == "PLAYER" and true or nil
    elseif unitstr then
      plate.cache.player = UnitIsPlayer(unitstr) and "PLAYER" or "NPC"
    end

    if player and unittype == "ENEMY_NPC" then unittype = "ENEMY_PLAYER" end
    if player and unittype == "FRIENDLY_NPC" then unittype = "FRIENDLY_PLAYER" end
    elite = plate.original.levelicon:IsShown() and not player and "boss" or elite
    if not class then plate.wait_for_scan = true end

    if not visible then return end
    if event == "PLAYER_TARGET_CHANGED" then unitstr = nil end
    if unitstr and not string.find(unitstr, "^0x") and UnitName(unitstr) ~= name then unitstr = nil end

    if (MobHealth3 or MobHealthFrame) and target and name == UnitName('target') and MobHealth_GetTargetCurHP() then
      hp = MobHealth_GetTargetCurHP() > 0 and MobHealth_GetTargetCurHP() or hp
      hpmax = MobHealth_GetTargetMaxHP() > 0 and MobHealth_GetTargetMaxHP() or hpmax
    end

    plate:Show()

    if target and cfg.targetglow then plate.glow:Show() else plate.glow:Hide() end

    if cfg.outcombatstate then
      local guid = plate.parent:GetName(1) or ""
      local color = GetCombatStateColor(guid)
      if not color then color = combatstate.NONE end
      plate.health.backdrop:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
    elseif target and cfg.targethighlight then
      plate.health.backdrop:SetBackdropBorderColor(plate.health.hlr, plate.health.hlg, plate.health.hlb, plate.health.hla)
    elseif C.nameplates.outfriendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outfriendly == "1" and unittype == "FRIENDLY_PLAYER" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outneutral == "1" and strfind(unittype, "NEUTRAL") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outenemy == "1" and strfind(unittype, "ENEMY") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    else
      plate.health.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
    end

    local TotemIcon = TotemPlate(name)
    if TotemIcon then
      plate.totem.icon:SetTexture("Interface\\Icons\\" .. TotemIcon)
      plate.glow:Hide(); plate.level:Hide(); plate.name:Hide(); plate.health:Hide(); plate.guild:Hide()
      plate.totem:Show()
    elseif HidePlate(unittype, name, (hpmax-hp == hpmin), target) then
      plate.level:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
      plate.name:SetParent(plate)
      plate.guild:SetPoint("BOTTOM", plate.name, "BOTTOM", -2, -(font_size + 2))
      plate.level:Show(); plate.name:Show(); plate.health:Hide()
      if guild and C.nameplates.showguildname == "1" then
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, -(font_size / 2) - 2)
      else
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, 0)
      end
      plate.totem:Hide()
    else
      plate.level:SetPoint("RIGHT", plate.health, "LEFT", -5, 0)
      plate.name:SetParent(plate.health)
      plate.guild:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, -(font_size + 4))
      plate.level:Show(); plate.name:Show(); plate.health:Show()
      plate.glow:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
      plate.totem:Hide()
    end

    -- PERF: Cache level string
    local levelStr = (plate.cachedLevelVal == level and plate.cachedElite == elite) and plate.cachedLevelStr
    if not levelStr then
      levelStr = string.format("%s%s", level, (elitestrings[elite] or ""))
      plate.cachedLevelStr = levelStr
      plate.cachedLevelVal = level
      plate.cachedElite = elite
    end
    plate.name:SetText(GetNameString(name))
    plate.level:SetText(levelStr)

    if levelFromDB and type(level) == "number" then
      local color = GetDifficultyColor(level)
      plate.level:SetTextColor(color.r + 0.3, color.g + 0.3, color.b + 0.3, 1)
    end

    if guild and C.nameplates.showguildname == "1" then
      plate.guild:SetText(guild)
      if guild == GetGuildInfo("player") then
        plate.guild:SetTextColor(0, 0.9, 0, 1)
      else
        plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
      end
      plate.guild:Show()
    else
      plate.guild:Hide()
    end

    -- PERF (ShaguPlates): Only update bar + HP text when values actually changed
    if plate.cache.hp ~= hp or plate.cache.hpmax ~= hpmax then
      plate.cache.hp = hp
      plate.cache.hpmax = hpmax
      plate.health:SetMinMaxValues(hpmin, hpmax)
      plate.health:SetValue(hp)

      if cfg.showhp then
        local rhp, rhpmax, estimated
        local guid = plate.parent:GetName(1)
        if guid and GetUnitField then
          local npHp = GetUnitField(guid, "health")
          local npMaxHp = GetUnitField(guid, "maxHealth")
          if npHp and npHp > 0 and npMaxHp and npMaxHp > 0 then
            rhp, rhpmax = npHp, npMaxHp
          end
        end
        if not rhp then
          if hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
            rhp, rhpmax = hp, hpmax
          elseif pfUI.libhealth and pfUI.libhealth.enabled then
            rhp, rhpmax, estimated = pfUI.libhealth:GetUnitHealthByName(name,level,tonumber(hp),tonumber(hpmax))
          end
        end
        -- PERF (ShaguPlates): concat instead of string.format
        local setting = cfg.hptextformat
        local hasdata = (rhp and rhpmax) or estimated or hpmax > 100 or (round(hpmax/100*hp) ~= hp)
        local pct = ceil(hp/hpmax*100)
        if setting == "curperc" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp).." | "..pct.."%")
        elseif setting == "cur" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp))
        elseif setting == "curmax" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp).." - "..Abbreviate(rhpmax))
        elseif setting == "curmaxs" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp).." / "..Abbreviate(rhpmax))
        elseif setting == "curmaxperc" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp).." - "..Abbreviate(rhpmax).." | "..pct.."%")
        elseif setting == "curmaxpercs" and hasdata and rhp then
          plate.health.text:SetText(Abbreviate(rhp).." / "..Abbreviate(rhpmax).." | "..pct.."%")
        elseif setting == "deficit" and rhp then
          plate.health.text:SetText("-"..Abbreviate(rhpmax - rhp)..(hasdata and "" or "%"))
        else
          plate.health.text:SetText(pct.."%")
        end
      end
    end

    local r, g, b, a = unpack(unitcolors[unittype])

    if unittype == "ENEMY_PLAYER" and C.nameplates["enemyclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    elseif unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    end

    if unitstr and UnitIsTapped(unitstr) and not UnitIsTappedByPlayer(unitstr) then
      r, g, b, a = .5, .5, .5, .8
    end

    if cfg.barcombatstate then
      local guid = plate.parent:GetName(1) or ""
      local color = GetCombatStateColor(guid)
      if color then r, g, b, a = color.r, color.g, color.b, color.a end
    end

    if r ~= plate.cache.r or g ~= plate.cache.g or b ~= plate.cache.b then
      plate.health:SetStatusBarColor(r, g, b, a)
      plate.cache.r, plate.cache.g, plate.cache.b = r, g, b
    end

    if r + g + b ~= plate.cache.namecolor and unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassnamec"] == "1" and class and RAID_CLASS_COLORS[class] then
      plate.name:SetTextColor(r, g, b, a)
      plate.cache.namecolor = r + g + b
    end

    for i=1, 5 do plate.combopoints[i]:Hide() end
    if target and C.nameplates.cpdisplay == "1" then
      for i=1, GetComboPoints("target") do plate.combopoints[i]:Show() end
    end

    -- =========================================================================
    -- DEBUFFS
    -- =========================================================================
    local index = 1
    local isFriendly = unittype == "FRIENDLY_PLAYER" or unittype == "FRIENDLY_NPC"
    local showDebuffsForType = cfg.showdebuffs and (isFriendly and cfg.showdebuffs_friendly or (not isFriendly and cfg.showdebuffs_hostile))

    if showDebuffsForType then
      if name ~= plate.cachedVerifyName or level ~= plate.cachedVerifyLevel then
        plate.cachedVerifyName = name
        plate.cachedVerifyLevel = level
        plate.cachedVerify = (name or "")..":"..(level or "")
      end
      local verify = plate.cachedVerify

      if C.nameplates["guessdebuffs"] == "1" and unitstr then
        plate:CacheDebuffs(unitstr, verify)
      end

      -- PERF (Nampower): reusable debuffDisplayBuf + IterDebuffs — no GC churn
      local debuffCount = 0
      for i = 1, 16 do debuffDisplayBuf[i].effect = nil end

      if unitstr and libdebuff and libdebuff.IterDebuffs and GetUnitGUID then
        _iterDebuffCount = 0
        libdebuff:IterDebuffs(unitstr, iterDebuffCallback)
        debuffCount = _iterDebuffCount
      elseif unitstr and libdebuff then
        for i = 1, 16 do
          local effect, rank, texture, stacks, dtype, duration, timeleft
          effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff(unitstr, i)
          if not effect then break end
          if texture then
            debuffCount = debuffCount + 1
            local b = debuffDisplayBuf[debuffCount]
            b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
          end
        end
      elseif plate.verify == verify then
        for i = 1, 16 do
          local effect, rank, texture, stacks, dtype, duration, timeleft = plate:UnitDebuff(i)
          if not effect then break end
          if texture then
            debuffCount = debuffCount + 1
            local b = debuffDisplayBuf[debuffCount]
            b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
          end
        end
      end

      for i = 1, debuffCount do
        local b = debuffDisplayBuf[i]
        if b.effect and b.texture and DebuffFilter(b.effect) then
          if not plate.debuffs[index] then
            CreateDebuffIcon(plate, index)
            UpdateDebuffConfig(plate, index)
          end

          local debuff = plate.debuffs[index]

          -- PERF (ShaguPlates): Only call API when value actually changed
          if debuff.lastTexture ~= b.texture then
            debuff.lastTexture = b.texture
            debuff.icon:SetTexture(b.texture)
            debuff.icon:SetTexCoord(.078, .92, .079, .937)
          end

          if not debuff.isShown then
            debuff.isShown = true
            debuff:Show()
          end

          if debuff.lastStacks ~= b.stacks then
            debuff.lastStacks = b.stacks
            if b.stacks and b.stacks > 1 and C.nameplates.debuffs["showstacks"] == "1" then
              debuff.stacks:SetText(b.stacks)
              debuff.stacks:Show()
            else
              debuff.stacks:Hide()
            end
          end

          if b.duration and b.timeleft and cfg.debufftimers then
            plate.cdCache = plate.cdCache or {}
            local newStart = GetTime() + b.timeleft - b.duration
            -- slot-based cache: invalidates automatically when a different debuff shifts into this slot
            local slotCache = plate.cdCache[index]
            local cachedStart = slotCache and slotCache.effect == b.effect and slotCache.start
            local cd = debuff.cd
            cd:Show()
            if not cachedStart or abs(cachedStart - newStart) > 0.5 then
              if not cd.configCached or cd.cachedAnim ~= cfg.debuffanim or cd.cachedText ~= cfg.debufftext then
                cd.pfCooldownStyleAnimation = cfg.debuffanim
                cd.pfCooldownStyleText = cfg.debufftext
                cd:SetAlpha(cfg.debuffanim == 1 and 1 or 0)
                cd.cachedAnim = cfg.debuffanim
                cd.cachedText = cfg.debufftext
                cd.configCached = true
              end
              CooldownFrame_SetTimer(cd, newStart, b.duration, 1)
              plate.cdCache[index] = plate.cdCache[index] or {}
              plate.cdCache[index].effect = b.effect
              plate.cdCache[index].start = newStart
            end
          end

          index = index + 1
        end
      end
    end

    -- PERF (ShaguPlates): Full state reset on hide
    for i = index, 16 do
      local debuff = plate.debuffs[i]
      if debuff and debuff.isShown then
        debuff.isShown = nil
        debuff.lastTexture = nil
        debuff.lastStacks = nil
        if debuff.cd then
          debuff.cd.cachedStart = nil
          debuff.cd.cachedEffect = nil
        end
        debuff:Hide()
      end
    end
  end

  nameplates.OnShow = function(frame)
    local frame = frame or this
    local nameplate = frame.nameplate

    local guid = frame:GetName(1)
    if guid then
      -- PERF (ShaguPlates): Clean up old GUID mapping when plate is reused
      if nameplate.cachedGuid and nameplate.cachedGuid ~= guid then
        if guidRegistry[nameplate.cachedGuid] == frame then
          guidRegistry[nameplate.cachedGuid] = nil
        end
      end
      nameplate.cachedGuid = guid
      guidRegistry[guid] = frame

      -- PERF (Nampower): Notify libunitscan to cache unit data without requiring mouseover
      if pfUI.api and pfUI.api.libunitscan and pfUI.api.libunitscan.ScanGuid then
        local unitName = nameplate.original.name:GetText()
        local npcFlags = GetUnitField and GetUnitField(guid, "npcFlags") or 0
        pfUI.api.libunitscan.ScanGuid(guid, unitName, npcFlags == 0)
      end
    end

    nameplates:OnDataChanged(nameplate)
  end

  nameplates.OnUpdate = function(frame, state)
    local nameplate = frame.nameplate
    local now = state and state.now or GetTime()

    local guid = frame:GetName(1)
    if guid and guid ~= nameplate.cachedGuid then
      if nameplate.cachedGuid and guidRegistry[nameplate.cachedGuid] == frame then
        guidRegistry[nameplate.cachedGuid] = nil
      end
      nameplate.cachedGuid = guid
      guidRegistry[guid] = frame
    end

    -- PERF: GUID-based target detection (stable, immune to alpha transitions)
    local targetGuid = state and state.targetGuid
    local target = (targetGuid and nameplate.cachedGuid and targetGuid == nameplate.cachedGuid) or
                   (state and state.hasTarget and frame:GetAlpha() >= 0.99) or nil

    -- PERF (ShaguPlates): Only set alpha when value actually changed
    local desiredAlpha = (target or not state.hasTarget) and 1 or cfg.notargalpha
    if nameplate.cachedAlpha ~= desiredAlpha then
      nameplate:SetAlpha(desiredAlpha)
      nameplate.cachedAlpha = desiredAlpha
    end

    -- =========================================================================
    -- CASTBAR VISIBILITY (before throttle — show/hide must always run)
    -- =========================================================================
    local castbar = nameplate.castbar
    local showCast = cfg.showcastbar and (not cfg.targetcastbar or target)
    local castInfo = showCast and nameplate.cachedGuid and GetCastInfo(nameplate.cachedGuid)
    local castActive = castInfo and castInfo.spellID and castInfo.endTime and now < castInfo.endTime
                       and castInfo.event ~= "CAST" and castInfo.event ~= "FAIL"

    local libcastActive = false
    if not castActive and showCast and nameplate.cachedGuid and pfGetCastInfo then
      local cast, _, _, _, startTime, endTime = pfGetCastInfo(nameplate.cachedGuid)
      if not cast then cast, _, _, _, startTime, endTime = pfGetChannelInfo(nameplate.cachedGuid) end
      libcastActive = cast ~= nil
    end

    if not castActive and not libcastActive then
      if castbar.isShown then castbar.isShown = nil; castbar.lastEndTime = nil; castbar.lastTime = nil; castbar:Hide() end
    end

    -- =========================================================================
    -- THROTTLE
    -- =========================================================================
    local isCastingNonTarget = not target and castbar.isShown
    local throttle
    if target then
      throttle = pfUI.throttle:Get("nameplates_target")
    elseif visiblePlateCount > 20 then
      throttle = pfUI.throttle:Get("nameplates_mass")
    else
      throttle = pfUI.throttle:Get("nameplates")
    end
    if isCastingNonTarget then
      local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
      if cbThrottle < throttle then throttle = cbThrottle end
    end

    local hasEventUpdate = nameplate.eventcache or nameplate.auraUpdate or nameplate.castUpdate or nameplate.targetUpdate or nameplate.comboUpdate
    if not hasEventUpdate and (nameplate.lasttick or 0) + throttle > now then return end
    nameplate.lasttick = now

    -- =========================================================================
    -- CASTBAR UPDATES (throttled via nameplates_castbar)
    -- =========================================================================
    local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
    if (nameplate.castbar_tick or 0) + cbThrottle <= now then
      nameplate.castbar_tick = now

      if castActive then
        local isChannel = castInfo.event == "CHANNEL"
        local duration = castInfo.endTime - castInfo.startTime
        if castbar.lastEndTime ~= castInfo.endTime then
          castbar.lastEndTime = castInfo.endTime
          castbar:SetMinMaxValues(0, duration)
          castbar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(isChannel and "channelcolor" or "castbarcolor")]))
          if castInfo.icon then
            castbar.icon.tex:SetTexture(castInfo.icon)
            castbar.icon.tex:SetTexCoord(.1,.9,.1,.9)
          end
          castbar.spell:SetText(cfg.spellname and castInfo.spellName or "")
        end
        local barValue = isChannel and (castInfo.endTime - now) or (now - castInfo.startTime)
        barValue = barValue < 0 and 0 or (barValue > duration and duration or barValue)
        castbar:SetValue(barValue)
        local timeLeft = floor((castInfo.endTime - now) * 10)
        if castbar.lastTime ~= timeLeft then
          castbar.lastTime = timeLeft
          if C.unitframes.castbardecimals == "1" then
            castbar.text:SetText(floor((castInfo.endTime - now) * 10) / 10)
          else
            castbar.text:SetText(string.format("%.2f", castInfo.endTime - now))
          end
        end
        if not castbar.isShown then castbar.isShown = true; castbar:Show() end

      elseif libcastActive and nameplate.cachedGuid and pfGetCastInfo then
        local cast, _, _, texture, startTime, endTime = pfGetCastInfo(nameplate.cachedGuid)
        local channel
        if not cast then channel, _, _, texture, startTime, endTime = pfGetChannelInfo(nameplate.cachedGuid) end
        if cast or channel then
          local effect = cast or channel
          local duration = endTime - startTime
          local max = duration / 1000
          local cur = now - startTime / 1000
          if channel then cur = max + startTime / 1000 - now end
          cur = cur < 0 and 0 or (cur > max and max or cur)
          if castbar.lastEndTime ~= endTime then
            castbar.lastEndTime = endTime
            castbar:SetMinMaxValues(0, max)
            castbar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(channel and "channelcolor" or "castbarcolor")]))
            if texture then castbar.icon.tex:SetTexture(texture); castbar.icon.tex:SetTexCoord(.1,.9,.1,.9) end
            castbar.spell:SetText(cfg.spellname and effect or "")
          end
          castbar:SetValue(cur)
          local remaining = channel and cur or (max - cur)
          local timeLeft = floor(remaining * 10)
          if castbar.lastTime ~= timeLeft then
            castbar.lastTime = timeLeft
            if C.unitframes.castbardecimals == "1" then
              castbar.text:SetText(floor(remaining * 10) / 10)
            else
              castbar.text:SetText(string.format("%.2f", remaining))
            end
          end
          if not castbar.isShown then castbar.isShown = true; castbar:Show() end
        end
      end
    end

    -- =========================================================================
    -- EVERYTHING BELOW RUNS AT THROTTLED RATE
    -- =========================================================================

    local update
    local original = nameplate.original
    local name = original.name:GetText()
    local mouseover = state and state.hasMouseover and original.glow:IsShown() or nil

    if hasEventUpdate then
      nameplates:OnDataChanged(nameplate)
      nameplate.eventcache = nil
      nameplate.auraUpdate = nil
      nameplate.castUpdate = nil
      nameplate.targetUpdate = nil
      nameplate.comboUpdate = nil
    end

    -- VANILLA OVERLAP/CLICKTHROUGH
    if pfUI.client <= 11200 then
      local useOverlap = C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0"
      local clickable = C.nameplates["clickthrough"] ~= "1"
      if not clickable then
        frame:EnableMouse(false); nameplate:EnableMouse(false)
      else
        local plate = useOverlap and nameplate or frame
        plate:EnableMouse(clickable)
      end
      if C.nameplates["overlap"] == "1" then
        if frame:GetWidth() > 1 then frame:SetWidth(1); frame:SetHeight(1) end
      else
        if not nameplate.dwidth then
          nameplate.dwidth = floor(nameplate:GetWidth() * UIParent:GetScale())
        end
        if floor(frame:GetWidth()) ~= nameplate.dwidth then
          frame:SetWidth(nameplate:GetWidth() * UIParent:GetScale())
          frame:SetHeight(nameplate:GetHeight() * UIParent:GetScale())
        end
      end
      local mouseEnabled = nameplate:IsMouseEnabled()
      if C.nameplates["clickthrough"] == "0" and C.nameplates["overlap"] == "1" and SpellIsTargeting() == mouseEnabled then
        nameplate:EnableMouse(not mouseEnabled)
      end
    end

    if nameplate.istarget ~= target then nameplate.target_strata = nil end

    if target and nameplate.target_strata ~= 1 then
      nameplate:SetFrameStrata("LOW")
      nameplate.target_strata = 1
    elseif not target and nameplate.target_strata ~= 0 then
      nameplate:SetFrameStrata("BACKGROUND")
      nameplate.target_strata = 0
    end

    nameplate.istarget = target

    if nameplate.cache.target ~= target then nameplate.cache.target = target; update = true end
    if nameplate.cache.mouseover ~= mouseover then nameplate.cache.mouseover = mouseover; update = true end
    if nameplate.wait_for_scan and GetUnitData(name, true) then nameplate.wait_for_scan = nil; update = true end

    local r, g, b = original.name:GetTextColor()
    local inCombatWithPlayer = false
    if cfg.namefightcolor then
      local g2 = nameplate.cachedGuid
      if g2 then inCombatWithPlayer = UnitAffectingCombat(g2) and UnitAffectingCombat("player") end
    end

    if r + g + b ~= nameplate.cache.namecolor or (cfg.namefightcolor and nameplate.cache.inCombat ~= inCombatWithPlayer) then
      nameplate.cache.namecolor = r + g + b
      nameplate.cache.inCombat = inCombatWithPlayer
      if cfg.namefightcolor then
        if (r > .9 and g < .2 and b < .2) or inCombatWithPlayer then
          nameplate.name:SetTextColor(1,0.4,0.2,1)
        else
          nameplate.name:SetTextColor(r,g,b,1)
        end
      else
        nameplate.name:SetTextColor(1,1,1,1)
      end
      update = true
    end

    local r, g, b = original.level:GetTextColor()
    r, g, b = r + .3, g + .3, b + .3
    if r + g + b ~= nameplate.cache.levelcolor then
      nameplate.cache.levelcolor = r + g + b
      nameplate.level:SetTextColor(r,g,b,1)
      update = true
    end

    if nameplate.debuffcache then
      for id = 1, 16 do
        local data = nameplate.debuffcache[id]
        if data and (not data.stop or data.stop < now) and not data.empty then
          data.empty = true
          update = true
        end
      end
    end

    if not nameplate.tick or nameplate.tick < now then update = true end

    if update then
      nameplates:OnDataChanged(nameplate)
      nameplate.tick = now + .5
    end

    -- =========================================================================
    -- ZOOM (ShaguPlates: instant zoom option)
    -- =========================================================================
    if target and cfg.targetzoom then
      local wc = cfg.width * cfg.zoomval
      local hc = cfg.heighthealth * (cfg.zoomval * .9)
      if cfg.zoominstant then
        if not nameplate.health.zoomed then
          nameplate.health:SetWidth(wc); nameplate.health:SetHeight(hc); nameplate.health.zoomed = true
        end
      else
        if not nameplate.health.zoomed then
          nameplate.health.targetWidth = wc; nameplate.health.targetHeight = hc
        end
        local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
        local twc, thc = nameplate.health.targetWidth, nameplate.health.targetHeight
        if twc and thc then
          if twc > w + 0.5 then nameplate.health:SetWidth(w*1.05); nameplate.health.zoomTransition = true
          elseif thc > h + 0.5 then nameplate.health:SetHeight(h*1.05); nameplate.health.zoomTransition = true
          else
            if nameplate.health.zoomTransition then
              nameplate.health:SetWidth(twc); nameplate.health:SetHeight(thc); nameplate.health.zoomTransition = nil
            end
            nameplate.health.zoomed = true
          end
        end
      end
    elseif nameplate.health.zoomed or nameplate.health.zoomTransition then
      if cfg.zoominstant then
        nameplate.health:SetWidth(cfg.width); nameplate.health:SetHeight(cfg.heighthealth)
        nameplate.health.zoomTransition = nil; nameplate.health.zoomed = nil
        nameplate.health.targetWidth = nil; nameplate.health.targetHeight = nil
      else
        local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
        if w > cfg.width + 0.5 then nameplate.health:SetWidth(w*.95)
        elseif h > cfg.heighthealth + 0.5 then nameplate.health:SetHeight(h*0.95)
        else
          nameplate.health:SetWidth(cfg.width); nameplate.health:SetHeight(cfg.heighthealth)
          nameplate.health.zoomTransition = nil; nameplate.health.zoomed = nil
          nameplate.health.targetWidth = nil; nameplate.health.targetHeight = nil
        end
      end
    end
  end

  nameplates.SetGameVariables = function()
    if C.nameplates["showhostile"] == "1" then
      _G.NAMEPLATES_ON = true; ShowNameplates()
    else
      _G.NAMEPLATES_ON = nil; HideNameplates()
    end
    if C.nameplates["showfriendly"] == "1" then
      _G.FRIENDNAMEPLATES_ON = true; ShowFriendNameplates()
    else
      _G.FRIENDNAMEPLATES_ON = nil; HideFriendNameplates()
    end
  end

  nameplates:SetGameVariables()

  nameplates.UpdateConfig = function()
    CacheConfig()
    RebuildOfftanks()
    DebuffFilterPopulate()

    local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
    local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
    local pvpType = GetZonePVPInfo()
    local nowFriendly = (pvpType == "friendly")

    if nowFriendly and (disableHostile or disableFriendly) then
      if not inFriendlyZone then
        inFriendlyZone = true
        savedHostileState = C.nameplates["showhostile"]
        savedFriendlyState = C.nameplates["showfriendly"]
      end
      if disableHostile then _G.NAMEPLATES_ON = nil; HideNameplates()
      elseif savedHostileState == "1" then _G.NAMEPLATES_ON = true; ShowNameplates() end
      if disableFriendly then _G.FRIENDNAMEPLATES_ON = nil; HideFriendNameplates()
      elseif savedFriendlyState == "1" then _G.FRIENDNAMEPLATES_ON = true; ShowFriendNameplates() end
      return
    elseif inFriendlyZone and not (disableHostile or disableFriendly) then
      inFriendlyZone = false
      if savedHostileState == "1" then C.nameplates["showhostile"] = savedHostileState end
      if savedFriendlyState == "1" then C.nameplates["showfriendly"] = savedFriendlyState end
      savedHostileState = nil; savedFriendlyState = nil
    end

    nameplates:SetGameVariables()

    for plate in pairs(registry) do
      plate.nameplate.cachedAlpha = nil
      nameplates.OnConfigChange(plate)
    end
  end

  if pfUI.client <= 11200 then
    local hookOnConfigChange = nameplates.OnConfigChange
    nameplates.OnConfigChange = function(self)
      hookOnConfigChange(self)
      local parent = self
      local nameplate = self.nameplate
      local plate = (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") and nameplate or parent
      parent:EnableMouse(false); nameplate:EnableMouse(false)
      if C.nameplates["vertical_offset"] ~= "0" then
        nameplate:SetPoint("TOP", parent, "TOP", 0, tonumber(C.nameplates["vertical_offset"]))
      end
      if C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0" then
        plate:SetScript("OnClick", function() parent:Click() end)
      end
      if C.nameplates["rightclick"] == "1" then
        plate:SetScript("OnMouseDown", nameplates.mouselook.OnMouseDown)
      else
        plate:SetScript("OnMouseDown", nil)
      end
    end

    local hookOnDataChanged = nameplates.OnDataChanged
    nameplates.OnDataChanged = function(self, nameplate)
      hookOnDataChanged(self, nameplate)
      if (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") then
        nameplate.parent:EnableMouse(false)
      end
    end

    nameplates.mouselook = CreateFrame("Frame", nil, UIParent)
    nameplates.mouselook.time = nil
    nameplates.mouselook.frame = nil
    nameplates.mouselook.OnMouseDown = function()
      if arg1 and arg1 == "RightButton" then
        MouselookStart()
        nameplates.mouselook.time = GetTime()
        nameplates.mouselook.frame = this
        nameplates.mouselook:Show()
      end
    end

    nameplates.mouselook:SetScript("OnUpdate", function()
      if not this.time or not this.frame then this:Hide(); return end
      if not IsMouselooking() and this.time + tonumber(C.nameplates["clickthreshold"]) < GetTime() then
        this:Hide(); return
      end
      if not IsMouselooking() then
        this.frame:Click("LeftButton")
        if UnitCanAttack("player", "target") and not nameplates.combat.inCombat then AttackTarget() end
        this:Hide(); return
      end
    end)
  end

  pfUI.nameplates = nameplates
end)