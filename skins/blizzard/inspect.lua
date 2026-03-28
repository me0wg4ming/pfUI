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

-- Nampower GetEquippedItem uses its own slot numbering (0-18), NOT GetInventorySlotInfo values
-- Docs: 1=Head 2=Neck 3=Shoulder 4=Shirt 5=Chest 6=Waist 7=Legs 8=Feet 9=Wrist 10=Hands
--       11=Finger1 12=Finger2 13=Trinket1 14=Trinket2 15=Back 16=MainHand 17=OffHand 18=Ranged 19=Tabard
local npSlotMap = {
  ["HeadSlot"]          = 1,
  ["NeckSlot"]          = 2,
  ["ShoulderSlot"]      = 3,
  ["ShirtSlot"]         = 4,
  ["ChestSlot"]         = 5,
  ["WaistSlot"]         = 6,
  ["LegsSlot"]          = 7,
  ["FeetSlot"]          = 8,
  ["WristSlot"]         = 9,
  ["HandsSlot"]         = 10,
  ["Finger0Slot"]       = 11,
  ["Finger1Slot"]       = 12,
  ["Trinket0Slot"]      = 13,
  ["Trinket1Slot"]      = 14,
  ["BackSlot"]          = 15,
  ["MainHandSlot"]      = 16,
  ["SecondaryHandSlot"] = 17,
  ["RangedSlot"]        = 18,
  ["TabardSlot"]        = 19,
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
            local slotName = string.sub(btn:GetName(), 8)  -- strip "Inspect" prefix
            local slotId = npSlotMap[slotName]
            local ok, npItem = slotId and pcall(GetEquippedItem, guid, slotId) or false, nil
            if not slotId then ok, npItem = true, nil end
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

  HookAddonOrVariable("Blizzard_InspectUI", function()
    -- Override InspectFrame_Show to remove the CanInspect() block
    -- but keep normal range requirement for opening (button still greys out)
    InspectFrame_Show = function(unit)
      HideUIPanel(InspectFrame)
      pcall(NotifyInspect, unit)
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

        -- OnEnter set after npCache is defined (see below)
        frame:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
      end

      local npCache = {}
      local npCacheGuid = nil
      local npTick

      local function PrefetchTarget(unit)
        if not unit then return end
        local guid = GetUnitGUID and GetUnitGUID(unit)
        if not guid then return end

        -- Check if at least one slot returns data - if not, we're out of range
        -- Keep the existing cache in that case so items stay visible
        local slotId = npSlotMap["HeadSlot"]
        local testOk, testItem = pcall(GetEquippedItem, guid, slotId)
        local hasData = testOk and testItem ~= nil
        -- also consider: all nil could mean no items equipped, not out of range
        -- use guid change as signal to force refresh
        local guidChanged = npCacheGuid ~= guid

        if not hasData and not guidChanged then
          -- out of range and same target - keep cache as-is
          return
        end

        npCacheGuid = guid
        -- only reset cache on guid change or when we have fresh data
        if guidChanged then npCache = {} end

        local gotAny = false
        for i, vslot in pairs(slots) do
          local sid = npSlotMap[vslot]
          local ok, npItem
          if sid then
            ok, npItem = pcall(GetEquippedItem, guid, sid)
          end
          if ok and npItem and npItem.itemId and npItem.itemId > 0 then
            local itemId = npItem.itemId
            local enchantId = npItem.permanentEnchantId or 0
            local displayInfoId = GetItemStatsField and GetItemStatsField(itemId, "displayInfoID")
            local texName = displayInfoId and GetItemIconTexture and GetItemIconTexture(displayInfoId)
            local tex = texName and ("Interface\\Icons\\" .. texName)
            local itemStats = GetItemStats and GetItemStats(itemId)
            local quality = itemStats and itemStats.quality
            npCache[vslot] = { itemId=itemId, enchantId=enchantId, tex=tex, quality=quality }
            gotAny = true
          elseif ok then
            -- slot is empty (in range but no item) - only update if we have data
            if hasData then npCache[vslot] = false end
          end
          -- if not ok: out of range, leave cache entry as-is
        end
      end

      -- Set OnEnter after npCache is defined so tooltips can read from cache
      for _, slot in pairs(slots) do
        local frame = _G["Inspect"..slot]
        if frame then
          local slotKey = slot  -- capture for closure
          local funce = frame:GetScript("OnEnter")
          frame:SetScript("OnEnter", function()
            local d = npCache[slotKey]
            if d and d.itemId then
              GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
              GameTooltip:SetHyperlink("item:" .. d.itemId .. ":" .. (d.enchantId or 0) .. ":0:0:0:0:0:0")
              GameTooltip:Show()
            elseif funce then
              funce()
            end
          end)
        end
      end

      local function UpdateSlots()
        if not InspectFrame.unit then return end

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

      npTick = CreateFrame("Frame")
      npTick.delay = 0
      npTick.pending = false
      npTick:Hide()
      npTick:SetScript("OnUpdate", function()
        local dt = arg1
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

      hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        TriggerDelay()
      end)

      hooksecurefunc("InspectPaperDollFrame_OnShow", function()
        npTick:Show()
        PrefetchTarget(InspectFrame.unit)
        UpdateSlots()
      end)

      -- Don't auto-close when out of range - keep frame open as long as possible
      -- The original InspectFrame_OnUpdate closed the frame when target was lost,
      -- we let it stay open so players can review gear after moving away
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