-- UnitXP_SP3 integration module
-- Provides Line of Sight indicator, OS notifications, and enhanced targeting
-- Requires UnitXP_SP3 DLL: https://github.com/allfoxwy/UnitXP_SP3

pfUI:RegisterModule("unitxp", "vanilla", function ()
  -- Check if UnitXP is available
  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if not hasUnitXP then return end

  local rawborder, border = GetBorderSize()

  -- Helper to create indicators after target frame exists
  local function CreateTargetIndicators()
    if not pfUI.uf or not pfUI.uf.target then return false end

    -- Behind Indicator for all units (TOP)
    if C.unitframes.behind_indicator == "1" and not pfUI.uf.target.behindIndicator then
      local behindFrame = CreateFrame("Frame", "pfBehindIndicator", pfUI.uf.target)
      behindFrame:SetAllPoints(pfUI.uf.target)
      behindFrame:SetFrameLevel(pfUI.uf.target:GetFrameLevel() + 10)

      behindFrame.text = behindFrame:CreateFontString(nil, "OVERLAY")
      behindFrame.text:SetFont(pfUI.font_default, 13, "OUTLINE")
      behindFrame.text:SetPoint("RIGHT", behindFrame, "RIGHT", -1, 7)
      behindFrame.text:SetTextColor(0.3, 1, 0.3, 1)
      behindFrame.text:SetText("BEHIND")
      behindFrame.text:Hide()

      local lastCheck = 0
      behindFrame:SetScript("OnUpdate", function()
        if GetTime() - lastCheck < 0.1 then return end
        lastCheck = GetTime()

        if not UnitExists("target") then
          this.text:Hide()
          return
        end

        local success, behind = pcall(UnitXP, "behind", "player", "target")
        if success and behind then
          this.text:Show()
        else
          this.text:Hide()
        end
      end)

      pfUI.uf.target.behindIndicator = behindFrame
    end

    -- Line of Sight Indicator on Target Frame (BELOW BEHIND)
    if C.unitframes.los_indicator == "1" and not pfUI.uf.target.losIndicator then
      local losFrame = CreateFrame("Frame", "pfLoSIndicator", pfUI.uf.target)
      losFrame:SetAllPoints(pfUI.uf.target)
      losFrame:SetFrameLevel(pfUI.uf.target:GetFrameLevel() + 10)

      losFrame.text = losFrame:CreateFontString(nil, "OVERLAY")
      losFrame.text:SetFont(pfUI.font_default, 13, "OUTLINE")
      losFrame.text:SetPoint("RIGHT", losFrame, "RIGHT", -1, -7)
      losFrame.text:SetTextColor(1, 0.3, 0.3, 1)
      losFrame.text:SetText("NO LOS")
      losFrame.text:Hide()

      local lastCheck = 0
      losFrame:SetScript("OnUpdate", function()
        if GetTime() - lastCheck < 0.2 then return end
        lastCheck = GetTime()

        if not UnitExists("target") then
          this.text:Hide()
          return
        end

        local success, inSight = pcall(UnitXP, "inSight", "player", "target")
        if success and inSight == false then
          this.text:Show()
        else
          this.text:Hide()
        end
      end)

      pfUI.uf.target.losIndicator = losFrame
    end

    return true
  end

  -- Try to create indicators now
  CreateTargetIndicators()

  -- Also try on PLAYER_ENTERING_WORLD in case target frame wasn't ready
  local initFrame = CreateFrame("Frame")
  initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  initFrame:RegisterEvent("PLAYER_LOGOUT")
  initFrame:SetScript("OnEvent", function()
    -- Handle shutdown to prevent crash 132
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      -- Stop indicator OnUpdate scripts
      if pfUI.uf and pfUI.uf.target then
        if pfUI.uf.target.behindIndicator then
          pfUI.uf.target.behindIndicator:SetScript("OnUpdate", nil)
        end
        if pfUI.uf.target.losIndicator then
          pfUI.uf.target.losIndicator:SetScript("OnUpdate", nil)
        end
      end
      return
    end
    
    CreateTargetIndicators()
    this:UnregisterAllEvents()
  end)

  -- OS Notification Support
  if C.unitframes.unitxp_notify == "1" then
    local notifyFrame = CreateFrame("Frame")
    notifyFrame:RegisterEvent("CHAT_MSG_WHISPER")
    notifyFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    notifyFrame:RegisterEvent("READY_CHECK")
    notifyFrame:RegisterEvent("RAID_INSTANCE_WELCOME")
    notifyFrame:RegisterEvent("PLAYER_LOGOUT")

    notifyFrame:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      
      pcall(UnitXP, "notify", "taskbarIcon")
      pcall(UnitXP, "notify", "systemSound")
    end)

    -- Also notify on BG queue pop
    local origBattlefieldPortShow = BattlefieldFrame_Show
    if origBattlefieldPortShow then
      BattlefieldFrame_Show = function()
        pcall(UnitXP, "notify", "taskbarIcon")
        pcall(UnitXP, "notify", "systemSound")
        return origBattlefieldPortShow()
      end
    end
  end

  -- Enhanced Distance API
  pfUI.api.GetPreciseDistance = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    local success, distance = pcall(UnitXP, "distanceBetween", unit1, unit2)
    if success then return distance end
    return nil
  end

  pfUI.api.IsInMeleeRange = function(unit)
    local success, distance = pcall(UnitXP, "distanceBetween", "player", unit, "meleeAutoAttack")
    if success and distance then
      return distance <= 5
    end
    return nil
  end

  pfUI.api.GetAoEDistance = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    local success, distance = pcall(UnitXP, "distanceBetween", unit1, unit2, "AoE")
    if success then return distance end
    return nil
  end

  -- Smart Targeting Helpers
  pfUI.api.TargetNearestEnemy = function()
    local success, found = pcall(UnitXP, "target", "nearestEnemy")
    return success and found
  end

  pfUI.api.TargetHighestHP = function()
    local success, found = pcall(UnitXP, "target", "mostHP")
    return success and found
  end

  pfUI.api.TargetNextEnemy = function()
    local success, found = pcall(UnitXP, "target", "nextEnemyInCycle")
    return success and found
  end

  pfUI.api.TargetPreviousEnemy = function()
    local success, found = pcall(UnitXP, "target", "previousEnemyInCycle")
    return success and found
  end

  pfUI.api.TargetNextMarked = function(order)
    local success, found = pcall(UnitXP, "target", "nextMarkedEnemyInCycle", order)
    return success and found
  end

  pfUI.api.UnitInLineOfSight = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    local success, inSight = pcall(UnitXP, "inSight", unit1, unit2)
    if success then return inSight end
    return nil
  end

  pfUI.api.UnitIsBehind = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    local success, behind = pcall(UnitXP, "behind", unit1, unit2)
    if success then return behind end
    return nil
  end

  -- Debug command to test UnitXP indicators
  SLASH_PFUNITXP1 = "/pfunitxp"
  SlashCmdList["PFUNITXP"] = function()
    local chat = DEFAULT_CHAT_FRAME
    chat:AddMessage("|cff33ffccpfUI|r: UnitXP Indicator Debug")

    -- Check if target exists
    if not UnitExists("target") then
      chat:AddMessage("  |cffff0000No target selected|r")
      return
    end

    -- Test behind
    local successB, behind = pcall(UnitXP, "behind", "player", "target")
    chat:AddMessage("  Behind check: success=" .. tostring(successB) .. " value=" .. tostring(behind) .. " type=" .. type(behind))

    -- Test LOS
    local successL, inSight = pcall(UnitXP, "inSight", "player", "target")
    chat:AddMessage("  LOS check: success=" .. tostring(successL) .. " value=" .. tostring(inSight) .. " type=" .. type(inSight))

    -- Check if indicator frames exist
    if pfUI.uf and pfUI.uf.target then
      chat:AddMessage("  Target frame: |cff00ff00exists|r")
      if pfUI.uf.target.behindIndicator then
        chat:AddMessage("  Behind indicator: |cff00ff00created|r, visible=" .. tostring(pfUI.uf.target.behindIndicator:IsVisible()))
      else
        chat:AddMessage("  Behind indicator: |cffff0000NOT created|r (check settings)")
      end
      if pfUI.uf.target.losIndicator then
        chat:AddMessage("  LOS indicator: |cff00ff00created|r")
      else
        chat:AddMessage("  LOS indicator: |cffff0000NOT created|r (check settings)")
      end
    else
      chat:AddMessage("  Target frame: |cffff0000NOT found|r")
    end
  end
end)
