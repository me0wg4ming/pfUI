pfUI:RegisterSkin("Custom Merchant", "vanilla", function ()
  if not CustomMerchantFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- Main frame
  StripTextures(CustomMerchantFrame)
  CreateBackdrop(CustomMerchantFrame, nil, nil, .75)
  CreateBackdropShadow(CustomMerchantFrame)

  CustomMerchantFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
  CustomMerchantFrame.backdrop:SetPoint("BOTTOMRIGHT", -32, 58)
  CustomMerchantFrame:SetHitRectInsets(10, 32, 10, 58)
  EnableMovable(CustomMerchantFrame)

  -- Close button
  SkinCloseButton(CustomMerchantFrameCloseButton, CustomMerchantFrame.backdrop, -6, -6)

  -- Title
  CustomMerchantNameText:ClearAllPoints()
  CustomMerchantNameText:SetPoint("TOP", CustomMerchantFrame.backdrop, "TOP", 0, -10)

  -- Item frames
  for i = 1, 10 do
    local item = _G["CustomMerchantItem" .. i]
    if item then
      StripTextures(item)

      local bg = item:CreateTexture(nil, "LOW")
      bg:SetTexture(1, 1, 1, .05)
      bg:SetAllPoints()

      local itemButton = _G["CustomMerchantItem" .. i .. "ItemButton"]
      if itemButton then
        StripTextures(itemButton)
        SkinButton(itemButton, nil, nil, nil, _G[itemButton:GetName() .. "IconTexture"])
      end
    end
  end

  -- Pagination buttons
  if CustomMerchantPrevPageButton then
    StripTextures(CustomMerchantPrevPageButton)
    SkinArrowButton(CustomMerchantPrevPageButton, "left", 18)
  end
  if CustomMerchantNextPageButton then
    StripTextures(CustomMerchantNextPageButton)
    SkinArrowButton(CustomMerchantNextPageButton, "right", 18)
  end
end)
