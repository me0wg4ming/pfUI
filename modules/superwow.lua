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

  -- Check if castbar exists for indicator positioning
  if pfUI.castbar and pfUI.castbar.player then
    chat:AddMessage("  |cff00ff00Castbar|r: Available for indicator anchoring")
  else
    chat:AddMessage("  |cffffff00Castbar|r: Not available (indicators use fallback position)")
  end

  -- Check indicator frames
  if pfUI.uf and pfUI.uf.target then
    chat:AddMessage("  |cff00ff00Target frame|r: exists")
  else
    chat:AddMessage("  |cffff0000Target frame|r: NOT found")
  end
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

  -- TrackUnit API for adding group members to minimap
  -- Tracks friendly units on the minimap for easier group coordination
  if TrackUnit and C.unitframes.track_group == "1" then
    local trackFrame = CreateFrame("Frame")
    trackFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    trackFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    trackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    trackFrame:RegisterEvent("PLAYER_LOGOUT")

    trackFrame:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end

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

  -- Enhance libcast with SuperWoW data for NPCs and other players
  -- Player casts use SPELLCAST_* events for proper pushback handling
  local supercast = CreateFrame("Frame")
  local playerGuid = nil

  supercast:RegisterEvent("PLAYER_ENTERING_WORLD")
  supercast:RegisterEvent("UNIT_CASTEVENT")
  supercast:RegisterEvent("PLAYER_LOGOUT")
  supercast:SetScript("OnEvent", function()
    -- Handle shutdown to prevent crash 132
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    end

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
          -- ignore casts without 'START' event, while there is already another cast.
          -- those events can be for example a frost shield proc while casting frostbolt.
          -- we want to keep the cast itself, so we simply skip those.
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
      -- For player: use playerName, for others: use GUID
      local dbKey = isPlayer and UnitName("player") or guid
      
      -- delete all cast entries
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
