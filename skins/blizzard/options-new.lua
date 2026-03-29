pfUI:RegisterSkin("Options - New", function ()
  if not OptionsFrame or not OptionsFrameCategoryList then return end
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()
  local br, bg, bb, ba = pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
  local er, eg, eb, ea = pfUI.api.GetStringColor(pfUI_config.appearance.border.color)

  -- main frame
  StripTextures(OptionsFrame)
  CreateBackdrop(OptionsFrame, nil, nil, .75)
  CreateBackdropShadow(OptionsFrame)
  EnableMovable(OptionsFrame)

  HookScript(OptionsFrame, "OnShow", function()
    this:ClearAllPoints()
    this:SetPoint("CENTER", 0, 0)
  end)

  -- header
  if OptionsFrameHeader then
    StripTextures(OptionsFrameHeader)
    local title = GetNoNameObject(OptionsFrameHeader, "FontString", "ARTWORK", "OPTIONS")
    if title then
      title:ClearAllPoints()
      title:SetPoint("TOP", OptionsFrame.backdrop, "TOP", 0, -10)
    end
  end

  -- category list
  if OptionsFrameCategoryList then
    StripTextures(OptionsFrameCategoryList)
    local catBG = CreateFrame("Frame", nil, OptionsFrame)
    catBG:SetFrameLevel(OptionsFrameCategoryList:GetFrameLevel() - 1)
    catBG:SetPoint("TOPLEFT",     OptionsFrameCategoryList, "TOPLEFT",     -border - 6, border + 10)
    catBG:SetPoint("BOTTOMRIGHT", OptionsFrameCategoryList, "BOTTOMRIGHT",  border,     -border)
    catBG:SetBackdrop(pfUI.backdrop)
    catBG:SetBackdropColor(br, bg, bb, ba)
    catBG:SetBackdropBorderColor(er, eg, eb, ea)
    if OptionsFrameCategoryListScrollFrame then
      StripTextures(OptionsFrameCategoryListScrollFrame)
      SkinScrollbar(OptionsFrameCategoryListScrollFrameScrollBar)
    end
  end

  -- content area
  if OptionsFrameContent then
    StripTextures(OptionsFrameContent)
    local contBG = CreateFrame("Frame", nil, OptionsFrame)
    contBG:SetFrameLevel(OptionsFrameContent:GetFrameLevel() - 1)
    contBG:SetPoint("TOPLEFT",     OptionsFrameContent, "TOPLEFT",     -border, border + 42)
    contBG:SetPoint("BOTTOMRIGHT", OptionsFrameContent, "BOTTOMRIGHT",  border, -border + 4)
    contBG:SetBackdrop(pfUI.backdrop)
    contBG:SetBackdropColor(br, bg, bb, ba)
    contBG:SetBackdropBorderColor(er, eg, eb, ea)
    if OptionsFrameContentScrollFrame then
      StripTextures(OptionsFrameContentScrollFrame)
      SkinScrollbar(OptionsFrameContentScrollFrameScrollBar)
    end
  end

  -- search box
  if OptionsFrameSearchBox then
    StripTextures(OptionsFrameSearchBox)
    CreateBackdrop(OptionsFrameSearchBox, nil, nil, .75)
    if OptionsFrameSearchBox.backdrop then
      OptionsFrameSearchBox.backdrop:SetPoint("TOPLEFT",     OptionsFrameSearchBox, "TOPLEFT",     -border, border + 0)
      OptionsFrameSearchBox.backdrop:SetPoint("BOTTOMRIGHT", OptionsFrameSearchBox, "BOTTOMRIGHT",  border, -border - 0)
    end
    if OptionsFrameSearchBoxClearButton then
      OptionsFrameSearchBoxClearButton:ClearAllPoints()
      OptionsFrameSearchBoxClearButton:SetPoint("RIGHT", OptionsFrameSearchBox, "RIGHT", -2, 0)
    end
  end

  -- buttons
  SkinButton(OptionsFrameOkay)
  SkinButton(OptionsFrameCancel)
  SkinButton(OptionsFrameDefaults)
  OptionsFrameOkay:ClearAllPoints()
  OptionsFrameOkay:SetPoint("RIGHT", OptionsFrameCancel, "LEFT", -2*bpad, 0)

  -- category buttons
  for i = 1, NUM_CATEGORIES_TO_DISPLAY or 18 do
    local btn = _G["OptionsFrameCategoryListCategory"..i]
    if btn then
      local bar = _G["OptionsFrameCategoryListCategory"..i.."Bar"]
      if bar then bar:SetTexture("") end
      local hl = btn:GetHighlightTexture()
      if hl then hl:SetTexture("") end
    end
  end

  -- SkinControls: called after UpdateOptions has set all slider values
  local function SkinControls()
    if not OptionsFrameContentScrollFrameChild then return end

    -- plain buttons (type="button", no .control wrapper)
    for i = 1, 20 do
      local btn = _G["OptionsFrameButton"..i]
      if not btn then break end
      if not btn._pfSkinned then
        StripTextures(btn, true)
        btn:SetBackdrop(pfUI.backdrop)
        local br, bg, bb = pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
        local er, eg, eb = pfUI.api.GetStringColor(pfUI_config.appearance.border.color)
        btn:SetBackdropColor(br, bg, bb, 0.75)
        btn:SetBackdropBorderColor(er, eg, eb, 1)
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        SetHighlight(btn, color.r, color.g, color.b)
        btn:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
        HookScript(btn, "OnMouseDown", function()
          StripTextures(this, true)
          this:SetBackdrop(pfUI.backdrop)
          this:SetBackdropColor(br, bg, bb, 0.75)
          this:SetBackdropBorderColor(er, eg, eb, 1)
        end)
        HookScript(btn, "OnMouseUp", function()
          StripTextures(this, true)
          this:SetBackdrop(pfUI.backdrop)
          this:SetBackdropColor(br, bg, bb, 0.75)
          this:SetBackdropBorderColor(er, eg, eb, 1)
        end)
        btn._pfSkinned = true
      end
    end

    -- sliders
    for i = 1, 20 do
      local wrapper = _G["OptionsFrameSlider"..i]
      if not wrapper then break end
      if wrapper:IsShown() and wrapper.control then
        local ctrl = wrapper.control
        SkinSlider(ctrl)
        -- reset Low/High labels to original XML positions (prevent drift on re-skin)
        local ctrlName = ctrl:GetName()
        local minLabel = _G[ctrlName.."MinValue"]
        local maxLabel = _G[ctrlName.."MaxValue"]
        if minLabel then
          minLabel:ClearAllPoints()
          minLabel:SetPoint("TOPLEFT", ctrl, "BOTTOMLEFT", 2, 0)
        end
        if maxLabel then
          maxLabel:ClearAllPoints()
          maxLabel:SetPoint("TOPRIGHT", ctrl, "BOTTOMRIGHT", -2, 0)
        end
      end
    end

    -- checkboxes and dropdowns
    for _, child in {OptionsFrameContentScrollFrameChild:GetChildren()} do
      if child.control then
        local ctype = child.control:GetFrameType()

        if ctype == "CheckButton" then
          SkinCheckbox(child.control, 28)
          if child.control.backdrop then
            child.control.backdrop:SetBackdropColor(0, 0, 0, 0)
          end
          -- reset label indent (dependency offset from OptionsFrame.lua)
          if child.label then
            child.label:ClearAllPoints()
            child.label:SetPoint("LEFT", child, "LEFT", 0, 0)
          end

        elseif ctype == "Frame" then
          local name = child.control:GetName()
          if name and _G[name .. "Button"] then
            if not child._pfDropSkinned then
              SkinDropDown(child.control)
              child._pfDropSkinned = true
            end
            if child.control.backdrop then child.control.backdrop:SetBackdropColor(0, 0, 0, 0) end
            if child.control.button and child.control.button.backdrop then
              child.control.button.backdrop:SetBackdropColor(0, 0, 0, 0)
            end
            local textFrame = _G[name .. "Text"]
            if textFrame then textFrame:SetDrawLayer("OVERLAY") end
            UIDropDownMenu_Initialize(child.control, child.control.initialize)
          end
        end
      end
    end
  end

  -- hook after category selection: UpdateOptions is local so we hook its caller
  hooksecurefunc("OptionsListButton_OnClick", SkinControls)
  -- also cover initial load
  HookScript(OptionsFrame, "OnShow", SkinControls)
end)