pfUI:RegisterModule("buff", "vanilla:tbc", function ()
  -- Hide Blizz
  BuffFrame:Hide()
  BuffFrame:UnregisterAllEvents()
  TemporaryEnchantFrame:Hide()
  TemporaryEnchantFrame:UnregisterAllEvents()

  local br, bg, bb, ba = GetStringColor(pfUI_config.appearance.border.color)
  local libdebuff = pfUI.api.libdebuff
  local libtipscan = pfUI.api.libtipscan
  local scanner = libtipscan and libtipscan:GetScanner("buff")

  -- ============================================================================
  -- RefreshBuffButton: Display using Nampower aura data stored on button
  -- ============================================================================
  local function RefreshBuffButton(buff)
    if buff.btype == "HELPFUL" then
      if C.buffs.separateweapons == "1" then
        buff.id = buff.gid - (buff.weapon ~= nil and buff.gid or 0)
      else
        buff.id = buff.gid - ((C.buffs.weapons == "1" and C.buffs.separateweapons == "0") and pfUI.buff.wepbuffs.count or 0)
      end
    else
      buff.id = buff.gid
    end

    if not buff.backdrop then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
    end

    -- Weapon buffs: still use Blizzard API (not in GetUnitField aura slots)
    if buff.btype == "HELPFUL" and ((C.buffs.separateweapons == "0" and buff.gid <= pfUI.buff.wepbuffs.count) or (pfUI.buff.wepbuffs.count > 0 and buff.weapon ~= nil)) then
        local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
        if pfUI.buff.wepbuffs.count == 2 then
          if buff.gid == 1 then
            buff.mode = "MAINHAND"
          else
            buff.mode = "OFFHAND"
          end
        else
          if C.buffs.separateweapons == "0" then
            buff.mode = mh and "MAINHAND" or oh and "OFFHAND"
          else
            if buff.gid == 1 then
              buff.mode = mh and "MAINHAND" or oh and "OFFHAND"
            else
              buff:Hide()
              return
            end
          end
        end

      if buff.mode == "MAINHAND" then
        local tex = GetInventoryItemTexture("player", 16)
        buff.texture:SetTexture(tex)
        if not tex then pfUI.buff.wepbuffs.pendingRetry = true end
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 16) or 1))
      elseif buff.mode == "OFFHAND" then
        local tex = GetInventoryItemTexture("player", 17)
        buff.texture:SetTexture(tex)
        if not tex then pfUI.buff.wepbuffs.pendingRetry = true end
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 17) or 1))
      end

    elseif buff.np_texture then
      -- Nampower aura data (set by IterBuffs/IterDebuffs in OnEvent)
      buff.mode = buff.btype
      buff.texture:SetTexture(buff.np_texture)

      if buff.btype == "HARMFUL" then
        local dtype = buff.np_dtype
        if dtype == "Magic" then
          buff.backdrop:SetBackdropBorderColor(0,1,1,1)
        elseif dtype == "Poison" then
          buff.backdrop:SetBackdropBorderColor(0,1,0,1)
        elseif dtype == "Curse" then
          buff.backdrop:SetBackdropBorderColor(1,0,1,1)
        elseif dtype == "Disease" then
          buff.backdrop:SetBackdropBorderColor(1,1,0,1)
        else
          buff.backdrop:SetBackdropBorderColor(1,0,0,1)
        end
      else
        buff.backdrop:SetBackdropBorderColor(br,bg,bb,ba)
      end
    else
      buff:Hide()
      return
    end

    buff:Show()
  end

  -- ============================================================================
  -- CreateBuffButton: Frame creation with Nampower tooltip and cancel
  -- ============================================================================
  local function CreateBuffButton(i, btype, weapon)
    local buttonName, buttonParent
    if btype == "HELPFUL" then
      if weapon == 1 then
        buttonName = "pfWepBuffFrame" .. i
        buttonParent = pfUI.buff.wepbuffs
      else
        buttonName = "pfBuffFrameBuff" .. i
        buttonParent = pfUI.buff.buffs
      end
    else
      buttonName = "pfDebuffFrameBuff" .. i
      buttonParent = pfUI.buff.debuffs
    end
    local buff = CreateFrame("Button", buttonName, buttonParent)
    buff.texture = buff:CreateTexture("BuffIcon" .. i, "BACKGROUND")
    buff.texture:SetTexCoord(.07,.93,.07,.93)
    buff.texture:SetAllPoints(buff)

    buff.timer = buff:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buff.timer:SetTextColor(1,1,1,1)
    buff.timer:SetJustifyH("CENTER")
    buff.timer:SetJustifyV("CENTER")

    buff.stacks = buff:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buff.stacks:SetTextColor(1,1,1,1)
    buff.stacks:SetJustifyH("RIGHT")
    buff.stacks:SetJustifyV("BOTTOM")
    buff.stacks:SetAllPoints(buff)

    buff:RegisterForClicks("RightButtonUp")

    buff.weapon = weapon
    buff.btype = btype
    buff.gid = i

    -- Tooltip
    buff:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if this.mode == "MAINHAND" then
        GameTooltip:SetInventoryItem("player", 16)
      elseif this.mode == "OFFHAND" then
        GameTooltip:SetInventoryItem("player", 17)
      elseif this.np_spellId and pfUI.api.libtooltip and pfUI.api.libtooltip.SetSpellByID then
        -- Nampower only: build tooltip from SpellRec data
        local remaining = 0
        if this.np_auraSlot and this.np_auraSlot == -1 then
          -- Overflow buff
          if this.np_startTime and this.np_duration then
            remaining = (this.np_startTime + this.np_duration) - GetTime()
          end
        elseif this.np_auraSlot and GetPlayerAuraDuration
            and not (pfUI.libdebuff_forced_no_timer and pfUI.libdebuff_forced_no_timer[this.np_spellId]) then
          local durSpellId, remainingMs = GetPlayerAuraDuration(this.np_auraSlot - 1)
          if durSpellId == this.np_spellId and remainingMs and remainingMs > 0 then
            remaining = remainingMs / 1000
          end
        end
        pfUI.api.libtooltip:SetSpellByID(GameTooltip, this.np_spellId, remaining, this.np_dtype, this.btype)
      elseif this.np_spellName then
        GameTooltip:AddLine(this.np_spellName, 1, 1, 1)
        GameTooltip:Show()

        -- Shift: show unbuffed raid/party members
        if IsShiftKeyDown() and this.np_texture then
          local playerlist = ""
          local first = true

          if UnitInRaid("player") then
            for ri=1,40 do
              local unitstr = "raid" .. ri
              if not UnitHasBuff(unitstr, this.np_texture) and UnitName(unitstr) then
                playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
                first = nil
              end
            end
          else
            if not UnitHasBuff("player", this.np_texture) then
              playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor("player") .. UnitName("player") .. "|r"
              first = nil
            end
            for pi=1,4 do
              local unitstr = "party" .. pi
              if not UnitHasBuff(unitstr, this.np_texture) and UnitName(unitstr) then
                playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
                first = nil
              end
            end
          end

          if strlen(playerlist) > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(T["Unbuffed"] .. ":", .3, 1, .8)
            GameTooltip:AddLine(playerlist,1,1,1,1)
            GameTooltip:Show()
          end
        end
      end
    end)

    buff:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Cancel
    buff:SetScript("OnClick", function()
      if CancelItemTempEnchantment and this.mode and this.mode == "MAINHAND" then
        CancelItemTempEnchantment(1)
      elseif CancelItemTempEnchantment and this.mode and this.mode == "OFFHAND" then
        CancelItemTempEnchantment(2)
      elseif this.np_spellId and CancelPlayerAuraSpellId then
        -- ignoreMissing=1 required for overflow buffs (no client aura slot)
        CancelPlayerAuraSpellId(this.np_spellId, 1)
        -- Remove from overflow tracking if it was an overflow buff
        if this.np_auraSlot == -1 and pfUI.libdebuff_overflow_buffs then
          pfUI.libdebuff_overflow_buffs[this.np_spellId] = nil
          -- Refresh buff.lua display
          if pfUI.buff and pfUI.buff:GetScript("OnEvent") then
            pfUI.buff:GetScript("OnEvent")()
          end
          -- Refresh player unitframe
          local pfPlayer = pfUI.uf and pfUI.uf.player
          if pfPlayer then
            pfPlayer.update_aura = true
          end
        end
      end
    end)

    RefreshBuffButton(buff)

    return buff
  end

  -- ============================================================================
  -- Main frame, events
  -- ============================================================================
  pfUI.buff = CreateFrame("Frame", "pfGlobalBuffFrame", UIParent)
  pfUI.buff:RegisterEvent("PLAYER_AURAS_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_INVENTORY_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_MODEL_CHANGED")
  pfUI.buff:SetScript("OnEvent", function()
    -- UNIT_MODEL_CHANGED fires for every unit nearby, only care about player
    if event == "UNIT_MODEL_CHANGED" and arg1 ~= "player" then return end

    if C.buffs.weapons == "1" then
      local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
      pfUI.buff.wepbuffs.count = (mh and 1 or 0) + (oh and 1 or 0)
    else
      pfUI.buff.wepbuffs.count = 0
    end

    -- Clear Nampower data on all buttons
    for i=1,table.getn(pfUI.buff.buffs.buttons) do
      local btn = pfUI.buff.buffs.buttons[i]
      if btn then
        btn.np_texture = nil
        btn.np_spellName = nil
        btn.np_spellId = nil
        btn.np_auraSlot = nil
        btn.np_dtype = nil
        btn.np_startTime = nil
        btn.np_duration = nil
      end
    end
    for i=1,table.getn(pfUI.buff.debuffs.buttons) do
      local btn = pfUI.buff.debuffs.buttons[i]
      if btn then
        btn.np_texture = nil
        btn.np_spellName = nil
        btn.np_spellId = nil
        btn.np_auraSlot = nil
        btn.np_dtype = nil
      end
    end

    -- Fill buff buttons from IterBuffs
    if libdebuff and libdebuff.IterBuffs then
      local buffIdx = (C.buffs.weapons == "1" and C.buffs.separateweapons == "0") and pfUI.buff.wepbuffs.count or 0
      libdebuff:IterBuffs("player", function(auraSlot, spellId, spellName, tex, stacks, timeleft, duration)
        buffIdx = buffIdx + 1
        local btn = pfUI.buff.buffs.buttons[buffIdx]
        if not btn then return end
        btn.np_texture = tex
        btn.np_spellName = spellName
        btn.np_spellId = spellId
        btn.np_auraSlot = auraSlot
        -- Overflow buffs: store timer data for OnUpdate
        if auraSlot == -1 and timeleft and duration then
          btn.np_startTime = GetTime() + timeleft - duration
          btn.np_duration = duration
        else
          btn.np_startTime = nil
          btn.np_duration = nil
        end
      end)
    end

    -- Fill debuff buttons from IterDebuffs
    if libdebuff and libdebuff.IterDebuffs then
      local debuffIdx = 0
      libdebuff:IterDebuffs("player", function(auraSlot, spellId, spellName, tex, stacks, dtype, duration, timeleft, caster, isOurs)
        debuffIdx = debuffIdx + 1
        local btn = pfUI.buff.debuffs.buttons[debuffIdx]
        if not btn then return end
        btn.np_texture = tex
        btn.np_spellName = spellName
        btn.np_spellId = spellId
        btn.np_auraSlot = auraSlot
        btn.np_dtype = dtype
      end)
    end

    -- Refresh display
    for i=1,table.getn(pfUI.buff.buffs.buttons) do
      if pfUI.buff.buffs.buttons[i] then RefreshBuffButton(pfUI.buff.buffs.buttons[i]) end
    end
    for i=1,table.getn(pfUI.buff.debuffs.buttons) do
      if pfUI.buff.debuffs.buttons[i] then RefreshBuffButton(pfUI.buff.debuffs.buttons[i]) end
    end
    if C.buffs.separateweapons == "1" then
      for i=1,2 do
        RefreshBuffButton(pfUI.buff.wepbuffs.buttons[i])
      end
    end

    -- If weapon icon textures were nil (e.g. after /reload), schedule a retry
    if pfUI.buff.wepbuffs.pendingRetry then
      pfUI.buff.wepbuffs.pendingRetry = nil
      pfUI.buff.wepbuffs.retryAt = GetTime() + 0.5
    end
  end)

  -- ============================================================================
  -- Consolidated OnUpdate: timers via GetPlayerAuraDuration
  -- ============================================================================
  pfUI.buff:SetScript("OnUpdate", function()
    local now = GetTime()

    -- Retry weapon icon textures that were nil on initial load (e.g. after /reload)
    if pfUI.buff.wepbuffs.retryAt and now >= pfUI.buff.wepbuffs.retryAt then
      pfUI.buff.wepbuffs.retryAt = nil
      if C.buffs.separateweapons == "1" then
        for i=1,2 do
          if pfUI.buff.wepbuffs.buttons[i] then RefreshBuffButton(pfUI.buff.wepbuffs.buttons[i]) end
        end
      else
        for i=1,pfUI.buff.wepbuffs.count do
          if pfUI.buff.buffs.buttons[i] then RefreshBuffButton(pfUI.buff.buffs.buttons[i]) end
        end
      end
    end

    if not this.nextUpdate then this.nextUpdate = now + 0.1 end
    if this.nextUpdate > now then return end
    this.nextUpdate = now + 0.1

    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
    local playerGuid = GetUnitGUID and GetUnitGUID("player")
    local auraApps = playerGuid and GetUnitField and GetUnitField(playerGuid, "auraApplications")

    -- Buff timers
    local buttons = pfUI.buff.buffs.buttons
    for i = 1, table.getn(pfUI.buff.buffs.buttons) do
      local buff = buttons[i]
      if buff and buff:IsShown() then
        local timeleft, stacks = 0, 0
        if buff.mode == "MAINHAND" then
          timeleft = mhtime and mhtime / 1000 or 0
          stacks = mhcharge or 0
        elseif buff.mode == "OFFHAND" then
          timeleft = ohtime and ohtime / 1000 or 0
          stacks = ohcharge or 0
        elseif buff.np_auraSlot and buff.np_auraSlot == -1 then
          -- Overflow buff: use stored timestamp + duration
          if buff.np_startTime and buff.np_duration then
            timeleft = (buff.np_startTime + buff.np_duration) - now
            if timeleft <= 0 then
              timeleft = 0
              -- Expired: remove from overflow tracking
              if buff.np_spellId and pfUI.libdebuff_overflow_buffs then
                pfUI.libdebuff_overflow_buffs[buff.np_spellId] = nil
              end
              buff:Hide()
              -- Trigger full refresh so remaining overflow buffs shift forward,
              -- same as what happens when an overflow buff is right-clicked
              if pfUI.buff and pfUI.buff:GetScript("OnEvent") then
                pfUI.buff:GetScript("OnEvent")()
              end
            end
          end
        elseif buff.np_auraSlot and buff.np_spellId and GetPlayerAuraDuration
            and not (pfUI.libdebuff_forced_no_timer and pfUI.libdebuff_forced_no_timer[buff.np_spellId]) then
          local durSpellId, remainingMs = GetPlayerAuraDuration(buff.np_auraSlot - 1)
          if durSpellId == buff.np_spellId and remainingMs and remainingMs > 0 then
            timeleft = remainingMs / 1000
          end
          if auraApps and auraApps[buff.np_auraSlot] then
            stacks = auraApps[buff.np_auraSlot] + 1
          end
        end
        buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText(stacks > 1 and stacks or "")
      end
    end

    -- Debuff timers
    buttons = pfUI.buff.debuffs.buttons
    for i = 1, table.getn(pfUI.buff.debuffs.buttons) do
      local buff = buttons[i]
      if buff and buff:IsShown() then
        local timeleft, stacks = 0, 0
        if buff.np_auraSlot and buff.np_spellId and GetPlayerAuraDuration
            and not (pfUI.libdebuff_forced_no_timer and pfUI.libdebuff_forced_no_timer[buff.np_spellId]) then
          local durSpellId, remainingMs = GetPlayerAuraDuration(buff.np_auraSlot - 1)
          if durSpellId == buff.np_spellId and remainingMs and remainingMs > 0 then
            timeleft = remainingMs / 1000
          end
          if auraApps and auraApps[buff.np_auraSlot] then
            stacks = auraApps[buff.np_auraSlot] + 1
          end
        end
        buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText(stacks > 1 and stacks or "")
      end
    end

    -- Weapon buff timers
    if C.buffs.separateweapons == "1" then
      buttons = pfUI.buff.wepbuffs.buttons
      for i = 1, 2 do
        local buff = buttons[i]
        if buff:IsShown() then
          local timeleft, stacks = 0, 0
          if buff.mode == "MAINHAND" then
            timeleft = mhtime and mhtime / 1000 or 0
            stacks = mhcharge or 0
          elseif buff.mode == "OFFHAND" then
            timeleft = ohtime and ohtime / 1000 or 0
            stacks = ohcharge or 0
          end
          buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText(stacks > 1 and stacks or "")
        end
      end
    end
  end)

  -- ============================================================================
  -- Weapon Buffs
  -- ============================================================================
  pfUI.buff.wepbuffs = CreateFrame("Frame", "pfWepBuffFrame", UIParent)
  pfUI.buff.wepbuffs.count = 0
  pfUI.buff.wepbuffs.buttons = {}
  for i=1,2 do
    pfUI.buff.wepbuffs.buttons[i] = CreateBuffButton(i, "HELPFUL", 1)
  end

  -- Buff Frame
  pfUI.buff.buffs = CreateFrame("Frame", "pfBuffFrame", UIParent)
  pfUI.buff.buffs.buttons = {}
  if C.buffs.buffs == "1" then
    local maxBuffs = (C.buffs.showoverflow == "1") and 48 or 32
    for i=1,maxBuffs do
      pfUI.buff.buffs.buttons[i] = CreateBuffButton(i, "HELPFUL")
    end
  else
    pfUI.buff.buffs:Hide()
  end

  -- Debuffs
  pfUI.buff.debuffs = CreateFrame("Frame", "pfDebuffFrame", UIParent)
  pfUI.buff.debuffs.buttons = {}
  if C.buffs.debuffs == "1" then
    local maxDebuffs = (C.buffs.showspillover == "1") and 32 or 16
    for i=1,maxDebuffs do
      pfUI.buff.debuffs.buttons[i] = CreateBuffButton(i, "HARMFUL")
    end
  else
    pfUI.buff.debuffs:Hide()
  end

  -- ============================================================================
  -- Config loading (unchanged)
  -- ============================================================================
  function pfUI.buff:UpdateConfigBuffButton(buff)
    local fontsize = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
    local rowcount, relFrame, offsetX, offsetY
    if buff.btype == "HELPFUL" then
      if buff.weapon == 1 and C.buffs.separateweapons == "1" then
        rowcount = floor((buff.gid-1) / tonumber(C.buffs.wepbuffrowsize))
        relFrame = pfUI.buff.wepbuffs
        offsetX = -(buff.gid-1-rowcount*tonumber(C.buffs.wepbuffrowsize))*(tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
        offsetY = -(rowcount) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
      else
        rowcount = floor((buff.gid-1) / tonumber(C.buffs.buffrowsize))
        relFrame = pfUI.buff.buffs
        offsetX = -(buff.gid-1-rowcount*tonumber(C.buffs.buffrowsize))*(tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
        offsetY = -(rowcount) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
      end
    else
      rowcount = floor((buff.gid-1) / tonumber(C.buffs.debuffrowsize))
      relFrame = pfUI.buff.debuffs
      offsetX = -(buff.gid-1-rowcount*tonumber(C.buffs.debuffrowsize))*(tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
      offsetY = -(rowcount) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing))
    end

    buff:SetWidth(tonumber(C.buffs.size))
    buff:SetHeight(tonumber(C.buffs.size))
    buff:ClearAllPoints()
    buff:SetPoint("TOPRIGHT", relFrame, "TOPRIGHT",offsetX, offsetY)

    buff.timer:SetFont(pfUI.font_default, fontsize, "OUTLINE")
    buff.stacks:SetFont(pfUI.font_default, fontsize+1, "OUTLINE")

    buff.timer:SetHeight(fontsize * 1.3)

    buff.timer:ClearAllPoints()
    if C.buffs.textinside == "1" then
      buff.timer:SetAllPoints(buff)
    else
      buff.timer:SetPoint("TOP", buff, "BOTTOM", 0, -3)
    end
  end

  function pfUI.buff:UpdateConfig()
    local fontsize = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize

    pfUI.buff.buffs:SetWidth(tonumber(C.buffs.buffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.buffs:SetHeight(ceil(48/tonumber(C.buffs.buffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.buffs:SetPoint("TOPRIGHT", pfUI.minimap or UIParent, "TOPLEFT", -4*tonumber(C.buffs.spacing), 0)
    UpdateMovable(pfUI.buff.buffs)

    pfUI.buff.debuffs:SetWidth(tonumber(C.buffs.debuffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.debuffs:SetHeight(ceil(16/tonumber(C.buffs.debuffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.debuffs:SetPoint("TOPRIGHT", pfUI.buff.buffs, "BOTTOMRIGHT", 0, 0)
    UpdateMovable(pfUI.buff.debuffs)

    if C.buffs.separateweapons == "1" then
      pfUI.buff.wepbuffs:ClearAllPoints()
      pfUI.buff.wepbuffs:SetWidth(tonumber(C.buffs.wepbuffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
      pfUI.buff.wepbuffs:SetHeight(ceil(2/tonumber(C.buffs.wepbuffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
      pfUI.buff.wepbuffs:SetPoint("TOPRIGHT", pfUI.buff.debuffs, "BOTTOMRIGHT", 0, 0)
      pfUI.buff.wepbuffs:Show()
      UpdateMovable(pfUI.buff.wepbuffs)
    else
      pfUI.buff.wepbuffs:Hide()
      RemoveMovable(pfUI.buff.wepbuffs)
    end

    for i=1,table.getn(pfUI.buff.buffs.buttons) do
      if pfUI.buff.buffs.buttons[i] then pfUI.buff:UpdateConfigBuffButton(pfUI.buff.buffs.buttons[i]) end
    end

    for i=1,table.getn(pfUI.buff.debuffs.buttons) do
      if pfUI.buff.debuffs.buttons[i] then pfUI.buff:UpdateConfigBuffButton(pfUI.buff.debuffs.buttons[i]) end
    end

    for i=1,2 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.wepbuffs.buttons[i])
    end

    pfUI.buff:GetScript("OnEvent")()
  end

  pfUI.buff:UpdateConfig()
end)