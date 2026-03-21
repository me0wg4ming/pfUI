pfUI:RegisterSkin("Barbershop", "vanilla", function ()
  if not BarbershopFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- Main frame
  StripTextures(BarbershopFrame)
  CreateBackdrop(BarbershopFrame, nil, nil, .75)
  CreateBackdropShadow(BarbershopFrame)

  BarbershopFrame.backdrop:SetPoint("TOPLEFT", 0, 0)
  BarbershopFrame.backdrop:SetPoint("BOTTOMRIGHT", 0, 0)
  EnableMovable(BarbershopFrame)

  -- Banner frame (title decoration)
  StripTextures(BarbershopBannerFrame)

  -- Selectors (hair style, color, facial hair)
  for i = 1, 3 do
    local selector = _G["BarbershopFrameSelector" .. i]
    if selector then
      StripTextures(selector)
      CreateBackdrop(selector, nil, true)

      local prev = _G["BarbershopFrameSelector" .. i .. "Prev"]
      local next = _G["BarbershopFrameSelector" .. i .. "Next"]
      if prev then
        StripTextures(prev)
        SkinArrowButton(prev, "left", 18)
      end
      if next then
        StripTextures(next)
        SkinArrowButton(next, "right", 18)
      end
    end
  end

  -- Money frame border
  if BarbershopFrameMoneyFrame then
    StripTextures(BarbershopFrameMoneyFrame)
  end

  -- Buttons
  SkinButton(BarbershopFrameOkayButton)
  SkinButton(BarbershopFrameCancelButton)
  SkinButton(BarbershopFrameResetButton)

  -- Turtle WoW's Barbershop calls PlayerFrame:Show() and TargetFrame:Show()
  -- on open/close. pfUI manages its own frames so we noop those calls.
  if C.unitframes.disable ~= "1" then
    if PlayerFrame then
      PlayerFrame:Hide()
      PlayerFrame.Show = function() return end
    end
    if TargetFrame then
      TargetFrame.Show = function() return end
    end
  end

  -- Fix: disable TargetFrameDebuff OnEnter scripts while barbershop is open
  -- to prevent SetUnitDebuff crash (TargetFrame is hidden but scripts remain active)
  local savedOnEnter = {}

  local origOnShow = BarbershopFrame:GetScript("OnShow")
  BarbershopFrame:SetScript("OnShow", function()
    for i = 1, 16 do
      local debuff = _G["TargetFrameDebuff" .. i]
      if debuff then
        savedOnEnter[i] = debuff:GetScript("OnEnter")
        debuff:SetScript("OnEnter", nil)
      end
    end
    if origOnShow then origOnShow() end
  end)

  local origOnHide = BarbershopFrame:GetScript("OnHide")
  BarbershopFrame:SetScript("OnHide", function()
    for i = 1, 16 do
      local debuff = _G["TargetFrameDebuff" .. i]
      if debuff and savedOnEnter[i] then
        debuff:SetScript("OnEnter", savedOnEnter[i])
      end
    end
    if origOnHide then origOnHide() end
  end)
end)
