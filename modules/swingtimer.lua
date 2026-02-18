pfUI:RegisterModule("swingtimer", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()

  -- Enable Nampower auto attack events
  if GetCVar and SetCVar then
    local success, value = pcall(GetCVar, "NP_EnableAutoAttackEvents")
    if success and value == "0" then
      pcall(SetCVar, "NP_EnableAutoAttackEvents", "1")
    end
  end

  -- HitInfo flags
  local HITINFO_LEFTSWING = 4

  -- Swing state
  local swingState = {
    mainhand = { speed = 0, nextSwing = 0, swinging = false },
    offhand = { speed = 0, nextSwing = 0, swinging = false }
  }

  -- Create container frame
  pfUI.swingtimer = CreateFrame("Frame", "pfSwingTimer", UIParent)
  pfUI.swingtimer:SetFrameStrata("MEDIUM")
  pfUI.swingtimer:Hide()

  local sw_width    = tonumber(C.unitframes.swingtimerwidth) or 200
  local sw_height   = tonumber(C.unitframes.swingtimerheight) or 12
  local sw_label    = C.unitframes.swingtimerlabel    ~= "0"
  local sw_oh       = C.unitframes.swingtimeroh       ~= "0"
  local sw_hs       = C.unitframes.swingtimerhsqueue  ~= "0"
  local sw_text     = C.unitframes.swingtimertext     ~= "0"
  local sw_fontsize = tonumber(C.unitframes.swingtimerfontsize) or 12
  local sw_texture  = pfUI.media[C.unitframes.swingtimertexture or "img:bar"]

  -- Mainhand bar
  pfUI.swingtimer.mainhand = CreateFrame("StatusBar", "pfSwingTimerMainhand", UIParent)
  pfUI.swingtimer.mainhand:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
  pfUI.swingtimer.mainhand:SetWidth(sw_width)
  pfUI.swingtimer.mainhand:SetHeight(sw_height)
  pfUI.swingtimer.mainhand:SetMinMaxValues(0, 1)
  pfUI.swingtimer.mainhand:SetValue(0)
  pfUI.swingtimer.mainhand:SetStatusBarTexture(sw_texture)
  pfUI.swingtimer.mainhand:SetStatusBarColor(0.8, 0.3, 0.3, 1)
  pfUI.swingtimer.mainhand:Hide()

  pfUI.swingtimer.mainhand.text = pfUI.swingtimer.mainhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.mainhand.text:SetPoint("CENTER", pfUI.swingtimer.mainhand, "CENTER", 0, 0)
  pfUI.swingtimer.mainhand.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.mainhand.text:SetTextColor(1, 1, 1, 1)
  pfUI.swingtimer.mainhand.text:SetText("")
  if not sw_text then pfUI.swingtimer.mainhand.text:Hide() end

  pfUI.swingtimer.mainhand.label = pfUI.swingtimer.mainhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.mainhand.label:SetPoint("RIGHT", pfUI.swingtimer.mainhand, "LEFT", -4, 0)
  pfUI.swingtimer.mainhand.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.mainhand.label:SetTextColor(0.8, 0.8, 0.8, 1)
  pfUI.swingtimer.mainhand.label:SetText(sw_label and "MH" or "")

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
  pfUI.swingtimer.offhand:SetStatusBarColor(0.3, 0.8, 0.3, 1)
  pfUI.swingtimer.offhand:Hide()

  pfUI.swingtimer.offhand.text = pfUI.swingtimer.offhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.offhand.text:SetPoint("CENTER", pfUI.swingtimer.offhand, "CENTER", 0, 0)
  pfUI.swingtimer.offhand.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.offhand.text:SetTextColor(1, 1, 1, 1)
  pfUI.swingtimer.offhand.text:SetText("")
  if not sw_text then pfUI.swingtimer.offhand.text:Hide() end

  pfUI.swingtimer.offhand.label = pfUI.swingtimer.offhand:CreateFontString("Status", "DIALOG", "GameFontNormal")
  pfUI.swingtimer.offhand.label:SetPoint("RIGHT", pfUI.swingtimer.offhand, "LEFT", -4, 0)
  pfUI.swingtimer.offhand.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
  pfUI.swingtimer.offhand.label:SetTextColor(0.8, 0.8, 0.8, 1)
  pfUI.swingtimer.offhand.label:SetText(sw_label and "OH" or "")

  CreateBackdrop(pfUI.swingtimer.offhand)
  CreateBackdropShadow(pfUI.swingtimer.offhand)

  -- HS/Cleave queue detection (Warrior only)
  local hsTrackedSlots = {}
  local cleaveTrackedSlots = {}

  local function UpdateHSCleaveSlots()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" or not sw_hs then return end
    hsTrackedSlots = {}
    cleaveTrackedSlots = {}
    for slot = 1, 120 do
      local texture = GetActionTexture(slot)
      local text = GetActionText(slot)
      if texture then
        if texture == "Interface\\Icons\\Ability_Rogue_Ambush" then
          tinsert(hsTrackedSlots, slot)
        elseif texture == "Interface\\Icons\\Ability_Warrior_Cleave" then
          tinsert(cleaveTrackedSlots, slot)
        elseif text then
          text = string.lower(text)
          if text == "heroic strike" or text == "heroicstrike" or text == "hs" then
            tinsert(hsTrackedSlots, slot)
          elseif text == "cleave" then
            tinsert(cleaveTrackedSlots, slot)
          end
        end
      end
    end
  end

  local function IsHSQueued()
    if not sw_hs then return false end
    for _, slot in ipairs(hsTrackedSlots) do
      if IsCurrentAction(slot) then return true end
    end
    return false
  end

  local function IsCleaveQueued()
    if not sw_hs then return false end
    for _, slot in ipairs(cleaveTrackedSlots) do
      if IsCurrentAction(slot) then return true end
    end
    return false
  end

  UpdateMovable(pfUI.swingtimer.mainhand)

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
      pfUI.swingtimer.offhand:Show()
    else
      swingState.mainhand.nextSwing = now + swingState.mainhand.speed
      swingState.mainhand.swinging = true
      pfUI.swingtimer.mainhand:Show()
    end

    pfUI.swingtimer:Show()
  end

  pfUI.swingtimer:SetScript("OnUpdate", function()
    local now = GetTime()
    local anyActive = false

    local mhR, mhG, mhB = 0.8, 0.3, 0.3
    if sw_hs and IsCleaveQueued() then
      mhR, mhG, mhB = 0.2, 0.9, 0.2
    elseif sw_hs and IsHSQueued() then
      mhR, mhG, mhB = 0.9, 0.9, 0.2
    end

    if swingState.mainhand.swinging then
      local remaining = swingState.mainhand.nextSwing - now
      if remaining <= 0 then
        swingState.mainhand.swinging = false
        pfUI.swingtimer.mainhand:Hide()
      else
        local progress = 1 - (remaining / swingState.mainhand.speed)
        pfUI.swingtimer.mainhand:SetValue(progress)
        pfUI.swingtimer.mainhand:SetStatusBarColor(mhR, mhG, mhB, 1)
        if sw_text then
          pfUI.swingtimer.mainhand.text:SetText(string.format("%.1f", remaining))
        end
        anyActive = true
      end
    end

    if sw_oh and swingState.offhand.swinging then
      local remaining = swingState.offhand.nextSwing - now
      if remaining <= 0 then
        swingState.offhand.swinging = false
        pfUI.swingtimer.offhand:Hide()
      else
        local progress = 1 - (remaining / swingState.offhand.speed)
        pfUI.swingtimer.offhand:SetValue(progress)
        if sw_text then
          pfUI.swingtimer.offhand.text:SetText(string.format("%.1f", remaining))
        end
        anyActive = true
      end
    elseif not sw_oh then
      pfUI.swingtimer.offhand:Hide()
    end

    if not anyActive then
      this:Hide()
    end
  end)

  local events = CreateFrame("Frame")
  events:RegisterEvent("AUTO_ATTACK_SELF")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("UNIT_INVENTORY_CHANGED")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("PLAYER_TARGET_CHANGED")
  events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

  local function ResetSwingTimers()
    swingState.mainhand.swinging = false
    swingState.offhand.swinging = false
    pfUI.swingtimer.mainhand:Hide()
    pfUI.swingtimer.offhand:Hide()
    pfUI.swingtimer:Hide()
  end

  events:SetScript("OnEvent", function()
    if event == "AUTO_ATTACK_SELF" then
      local hitInfo = arg4 or 0
      local isOffhand = bit.band(hitInfo, HITINFO_LEFTSWING) ~= 0
      StartSwing(isOffhand)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_INVENTORY_CHANGED" then
      if arg1 and arg1 ~= "player" then return end
      UpdateWeaponSpeeds()
      UpdateHSCleaveSlots()
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
      UpdateHSCleaveSlots()
    elseif event == "PLAYER_REGEN_DISABLED" then
      UpdateWeaponSpeeds()
    elseif event == "PLAYER_REGEN_ENABLED" then
      ResetSwingTimers()
    elseif event == "PLAYER_TARGET_CHANGED" then
      if not UnitExists("target") or UnitIsDead("target") then
        ResetSwingTimers()
      end
    end
  end)

  UpdateWeaponSpeeds()
  UpdateHSCleaveSlots()
end)