pfUI:RegisterModule("tracking", "vanilla", function ()

  MINIMAP_TRACKING_FRAME:UnregisterAllEvents()
  MINIMAP_TRACKING_FRAME:Hide()

  local function HasEntries(tbl)
    for _ in pairs(tbl) do
      return true
    end
    return nil
  end

  local rawborder, border = GetBorderSize()
  local size = tonumber(C.appearance.minimap.tracking_size)
  local pulse = C.appearance.minimap.tracking_pulse == "1"

  local knownTrackingSpells = {
    any = {
      2481,  -- Find Treasure
      2580,  -- Find Minerals
      2383,  -- Find Herbs
      52917, -- Find Trees
    },
    HUNTER = {
      1494,  -- Track Beasts, 4+
      19883, -- Track Humanoids, 10+
      19884, -- Track Undead, 18+
      19885, -- Track Hidden, 24+
      19880, -- Track Elementals, 26+
      19878, -- Track Demons, 32+
      19882, -- Track Giants, 40+
      19879  -- Track Dragonkin, 50+	  
    },
    PALADIN = {
      5502   -- Sense Undead, 20+
    },
    WARLOCK = {
      5500   -- Sense Demons, 24+
    },
    DRUID = {
      5225   -- Track Humanoids, 32+, Cat Form only!
    }
  }

  local state = {
    texture = nil,
    spells = {}
  }

  pfUI.tracking = CreateFrame("Button", "pfUITracking", UIParent)

  pfUI.tracking:SetFrameStrata("HIGH")
  CreateBackdrop(pfUI.tracking, border)
  CreateBackdropShadow(pfUI.tracking)

  pfUI.tracking:SetPoint("TOPLEFT", pfUI.minimap, -10, -10)
  UpdateMovable(pfUI.tracking)
  pfUI.tracking:SetWidth(size)
  pfUI.tracking:SetHeight(size)

  pfUI.tracking.icon = pfUI.tracking:CreateTexture("BACKGROUND")
  pfUI.tracking.icon:SetTexCoord(.08, .92, .08, .92)
  pfUI.tracking.icon:SetAllPoints(pfUI.tracking)

  pfUI.tracking.menu = CreateFrame("Frame", "pfUIDropDownMenuTracking", nil, "UIDropDownMenuTemplate")

  pfUI.tracking:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.tracking:RegisterEvent("PLAYER_AURAS_CHANGED")
  pfUI.tracking:RegisterEvent("SPELLS_CHANGED")
  pfUI.tracking:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  pfUI.tracking:SetScript("OnEvent", function()
    if event == "SPELLS_CHANGED" then
      state.spells = {}
    end

    this:RefreshSpells()
    this:RefreshMenu()
  end)

  pfUI.tracking:SetScript("OnUpdate", function()
    if this.pulse then
      local _,_,_,alpha = this.icon:GetVertexColor()
      local fpsmod = GetFramerate() / 30
      if not alpha or alpha >= 0.9 then
        this.modifier = -0.03 / fpsmod
      elseif alpha <= .5 then
        this.modifier = 0.03  / fpsmod
      end

      this.icon:SetVertexColor(1,1,1,alpha + this.modifier)
    end
  end)

  pfUI.tracking:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pfUI.tracking:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      pfUI.tracking:InitMenu()
      ToggleDropDownMenu(1, nil, pfUI.tracking.menu, this, -5, -5)
    end
    if arg1 == "LeftButton" and state.texture then
      CancelTrackingBuff()
    end
  end)

  pfUI.tracking:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    if state.texture then
      GameTooltip:SetTrackingSpell()
    else
      GameTooltip:SetText(T["No tracking spell active"])
    end
    GameTooltip:Show()
  end)

  pfUI.tracking:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local function addSpell(spellId)
    if state.spells[spellId] then return end

    local spellName = GetSpellRecField(spellId, "name")
    local spellIndex = GetSpellSlotTypeIdForName(spellName)

    if spellIndex ~= 0 then
      local spellIconId = GetSpellRecField(spellId, "spellIconID")
      local spellTexture = GetSpellIconTexture(spellIconId)

      state.spells[spellId] = {
        index = spellIndex,
        name = spellName,
        texture = spellTexture
      }
    end
  end

  function pfUI.tracking:RefreshSpells()
    local _, playerClass = UnitClass("player")
    local isCatForm = pfUI.tracking:PlayerIsDruidInCatForm(playerClass)

	  -- scan for generic tracking icons
    for _, spellId in pairs(knownTrackingSpells["any"]) do
	    addSpell(spellId)
	  end

    -- scan class specific tracking icons
    if knownTrackingSpells[playerClass] then
      for _, spellId in pairs(knownTrackingSpells[playerClass]) do
        addSpell(spellId)
      end
    end

    -- remove humanoid tracking for non-cat druids
    if playerClass == "DRUID" and not isCatForm then
      state.spells[5225] = nil
    end
  end

  function pfUI.tracking:RefreshMenu()
    local texture = GetTrackingTexture()
    if texture and texture ~= state.texture then
      state.texture = texture
      pfUI.tracking.pulse = nil
      pfUI.tracking.icon:SetTexture(texture)
      pfUI.tracking.icon:SetVertexColor(1,1,1,1)
      pfUI.tracking:Show()
    elseif not texture then
      state.texture = nil

      if pulse and HasEntries(state.spells) then
        pfUI.tracking.pulse = true
        pfUI.tracking.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        pfUI.tracking.icon:SetVertexColor(1,1,1,1)
        pfUI.tracking:Show()
      else
        pfUI.tracking.pulse = nil
        pfUI.tracking:Hide()
      end
    end
  end

  function pfUI.tracking:PlayerIsDruidInCatForm(playerClass)
    if playerClass == "DRUID" then
      for i = 0, 31 do
        local texture = GetPlayerBuffTexture(i)
        if not texture then break end
        if strfind(texture, "Ability_Druid_CatForm") then
          return true
        end
      end
    end
    return false
  end

  function pfUI.tracking:InitMenu()
    UIDropDownMenu_Initialize(pfUI.tracking.menu, function ()
      UIDropDownMenu_AddButton({text = T["Minimap Tracking"], isTitle = 1})

      local sorted = {}
      for _, spell in pairs(state.spells) do
        table.insert(sorted, spell)
      end
      table.sort(sorted, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
      end)

      for _, spell in pairs(sorted) do
        UIDropDownMenu_AddButton({
          text = spell.name,
          icon = spell.texture,
          tCoordLeft = .1,
          tCoordRight = .9,
          tCoordTop = .1,
          tCoordBottom = .9,
          checked = spell.texture == state.texture,
          arg1 = spell,
          func = function (arg1)
            CastSpell(arg1.index, BOOKTYPE_SPELL)
            CloseDropDownMenus()
          end
        })
      end
    end, "MENU")
  end
end)
