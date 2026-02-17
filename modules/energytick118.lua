pfUI:RegisterModule("energytick", "vanilla:tbc", function ()
  if not pfUI.uf or not pfUI.uf.player then return end
  local energytick = CreateFrame("Frame", nil, pfUI.uf.player.power.bar)
  energytick:SetAllPoints(pfUI.uf.player.power.bar)
  energytick:RegisterEvent("PLAYER_ENTERING_WORLD")
  energytick:RegisterEvent("UNIT_DISPLAYPOWER")
  energytick:RegisterEvent("UNIT_ENERGY")
  energytick:RegisterEvent("UNIT_MANA")
  energytick:RegisterEvent("CHARACTER_POINTS_CHANGED") -- For talent changes
  energytick:RegisterEvent("UNIT_STATS") -- For agility changes
  
  -- Function to calculate current energy tick rate
  local function GetEnergyTickRate()
    local baseTickRate = 2.0 -- Base 2 seconds
    
    -- Check for Blade Rush talent (tab 2, talent 16)
    local _, _, _, _, currRank = GetTalentInfo(2, 16)
    local bladeRushRank = currRank or 0
    
    if bladeRushRank > 0 then
      local agility = UnitStat("player", 2) -- 2 is agility stat index
      local reductionPerAgi = 0.0006 * bladeRushRank -- 0.0006 for rank 1, 0.0012 for rank 2
      local totalReduction = agility * reductionPerAgi
      baseTickRate = baseTickRate - totalReduction
      
      -- Ensure we don't go below a reasonable minimum (e.g., 0.5 seconds)
      if baseTickRate < 0.5 then
        baseTickRate = 0.5
      end
    end
    
    return baseTickRate
  end
  
  energytick:SetScript("OnEvent", function()
    if UnitPowerType("player") == 0 and C.unitframes.player.manatick == "1" then
      this.mode = "MANA"
      this:Show()
    elseif UnitPowerType("player") == 3 and C.unitframes.player.energy == "1" then
      this.mode = "ENERGY"
      this:Show()
    else
      this:Hide()
    end
    
    if event == "PLAYER_ENTERING_WORLD" then
      this.lastMana = UnitMana("player")
    end
    
    -- Recalculate tick rate when talents or stats change
    if event == "CHARACTER_POINTS_CHANGED" or event == "UNIT_STATS" then
      if this.mode == "ENERGY" then
        this.energyTickRate = GetEnergyTickRate()
      end
    end
    
    if (event == "UNIT_MANA" or event == "UNIT_ENERGY") and arg1 == "player" then
      this.currentMana = UnitMana("player")
      local diff = 0
      if this.lastMana then
        diff = this.currentMana - this.lastMana
      end
      
      if this.mode == "MANA" and diff < 0 then
        this.target = 5
      elseif this.mode == "MANA" and diff > 0 then
        if this.max ~= 5 and diff > (this.badtick and this.badtick*1.2 or 5) then
          this.target = 2
        else
          this.badtick = diff
        end
      elseif this.mode == "ENERGY" and diff > 0 then
        -- Use dynamic tick rate for energy
        this.energyTickRate = GetEnergyTickRate()
        this.target = this.energyTickRate
      end
      this.lastMana = this.currentMana
    end
  end)
  
  energytick:SetScript("OnUpdate", function()
    if this.target then
      this.start, this.max = GetTime(), this.target
      this.target = nil
    end
    if not this.start then return end
    
    this.current = GetTime() - this.start
    if this.current > this.max then
      -- For energy mode, use dynamic tick rate; for mana, use default 2 seconds
      local nextTickRate = (this.mode == "ENERGY") and GetEnergyTickRate() or 2
      this.start, this.max, this.current = GetTime(), nextTickRate, 0
    end
    
    local pos = (C.unitframes.player.pwidth ~= "-1" and C.unitframes.player.pwidth or C.unitframes.player.width) * (this.current / this.max)
    if not C.unitframes.player.pheight then return end
    this.spark:SetPoint("LEFT", pos-((C.unitframes.player.pheight+5)/2), 0)
  end)
  
  energytick.spark = energytick:CreateTexture(nil, 'OVERLAY')
  energytick.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
  energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
  energytick.spark:SetBlendMode('ADD')
  
  -- update spark size on player frame changes
  local hookUpdateConfig = pfUI.uf.player.UpdateConfig
  function pfUI.uf.player.UpdateConfig()
    -- update spark sizes
    energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
    energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
    -- run default unitframe update function
    hookUpdateConfig(pfUI.uf.player)
  end
end)