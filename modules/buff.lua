pfUI:RegisterModule("buff", "vanilla:tbc", function ()
  -- Hide Blizz
  BuffFrame:Hide()
  BuffFrame:UnregisterAllEvents()
  TemporaryEnchantFrame:Hide()
  TemporaryEnchantFrame:UnregisterAllEvents()

  local br, bg, bb, ba = GetStringColor(pfUI_config.appearance.border.color)

  -- ============================================================================
  -- Nampower detection
  -- ============================================================================
  local hasNampower = GetNampowerVersion and GetUnitField and GetPlayerAuraDuration and true or false
  local libdebuff = pfUI.api.libdebuff

  -- ============================================================================
  -- CORE: RefreshBuffButton
  -- Uses Nampower GetPlayerBuffSlotMap/GetPlayerDebuffSlotMap when available,
  -- falls back to Blizzard GetPlayerBuff API otherwise.
  -- ============================================================================

  local function RefreshBuffButton(buff)
    if buff.btype == "HELPFUL" then
      if C.buffs.separateweapons == "1" then
        buff.id = buff.gid - (buff.weapon ~= nill and buff.gid or 0)
      else
        buff.id = buff.gid - pfUI.buff.wepbuffs.count
      end
    else
      buff.id = buff.gid
    end

    if not buff.backdrop then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
    end

    --detect weapon buffs
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

      -- Set Weapon Texture and Border
      if buff.mode == "MAINHAND" then
        buff.texture:SetTexture(GetInventoryItemTexture("player", 16))
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 16) or 1))
      elseif buff.mode == "OFFHAND" then
        buff.texture:SetTexture(GetInventoryItemTexture("player", 17))
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 17) or 1))
      end

    -- ====== Nampower path: Use slot maps for stable ordering ======
    elseif hasNampower and libdebuff then
      local slotMap, entry
      if buff.btype == "HELPFUL" and C.buffs.buffs == "1" then
        slotMap = libdebuff.GetPlayerBuffSlotMap and libdebuff.GetPlayerBuffSlotMap()
        if slotMap then entry = slotMap[buff.id] end
      elseif buff.btype == "HARMFUL" and C.buffs.debuffs == "1" then
        slotMap = libdebuff.GetPlayerDebuffSlotMap and libdebuff.GetPlayerDebuffSlotMap()
        if slotMap then entry = slotMap[buff.id] end
      end

      if entry then
        buff.mode = buff.btype
        buff.texture:SetTexture(entry.texture)
        buff.spellid = entry.spellId
        buff.np_entry = entry  -- Store full entry for timer/tooltip access

        if buff.btype == "HARMFUL" then
          local dtype = entry.dtype
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

    -- ====== Fallback: Blizzard GetPlayerBuff API ======
    else
      buff.bid = GetPlayerBuff(PLAYER_BUFF_START_ID+buff.id, buff.btype)
      buff.spellid = GetPlayerBuffID and buff.bid and GetPlayerBuffID(buff.bid) or nil

      if GetPlayerBuffTexture(buff.bid) and (( buff.btype == "HARMFUL" and C.buffs.debuffs == "1" ) or ( buff.btype == "HELPFUL" and C.buffs.buffs == "1" )) then
        buff.mode = buff.btype
        buff.texture:SetTexture(GetPlayerBuffTexture(buff.bid))

        if buff.btype == "HARMFUL" then
          local dtype = GetPlayerBuffDispelType(buff.bid)
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
    end

    buff:Show()
  end

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

    buff:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if this.mode == this.btype then
        -- Prefer Blizzard tooltip via bid (best quality)
        if this.np_entry and this.np_entry.bid then
          GameTooltip:SetPlayerBuff(this.np_entry.bid)
        elseif this.bid then
          GameTooltip:SetPlayerBuff(this.bid)
        elseif this.spellid and GetSpellRec then
          -- Fallback: build tooltip from GetSpellRec
          local rec = GetSpellRec(this.spellid)
          if rec then
            GameTooltip:SetText(rec.name or "Unknown", 1, 1, 1)
            if rec.rank and rec.rank ~= "" then
              GameTooltip:AddLine(rec.rank, 0.5, 0.5, 0.5)
            end
            local desc = rec.tooltip or rec.description or ""
            if desc ~= "" then
              GameTooltip:AddLine(desc, 1, 0.82, 0, 1)
            end
          end
          GameTooltip:Show()
        end

        if IsShiftKeyDown() then
          local texture = nil
          if this.np_entry then
            texture = this.np_entry.texture
          elseif this.bid then
            texture = GetPlayerBuffTexture(this.bid)
          end

          if texture then
            local playerlist = ""
            local first = true

            if UnitInRaid("player") then
              for i=1,40 do
                local unitstr = "raid" .. i
                if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
                  playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
                  first = nil
                end
              end
            else
              if not UnitHasBuff("player", texture) then
                playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor("player") .. UnitName("player") .. "|r"
                first = nil
              end

              for i=1,4 do
                local unitstr = "party" .. i
                if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
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
      elseif this.mode == "MAINHAND" then
        GameTooltip:SetInventoryItem("player", 16)
      elseif this.mode == "OFFHAND" then
        GameTooltip:SetInventoryItem("player", 17)
      end
    end)

    buff:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    buff:SetScript("OnClick", function()
      if CancelItemTempEnchantment and this.mode and this.mode == "MAINHAND" then
        CancelItemTempEnchantment(1)
      elseif CancelItemTempEnchantment and this.mode and this.mode == "OFFHAND" then
        CancelItemTempEnchantment(2)
      else
        if CancelPlayerAuraSpellId and this.spellid then
          CancelPlayerAuraSpellId(this.spellid)
        elseif this.bid then
          CancelPlayerBuff(this.bid)
        end
      end
    end)

    RefreshBuffButton(buff)

    return buff
  end

  local function GetNumBuffs()
    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
    local offset = (mh and 1 or 0) + (oh and 1 or 0)

    if hasNampower and libdebuff and libdebuff.GetPlayerBuffSlotMap then
      local buffMap = libdebuff.GetPlayerBuffSlotMap()
      if buffMap then
        return (buffMap.count or 0) + offset
      end
    end

    -- Fallback: Blizzard API
    for i=1,32 do
      local bid, untilCancelled = GetPlayerBuff(PLAYER_BUFF_START_ID+i, "HELPFUL")
      if bid < 0 then
        return i - 1 + offset
      end
    end
    return 0 + offset
  end

  pfUI.buff = CreateFrame("Frame", "pfGlobalBuffFrame", UIParent)
  pfUI.buff:RegisterEvent("PLAYER_AURAS_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_INVENTORY_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_MODEL_CHANGED")
  pfUI.buff:SetScript("OnEvent", function()
    -- Invalidate Nampower player slot map cache on aura change
    if hasNampower and libdebuff and libdebuff.InvalidatePlayerSlotMapCache then
      libdebuff.InvalidatePlayerSlotMapCache()
    end

    if C.buffs.weapons == "1" then
      local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
      pfUI.buff.wepbuffs.count = (mh and 1 or 0) + (oh and 1 or 0)
    else
      pfUI.buff.wepbuffs.count = 0
    end

    for i=1,32 do
      RefreshBuffButton(pfUI.buff.buffs.buttons[i])
    end

    for i=1,16 do
      RefreshBuffButton(pfUI.buff.debuffs.buttons[i])
    end

    if C.buffs.separateweapons == "1" then
      for i=1,2 do
        RefreshBuffButton(pfUI.buff.wepbuffs.buttons[i])
      end
    end
  end)

  -- PERF: Consolidated OnUpdate handler for all buff timers
  pfUI.buff:SetScript("OnUpdate", function()
    local now = GetTime()
    if not this.nextUpdate then this.nextUpdate = now + 0.1 end
    if this.nextUpdate > now then return end
    this.nextUpdate = now + 0.1

    -- Cache weapon enchant info once per update cycle
    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()

    -- Update all visible buff buttons
    local buttons = pfUI.buff.buffs.buttons
    for i = 1, 32 do
      local buff = buttons[i]
      if buff:IsShown() then
        local timeleft, stackCount = 0, 0
        if buff.mode == "MAINHAND" then
          timeleft = mhtime and mhtime / 1000 or 0
          stackCount = mhcharge or 0
        elseif buff.mode == "OFFHAND" then
          timeleft = ohtime and ohtime / 1000 or 0
          stackCount = ohcharge or 0
        elseif buff.mode == buff.btype then
          -- Nampower: re-read live timer from slot map
          if hasNampower and libdebuff and libdebuff.GetPlayerBuffSlotMap then
            local buffMap = libdebuff.GetPlayerBuffSlotMap()
            local entry = buffMap and buffMap[buff.id]
            if entry then
              timeleft = entry.timeleft or 0
              stackCount = entry.stacks or 0
            end
          elseif buff.bid then
            -- Fallback: Blizzard API
            timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
            stackCount = GetPlayerBuffApplications(buff.bid, buff.btype)
          end
        end
        buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText(stackCount > 1 and stackCount or "")
      end
    end

    -- Update all visible debuff buttons
    buttons = pfUI.buff.debuffs.buttons
    for i = 1, 16 do
      local buff = buttons[i]
      if buff:IsShown() then
        local timeleft, stackCount = 0, 0
        if buff.mode == buff.btype then
          -- Nampower: re-read live timer from slot map
          if hasNampower and libdebuff and libdebuff.GetPlayerDebuffSlotMap then
            local debuffMap = libdebuff.GetPlayerDebuffSlotMap()
            local entry = debuffMap and debuffMap[buff.id]
            if entry then
              timeleft = entry.timeleft or 0
              stackCount = entry.stacks or 0
            end
          elseif buff.bid then
            -- Fallback: Blizzard API
            timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
            stackCount = GetPlayerBuffApplications(buff.bid, buff.btype)
          end
        end
        buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText(stackCount > 1 and stackCount or "")
      end
    end

    -- Update weapon buff buttons if separate
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

  -- Weapon Buffs
  pfUI.buff.wepbuffs = CreateFrame("Frame", "pfWepBuffFrame", UIParent)
  pfUI.buff.wepbuffs.count = 0
  pfUI.buff.wepbuffs.buttons = {}
  for i=1,2 do
    pfUI.buff.wepbuffs.buttons[i] = CreateBuffButton(i, "HELPFUL", 1)
  end

  -- Buff Frame
  pfUI.buff.buffs = CreateFrame("Frame", "pfBuffFrame", UIParent)
  pfUI.buff.buffs.buttons = {}
  for i=1,32 do
    pfUI.buff.buffs.buttons[i] = CreateBuffButton(i, "HELPFUL")
  end

  -- Debuffs
  pfUI.buff.debuffs = CreateFrame("Frame", "pfDebuffFrame", UIParent)
  pfUI.buff.debuffs.buttons = {}
  for i=1,16 do
    pfUI.buff.debuffs.buttons[i] = CreateBuffButton(i, "HARMFUL")
  end

  -- config loading
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
    pfUI.buff.buffs:SetHeight(ceil(32/tonumber(C.buffs.buffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
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

    for i=1,32 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.buffs.buttons[i])
    end

    for i=1,16 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.debuffs.buttons[i])
    end

    for i=1,2 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.wepbuffs.buttons[i])
    end

    pfUI.buff:GetScript("OnEvent")()
  end

  pfUI.buff:UpdateConfig()
end)
