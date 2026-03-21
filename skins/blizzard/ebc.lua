pfUI:RegisterSkin("Everlook Broadcasting", "vanilla", function ()
  if not EBC_Minimap then return end

  -- Minimap button border
  for _, region in ipairs({ EBC_Minimap:GetRegions() }) do
    if region.GetTexture and region:GetTexture() == "Interface\\Minimap\\MiniMap-TrackingBorder" then
      region:SetTexture(nil)
    end
  end

  -- Dropdown panel
  if EBCMinimapDropdown then
    StripTextures(EBCMinimapDropdown)
    CreateBackdrop(EBCMinimapDropdown, nil, nil, .75)
    CreateBackdropShadow(EBCMinimapDropdown)

    -- Checkbuttons
    for i = 1, 2 do
      local cb = _G["EBCMinimapDropdownCheckButton" .. i]
      if cb then
        SkinCheckbox(cb)
      end
    end

    -- Volume slider
    if EBCMinimapDropdownSlider then
      SkinSlider(EBCMinimapDropdownSlider)
    end
  end
end)
