pfUI:RegisterSkin("Turtle LFT", "vanilla", function ()
  -- Only run if the LFT addon is loaded
  if not LFTFrame then return end

  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  -- ============================================================
  --  LFTFrame (main window)
  -- ============================================================
  StripTextures(LFTFrame, true)
  CreateBackdrop(LFTFrame, nil, nil, .75)
  CreateBackdropShadow(LFTFrame)

  -- pull backdrop inset to match the actual usable area
  -- original frame is 384x512 with large art borders
  LFTFrame.backdrop:SetPoint("TOPLEFT",     LFTFrame, "TOPLEFT",     14, -10)
  LFTFrame.backdrop:SetPoint("BOTTOMRIGHT", LFTFrame, "BOTTOMRIGHT", -30, 70)
  LFTFrame:SetHitRectInsets(14, 30, 10, 70)
  EnableMovable(LFTFrame)

  -- close button  (unnamed UIPanelCloseButton child)
  local closeBtn = GetNoNameObject(LFTFrame, "Button", nil, "UI-Panel-MinimizeButton-Up")
  if closeBtn then
    SkinCloseButton(closeBtn, LFTFrame.backdrop, -6, -6)
  end

  -- title
  local title = GetNoNameObject(LFTFrame, "FontString")
  if title then
    title:ClearAllPoints()
    title:SetPoint("TOP", LFTFrame.backdrop, "TOP", 0, -10)
  end

  -- tabs
  SkinTab(LFTFrameTab1)
  LFTFrameTab1:ClearAllPoints()
  LFTFrameTab1:SetPoint("TOPLEFT", LFTFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))

  SkinTab(LFTFrameTab2)
  LFTFrameTab2:ClearAllPoints()
  LFTFrameTab2:SetPoint("LEFT", LFTFrameTab1, "RIGHT", border * 2 + 1, 0)

  -- scrollframe
  StripTextures(LFTFrameScrollFrame)
  CreateBackdrop(LFTFrameScrollFrame)
  SkinScrollbar(LFTFrameScrollFrameScrollBar, true)

  -- search editbox
  if LFTFrameSearch then
    StripTextures(LFTFrameSearch)
    CreateBackdrop(LFTFrameSearch)
  end

  -- dropdown
  SkinDropDown(LFTFrameDropDown, nil, nil, nil, true)

  -- main buttons
  SkinButton(LFTFrameMainButton)
  SkinButton(LFTFrameNewGroupButton)
  SkinButton(LFTFrameSendMessageButton)

  -- ============================================================
  --  LFTNewGroupFrame (create / edit group panel)
  -- ============================================================
  -- NOTE: Do NOT use StripTextures recursively here — the role
  -- icon textures ($parentIcon on BORDER layer) live on the
  -- EditBox children and would be wiped out.
  StripTextures(LFTNewGroupFrame)   -- non-recursive: only the frame itself
  CreateBackdrop(LFTNewGroupFrame, nil, nil, .75)
  CreateBackdropShadow(LFTNewGroupFrame)

  -- title editbox background buttons (decorative frames, safe to strip)
  if LFTNewGroupTitleBackground    then StripTextures(LFTNewGroupTitleBackground)    end
  if LFTNewGroupDescriptionBackground then StripTextures(LFTNewGroupDescriptionBackground) end

  -- title editbox — backdrop only, no StripTextures (keeps font/focus intact)
  if LFTNewGroupTitleText then
    CreateBackdrop(LFTNewGroupTitleText)
  end

  -- description scrollframe
  if LFTNewGroupDescription then
    StripTextures(LFTNewGroupDescription)
    CreateBackdrop(LFTNewGroupDescription)
    SkinScrollbar(LFTNewGroupDescriptionScrollBar, true)
  end

  -- role limit editboxes — strip only the border slice textures, restore icons after
  local roleIcons = {
    "Interface\\FrameXML\\LFT\\images\\tank2",
    "Interface\\FrameXML\\LFT\\images\\healer2",
    "Interface\\FrameXML\\LFT\\images\\damage2",
  }
  for i = 1, 3 do
    local eb = _G["LFTNewGroupRole" .. i .. "EditBox"]
    if eb then
      -- strip the three Common-Input-Border slice textures by name
      local left   = _G["LFTNewGroupRole" .. i .. "EditBoxLeft"]
      local right  = _G["LFTNewGroupRole" .. i .. "EditBoxRight"]
      local middle = _G["LFTNewGroupRole" .. i .. "EditBoxMiddle"]
      if left   then left:SetTexture(nil)   end
      if right  then right:SetTexture(nil)  end
      if middle then middle:SetTexture(nil) end
      CreateBackdrop(eb)
      -- restore the role icon (sits on BORDER layer, untouched by above)
      local icon = _G["LFTNewGroupRole" .. i .. "EditBoxIcon"]
      if icon then icon:SetTexture(roleIcons[i]) end
    end
  end

  -- preset dropdown
  if LFTNewGroupFramePresetDropDown then
    SkinDropDown(LFTNewGroupFramePresetDropDown, nil, nil, nil, true)
  end

  -- buttons
  SkinButton(LFTNewGroupOkButton)
  SkinButton(LFTNewGroupCancelButton)
  if LFTNewGroupFrameDeleteButton    then SkinButton(LFTNewGroupFrameDeleteButton)    end
  if LFTNewGroupFrameRoleCheckButton then SkinButton(LFTNewGroupFrameRoleCheckButton) end
  if LFTNewGroupFrameSavePresetButton then SkinButton(LFTNewGroupFrameSavePresetButton) end
  -- DeletePresetButton is a pure icon button (CancelButton textures) - leave it untouched

  -- ============================================================
  --  LFTRoleCheckFrame (role selection popup)
  -- ============================================================
  StripTextures(LFTRoleCheckFrame, true)
  CreateBackdrop(LFTRoleCheckFrame, nil, nil, .9)
  CreateBackdropShadow(LFTRoleCheckFrame)
  EnableMovable(LFTRoleCheckFrame)

  SkinButton(LFTRoleCheckFrameConfirmButton)
  SkinButton(LFTRoleCheckFrameDeclineButton)

  -- ============================================================
  --  LFTGroupReadyFrame (dungeon found popup)
  -- ============================================================
  StripTextures(LFTGroupReadyFrame, true)
  CreateBackdrop(LFTGroupReadyFrame, nil, nil, .9)
  CreateBackdropShadow(LFTGroupReadyFrame)

  SkinButton(LFTGroupReadyFrameConfirmButton)
  SkinButton(LFTGroupReadyFrameDeclineButton)

  -- ============================================================
  --  LFTGroupReadyStatusFrame (waiting-for-others popup)
  -- ============================================================
  StripTextures(LFTGroupReadyStatusFrame, true)
  CreateBackdrop(LFTGroupReadyStatusFrame, nil, nil, .9)
  CreateBackdropShadow(LFTGroupReadyStatusFrame)
end)