pfUI:RegisterSkin("RaidUI", function ()
  HookAddonOrVariable("Blizzard_RaidUI", function()

    for i = 1, (NUM_RAID_GROUPS or 8) do
      local group = _G["RaidGroup"..i]
      if group and group.GetRegions then
        StripTextures(group)

        for j = 1, (MEMBERS_PER_RAID_GROUP or 5) do
          local slot = _G["RaidGroup"..i.."Slot"..j]
          if slot and slot.GetRegions then
            StripTextures(slot)
            CreateBackdrop(slot, nil, true)
            SetHighlight(slot, 1, 1, 0)
          end
        end
      end
    end

    for i = 1, (MAX_RAID_MEMBERS or 40) do
      local button = _G["RaidGroupButton"..i]
      if button and button.GetRegions then
        StripTextures(button)
        CreateBackdrop(button, nil, true)
        SetHighlight(button, 1, 1, 0)
      end
    end

    if RaidFrameAddMemberButton  then SkinButton(RaidFrameAddMemberButton)  end
    if RaidFrameReadyCheckButton then SkinButton(RaidFrameReadyCheckButton) end

  end)
end)