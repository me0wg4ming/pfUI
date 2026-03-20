local slots = {
  "HeadSlot",
  "NeckSlot",
  "ShoulderSlot",
  "BackSlot",
  "ChestSlot",
  "ShirtSlot",
  "TabardSlot",
  "WristSlot",
  "HandsSlot",
  "WaistSlot",
  "LegsSlot",
  "FeetSlot",
  "Finger0Slot",
  "Finger1Slot",
  "Trinket0Slot",
  "Trinket1Slot",
  "MainHandSlot",
  "SecondaryHandSlot",
  "RangedSlot",
}

pfUI:RegisterSkin("Inspect", "tbc", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  HookAddonOrVariable("Blizzard_InspectUI", function()
    CreateBackdrop(InspectFrame, nil, nil, .75)
    CreateBackdropShadow(InspectFrame)

    InspectFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
    InspectFrame.backdrop:SetPoint("BOTTOMRIGHT", -30, 72)
    InspectFrame:SetHitRectInsets(10,30,10,72)
    EnableMovable("InspectFrame", "Blizzard_InspectUI", INSPECTFRAME_SUBFRAMES)

    SkinCloseButton(InspectFrameCloseButton, InspectFrame.backdrop, -6, -6)

    InspectFrame:DisableDrawLayer("ARTWORK")

    InspectNameText:ClearAllPoints()
    InspectNameText:SetPoint("TOP", InspectFrame.backdrop, "TOP", 0, -10)
    InspectGuildText:Show()
    InspectGuildText:ClearAllPoints()
    InspectGuildText:SetPoint("TOP", InspectLevelText, "BOTTOM", 0, -1)

    for i = 1, 3 do
      local tab = _G["InspectFrameTab"..i]
      local lastTab = _G["InspectFrameTab"..(i-1)]
      tab:ClearAllPoints()
      if lastTab then
        tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
    else
        tab:SetPoint("TOPLEFT", InspectFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))
      end
      SkinTab(tab)
    end

    do -- Character Tab
      StripTextures(InspectPaperDollFrame)

      EnableClickRotate(InspectModelFrame)
      local rotL = InspectModelRotateLeftButton or InspectModelFrameRotateLeftButton
      if rotL then rotL:Hide() end
      local rotR = InspectModelRotateRightButton or InspectModelFrameRotateRightButton
      if rotR then rotR:Hide() end

      for _, slot in pairs(slots) do
        local frame = _G["Inspect"..slot]
        SkinButton(frame, nil, nil, nil, _G["Inspect"..slot.."IconTexture"], true)
      end

      hooksecurefunc("InspectPaperDollFrame_OnShow", function()
        local guild, title = GetGuildInfo(InspectFrame.unit)
        local text = guild and format(TEXT(GUILD_TITLE_TEMPLATE), title, guild) or ""
        InspectGuildText:SetText(text)
      end)

      local function RefreshTbcSlots()
        local unit = InspectFrame.unit
        local guid = unit and GetUnitGUID and GetUnitGUID(unit)
        if not guid then return end
        for _, slot in pairs(slots) do
          local btn = _G["Inspect"..slot]
          if btn then
            local slotId = btn:GetID()
            local ok, npItem = pcall(GetEquippedItem, guid, slotId)
            if not ok then npItem = nil end
            if npItem and npItem.itemId and npItem.itemId > 0 then
              local itemId = npItem.itemId
              local displayInfoId = GetItemStatsField and GetItemStatsField(itemId, "displayInfoID")
              local texName = displayInfoId and GetItemIconTexture and GetItemIconTexture(displayInfoId)
              local tex = texName and ("Interface\\Icons\\" .. texName)
              if tex then SetItemButtonTexture(btn, tex) end
              local itemStats = GetItemStats and GetItemStats(itemId)
              local quality = itemStats and itemStats.quality
              if quality and quality > 0 then
                btn:SetBackdropBorderColor(GetItemQualityColor(quality))
              else
                btn:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
              end
            else
              btn:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
            end
          end
        end
      end

      local npDelayTbc = CreateFrame("Frame")
      npDelayTbc:Hide()
      npDelayTbc.elapsed = 0
      npDelayTbc:SetScript("OnUpdate", function()
        npDelayTbc.elapsed = npDelayTbc.elapsed + arg1
        if npDelayTbc.elapsed >= 0.3 then
          npDelayTbc:Hide()
          npDelayTbc.elapsed = 0
          RefreshTbcSlots()
        end
      end)

      hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        npDelayTbc.elapsed = 0
        npDelayTbc:Show()
      end)
    end

    do -- PVP Tab
      StripTextures(InspectPVPFrame)
    end

    -- NOTE: Old "InspectTalentFrame" block removed - Turtle WoW replaced it with
    -- InspectTalentsFrame + TWTalentFrame (handled in turtle-wow.lua)
  end)
end)

pfUI:RegisterSkin("Inspect", "vanilla", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- Nampower-based range check for Inspect dropdown button
  if TargetFrameDropDown then
    local origInit = TargetFrameDropDown.initialize
    TargetFrameDropDown.initialize = function()
      local inRange = pfUI.api.librange and pfUI.api.librange:UnitInInspectRange("target")
      UnitPopupButtons["INSPECT"].dist = inRange and 0 or 1
      if origInit then origInit() end
    end
  end

  HookAddonOrVariable("Blizzard_InspectUI", function()
    InspectFrame_Show = function(unit)
      HideUIPanel(InspectFrame)
      NotifyInspect(unit)
      InspectFrame.unit = unit
      ShowUIPanel(InspectFrame)
    end

    CreateBackdrop(InspectFrame, nil, nil, .75)
    CreateBackdropShadow(InspectFrame)

    InspectFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
    InspectFrame.backdrop:SetPoint("BOTTOMRIGHT", -30, 72)
    InspectFrame:SetHitRectInsets(10,30,10,72)
    EnableMovable("InspectFrame", "Blizzard_InspectUI", INSPECTFRAME_SUBFRAMES)

    SkinCloseButton(InspectFrameCloseButton, InspectFrame.backdrop, -6, -6)

    InspectFrame:DisableDrawLayer("ARTWORK")

    InspectNameText:ClearAllPoints()
    InspectNameText:SetPoint("TOP", InspectFrame.backdrop, "TOP", 0, -10)

    -- Turtle WoW has 4 inspect tabs: Character, Honor, Arena, Talents
    for i = 1, 4 do
      local tab = _G["InspectFrameTab"..i]
      if tab then
        local lastTab = _G["InspectFrameTab"..(i-1)]
        tab:ClearAllPoints()
        if lastTab then
          tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
        else
          tab:SetPoint("TOPLEFT", InspectFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))
        end
        SkinTab(tab)
      end
    end

    do -- Character Tab
      StripTextures(InspectPaperDollFrame)

      EnableClickRotate(InspectModelFrame)
      local rotL = InspectModelRotateLeftButton or InspectModelFrameRotateLeftButton
      if rotL then rotL:Hide() end
      local rotR = InspectModelRotateRightButton or InspectModelFrameRotateRightButton
      if rotR then rotR:Hide() end

      for _, slot in pairs(slots) do
        local frame = _G["Inspect"..slot]
        StripTextures(frame)
        CreateBackdrop(frame)
        SetAllPointsOffset(frame.backdrop, frame, 0)
        HandleIcon(frame.backdrop, _G["Inspect"..slot.."IconTexture"])

        -- Nampower-based tooltip via hyperlink
        local funce = frame:GetScript("OnEnter")
        frame:SetScript("OnEnter", function()
          local unit = InspectFrame.unit
          if not unit or not (pfUI.api.librange and pfUI.api.librange:UnitInInspectRange(unit)) then return end
          local guid = unit and GetUnitGUID and GetUnitGUID(unit)
          local slotId = this:GetID()
          local ok, npItem = pcall(function() return guid and GetEquippedItem and GetEquippedItem(guid, slotId) end)
          if not ok then npItem = nil end
          if npItem and npItem.itemId and npItem.itemId > 0 then
            local itemId    = npItem.itemId
            local enchantId = npItem.permanentEnchantId or 0
            GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
            GameTooltip:SetHyperlink("item:" .. itemId .. ":" .. enchantId .. ":0:0:0:0:0:0")
            GameTooltip:Show()
          elseif funce then
            funce()
          end
        end)
        frame:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
      end

      -- cache: prefetched item data per guid, keyed by slot name
      local npCache = {}
      local npCacheGuid = nil
      local npTick -- forward declaration, initialized below

      local function PrefetchTarget(unit)
        if not unit then return end
        local guid = GetUnitGUID and GetUnitGUID(unit)
        if not guid then return end
        -- out of range check: 41yd via Arcane Shot range (works for all classes via Nampower)
        if not (pfUI.api.librange and pfUI.api.librange:UnitInInspectRange(unit)) then return end

        npCacheGuid = guid
        npCache = {}

        for i, vslot in pairs(slots) do
          local slotId = GetInventorySlotInfo(vslot)
          local ok, npItem = pcall(GetEquippedItem, guid, slotId)
          if not ok then
            npTick.pending = true
            npTick.delay = 0
            return
          end
          local itemId = npItem and npItem.itemId and npItem.itemId > 0 and npItem.itemId
          if itemId then
            local enchantId = npItem.permanentEnchantId or 0
            local displayInfoId = GetItemStatsField and GetItemStatsField(itemId, "displayInfoID")
            local texName = displayInfoId and GetItemIconTexture and GetItemIconTexture(displayInfoId)
            local tex = texName and ("Interface\\Icons\\" .. texName)
            local itemStats = GetItemStats and GetItemStats(itemId)
            local quality = itemStats and itemStats.quality
            npCache[vslot] = { itemId=itemId, enchantId=enchantId, tex=tex, quality=quality }
          else
            npCache[vslot] = false
          end
        end
      end


      local function UpdateSlots()
        if not InspectFrame.unit then return end

        -- check if all icons are ready, retry if not
        local allReady = true
        for i, vslot in pairs(slots) do
          local d = npCache[vslot]
          if d and not d.tex then
            allReady = false
            break
          end
        end

        if not allReady then
          npTick.pending = true
          npTick.delay = 0
          return
        end

        -- guild text
        local guild, title, rank = GetGuildInfo(InspectFrame.unit)
        if guild then
          InspectGuildText:SetPoint("TOP", InspectLevelText, "BOTTOM", 0, -1)
          InspectGuildText:SetText(format(TEXT(GUILD_TITLE_TEMPLATE), title, guild))
          InspectGuildText:Show()
        else
          InspectGuildText:SetText("")
          InspectGuildText:Hide()
        end

        for i, vslot in pairs(slots) do
          local frame = _G["Inspect" .. vslot]
          local d = npCache[vslot]

          if d then
            SetItemButtonTexture(frame, d.tex)
            frame.hasItem = 1
            if d.quality and d.quality > 0 then
              local r, g, b = GetItemQualityColor(d.quality)
              frame.backdrop:SetBackdropBorderColor(r, g, b, 1)
            else
              frame.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
            end
            if ShaguScore then
              if not frame.scoreText then
                frame.scoreText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                frame.scoreText:SetFont(pfUI.font_default, 12, "OUTLINE")
                frame.scoreText:SetPoint("TOPRIGHT", 0, 0)
              end
              local itemLevel = ShaguScore.Database[d.itemId] or 0
              local score = d.quality and ShaguScore:Calculate(vslot, d.quality, itemLevel) or 0
              if score and score > 0 then
                local r, g, b = GetItemQualityColor(d.quality)
                frame.scoreText:SetText(score)
                frame.scoreText:SetTextColor(r, g, b)
              else
                frame.scoreText:SetText("")
              end
            end
          else
            CreateBackdrop(frame)
            SetAllPointsOffset(frame.backdrop, frame, 0)
            frame.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
            if frame.scoreText then frame.scoreText:SetText("") end
          end
        end
      end

      -- OnUpdate frame: 20ms prefetch delay + 0.5s range check
      npTick = CreateFrame("Frame")
      npTick.delay = 0
      npTick.range = 0
      npTick.pending = false
      npTick:Hide()
      npTick:SetScript("OnUpdate", function()
        local dt = arg1
        -- range check throttled to 0.5s
        npTick.range = npTick.range + dt
        if npTick.range >= 0.5 then
          npTick.range = 0
          local unit = InspectFrame.unit
          if not unit or not (pfUI.api.librange and pfUI.api.librange:UnitInInspectRange(unit)) then
            HideUIPanel(InspectFrame)
            npTick:Hide()
            return
          end
        end
        -- 20ms prefetch delay on item swap
        if npTick.pending then
          npTick.delay = npTick.delay + dt
          if npTick.delay >= 0.02 then
            npTick.pending = false
            npTick.delay = 0
            PrefetchTarget(InspectFrame.unit)
            UpdateSlots()
          end
        end
      end)

      local function TriggerDelay()
        if not npTick.pending then
          npTick.pending = true
          npTick.delay = 0
        end
      end

      -- item swap during inspect: re-prefetch and re-apply
      hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        TriggerDelay()
      end)

      -- on open: prefetch and apply immediately, start tick
      hooksecurefunc("InspectPaperDollFrame_OnShow", function()
        npTick.range = 0
        npTick:Show()
        PrefetchTarget(InspectFrame.unit)
        UpdateSlots()
      end)

      -- stop tick when frame closes
      hooksecurefunc("InspectFrame_OnHide", function()
        npTick:Hide()
      end)
    end

    do -- Honor Tab
      StripTextures(InspectHonorFrame)

      CreateBackdrop(InspectHonorFrameProgressBar)
      InspectHonorFrameProgressBar:SetStatusBarTexture(pfUI.media["img:bar"])
      InspectHonorFrameProgressBar:SetHeight(24)
    end

    do -- Turtle WoW Talent Tab (TWTalentFrame)
      if TWTalentFrame then
        StripTextures(TWTalentFrame)

        StripTextures(TWTalentFrameScrollFrame)
        SkinScrollbar(TWTalentFrameScrollFrameScrollBar)

        for i = 1, 3 do
          SkinTab(_G["TWTalentFrameTab"..i])
        end

        for i = 1, (MAX_NUM_TALENTS or 100) do
          local talent = _G["TWTalentFrameTalent"..i]
          if talent then
            StripTextures(talent)
            SkinButton(talent, nil, nil, nil, _G["TWTalentFrameTalent"..i.."IconTexture"])
            local rank = _G["TWTalentFrameTalent"..i.."Rank"]
            if rank then
              rank:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
            end
          end
        end
      end
    end
  end)
end)