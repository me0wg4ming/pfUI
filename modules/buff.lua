pfUI:RegisterModule("buff", "vanilla:tbc", function ()
  -- Hide Blizz
  BuffFrame:Hide()
  BuffFrame:UnregisterAllEvents()
  TemporaryEnchantFrame:Hide()
  TemporaryEnchantFrame:UnregisterAllEvents()

  local br, bg, bb, ba = GetStringColor(pfUI_config.appearance.border.color)

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
    
    -- NEW: Use GetUnitField + sorted slots to find correct buff/debuff
    local useNampower = false
    local targetSlot = nil
    local spellId = nil
    
    if GetUnitField and UnitExists then
      local _, guid = UnitExists("player")
      local auras = guid and GetUnitField(guid, "aura")
      
      if auras then
        -- Collect occupied slots based on buff type
        local occupiedSlots = {}
        local startSlot, endSlot
        
        if buff.btype == "HELPFUL" then
          -- Buffs: slots 1-32
          startSlot, endSlot = 1, 32
        else
          -- Debuffs: slots 33-48
          startSlot, endSlot = 33, 48
        end
        
        for fieldSlot = startSlot, endSlot do
          local sid = auras[fieldSlot]
          if sid and sid > 0 then
            table.insert(occupiedSlots, fieldSlot)
          end
        end
        
        table.sort(occupiedSlots)
        
        -- Use buff.gid for slot lookup
        targetSlot = occupiedSlots[buff.gid]
        if targetSlot then
          spellId = auras[targetSlot]
          useNampower = true
        end
      end
    end
    
    -- Fallback: Use old Blizzard method
    if not useNampower then
      buff.bid = GetPlayerBuff(PLAYER_BUFF_START_ID+buff.id, buff.btype)
    else
      -- Store both for compatibility
      buff.targetSlot = targetSlot  -- GetUnitField slot (1-based)
      buff.spellId = spellId
      -- Also get Blizzard slot for fallback
      buff.bid = GetPlayerBuff(PLAYER_BUFF_START_ID+buff.id, buff.btype)
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
    elseif useNampower and spellId and libdebuff and libdebuff.GetSpellIcon and (( buff.btype == "HARMFUL" and C.buffs.debuffs == "1" ) or ( buff.btype == "HELPFUL" and C.buffs.buffs == "1" )) then
      -- NEW: Use libdebuff icon for correct display
      buff.mode = buff.btype
      local texture = libdebuff:GetSpellIcon(spellId)
      buff.texture:SetTexture(texture)

      if buff.btype == "HARMFUL" and GetSpellRec then
        -- Get dispel type from SpellRec
        local spellRec = GetSpellRec(spellId)
        if spellRec and spellRec.dispel then
          local dispelTypes = {
            [0] = "none",
            [1] = "Magic",
            [2] = "Curse", 
            [3] = "Disease",
            [4] = "Poison"
          }
          local dtype = dispelTypes[spellRec.dispel] or "none"
          
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
          buff.backdrop:SetBackdropBorderColor(1,0,0,1)
        end
      else
        buff.backdrop:SetBackdropBorderColor(br,bg,bb,ba)
      end
    elseif GetPlayerBuffTexture(buff.bid) and (( buff.btype == "HARMFUL" and C.buffs.debuffs == "1" ) or ( buff.btype == "HELPFUL" and C.buffs.buffs == "1" )) then
      -- Set Buff Texture and Border
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
      -- Fallback: try UnitBuff/UnitDebuff API which may be more reliable in some cases
      local fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId
      local maxSlots = buff.btype == "HELPFUL" and 32 or 16

      if buff.id >= 1 and buff.id <= maxSlots then
        if buff.btype == "HELPFUL" and C.buffs.buffs == "1" then
          for i = 1, maxSlots do
            local tex, stacks, dtype, spellId = UnitBuff("player", i)
            if tex and i == buff.id then
              fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId = tex, stacks, dtype, spellId
              break
            end
            if not tex then break end
          end
        elseif buff.btype == "HARMFUL" and C.buffs.debuffs == "1" then
          for i = 1, maxSlots do
            local tex, stacks, dtype, spellId = UnitDebuff("player", i)
            if tex and i == buff.id then
              fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId = tex, stacks, dtype, spellId
              break
            end
            if not tex then break end
          end
        end
      end

      if fallbackTexture then
        buff.mode = buff.btype
        buff.fallbackSpellId = fallbackSpellId
        buff.texture:SetTexture(fallbackTexture)
        if buff.btype == "HARMFUL" then
          if fallbackDispelType == "Magic" then
            buff.backdrop:SetBackdropBorderColor(0,1,1,1)
          elseif fallbackDispelType == "Poison" then
            buff.backdrop:SetBackdropBorderColor(0,1,0,1)
          elseif fallbackDispelType == "Curse" then
            buff.backdrop:SetBackdropBorderColor(1,0,1,1)
          elseif fallbackDispelType == "Disease" then
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

    -- PERF: OnUpdate moved to consolidated parent frame handler (see pfUI.buff:SetScript("OnUpdate"))
    -- Individual buff frames no longer have their own OnUpdate

    buff:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if this.mode == this.btype then
        -- NEW: Use GetSpellRec if we have spellId from Nampower
        if this.spellId and GetSpellRec then
          local spellRec = GetSpellRec(this.spellId)
          if spellRec then
            GameTooltip:AddLine(spellRec.name, 1, 1, 1)
            if spellRec.rank and spellRec.rank ~= "" then
              GameTooltip:AddLine(spellRec.rank, 0.5, 0.5, 0.5)
            end
            
            local tooltipText = spellRec.tooltip or spellRec.description or ""
            if tooltipText ~= "" then
              -- Cross-spell references ($12345s1, $12345d1)
              local crossRefs = {}
              for refSpellId, valueType, index in string.gfind(tooltipText, "%$(%d+)([sd])(%d)") do
                local refId = tonumber(refSpellId)
                local idx = tonumber(index)
                
                if not crossRefs[refId] then
                  crossRefs[refId] = GetSpellRec(refId)
                end
                
                if crossRefs[refId] then
                  local placeholder = "$" .. refSpellId .. valueType .. index
                  local value = nil
                  
                  if valueType == "s" then
                    if crossRefs[refId].effectBasePoints and crossRefs[refId].effectBasePoints[idx] then
                      value = crossRefs[refId].effectBasePoints[idx] + 1
                    end
                  elseif valueType == "d" then
                    local durationIndex = crossRefs[refId].durationIndex
                    local durationTable = {
                      [1] = 10, [3] = 30, [6] = 60, [8] = 120, [9] = 180,
                      [10] = 300, [11] = 600, [21] = 3, [23] = 5, [27] = 15
                    }
                    value = durationTable[durationIndex]
                  end
                  
                  if value then
                    tooltipText = string.gsub(tooltipText, placeholder, value)
                  end
                end
              end
              
              -- Standard placeholders ($s1, $S1, etc.)
              if spellRec.effectBasePoints then
                for i, basePoint in ipairs(spellRec.effectBasePoints) do
                  local value = basePoint + 1
                  tooltipText = string.gsub(tooltipText, "%$s" .. i, value)
                  tooltipText = string.gsub(tooltipText, "%$S" .. i, value)
                end
              end
              
              -- Duration placeholder
              if spellRec.durationIndex then
                local durationTable = {
                  [1] = 10, [3] = 30, [6] = 60, [8] = 120, [9] = 180,
                  [10] = 300, [11] = 600, [21] = 3, [23] = 5, [27] = 15
                }
                local durationValue = durationTable[spellRec.durationIndex]
                if durationValue then
                  tooltipText = string.gsub(tooltipText, "%$d", durationValue)
                end
              end
              
              GameTooltip:AddLine(tooltipText, 1, 0.82, 0, 1)
            end
            GameTooltip:Show()
          else
            -- Fallback to Blizzard
            GameTooltip:SetPlayerBuff(this.bid)
          end
        else
          -- Fallback to Blizzard
          GameTooltip:SetPlayerBuff(this.bid)
        end

        if IsShiftKeyDown() then
          -- NEW: Use libdebuff icon if available
          local texture
          if this.spellId and libdebuff and libdebuff.GetSpellIcon then
            texture = libdebuff:GetSpellIcon(this.spellId)
          else
            texture = GetPlayerBuffTexture(this.bid)
          end

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
        -- Use GetPlayerBuffID to find and cancel by SpellID
        -- This method works correctly even after slot shifts
        if this.spellId and GetPlayerBuffID then
          local ix = 0
          while true do
            local blizzSlot = GetPlayerBuff(ix, this.btype)
            if blizzSlot == -1 then break end
            
            -- Get SpellID from this Blizzard slot
            local buffSpellId = GetPlayerBuffID(blizzSlot)
            -- Handle negative SpellIDs (convert to positive)
            buffSpellId = (buffSpellId < -1) and (buffSpellId + 65536) or buffSpellId
            
            if buffSpellId == this.spellId then
              CancelPlayerBuff(blizzSlot)
              return
            end
            
            ix = ix + 1
            
            -- Safety: Don't loop forever
            if ix > 32 then break end
          end
        else
          -- Fallback if GetPlayerBuffID not available
          CancelPlayerBuff(this.gid - 1)
        end
      end
    end)

    RefreshBuffButton(buff)

    return buff
  end

  local function GetNumBuffs()
    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
    local offset = (mh and 1 or 0) + (oh and 1 or 0)

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
  -- This replaces 50 individual OnUpdate handlers with a single one
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
        local timeleft, stacks = 0, 0
        if buff.mode == buff.btype then
          -- NEW: Use GetPlayerAuraDuration if we have targetSlot
          if buff.targetSlot and GetPlayerAuraDuration then
            local durationSpellId, durationMs = GetPlayerAuraDuration(buff.targetSlot - 1)
            if durationSpellId and durationMs and durationMs > 0 then
              timeleft = durationMs / 1000
            end
            -- Get stacks from GetUnitField
            if GetUnitField and UnitExists then
              local _, guid = UnitExists("player")
              if guid then
                local auraApplications = GetUnitField(guid, "auraApplications")
                stacks = (auraApplications and auraApplications[buff.targetSlot]) or 0
              end
            end
          else
            -- Fallback
            timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
            stacks = GetPlayerBuffApplications(buff.bid, buff.btype)
          end
        elseif buff.mode == "MAINHAND" then
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

    -- Update all visible debuff buttons
    buttons = pfUI.buff.debuffs.buttons
    for i = 1, 16 do
      local buff = buttons[i]
      if buff:IsShown() then
        local timeleft, stacks = 0, 0
        -- NEW: Use GetPlayerAuraDuration if we have targetSlot
        if buff.targetSlot and GetPlayerAuraDuration then
          local durationSpellId, durationMs = GetPlayerAuraDuration(buff.targetSlot - 1)
          if durationSpellId and durationMs and durationMs > 0 then
            timeleft = durationMs / 1000
          end
          -- Get stacks from GetUnitField
          if GetUnitField and UnitExists then
            local _, guid = UnitExists("player")
            if guid then
              local auraApplications = GetUnitField(guid, "auraApplications")
              stacks = (auraApplications and auraApplications[buff.targetSlot]) or 0
            end
          end
        else
          -- Fallback
          timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
          stacks = GetPlayerBuffApplications(buff.bid, buff.btype)
        end
        buff.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText(stacks > 1 and stacks or "")
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