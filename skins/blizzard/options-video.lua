pfUI:RegisterSkin("Options - Video", "vanilla", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  local MAX_SLIDERS = 9
  local MAX_CHECKBOXES = 18

  for i=1, MAX_SLIDERS do
    local slider = _G["OptionsFrameSlider"..i]
    local shift = 0
    if i == 1 or i == 6 then shift = 4
    elseif i == 4 or i == 8 then shift = 10
    end
    local point, anchor, anchorPoint, x, y = slider:GetPoint()
    slider:ClearAllPoints()
    slider:SetPoint(point, anchor, anchorPoint, x, y - shift)
  end

  CreateBackdrop(OptionsFrame, nil, nil, .75)
  CreateBackdropShadow(OptionsFrame)

  EnableMovable(OptionsFrame)

  HookScript(OptionsFrame, "OnShow", function()
    this:ClearAllPoints()
    this:SetPoint("CENTER", 0, 0)
  end)

  OptionsFrameHeader:SetTexture("")
  local OptionsFrameHeaderText = GetNoNameObject(OptionsFrame, "FontString", "ARTWORK", VIDEOOPTIONS_MENU)
  OptionsFrameHeaderText:ClearAllPoints()
  OptionsFrameHeaderText:SetPoint("TOP", OptionsFrame.backdrop, "TOP", 0, -10)

  CreateBackdrop(OptionsFrameDisplay, nil, true, .75)
  CreateBackdrop(OptionsFrameWorldAppearance, nil, true, .75)
  CreateBackdrop(OptionsFrameBrightness, nil, true, .75)
  CreateBackdrop(OptionsFramePixelShaders, nil, true, .75)
  CreateBackdrop(OptionsFrameMiscellaneous, nil, true, .75)

  SkinButton(OptionsFrameDefaults)
  SkinButton(OptionsFrameCancel)
  SkinButton(OptionsFrameOkay)
  OptionsFrameOkay:ClearAllPoints()
  OptionsFrameOkay:SetPoint("RIGHT", OptionsFrameCancel, "LEFT", -2*bpad, 0)

  SkinDropDown(OptionsFrameResolutionDropDown)
  SkinDropDown(OptionsFrameRefreshDropDown)
  SkinDropDown(OptionsFrameMultiSampleDropDown)

  for i=1, MAX_SLIDERS do
    SkinSlider(_G["OptionsFrameSlider"..i])
  end

  for i=1, MAX_CHECKBOXES do
    local btn = _G["OptionsFrameCheckButton"..i]
    if btn then
      SkinCheckbox(btn, 28)
    end
  end
end)
