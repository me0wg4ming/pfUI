pfUI:RegisterSkin("RaidUI", "vanilla", function ()
  HookAddonOrVariable("Blizzard_RaidUI", function()

    -- skin each RaidGroup frame (8 groups, each with a label + 5 slots)
    for i = 1, NUM_RAID_GROUPS do
      local group = _G["RaidGroup"..i]
      if group then
        StripTextures(group)
        CreateBackdrop(group, nil, nil, .75)

        local label = _G["RaidGroup"..i.."Label"]
        if label then
          label:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        end
      end
    end

    -- skin each RaidGroupButton (40 members)
    for i = 1, MAX_RAID_MEMBERS do
      local button = _G["RaidGroupButton"..i]
      if button then
        StripTextures(button)
        CreateBackdrop(button, nil, nil, .75)

        local name  = _G["RaidGroupButton"..i.."Name"]
        local level = _G["RaidGroupButton"..i.."Level"]
        local class = _G["RaidGroupButton"..i.."Class"]
        if name  then name:SetFont(pfUI.font_default,  C.global.font_size, "OUTLINE") end
        if level then level:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE") end
        if class then class:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE") end
      end
    end

    -- skin the Add Member and Ready Check buttons on the RaidFrame panel
    SkinButton(RaidFrameAddMemberButton)
    SkinButton(RaidFrameReadyCheckButton)

  end)
end)
