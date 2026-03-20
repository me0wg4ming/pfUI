pfUI:RegisterSkin("RaidUI", "vanilla", function ()
  HookAddonOrVariable("Blizzard_RaidUI", function()

    for i = 1, NUM_RAID_GROUPS do
      local group = _G["RaidGroup"..i]
      if group then
        StripTextures(group)

        for j = 1, MEMBERS_PER_RAID_GROUP do
          local slot = _G["RaidGroup"..i.."Slot"..j]
          if slot then
            StripTextures(slot)
            CreateBackdrop(slot, nil, true)
            SetHighlight(slot, 1, 1, 0)

          end
        end
      end
    end

    for i = 1, MAX_RAID_MEMBERS do
      local button = _G["RaidGroupButton"..i]
      if button then
        StripTextures(button)
        CreateBackdrop(button, nil, true)
        SetHighlight(button, 1, 1, 0)
      end
    end

    if RaidFrameAddMemberButton  then SkinButton(RaidFrameAddMemberButton)  end
    if RaidFrameReadyCheckButton then SkinButton(RaidFrameReadyCheckButton) end

  end)
end)
