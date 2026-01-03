pfUI:RegisterSkin("Options - Sound", "vanilla", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  local SoundOptionsFrameHeaderText = GetNoNameObject(SoundOptionsFrame, "FontString", "ARTWORK", SOUNDOPTIONS_MENU)
  local NUM_CHECKBOXES = 8
  local NUM_SLIDERS = 4

  SoundOptionsFrameOkay:ClearAllPoints()
  SoundOptionsFrameOkay:SetPoint("RIGHT", SoundOptionsFrameCancel, "LEFT", -2*bpad, 0)
  SoundOptionsFrameSlider1:ClearAllPoints()
  SoundOptionsFrameSlider1:SetPoint("TOPRIGHT", SoundOptionsFrame, "TOPRIGHT", -18, -43)
  for i=2, NUM_SLIDERS do
    _G["SoundOptionsFrameSlider"..i]:ClearAllPoints()
    _G["SoundOptionsFrameSlider"..i]:SetPoint("TOP", _G["SoundOptionsFrameSlider"..i-1], "BOTTOM", 0, -30)
  end

  StripTextures(SoundOptionsFrame)
  CreateBackdrop(SoundOptionsFrame, nil, true, .75)
  CreateBackdropShadow(SoundOptionsFrame)

  EnableMovable(SoundOptionsFrame)

  HookScript(SoundOptionsFrame, "OnShow", function()
    this:ClearAllPoints()
    this:SetPoint("CENTER", 0, 0)
  end)

  SoundOptionsFrameHeaderText:ClearAllPoints()
  SoundOptionsFrameHeaderText:SetPoint("TOP", 0, -10)

  SkinButton(SoundOptionsFrameDefaults)
  SkinButton(SoundOptionsFrameCancel)
  SkinButton(SoundOptionsFrameOkay)

  for i=1, NUM_CHECKBOXES do
    local btn = _G["SoundOptionsFrameCheckButton"..i]
    if btn then
      SkinCheckbox(btn, 28)
    end
  end

  for i=1, NUM_SLIDERS do
    SkinSlider(_G["SoundOptionsFrameSlider"..i])
  end
end)
