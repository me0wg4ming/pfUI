-- Compatibility layer to use castbars provided by SuperWoW:
-- https://github.com/balakethelock/SuperWoW

-- DLL Status Check Command (always available)
SLASH_PFDLLSTATUS1 = "/pfdll"
SlashCmdList["PFDLLSTATUS"] = function()
  local chat = DEFAULT_CHAT_FRAME
  chat:AddMessage("|cff33ffccpfUI|r: DLL Status Check")

  -- SuperWoW
  if SUPERWOW_VERSION then
    chat:AddMessage("  |cff00ff00SuperWoW|r: v" .. tostring(SUPERWOW_VERSION))
  elseif SpellInfo or SetAutoloot then
    chat:AddMessage("  |cffffff00SuperWoW|r: Detected (old version)")
  else
    chat:AddMessage("  |cffff0000SuperWoW|r: Not detected")
  end

  -- Nampower
  if GetNampowerVersion then
    chat:AddMessage("  |cff00ff00Nampower|r: v" .. tostring(GetNampowerVersion()))
  else
    chat:AddMessage("  |cffff0000Nampower|r: Not detected")
  end

  -- UnitXP
  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if hasUnitXP then
    chat:AddMessage("  |cff00ff00UnitXP_SP3|r: Detected")
  else
    chat:AddMessage("  |cffff0000UnitXP_SP3|r: Not detected")
  end

  -- Check if castbar exists for indicator positioning
  if pfUI.castbar and pfUI.castbar.player then
    chat:AddMessage("  |cff00ff00Castbar|r: Available for indicator anchoring")
  else
    chat:AddMessage("  |cffffff00Castbar|r: Not available (indicators use fallback position)")
  end

  -- Check indicator frames
  if pfUI.uf and pfUI.uf.target then
    chat:AddMessage("  |cff00ff00Target frame|r: exists")
    if pfUI.uf.target.behindIndicator then
      chat:AddMessage("  |cff00ff00Behind indicator|r: created")
    else
      chat:AddMessage("  |cffff0000Behind indicator|r: NOT created")
    end
    if pfUI.uf.target.losIndicator then
      chat:AddMessage("  |cff00ff00LOS indicator|r: created")
    else
      chat:AddMessage("  |cffff0000LOS indicator|r: NOT created")
    end
  else
    chat:AddMessage("  |cffff0000Target frame|r: NOT found")
  end
end

-- UnitXP Behind/LOS test command
SLASH_PFBEHIND1 = "/pfbehind"
SlashCmdList["PFBEHIND"] = function()
  local chat = DEFAULT_CHAT_FRAME
  if not UnitExists("target") then
    chat:AddMessage("|cff33ffccpfUI|r: No target")
    return
  end

  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if not hasUnitXP then
    chat:AddMessage("|cff33ffccpfUI|r: UnitXP not available")
    return
  end

  local successB, behind = pcall(UnitXP, "behind", "player", "target")
  local successL, inSight = pcall(UnitXP, "inSight", "player", "target")

  chat:AddMessage("|cff33ffccpfUI|r: Behind=" .. tostring(behind) .. " LOS=" .. tostring(inSight))
end

pfUI:RegisterModule("superwow", "vanilla", function ()
  if SetAutoloot and SpellInfo and not SUPERWOW_VERSION then
    -- Turn every enchanting link that we create in the enchanting frame,
    -- from "spell:" back into "enchant:". The enchant-version is what is
    -- used by all unmodified game clients. This is required to generate
    -- usable links for everyone from the enchant frame while having SuperWoW.
    local HookGetCraftItemLink = GetCraftItemLink
    _G.GetCraftItemLink = function(index)
      local link = HookGetCraftItemLink(index)
      return string.gsub(link, "spell:", "enchant:")
    end

    -- Convert every enchanting link that we receive into a
    -- spell link, as for some reason SuperWoW can't handle
    -- enchanting links at all and requires it to be a spell.
    local HookSetItemRef = SetItemRef
    _G.SetItemRef = function(link, text, button)
      link = string.gsub(link, "enchant:", "spell:")
      HookSetItemRef(link, text, button)
    end

    local HookGameTooltipSetHyperlink = GameTooltip.SetHyperlink
    _G.GameTooltip.SetHyperlink = function(self, link)
      link = string.gsub(link, "enchant:", "spell:")
      HookGameTooltipSetHyperlink(self, link)
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffffffaaAn old version of SuperWoW was detected. Please consider updating:")
    DEFAULT_CHAT_FRAME:AddMessage("-> https://github.com/balakethelock/SuperWoW/releases/")
  end

  if SUPERWOW_VERSION == "1.5" then
    QueueFunction(function()
      local pfCombatText_AddMessage = _G.CombatText_AddMessage
      _G.CombatText_AddMessage = function(message, a, b, c, d, e, f)
        local match, _, hex = string.find(message, ".+ %[(0x.+)%]")
        if hex and UnitName(hex) then
          message = string.gsub(message, hex, UnitName(hex))
        end

        pfCombatText_AddMessage(message, a, b, c, d, e, f)
      end
    end)
  end

  -- Add native mouseover support
  if SUPERWOW_VERSION and pfUI.uf and pfUI.uf.mouseover then
    _G.SlashCmdList.PFCAST = function(msg)
      local func = loadstring(msg or "")
      local unit = "mouseover"

      if not UnitExists(unit) then
        local frame = GetMouseFocus()
        if frame.label and frame.id then
          unit = frame.label .. frame.id
        elseif UnitExists("target") then
          unit = "target"
        elseif GetCVar("autoSelfCast") == "1" then
          unit = "player"
        else
          return
        end
      end

      if func then
        -- set mouseover to target for script if needed
        local switch_target = not UnitIsUnit("target", unit)
        if switch_target then TargetUnit(unit) end
        func()
        if switch_target then TargetLastTarget() end
      else
        -- write temporary unit name
        pfUI.uf.mouseover.unit = unit

        -- cast spell to unitstr
        CastSpellByName(msg, unit)

        -- remove temporary mouseover unit
        pfUI.uf.mouseover.unit = nil
      end
    end
  end

  -- Add support for druid mana bars
  if SUPERWOW_VERSION and pfUI.uf and pfUI.uf.player and pfUI_config.unitframes.druidmanabar == "1" then
    local parent = pfUI.uf.player.power.bar
    local config = pfUI.uf.player.config
    local mana = config.defcolor == "0" and config.manacolor or pfUI_config.unitframes.manacolor
    local r, g, b, a = pfUI.api.strsplit(",", mana)
    local rawborder, default_border = GetBorderSize("unitframes")
    local _, class = UnitClass("player")
    local width = config.pwidth ~= "-1" and config.pwidth or config.width

    local fontname = pfUI.font_unit
    local fontsize = tonumber(pfUI_config.global.font_unit_size)
    local fontstyle = pfUI_config.global.font_unit_style

    if config.customfont == "1" then
      fontname = pfUI.media[config.customfont_name]
      fontsize = tonumber(config.customfont_size)
      fontstyle = config.customfont_style
    end

    local druidmana = CreateFrame("StatusBar", "pfDruidMana", UIParent)
    druidmana:SetFrameStrata(parent:GetFrameStrata())
    druidmana:SetFrameLevel(parent:GetFrameLevel() + 16)
    druidmana:SetStatusBarTexture(pfUI.media[config.pbartexture])
    druidmana:SetStatusBarColor(r, g, b, a)
    druidmana:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2*default_border - config.pspace)
    druidmana:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2*default_border - config.pspace)
    druidmana:SetWidth(width)
    druidmana:SetHeight(tonumber(pfUI_config.unitframes.druidmanaheight) or 6)
    druidmana:EnableMouse(true)
    druidmana:Hide()

    UpdateMovable(druidmana)
    CreateBackdrop(druidmana)
    CreateBackdropShadow(druidmana)

    druidmana:RegisterEvent("UNIT_MANA")
    druidmana:RegisterEvent("UNIT_MAXMANA")
    druidmana:RegisterEvent("UNIT_DISPLAYPOWER")
    druidmana:SetScript("OnEvent", function()
      if UnitPowerType("player") == 0 then
        this:Hide()
        return
      end

      local _, mana = UnitMana("player")
      local _, max = UnitManaMax("player")
      local perc = math.ceil(mana / max * 100)
      if perc == 100 then
        this.text:SetText(string.format("%s", Abbreviate(mana)))
      else
        this.text:SetText(string.format("%s - %s%%", Abbreviate(mana), perc))
      end
      this:SetMinMaxValues(0, max)
      this:SetValue(mana)
      this:Show()
    end)

    druidmana.text = druidmana:CreateFontString("Status", "OVERLAY", "GameFontNormalSmall")
    druidmana.text:SetFontObject(GameFontWhite)
    druidmana.text:SetFont(fontname, fontsize, fontstyle)
    druidmana.text:SetPoint("RIGHT", -2*(default_border + config.txtpowerrightoffx), 0)
    druidmana.text:SetPoint("LEFT", 2*(default_border + config.txtpowerrightoffx), 0)
    druidmana.text:SetJustifyH("RIGHT")

    if config["powercolor"] == "1" then
      local r = ManaBarColor[0].r
      local g = ManaBarColor[0].g
      local b = ManaBarColor[0].b

      if pfUI_config.unitframes.pastel == "1" then
        druidmana.text:SetTextColor((r+.75)*.5, (g+.75)*.5, (b+.75)*.5, 1)
      else
        druidmana.text:SetTextColor(r, g, b, a)
      end
    end

    if pfUI_config.unitframes.druidmanatext == "1" then
      druidmana.text:Show()
    else
      druidmana.text:Hide()
    end

    if class ~= "DRUID" then
      druidmana:UnregisterAllEvents()
      druidmana:Hide()
    end
  end

  -- Add support for guid based focus frame
  if SUPERWOW_VERSION and pfUI.uf and pfUI.uf.focus then
    local focus = function(unitstr)
      -- try to read target's unit guid
      local _, guid = UnitExists(unitstr)

      if guid and pfUI.uf.focus then
        -- update focus frame
        pfUI.uf.focus.unitname = nil
        pfUI.uf.focus.label = guid
        pfUI.uf.focus.id = ""

        -- update focustarget frame
        pfUI.uf.focustarget.unitname = nil
        pfUI.uf.focustarget.label = guid .. "target"
        pfUI.uf.focustarget.id = ""
      end

      return guid
    end

    -- extend the builtin /focus slash command
    local legacyfocus = SlashCmdList.PFFOCUS
    function SlashCmdList.PFFOCUS(msg)
      -- try to perform guid based focus
      local guid = focus("target")

      -- run old focus emulation
      if not guid then legacyfocus(msg) end
    end

    -- extend the builtin /swapfocus slash command
    local legacyswapfocus = SlashCmdList.PFSWAPFOCUS
    function SlashCmdList.PFSWAPFOCUS(msg)
      -- save previous focus values
      local oldlabel = pfUI.uf.focus.label or ""
      local oldid = pfUI.uf.focus.id or ""

      -- try to perform guid based focus
      local guid = focus("target")

      -- target old focus
      if guid and oldlabel and oldid then
        TargetUnit(oldlabel..oldid)
      end

      -- run old focus emulation
      if not guid then legacyswapfocus(msg) end
    end
  end

  -- Enhance libdebuff with SuperWoW data
  local superdebuff = CreateFrame("Frame")
  superdebuff:RegisterEvent("UNIT_CASTEVENT")
  superdebuff:SetScript("OnEvent", function()
    -- variable assignments
    local caster, target, event, spell, duration = arg1, arg2, arg3, arg4

    -- skip other caster and empty target events
    local _, guid = UnitExists("player")
    if caster ~= guid then return end
    if event ~= "CAST" then return end
    if not target or target == "" then return end

    -- assign all required data
    local unit = UnitName(target)
    local unitlevel = UnitLevel(target)
    local effect, rank = SpellInfo(spell)
    local duration = libdebuff:GetDuration(effect, rank)
    local caster = "player"

    -- add effect to current debuff data
    libdebuff:AddEffect(unit, unitlevel, effect, duration, caster)
  end)

  -- TrackUnit API for adding group members to minimap
  -- Tracks friendly units on the minimap for easier group coordination
  if TrackUnit and C.unitframes.track_group == "1" then
    local trackFrame = CreateFrame("Frame")
    trackFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    trackFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    trackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    trackFrame:SetScript("OnEvent", function()
      -- Track party members
      for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsConnected(unit) then
          pcall(TrackUnit, unit)
        end
      end

      -- Track raid members
      for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsUnit(unit, "player") then
          pcall(TrackUnit, unit)
        end
      end
    end)
  end

  -- Raid Marker Targeting API
  -- Allows targeting units by raid marker ("mark1" to "mark8")
  if SUPERWOW_VERSION then
    pfUI.api.GetMarkedUnit = function(markIndex)
      local markUnit = "mark" .. markIndex
      if UnitExists(markUnit) then
        return markUnit
      end
      return nil
    end

    pfUI.api.TargetMark = function(markIndex)
      local markUnit = "mark" .. markIndex
      if UnitExists(markUnit) then
        TargetUnit(markUnit)
        return true
      end
      return false
    end

    -- Get owner of pet/totem using "owner" suffix
    pfUI.api.GetUnitOwner = function(unit)
      local ownerUnit = unit .. "owner"
      if UnitExists(ownerUnit) then
        return UnitName(ownerUnit), ownerUnit
      end
      return nil
    end
  end

  -- Enhanced SpellInfo API wrapper
  if SpellInfo then
    pfUI.api.GetSpellInfo = function(spellId)
      local name, rank, texture, minRange, maxRange = SpellInfo(spellId)
      return {
        name = name,
        rank = rank,
        texture = texture,
        minRange = minRange,
        maxRange = maxRange,
        spellId = spellId
      }
    end
  end

  -- Clickthrough Mode API
  -- Allows clicking through corpses to loot underneath
  if Clickthrough then
    pfUI.api.SetClickthrough = function(enabled)
      Clickthrough(enabled and 1 or 0)
    end

    pfUI.api.GetClickthrough = function()
      return Clickthrough() == 1
    end

    pfUI.api.ToggleClickthrough = function()
      local current = Clickthrough()
      Clickthrough(current == 1 and 0 or 1)
      return Clickthrough() == 1
    end

    -- Add slash command for clickthrough toggle
    SLASH_PFCLICKTHROUGH1 = "/clickthrough"
    SLASH_PFCLICKTHROUGH2 = "/ct"
    SlashCmdList["PFCLICKTHROUGH"] = function()
      local enabled = pfUI.api.ToggleClickthrough()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Clickthrough mode " .. (enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
    end
  end

  -- Autoloot Control API
  if SetAutoloot then
    pfUI.api.SetAutoloot = function(enabled)
      SetAutoloot(enabled and 1 or 0)
    end

    pfUI.api.GetAutoloot = function()
      return SetAutoloot() == 1
    end

    pfUI.api.ToggleAutoloot = function()
      local current = SetAutoloot()
      SetAutoloot(current == 1 and 0 or 1)
      return SetAutoloot() == 1
    end
  end

  -- Config Import/Export API using ImportFile/ExportFile
  if ImportFile and ExportFile then
    pfUI.api.ExportConfig = function(filename)
      filename = filename or "pfUI_config_backup.txt"
      local configStr = ""

      -- Serialize config to string
      local function serialize(tbl, indent)
        indent = indent or ""
        local result = "{\n"
        for k, v in pairs(tbl) do
          local keyStr = type(k) == "string" and '["' .. k .. '"]' or "[" .. tostring(k) .. "]"
          if type(v) == "table" then
            result = result .. indent .. "  " .. keyStr .. " = " .. serialize(v, indent .. "  ") .. ",\n"
          elseif type(v) == "string" then
            result = result .. indent .. "  " .. keyStr .. ' = "' .. v .. '",\n'
          else
            result = result .. indent .. "  " .. keyStr .. " = " .. tostring(v) .. ",\n"
          end
        end
        return result .. indent .. "}"
      end

      if pfUI_config then
        configStr = "pfUI_config = " .. serialize(pfUI_config)
        ExportFile(filename, configStr)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Config exported to imports/" .. filename)
        return true
      end
      return false
    end

    pfUI.api.ImportConfig = function(filename)
      filename = filename or "pfUI_config_backup.txt"
      local content = ImportFile(filename)
      if content and content ~= "" then
        -- Load the config string
        local func, err = loadstring(content)
        if func then
          func()
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Config imported from imports/" .. filename)
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Please /reload to apply changes")
          return true
        else
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Error parsing config: " .. (err or "unknown"))
        end
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Could not read imports/" .. filename)
      end
      return false
    end

    -- Slash commands for config backup
    SLASH_PFEXPORT1 = "/pfexport"
    SlashCmdList["PFEXPORT"] = function(msg)
      pfUI.api.ExportConfig(msg ~= "" and msg or nil)
    end

    SLASH_PFIMPORT1 = "/pfimport"
    SlashCmdList["PFIMPORT"] = function(msg)
      pfUI.api.ImportConfig(msg ~= "" and msg or nil)
    end
  end

  -- GetPlayerBuffID wrapper
  if GetPlayerBuffID then
    pfUI.api.GetPlayerBuffSpellId = function(buffIndex)
      return GetPlayerBuffID(buffIndex)
    end
  end

  -- CombatLogAdd wrapper for logging
  if CombatLogAdd then
    pfUI.api.LogToCombatLog = function(text, raw)
      CombatLogAdd(text, raw and 1 or nil)
    end
  end

  -- Local Raid Markers (marks only visible to self)
  if SetRaidTarget then
    local origSetRaidTarget = SetRaidTarget
    pfUI.api.SetLocalRaidTarget = function(unit, index)
      origSetRaidTarget(unit, index, "local")
    end
  end

  -- Enhanced GetContainerItemInfo for charges
  -- SuperWoW returns charges as negative numbers
  pfUI.api.GetItemCharges = function(bag, slot)
    local texture, count = GetContainerItemInfo(bag, slot)
    if count and count < 0 then
      return math.abs(count) -- Return positive charge count
    end
    return nil -- Not a charged item
  end

  -- Weapon Enchant Info on other players
  if GetWeaponEnchantInfo then
    local origGetWeaponEnchantInfo = GetWeaponEnchantInfo
    pfUI.api.GetUnitWeaponEnchants = function(unit)
      if unit and unit ~= "player" then
        local mhName, ohName = GetWeaponEnchantInfo(unit)
        return {
          mainHand = mhName,
          offHand = ohName,
        }
      else
        local hasMainHandEnchant, mainHandExpiration, mainHandCharges, hasOffHandEnchant, offHandExpiration, offHandCharges = origGetWeaponEnchantInfo()
        return {
          mainHand = hasMainHandEnchant and true or false,
          mainHandExpiration = mainHandExpiration,
          mainHandCharges = mainHandCharges,
          offHand = hasOffHandEnchant and true or false,
          offHandExpiration = offHandExpiration,
          offHandCharges = offHandCharges,
        }
      end
    end
  end

  -- Enhance libcast with SuperWoW data for NPCs and other players only
  -- Player casts use SPELLCAST_* events for proper pushback handling
  local supercast = CreateFrame("Frame")
  local playerGuid = nil

  supercast:RegisterEvent("PLAYER_ENTERING_WORLD")
  supercast:RegisterEvent("UNIT_CASTEVENT")
  supercast:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
      -- Cache player GUID
      if UnitExists then
        local _, guid = UnitExists("player")
        playerGuid = guid
      end
      return
    end

    local guid = arg1
    local isPlayer = guid == playerGuid

    -- For non-player units: disable combat parsing events (one-time init)
    if not isPlayer and not supercast.init then
      -- disable combat parsing events in superwow mode (for non-player units)
      libcast:UnregisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
      libcast:UnregisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
      supercast.init = true
    end

    if arg3 == "START" or arg3 == "CAST" or arg3 == "CHANNEL" then
      local target = arg2
      local event_type = arg3
      local spell_id = arg4
      local timer = arg5

      -- get spell info from spell id
      local spell, icon, _
      if SpellInfo and SpellInfo(spell_id) then
        spell, _, icon = SpellInfo(spell_id)
      end

      -- set fallback values
      spell = spell or UNKNOWN
      icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"

      -- skip on buff procs during cast
      if event_type == "CAST" then
        if not libcast.db[guid] or libcast.db[guid].cast ~= spell then
          return
        end
      end

      -- For player: store in libcast.db[playerName] so pushback tracking works
      -- For others: store by GUID
      local dbKey = isPlayer and UnitName("player") or guid
      
      -- add cast action to the database
      if not libcast.db[dbKey] then libcast.db[dbKey] = {} end
      libcast.db[dbKey].cast = spell
      libcast.db[dbKey].rank = nil
      libcast.db[dbKey].start = GetTime()
      libcast.db[dbKey].casttime = timer or 0
      libcast.db[dbKey].icon = icon
      libcast.db[dbKey].channel = event_type == "CHANNEL" or false
    elseif arg3 == "FAIL" then
      local dbKey = isPlayer and UnitName("player") or guid
      if libcast.db[dbKey] then
        libcast.db[dbKey].cast = nil
        libcast.db[dbKey].rank = nil
        libcast.db[dbKey].start = nil
        libcast.db[dbKey].casttime = nil
        libcast.db[dbKey].icon = nil
        libcast.db[dbKey].channel = nil
      end
    end
  end)
end)
