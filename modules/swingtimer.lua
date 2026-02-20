pfUI:RegisterModule("swingtimer", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()

  -- HitInfo flags (EVENTS.md)
  local HITINFO_LEFTSWING  = 4      -- 0x4: Off-hand attack
  local HITINFO_NOACTION   = 65536  -- 0x10000: server did not advance the swing clock

  -- SPELL_QUEUE_EVENT codes (EVENTS.md)
  local ON_SWING_QUEUED      = 0
  local ON_SWING_QUEUE_POPPED = 1

  -- Swing state
  local swingState = {
    mainhand = { speed = 0, nextSwing = 0, swinging = false },
    offhand  = { speed = 0, nextSwing = 0, swinging = false },
    ranged   = { speed = 0, nextSwing = 0, swinging = false },
  }

  -- Ranged spell IDs that trigger the ranged swing timer (replaces MH)
  local RANGED_SPELLIDS = {
    [75]   = true,  -- Auto Shot (Hunter)
    [2764] = true,  -- Throw (Warrior/Rogue)
  }

  -- Create container frame
  pfUI.swingtimer = CreateFrame("Frame", "pfSwingTimer", UIParent)
  pfUI.swingtimer:SetFrameStrata("MEDIUM")
  pfUI.swingtimer:Hide()

  -- Read config once at load into locals
  local sw_width     = tonumber(C.unitframes.swingtimerwidth) or 200
  local sw_height    = tonumber(C.unitframes.swingtimerheight) or 12
  local sw_texture   = C.unitframes.swingtimertexture or "Interface\\AddOns\\pfUI\\img\\bar"
  local sw_showtext  = C.unitframes.swingtimertext ~= "0"
  local sw_showlabel = C.unitframes.swingtimerlabel ~= "0"
  local sw_showoh     = C.unitframes.swingtimeroffhand ~= "0"
  local sw_showranged = C.unitframes.swingtimerranged ~= "0"
  local sw_fontsize   = tonumber(C.unitframes.swingtimerfontsize) or 12
  local isHunter = UnitClass("player") == "Hunter"
  local sw_hsqueue   = C.unitframes.swingtimerhsqueue ~= "0"

  -- Parse color strings "r,g,b,a" into components
  local function ParseColor(str, dr, dg, db, da)
    if not str or str == "" then return dr, dg, db, da end
    local _, _, r, g, b, a = string.find(str, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
    if r then
      return tonumber(r) or dr, tonumber(g) or dg, tonumber(b) or db, tonumber(a) or da
    end
    return dr, dg, db, da
  end

  local mhR, mhG, mhB, mhA = ParseColor(C.unitframes.swingtimermhcolor, 0.8, 0.3, 0.3, 1)
  local ohR, ohG, ohB, ohA = ParseColor(C.unitframes.swingtimerohcolor, 0.3, 0.8, 0.3, 1)
  local raR, raG, raB, raA = ParseColor(C.unitframes.swingtimerrangedcolor, 0.3, 0.6, 1.0, 1)
  local rwR, rwG, rwB, rwA = ParseColor(C.unitframes.swingtimerrangedwarncolor, 0.9, 0.0, 0.0, 1)

  -- Store default MH color for HS/Cleave restore
  local mhDefaultR, mhDefaultG, mhDefaultB = mhR, mhG, mhB

  -- Mainhand bar
  pfUI.swingtimer.mainhand = CreateFrame("StatusBar", "pfSwingTimerMainhand", UIParent)
  pfUI.swingtimer.mainhand:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
  pfUI.swingtimer.mainhand:SetWidth(sw_width)
  pfUI.swingtimer.mainhand:SetHeight(sw_height)
  pfUI.swingtimer.mainhand:SetMinMaxValues(0, 1)
  pfUI.swingtimer.mainhand:SetValue(0)
  pfUI.swingtimer.mainhand:SetStatusBarTexture(sw_texture)
  pfUI.swingtimer.mainhand:SetStatusBarColor(mhR, mhG, mhB, mhA)
  pfUI.swingtimer.mainhand:Hide()

  pfUI.swingtimer.mainhand.text = pfUI.swingtimer.mainhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.mainhand.text:SetPoint("CENTER", pfUI.swingtimer.mainhand, "CENTER", 0, 0)
  pfUI.swingtimer.mainhand.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.mainhand.text:SetTextColor(1, 1, 1, 1)
  pfUI.swingtimer.mainhand.text:SetText("")
  if not sw_showtext then pfUI.swingtimer.mainhand.text:Hide() end

  pfUI.swingtimer.mainhand.label = pfUI.swingtimer.mainhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.mainhand.label:SetPoint("RIGHT", pfUI.swingtimer.mainhand, "LEFT", -4, 0)
  pfUI.swingtimer.mainhand.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.mainhand.label:SetTextColor(0.8, 0.8, 0.8, 1)
  pfUI.swingtimer.mainhand.label:SetText(sw_showlabel and "MH" or "")

  CreateBackdrop(pfUI.swingtimer.mainhand)
  CreateBackdropShadow(pfUI.swingtimer.mainhand)

  -- Offhand bar
  pfUI.swingtimer.offhand = CreateFrame("StatusBar", "pfSwingTimerOffhand", UIParent)
  pfUI.swingtimer.offhand:SetPoint("TOP", pfUI.swingtimer.mainhand, "BOTTOM", 0, -4)
  pfUI.swingtimer.offhand:SetWidth(sw_width)
  pfUI.swingtimer.offhand:SetHeight(sw_height)
  pfUI.swingtimer.offhand:SetMinMaxValues(0, 1)
  pfUI.swingtimer.offhand:SetValue(0)
  pfUI.swingtimer.offhand:SetStatusBarTexture(sw_texture)
  pfUI.swingtimer.offhand:SetStatusBarColor(ohR, ohG, ohB, ohA)
  pfUI.swingtimer.offhand:Hide()

  pfUI.swingtimer.offhand.text = pfUI.swingtimer.offhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.offhand.text:SetPoint("CENTER", pfUI.swingtimer.offhand, "CENTER", 0, 0)
  pfUI.swingtimer.offhand.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.offhand.text:SetTextColor(1, 1, 1, 1)
  pfUI.swingtimer.offhand.text:SetText("")
  if not sw_showtext then pfUI.swingtimer.offhand.text:Hide() end

  pfUI.swingtimer.offhand.label = pfUI.swingtimer.offhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.offhand.label:SetPoint("RIGHT", pfUI.swingtimer.offhand, "LEFT", -4, 0)
  pfUI.swingtimer.offhand.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.offhand.label:SetTextColor(0.8, 0.8, 0.8, 1)
  pfUI.swingtimer.offhand.label:SetText(sw_showlabel and "OH" or "")

  CreateBackdrop(pfUI.swingtimer.offhand)
  CreateBackdropShadow(pfUI.swingtimer.offhand)

  -- Ranged bar (bow/gun/crossbow - triggered by SPELL_GO_SELF for Auto Shot / Throw)
  pfUI.swingtimer.ranged = CreateFrame("StatusBar", "pfSwingTimerRanged", UIParent)
  pfUI.swingtimer.ranged:SetPoint("TOP", pfUI.swingtimer.offhand, "BOTTOM", 0, -4)
  pfUI.swingtimer.ranged:SetWidth(sw_width)
  pfUI.swingtimer.ranged:SetHeight(sw_height)
  pfUI.swingtimer.ranged:SetMinMaxValues(0, 1)
  pfUI.swingtimer.ranged:SetValue(0)
  pfUI.swingtimer.ranged:SetStatusBarTexture(sw_texture)
  pfUI.swingtimer.ranged:SetStatusBarColor(raR, raG, raB, raA)
  pfUI.swingtimer.ranged:Hide()

  pfUI.swingtimer.ranged.text = pfUI.swingtimer.ranged:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.ranged.text:SetPoint("CENTER", pfUI.swingtimer.ranged, "CENTER", 0, 0)
  pfUI.swingtimer.ranged.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.ranged.text:SetTextColor(1, 1, 1, 1)
  pfUI.swingtimer.ranged.text:SetText("")
  if not sw_showtext then pfUI.swingtimer.ranged.text:Hide() end

  pfUI.swingtimer.ranged.label = pfUI.swingtimer.ranged:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.ranged.label:SetPoint("RIGHT", pfUI.swingtimer.ranged, "LEFT", -4, 0)
  pfUI.swingtimer.ranged.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.ranged.label:SetTextColor(0.8, 0.8, 0.8, 1)
  pfUI.swingtimer.ranged.label:SetText(sw_showlabel and "Ra" or "")

  CreateBackdrop(pfUI.swingtimer.ranged)
  CreateBackdropShadow(pfUI.swingtimer.ranged)

  -- HS/Cleave queue state
  local hsQueued           = false
  local cleaveQueued       = false
  local isWarrior          = false
  local cachedHSSlots      = {}
  local cachedCleaveSlots  = {}
  local useSpellQueueEvent = false

  -- Heroic Strike spell IDs (all ranks)
  local hsSpellIDs = {
    [78] = true, [284] = true, [285] = true, [1608] = true,
    [11564] = true, [11565] = true, [11566] = true, [11567] = true,
    [25286] = true,
  }
  -- Cleave spell IDs (all ranks)
  local cleaveSpellIDs = {
    [845] = true, [7369] = true, [11608] = true, [11609] = true,
    [20569] = true,
  }

  local function RebuildQueueSlotCache()
    if not isWarrior or not sw_hsqueue or useSpellQueueEvent then return end

    cachedHSSlots     = {}
    cachedCleaveSlots = {}

    for slot = 1, 120 do
      local tex  = GetActionTexture(slot)
      local name = GetActionText(slot)

      if tex then
        if string.find(tex, "Ability_Rogue_Ambush") then
          table.insert(cachedHSSlots, slot)
        elseif string.find(tex, "Ability_Warrior_Cleave") then
          table.insert(cachedCleaveSlots, slot)
        end
      end

      if name then
        local lower = string.lower(name)
        if lower == "heroic strike" or lower == "heroicstrike" or lower == "hs" then
          table.insert(cachedHSSlots, slot)
        elseif lower == "cleave" then
          table.insert(cachedCleaveSlots, slot)
        end
      end
    end
  end

  local function CheckQueuedAction(slotList)
    for i = 1, table.getn(slotList) do
      if IsCurrentAction(slotList[i]) then return true end
    end
    return false
  end

  local function IsHSOrCleaveQueued()
    if not sw_hsqueue or not isWarrior then return false, false end
    if useSpellQueueEvent then
      return hsQueued, cleaveQueued
    end
    return CheckQueuedAction(cachedHSSlots), CheckQueuedAction(cachedCleaveSlots)
  end

  UpdateMovable(pfUI.swingtimer.mainhand)

  -- VERSION B TEST: HasOffhandWeapon() removed.
  -- The original used GetItemInfo() to detect OH weapon type, but GetItemInfo()
  -- returns nil on first login before the item cache is populated, causing
  -- offhand.speed to stay 0. Now we just read offhandAttackTime directly,
  -- same as the old working version.
  local function UpdateWeaponSpeeds()
    if not GetUnitField then return end

    local mhSpeed = GetUnitField("player", "baseAttackTime")
    local ohSpeed = GetUnitField("player", "offhandAttackTime")

    if mhSpeed and mhSpeed > 0 then
      swingState.mainhand.speed = mhSpeed / 1000
    end

    if ohSpeed and ohSpeed > 0 then
      swingState.offhand.speed = ohSpeed / 1000
    else
      swingState.offhand.speed = 0
    end

    local raSpeed = GetUnitField("player", "rangedAttackTime")
    if raSpeed and raSpeed > 0 then
      swingState.ranged.speed = raSpeed / 1000
    else
      swingState.ranged.speed = 0
    end
  end

  local function StartSwing(isOffhand)
    local now = GetTime()

    -- always refresh speeds to catch haste buffs/debuffs
    UpdateWeaponSpeeds()

    -- dual-wield guard: if MH swing just started (<100ms ago) and this isn't
    -- flagged as offhand, it's likely an OH event with missing flag
    if not isOffhand and swingState.offhand.speed > 0 then
      local mhAge = now - (swingState.mainhand.nextSwing - swingState.mainhand.speed)
      if swingState.mainhand.swinging and mhAge > 0 and mhAge < 0.1 then
        isOffhand = true
      end
    end

    if isOffhand and swingState.offhand.speed > 0 then
      swingState.offhand.nextSwing = now + swingState.offhand.speed
      swingState.offhand.swinging = true
      if sw_showoh then pfUI.swingtimer.offhand:Show() end
    else
      swingState.mainhand.nextSwing = now + swingState.mainhand.speed
      swingState.mainhand.swinging = true
      pfUI.swingtimer.mainhand:Show()
    end

    pfUI.swingtimer:Show()
  end

  local function StartRangedSwing()
    if not sw_showranged then return end
    UpdateWeaponSpeeds()
    if swingState.ranged.speed <= 0 then return end
    swingState.mainhand.swinging = false
    pfUI.swingtimer.mainhand:Hide()
    swingState.ranged.nextSwing = GetTime() + swingState.ranged.speed
    swingState.ranged.swinging  = true
    pfUI.swingtimer.ranged:Show()
    pfUI.swingtimer:Show()
  end

  pfUI.swingtimer:SetScript("OnUpdate", function()
    local now = GetTime()
    local anyActive = false

    local curR, curG, curB = mhDefaultR, mhDefaultG, mhDefaultB
    if sw_hsqueue and isWarrior then
      local hs, cl = IsHSOrCleaveQueued()
      if cl then
        curR, curG, curB = 0.2, 0.9, 0.2
      elseif hs then
        curR, curG, curB = 0.9, 0.9, 0.2
      end
    end

    if swingState.mainhand.swinging then
      local remaining = swingState.mainhand.nextSwing - now

      if remaining <= 0 then
        swingState.mainhand.swinging = false
        pfUI.swingtimer.mainhand:Hide()
      else
        local progress = 1 - (remaining / swingState.mainhand.speed)
        pfUI.swingtimer.mainhand:SetValue(progress)
        pfUI.swingtimer.mainhand:SetStatusBarColor(curR, curG, curB, mhA)
        if sw_showtext then
          pfUI.swingtimer.mainhand.text:SetText(string.format("%.1f", remaining))
        end
        anyActive = true
      end
    end

    if sw_showoh and swingState.offhand.swinging then
      local remaining = swingState.offhand.nextSwing - now

      if remaining <= 0 then
        swingState.offhand.swinging = false
        pfUI.swingtimer.offhand:Hide()
      else
        local progress = 1 - (remaining / swingState.offhand.speed)
        pfUI.swingtimer.offhand:SetValue(progress)
        if sw_showtext then
          pfUI.swingtimer.offhand.text:SetText(string.format("%.1f", remaining))
        end
        anyActive = true
      end
    elseif not sw_showoh then
      pfUI.swingtimer.offhand:Hide()
    end

    if sw_showranged and swingState.ranged.swinging then
      local remaining = swingState.ranged.nextSwing - now

      if remaining <= 0 then
        swingState.ranged.swinging = false
        pfUI.swingtimer.ranged:Hide()
      else
        local progress = 1 - (remaining / swingState.ranged.speed)
        pfUI.swingtimer.ranged:SetValue(progress)
        if isHunter then
          if remaining < 0.5 then
            pfUI.swingtimer.ranged:SetStatusBarColor(rwR, rwG, rwB, rwA)
          else
            pfUI.swingtimer.ranged:SetStatusBarColor(raR, raG, raB, raA)
          end
        end
        if sw_showtext then
          pfUI.swingtimer.ranged.text:SetText(string.format("%.1f", remaining))
        end
        anyActive = true
      end
    elseif not sw_showranged then
      pfUI.swingtimer.ranged:Hide()
    end

    if not anyActive then
      if not pfUI.swingtimer.mainhand:IsShown()
        and not pfUI.swingtimer.offhand:IsShown()
        and not pfUI.swingtimer.ranged:IsShown() then
        this:Hide()
      end
    end
  end)

  local events = CreateFrame("Frame")
  events:RegisterEvent("AUTO_ATTACK_SELF")
  events:RegisterEvent("AUTO_ATTACK_OTHER")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("UNIT_INVENTORY_CHANGED")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  events:RegisterEvent("UNIT_DIED")
  events:RegisterEvent("SPELL_QUEUE_EVENT")
  events:RegisterEvent("SPELL_GO_SELF")

  local function ResetSwingTimers()
    swingState.mainhand.swinging = false
    swingState.offhand.swinging  = false
    swingState.ranged.swinging   = false
    pfUI.swingtimer.mainhand:Hide()
    pfUI.swingtimer.offhand:Hide()
    pfUI.swingtimer.ranged:Hide()
    pfUI.swingtimer:Hide()
  end

  local playerGUID = nil

  events:SetScript("OnEvent", function()
    if event == "AUTO_ATTACK_SELF" then
      local hitInfo = arg4 or 0
      -- HITINFO_NOACTION: server did not advance the swing clock, ignore
      if bit.band(hitInfo, HITINFO_NOACTION) ~= 0 then return end
      local isOffhand = bit.band(hitInfo, HITINFO_LEFTSWING) ~= 0
      StartSwing(isOffhand)

    elseif event == "AUTO_ATTACK_OTHER" then
      if not swingState.mainhand.swinging then return end
      local targetGuid = arg2
      if not targetGuid or not playerGUID then return end
      if targetGuid ~= playerGUID then return end
      local victimState = arg5 or 0
      if victimState == 3 then
        local now = GetTime()
        local remaining = swingState.mainhand.nextSwing - now
        local reduction = swingState.mainhand.speed * 0.4
        local minRemaining = swingState.mainhand.speed * 0.2
        local newRemaining = remaining - reduction
        if newRemaining < minRemaining then newRemaining = minRemaining end
        if newRemaining < remaining then
          swingState.mainhand.nextSwing = now + newRemaining
        end
      end

    elseif event == "SPELL_QUEUE_EVENT" then
      local eventCode = arg1 or -1
      local spellId   = arg2 or 0
      if eventCode == ON_SWING_QUEUED then
        useSpellQueueEvent = true
        if hsSpellIDs[spellId] then
          hsQueued = true; cleaveQueued = false
        elseif cleaveSpellIDs[spellId] then
          cleaveQueued = true; hsQueued = false
        end
      elseif eventCode == ON_SWING_QUEUE_POPPED then
        hsQueued = false; cleaveQueued = false
      end

    elseif event == "PLAYER_ENTERING_WORLD" then
      local _, class = UnitClass("player")
      isWarrior  = (class == "WARRIOR")
      playerGUID = UnitExists("player")
      UpdateWeaponSpeeds()
      RebuildQueueSlotCache()

    elseif event == "SPELL_GO_SELF" then
      local spellId = arg2 or 0
      if RANGED_SPELLIDS[spellId] then
        StartRangedSwing()
      end

    elseif event == "UNIT_INVENTORY_CHANGED" then
      if arg1 and arg1 ~= "player" then return end
      UpdateWeaponSpeeds()
      if swingState.offhand.speed == 0 then
        swingState.offhand.swinging = false
        pfUI.swingtimer.offhand:Hide()
      end
      if swingState.ranged.speed == 0 then
        swingState.ranged.swinging = false
        pfUI.swingtimer.ranged:Hide()
      end

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
      RebuildQueueSlotCache()

    elseif event == "PLAYER_REGEN_DISABLED" then
      UpdateWeaponSpeeds()

    elseif event == "PLAYER_REGEN_ENABLED" then
      ResetSwingTimers()
      hsQueued     = false
      cleaveQueued = false

    elseif event == "UNIT_DIED" then
      -- Only reset if the player themselves died
      local guid = arg1
      if not guid then return end
      if guid == playerGUID then
        ResetSwingTimers()
      end
    end
  end)

  UpdateWeaponSpeeds()
end)