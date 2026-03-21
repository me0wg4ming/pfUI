pfUI:RegisterSkin("Arena Score", "vanilla", function ()
  if not ArenaScoreFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- Main frame
  StripTextures(ArenaScoreFrame)
  CreateBackdrop(ArenaScoreFrame, nil, nil, .75)
  CreateBackdropShadow(ArenaScoreFrame)

  ArenaScoreFrame.backdrop:SetPoint("TOPLEFT", 10, -14)
  ArenaScoreFrame.backdrop:SetPoint("BOTTOMRIGHT", -112, 68)
  ArenaScoreFrame:SetHitRectInsets(10, 112, 14, 68)

  -- Close button
  SkinCloseButton(ArenaScoreFrameCloseButton, ArenaScoreFrame.backdrop, -6, -6)

  -- Title
  ArenaScoreFrameTitle:ClearAllPoints()
  ArenaScoreFrameTitle:SetPoint("TOP", ArenaScoreFrame.backdrop, "TOP", 0, -10)
end)
