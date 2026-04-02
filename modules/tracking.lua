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

  -- Tracking spells identified by SpellID + expected icon path.
  -- SpellID is the primary identifier (stable, locale-independent).
  -- Icon path is used as secondary confirmation when scanning the spellbook.
  local knownTrackingSpells = {
    any = {
      { id = 2481,  icon = "Racial_Dwarf_FindTreasure"       }, -- Find Treasure
      { id = 2580,  icon = "Spell_Nature_Earthquake"          }, -- Find Minerals
      { id = 2383,  icon = "INV_Misc_Flower_02"               }, -- Find Herbs (Rank 1)
      { id = 8387,  icon = "INV_Misc_Flower_02"               }, -- Find Herbs (Rank 2)
      { id = 52917, icon = "INV_TradeSkillItem_03"            }, -- Find Trees (TurtleWow)
    },
    HUNTER = {
      { id = 1494,  icon = "Ability_Tracking"                 }, -- Track Beasts
      { id = 19883, icon = "Spell_Holy_PrayerOfHealing"       }, -- Track Humanoids
      { id = 19884, icon = "Spell_Shadow_DarkSummoning"       }, -- Track Undead
      { id = 19885, icon = "Ability_Stealth"                  }, -- Track Hidden
      { id = 19880, icon = "Spell_Frost_SummonWaterElemental" }, -- Track Elementals
      { id = 19878, icon = "Spell_Shadow_SummonFelHunter"     }, -- Track Demons
      { id = 19882, icon = "Ability_Racial_Avatar"            }, -- Track Giants
      { id = 19879, icon = "INV_Misc_Head_Dragon_01"          }, -- Track Dragonkin
    },
    PALADIN = {
      { id = 5502,  icon = "Spell_Holy_SenseUndead"           }, -- Sense Undead
    },
    WARLOCK = {
      { id = 5500,  icon = "Spell_Shadow_Metamorphosis"       }, -- Sense Demons
    },
    DRUID = {
      { id = 5225,  icon = "Ability_Tracking"                 }, -- Track Humanoids (Cat Form only)
    },
  }

  -- Build a flat lookup: spellId -> entry, for fast spellbook matching
  local spellIdLookup = {}
  for _, entries in pairs(knownTrackingSpells) do
    for _, entry in ipairs(entries) do
      spellIdLookup[entry.id] = entry
    end
  end

  local state = {
    texture = nil,
    spells = {}
  }

  pfUI.tracking = CreateFrame("Button", "pfUITracking", UIParent)
  pfUI.tracking.invalidSpells = {}

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

  function pfUI.tracking:RefreshSpells()
    local _, playerClass = UnitClass("player")
    local isCatForm = pfUI.tracking:PlayerIsDruidInCatForm(playerClass)

    -- Build set of valid SpellIDs for this class
    local validIds = {}
    for _, entry in ipairs(knownTrackingSpells.any) do
      validIds[entry.id] = true
    end
    if knownTrackingSpells[playerClass] then
      for _, entry in ipairs(knownTrackingSpells[playerClass]) do
        validIds[entry.id] = true
      end
    end

    -- Druids only get Track Humanoids in Cat Form
    if playerClass == "DRUID" and not isCatForm then
      validIds[5225] = nil
    end

    -- Scan spellbook: match by icon path, confirm SpellID is valid for this class
    for tabIndex = 1, GetNumSpellTabs() do
      local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
      for spellIndex = offset + 1, offset + numSpells do
        local spellTexture = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
        local spellName    = GetSpellName(spellIndex, BOOKTYPE_SPELL)

        if pfUI.tracking.invalidSpells[spellName] then
          spellTexture = nil
        end

        if spellTexture then
          local lowerTexture = string.lower(spellTexture)
          for spellId, entry in pairs(spellIdLookup) do
            if validIds[spellId] and not state.spells[spellId]
              and strfind(lowerTexture, string.lower(entry.icon)) then
              state.spells[spellId] = {
                index   = spellIndex,
                name    = spellName,
                texture = spellTexture,
                spellId = spellId,
              }
            end
          end
        end
      end
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
      local b = GetUnitField("player", "bytes1")
      if b then
        local form = math.floor(b / 65536) - math.floor(b / 16777216) * 256
        return form == 1  -- 1 = Cat Form
      end
    end
    return false
  end

  function pfUI.tracking:InitMenu()
    UIDropDownMenu_Initialize(pfUI.tracking.menu, function ()
      UIDropDownMenu_AddButton({text = T["Minimap Tracking"], isTitle = 1})
      for _, spell in pairs(state.spells) do
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