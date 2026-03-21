pfUI:RegisterSkin("Transmog", "vanilla", function ()
  if not TransmogFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- Main frame
  StripTextures(TransmogFrame, true)
  CreateBackdrop(TransmogFrame, nil, nil, .75)
  CreateBackdropShadow(TransmogFrame)

  TransmogFrame.backdrop:SetPoint("TOPLEFT", 14, -10)
  TransmogFrame.backdrop:SetPoint("BOTTOMRIGHT", -14, 10)
  TransmogFrame:SetHitRectInsets(14, 14, 10, 10)
  EnableMovable(TransmogFrame)

  -- Close button
  SkinCloseButton(TransmogFrameCloseButton, TransmogFrame.backdrop, -6, -6)

  -- Title
  TransmogFrameTitleText:ClearAllPoints()
  TransmogFrameTitleText:SetPoint("TOP", TransmogFrame.backdrop, "TOP", 0, -10)

  -- Search box
  if TransmogFrameSearch then
    StripTextures(TransmogFrameSearch)
    CreateBackdrop(TransmogFrameSearch)
  end

  -- Outfits dropdown
  if TransmogFrameOutfits then
    SkinDropDown(TransmogFrameOutfits)
  end

  -- Tab buttons (Items / Outfits)
  if TransmogFrameItemsButton then SkinButton(TransmogFrameItemsButton) end
  if TransmogFrameSetsButton then SkinButton(TransmogFrameSetsButton) end
  if TransmogFrameApplyButton then SkinButton(TransmogFrameApplyButton) end
  if TransmogFrameSaveOutfit then SkinButton(TransmogFrameSaveOutfit) end

  -- Arrow buttons (pagination)
  if TransmogFrameLeftArrow then
    StripTextures(TransmogFrameLeftArrow)
    SkinArrowButton(TransmogFrameLeftArrow, "left", 18)
  end
  if TransmogFrameRightArrow then
    StripTextures(TransmogFrameRightArrow)
    SkinArrowButton(TransmogFrameRightArrow, "right", 18)
  end

  -- Equipment slot buttons
  local slots = {
    "HeadSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot",
    "WaistSlot", "LegsSlot", "FeetSlot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
  }

  for _, name in ipairs(slots) do
    local slot = _G[name]
    if slot then
      local icon = _G[name .. "ItemIcon"]
      StripTextures(slot)
      CreateBackdrop(slot, nil, true)
      if icon then
        icon:SetTexCoord(.08, .92, .08, .92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
      end
    end
  end
end)
