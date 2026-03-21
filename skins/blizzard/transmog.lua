pfUI:RegisterSkin("Transmog", "vanilla", function ()
  if not TransmogFrame then return end

  -- Strip all background/border textures from the main frame
  -- The frame has Background1/2 (ui1/ui2 textures) and a Splash texture
  StripTextures(TransmogFrame, true)

  -- Apply pfUI backdrop
  CreateBackdrop(TransmogFrame, nil, nil, .75)
  CreateBackdropShadow(TransmogFrame)
  EnableMovable(TransmogFrame)

  -- Close button
  SkinCloseButton(TransmogFrameCloseButton, TransmogFrame.backdrop, -6, -6)

  -- Buttons
  if TransmogFrameItemsButton then StripTextures(TransmogFrameItemsButton) SkinButton(TransmogFrameItemsButton) end
  if TransmogFrameSetsButton then StripTextures(TransmogFrameSetsButton) SkinButton(TransmogFrameSetsButton) end
  if TransmogFrameSaveOutfit then SkinButton(TransmogFrameSaveOutfit) end
  if TransmogFrameApplyButton then SkinButton(TransmogFrameApplyButton) end

  -- Search box
  if TransmogFrameSearch then
    StripTextures(TransmogFrameSearch)
    CreateBackdrop(TransmogFrameSearch)
  end

  -- Outfits dropdown
  if TransmogFrameOutfits then
    SkinDropDown(TransmogFrameOutfits)
  end

  -- Pagination arrows
  if TransmogFrameLeftArrow then
    StripTextures(TransmogFrameLeftArrow)
    SkinArrowButton(TransmogFrameLeftArrow, "left", 18)
  end
  if TransmogFrameRightArrow then
    StripTextures(TransmogFrameRightArrow)
    SkinArrowButton(TransmogFrameRightArrow, "right", 18)
  end

  -- Equipment slots from TransmogPlayerSlotTemplate
  -- Names come directly from XML: HeadSlot, ShoulderSlot, etc.
  -- ShirtSlot IS in the InventorySlots table in the Lua (slot 4) so we include it
  local slots = {
    "HeadSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot",
    "WaistSlot", "LegsSlot", "FeetSlot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
  }

  for _, name in ipairs(slots) do
    local slot = _G[name]
    if slot then
      -- Strip all the custom transmog border textures defined in TransmogPlayerSlotTemplate
      -- NoEquip is intentionally kept (shows the X when slot is empty)
      local textures = { "Border", "BorderHi", "BorderFull", "BorderSelected", "BorderHighlight" }
      for _, t in ipairs(textures) do
        local tex = _G[name .. t]
        if tex then tex:SetTexture(nil) end
      end

      -- Apply pfUI backdrop to the slot button
      CreateBackdrop(slot, nil, true)

      -- Fix the item icon to fill the slot properly
      local icon = _G[name .. "ItemIcon"]
      if icon then
        icon:SetTexCoord(.08, .92, .08, .92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
      end
    end
  end

  -- TransmogFrameLookTemplate items (browsing grid, named TransmogFrameLook1..15)
  -- Each has a Button child and a DressUpModel child
  local function SkinLookButton(frame)
    if not frame or frame._pfSkinned then return end
    frame._pfSkinned = true
    local btn = _G[frame:GetName() .. "Button"]
    if btn then
      StripTextures(btn)
      CreateBackdrop(btn, nil, true)
    end
  end

  local origOnShow = TransmogFrame:GetScript("OnShow")
  TransmogFrame:SetScript("OnShow", function()
    if origOnShow then origOnShow() end
    for i = 1, 20 do
      SkinLookButton(_G["TransmogFrameLook" .. i])
    end
  end)
end)
