pfUI:RegisterSkin("Turtle Shop", "vanilla", function ()
  if not ShopFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- ============================================================
  --  Helper: skin the 8 entry frames
  -- ============================================================
  local function SkinEntryFrames()
    for i = 1, 8 do
      local entry = _G["ShopFrameEntryFrame" .. i]
      if entry and not entry._pfSkinned then
        entry._pfSkinned = true
        for _, region in ipairs({ entry:GetRegions() }) do
          if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
            region:SetTexture(nil)
          end
        end
      end
    end
  end

  -- ============================================================
  --  ShopFrame main window
  -- ============================================================
  StripTextures(ShopFrame, true)
  CreateBackdrop(ShopFrame, nil, nil, .75)
  CreateBackdropShadow(ShopFrame)

  ShopFrame.backdrop:SetPoint("TOPLEFT",     ShopFrame, "TOPLEFT",     14, -10)
  ShopFrame.backdrop:SetPoint("BOTTOMRIGHT", ShopFrame, "BOTTOMRIGHT", -14, 10)
  EnableMovable(ShopFrame)

  SkinCloseButton(ShopFrameCloseButton, ShopFrame.backdrop, -6, -6)

  ShopFrameTitleText:ClearAllPoints()
  ShopFrameTitleText:SetPoint("TOP", ShopFrame.backdrop, "TOP", 0, -10)

  -- ============================================================
  --  Category scrollframe
  -- ============================================================
  StripTextures(ShopFrameCategoriesScrollFrame)
  CreateBackdrop(ShopFrameCategoriesScrollFrame)
  SkinScrollbar(ShopFrameCategoriesScrollFrameScrollBar, true)

  -- ============================================================
  --  Search editbox
  -- ============================================================
  StripTextures(ShopFrameSearchBox)
  CreateBackdrop(ShopFrameSearchBox)

  -- ============================================================
  --  AutoDress checkbox
  -- ============================================================
  SkinCheckbox(ShopFrameAutoDress)

  -- ============================================================
  --  Buttons
  -- ============================================================
  SkinButton(ShopFrameClaimButton)
  CreateBackdrop(ShopFramePreviousButton, nil, true)
  CreateBackdrop(ShopFrameNextButton, nil, true)

  -- ============================================================
  --  Entry frames
  -- ============================================================
  SkinEntryFrames()

  local origOnShow = ShopFrame:GetScript("OnShow")
  ShopFrame:SetScript("OnShow", function()
    if origOnShow then origOnShow() end
    SkinEntryFrames()
  end)

  -- ============================================================
  --  ShopDressUpFrame
  -- ============================================================
  if ShopDressUpFrame then
    StripTextures(ShopDressUpFrame, true)
    CreateBackdrop(ShopDressUpFrame, nil, nil, .75)
    CreateBackdropShadow(ShopDressUpFrame)

    if ShopDressUpFrameUndressButton then SkinButton(ShopDressUpFrameUndressButton) end
    if ShopDressUpFrameResetButton   then SkinButton(ShopDressUpFrameResetButton)   end
    if ShopDressUpFrameCloseButton   then
      SkinCloseButton(ShopDressUpFrameCloseButton, ShopDressUpFrame.backdrop, -6, -6)
    end
  end
end)