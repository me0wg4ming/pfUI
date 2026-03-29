pfUI:RegisterModule("updatenotify", function ()
  local alreadyshown = false
  local localversion  = tonumber(pfUI.version.major*10000 + pfUI.version.minor*100 + pfUI.version.fix)
  local remoteversion = tonumber(pfUI_init.updateavailable) or 0
  local loginchannels = { "BATTLEGROUND", "RAID", "GUILD" }
  local groupchannels = { "BATTLEGROUND", "RAID" }

  -- Determine branch from toc version string.
  -- experiment toc has "9.x.x (experiment version)", master does not.
  -- Only notify players on the same branch about updates.
  local tocversion = GetAddOnMetadata(pfUI.name, "Version") or ""
  local localbranch = strfind(tocversion, "experiment") and "exp" or "master"
  local versionmsg  = "VERSION:" .. localversion .. ":" .. localbranch

  pfUI.updater = CreateFrame("Frame")
  pfUI.updater:RegisterEvent("CHAT_MSG_ADDON")
  pfUI.updater:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.updater:RegisterEvent("PARTY_MEMBERS_CHANGED")
  pfUI.updater:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" and arg1 == "pfUI" then
      local v, rv, branch = pfUI.api.strsplit(":", arg2)
      local rv = tonumber(rv)
      -- only process VERSION messages from the same branch
      -- messages without a branch tag (old versions) are ignored
      if v == "VERSION" and rv and branch == localbranch then
        if rv > localversion then
          pfUI_init.updateavailable = rv
        end
      end
    end

    if event == "PARTY_MEMBERS_CHANGED" then
      local groupsize = GetNumRaidMembers() > 0 and GetNumRaidMembers() or GetNumPartyMembers() > 0 and GetNumPartyMembers() or 0
      if ( this.group or 0 ) < groupsize then
        for _, chan in pairs(groupchannels) do
          SendAddonMessage("pfUI", versionmsg, chan)
        end
      end
      this.group = groupsize
    end

    if event == "PLAYER_ENTERING_WORLD" then
      if not alreadyshown and localversion < remoteversion then
        DEFAULT_CHAT_FRAME:AddMessage(T["|cff33ffccpf|rUI: New version available! Have a look at http://shagu.org !"])
        DEFAULT_CHAT_FRAME:AddMessage(T["|cffddddddIt's always safe to upgrade |cff33ffccpf|rUI. |cffddddddYou won't lose any of your configuration."])
        pfUI_init.updateavailable = localversion
        alreadyshown = true
      end

      for _, chan in pairs(loginchannels) do
        SendAddonMessage("pfUI", versionmsg, chan)
      end
    end
  end)
end)
