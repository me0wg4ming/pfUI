pfUI:RegisterModule("aurahider", "vanilla:tbc", function()
  if not GetNampowerVersion then return end

  -- Initialize global hidden buffs lookup table (used by libdebuff IterBuffs/IterDebuffs)
  pfUI_HiddenBuffsLookup = {}
  pfUI_HiddenBuffNames = {}
  if pfUI_config and pfUI_config.buffs and pfUI_config.buffs.hidelist and pfUI_config.buffs.hidelist ~= "" then
    for id in string.gfind(pfUI_config.buffs.hidelist, "([^#]+)") do
      local spellId = tonumber(id)
      if spellId then
        pfUI_HiddenBuffsLookup[spellId] = true
        local sname = GetSpellRecField and GetSpellRecField(spellId, "name")
        if sname and sname ~= "" then
          pfUI_HiddenBuffNames[sname] = true
        end
      end
    end
  end
end)
-- BuffAnalyzer: standalone frame to inspect target buffs/debuffs and add to hidelist
pfUI:RegisterModule("auraanalyzer", "vanilla:tbc", function()
  if not GetNampowerVersion then return end

  local FRAME_WIDTH  = 300
  local FRAME_HEIGHT = 420
  local HEADER_HEIGHT = 40
  local ROW_HEIGHT = 34
  local ICON_SIZE  = 24

  -- Main frame
  local frame = CreateFrame("Frame", "pfUIBuffAnalyzer", UIParent)
  frame:Hide()
  frame:SetPoint("CENTER", 0, 0)
  frame:SetWidth(FRAME_WIDTH)
  frame:SetHeight(FRAME_HEIGHT)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetClampedToScreen(true)
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel(100)

  -- pfUI backdrop + shadow
  CreateBackdrop(frame)
  CreateBackdropShadow(frame)

  -- ── Header bar ──────────────────────────────────────────────
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  header:SetHeight(HEADER_HEIGHT)
  CreateBackdrop(header, nil, true, 0.6)

  -- Portrait texture in header
  local portrait = header:CreateTexture(nil, "ARTWORK")
  portrait:SetWidth(HEADER_HEIGHT - 4)
  portrait:SetHeight(HEADER_HEIGHT - 4)
  portrait:SetPoint("LEFT", header, "LEFT", 4, 0)
  portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Portrait border
  local portraitBorder = header:CreateTexture(nil, "OVERLAY")
  portraitBorder:SetWidth(HEADER_HEIGHT - 2)
  portraitBorder:SetHeight(HEADER_HEIGHT - 2)
  portraitBorder:SetPoint("CENTER", portrait, "CENTER", 0, 0)

  -- Title text
  local title = header:CreateFontString(nil, "OVERLAY")
  title:SetFont(pfUI.font_unit, 11, "OUTLINE")
  title:SetPoint("LEFT",  portrait, "RIGHT", 6, 1)
  title:SetPoint("RIGHT", header,   "RIGHT", -22, 0)
  title:SetJustifyH("LEFT")
  title:SetText("Spell Analyzer")
  frame.title = title

  -- Close button (pfUI style X)
  local closeBtn = CreateFrame("Button", nil, header)
  closeBtn:SetWidth(16)
  closeBtn:SetHeight(16)
  closeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
  local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
  closeTex:SetFont(pfUI.font_unit, 11, "OUTLINE")
  closeTex:SetAllPoints(closeBtn)
  closeTex:SetText("|cffaaaaaa×|r")
  closeBtn:SetScript("OnEnter", function() closeTex:SetText("|cffffffff×|r") end)
  closeBtn:SetScript("OnLeave", function() closeTex:SetText("|cffaaaaaa×|r") end)
  closeBtn:SetScript("OnClick", function() frame:Hide(); frame.unit = "target" end)

  -- ── Scroll area ──────────────────────────────────────────────
  local scroll = CreateFrame("ScrollFrame", "pfUIBuffAnalyzerScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     4, -(HEADER_HEIGHT + 2))
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 4)

  -- Skin the scrollbar to be minimal
  local sb = pfUIBuffAnalyzerScrollScrollBar
  if sb then
    sb:SetWidth(6)
  end

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(FRAME_WIDTH - 28)
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  frame.buffRows = {}

  -- ── Row factory ──────────────────────────────────────────────
  local function CreateBuffRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetWidth(FRAME_WIDTH - 28)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    -- Hover highlight
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(row)
    hl:SetTexture(1, 1, 1, 0.06)
    hl:Hide()
    row.hl = hl

    -- Separator line at bottom
    local sep = row:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetTexture(0.2, 0.2, 0.2, 0.8)

    -- Icon
    local iconBg = row:CreateTexture(nil, "BACKGROUND")
    iconBg:SetWidth(ICON_SIZE + 2)
    iconBg:SetHeight(ICON_SIZE + 2)
    iconBg:SetPoint("LEFT", row, "LEFT", 4, 0)
    iconBg:SetTexture(0, 0, 0, 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(ICON_SIZE)
    icon:SetHeight(ICON_SIZE)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    -- Spell name
    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(pfUI.font_unit, 10, "OUTLINE")
    nameText:SetPoint("LEFT",  iconBg, "RIGHT", 5, 3)
    nameText:SetPoint("RIGHT", row,    "RIGHT", -6, 3)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- SpellID + rank subtext
    local subText = row:CreateFontString(nil, "OVERLAY")
    subText:SetFont(pfUI.font_unit, 8, "OUTLINE")
    subText:SetPoint("LEFT",  iconBg, "RIGHT", 5, -7)
    subText:SetPoint("RIGHT", row,    "RIGHT", -6, -7)
    subText:SetJustifyH("LEFT")
    row.subText = subText

    row:SetScript("OnEnter", function()
      hl:Show()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      local shown = false
      if this.spellId then
        local lt = pfUI.api.libtooltip
        if lt and lt.SetSpellByID then
          shown = lt:SetSpellByID(GameTooltip, this.spellId)
        end
      end
      if not shown then
        GameTooltip:AddLine(this.spellName or "Unknown", 1, 1, 1)
        if this.spellId then
          GameTooltip:AddLine("SpellID: " .. this.spellId, 0.6, 0.6, 0.6)
        end
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      hl:Hide()
      GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function()
      if not this.spellId then return end

      local currentList = pfUI_config.buffs.hidelist or ""
      local alreadyHidden = false

      if currentList ~= "" then
        for id in string.gfind(currentList, "([^#]+)") do
          if tonumber(id) == this.spellId then
            alreadyHidden = true
            break
          end
        end
      end

      if not alreadyHidden then
        if currentList == "" then
          pfUI_config.buffs.hidelist = tostring(this.spellId)
        else
          pfUI_config.buffs.hidelist = currentList .. "#" .. this.spellId
        end

        if pfUI.api.libdebuff then
          pfUI.api.libdebuff:ClearBuffCache()
        end
        if pfUI.aurahider_forceRefresh then
          pfUI.aurahider_forceRefresh()
        end

        local name = GetSpellRecField and GetSpellRecField(this.spellId, "name") or "Unknown"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[AuraHider] Hidden:|r " .. name .. " (" .. this.spellId .. ")")

        if pfUI.gui and pfUI.gui.updateHiddenBuffsList then
          pfUI.gui.updateHiddenBuffsList()
        end

        frame.Update()
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[AuraHider] Already in hidden list!|r")
      end
    end)

    row:Hide()
    return row
  end

  for i = 1, 48 do
    frame.buffRows[i] = CreateBuffRow(i)
  end

  -- ── Update function ──────────────────────────────────────────
  frame.unit = "target" -- default, overridden when opened for player

  frame.Update = function(unit)
    unit = unit or frame.unit or "target"
    frame.unit = unit
    if not UnitExists(unit) then
      frame:Hide()
      return
    end

    -- Update portrait
    SetPortraitTexture(portrait, unit)

    -- Update title with class color
    local targetName = UnitName(unit) or "?"
    local _, class = UnitClass(unit)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local hex = cc and string.format("%02x%02x%02x",
      math.floor(cc.r * 255),
      math.floor(cc.g * 255),
      math.floor(cc.b * 255)) or "ffffff"
    title:SetText("|cff" .. hex .. targetName .. "|r")

    local guid = GetUnitGUID and GetUnitGUID(unit)
    if not guid or not GetUnitField then
      title:SetText("|cffff4444Nampower required|r")
      return
    end

    local auras    = GetUnitField(guid, "aura")
    local auraApps = GetUnitField(guid, "auraApplications")

    for i = 1, 48 do frame.buffRows[i]:Hide() end
    if not auras then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[AH] auras nil - early return|r")
      return
    end

    local displayCount = 0

    for i = 1, 48 do
      local spellId = auras[i]
      if spellId and spellId > 0 then
        local isHidden = pfUI_HiddenBuffsLookup and pfUI_HiddenBuffsLookup[spellId]
        if not isHidden then
          displayCount = displayCount + 1
          local row = frame.buffRows[displayCount]
          row.spellId = spellId

          local stacks = 1
          if auraApps and auraApps[i] then stacks = auraApps[i] + 1 end

          local name    = "Unknown"
          local rank    = ""
          local texture = nil

          if GetSpellRecField then
            name = GetSpellRecField(spellId, "name") or "Unknown"
            if name == "" then name = "Unknown" end
            rank = GetSpellRecField(spellId, "rank") or ""

            if GetSpellIconTexture then
              local iconId = GetSpellRecField(spellId, "spellIconID")
              if iconId then
                texture = GetSpellIconTexture(iconId)
                if texture and not string.find(texture, "\\") then
                  texture = "Interface\\Icons\\" .. texture
                end
              end
            end
          end

          row.spellName = name
          row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

          -- Name line: pfUI tooltip gold, debuff slots slightly different
          local nameColor = isDebuff and "|cffff6060" or "|cffffd100"
          local stackStr = stacks > 1 and (" |cffffcc00x" .. stacks .. "|r") or ""
          row.nameText:SetText(nameColor .. name .. "|r" .. stackStr)

          -- Sub line: rank in red (pfUI style), spellId in grey
          local sub = ""
          if rank ~= "" then sub = "|cffff4444" .. rank .. "|r  " end
          sub = sub .. "|cff44ff44" .. spellId .. "|r"
          row.subText:SetText(sub)

          row:SetPoint("TOPLEFT", 0, -(displayCount - 1) * ROW_HEIGHT)
          row:Show()
        end
      end
    end

    local contentHeight = math.max(displayCount * ROW_HEIGHT, FRAME_HEIGHT - HEADER_HEIGHT - 10)
    content:SetHeight(contentHeight)
    scroll:UpdateScrollChildRect()
  end

  -- ── Global hooks ─────────────────────────────────────────────
  pfUI.gui = pfUI.gui or {}
  pfUI.gui.updateBuffAnalyzer = frame.Update

  pfUI.aurahider_forceRefresh = function()
    if pfUI.buff and pfUI.buff:GetScript("OnEvent") then
      pfUI.buff:GetScript("OnEvent")()
    end
    if pfUI.uf and pfUI.uf.frames then
      for _, f in pairs(pfUI.uf.frames) do
        f.update_aura = true
      end
    end
  end

  -- UNIT_AURA_GUID (Nampower) for enemies, UNIT_AURA (TurtleWoW) for friendlies
  -- UNIT_AURA fires after aura data is updated (TurtleWoW/Nampower), sufficient for icon display
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UNIT_AURA")
  frame:SetScript("OnEvent", function()
    if not frame:IsShown() then return end
    if event == "PLAYER_TARGET_CHANGED" then
      frame.unit = UnitExists("target") and "target" or "player"
      if UnitExists(frame.unit) then
        frame.Update()
      else
        frame:Hide()
        frame.unit = "target"
      end
      return
    end
    local unit = frame.unit or "target"
    if event == "UNIT_AURA" and arg1 ~= unit then return end
    if UnitExists(unit) then
      frame.Update()
    else
      frame:Hide()
      frame.unit = "target"
    end
  end)

  -- debuff_added/removed for debuffs on target
  local function refreshNow()
    local unit = frame.unit or "target"
    if frame:IsShown() and UnitExists(unit) then frame.Update() end
  end

  pfUI.libdebuff_debuff_added_other_hooks = pfUI.libdebuff_debuff_added_other_hooks or {}
  table.insert(pfUI.libdebuff_debuff_added_other_hooks, function(guid, luaSlot, spellId, stackCount)
    if not frame:IsShown() then return end
    if not GetUnitGUID or GetUnitGUID(frame.unit or "target") ~= guid then return end
    refreshNow()
  end)

  pfUI.libdebuff_debuff_removed_other_hooks = pfUI.libdebuff_debuff_removed_other_hooks or {}
  table.insert(pfUI.libdebuff_debuff_removed_other_hooks, function(guid, luaSlot, spellId)
    if not frame:IsShown() then return end
    if not GetUnitGUID or GetUnitGUID(frame.unit or "target") ~= guid then return end
    refreshNow()
  end)

  -- Heartbeat fallback via central libdebuff timer (2s)
  pfUI.libdebuff_heartbeat_hooks = pfUI.libdebuff_heartbeat_hooks or {}
  pfUI.libdebuff_heartbeat_hooks["aurahider"] = function()
    local unit = frame.unit or "target"
    if frame:IsShown() and UnitExists(unit) then frame.Update() end
  end

  -- ── Right-click menu integration ─────────────────────────────
  -- Add "Hide Auras" to player self-menu and target/other-player menus
  if UnitPopupButtons and UnitPopupMenus then
    UnitPopupButtons["PF_HIDE_AURAS"] = { text = "|cffff4444Hide Auras|r", dist = 0 }

    -- SELF = PlayerFrame right-click (yourself)
    if UnitPopupMenus["SELF"] then
      table.insert(UnitPopupMenus["SELF"], "PF_HIDE_AURAS")
    end

    -- PLAYER = TargetFrame right-click when target is another player
    if UnitPopupMenus["PLAYER"] then
      table.insert(UnitPopupMenus["PLAYER"], "PF_HIDE_AURAS")
    end

    hooksecurefunc("UnitPopup_OnClick", function()
      if this.value ~= "PF_HIDE_AURAS" then return end

      local dropdownFrame = _G[UIDROPDOWNMENU_INIT_MENU]
      local dropdownUnit = dropdownFrame and dropdownFrame.unit or ""
      local isSelf = UnitIsUnit(dropdownUnit, "player")
      local unit = isSelf and "player" or "target"

      if not UnitExists(unit) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[AuraHider] No target selected!|r")
        return
      end

      if frame:IsShown() then
        frame:Hide()
        frame.unit = "target"
      else
        frame:ClearAllPoints()
        if pfUI.gui and pfUI.gui:IsShown() then
          frame:SetPoint("TOPLEFT", pfUI.gui, "TOPRIGHT", 5, 0)
        else
          frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        frame.Update(unit)
        frame:Show()
      end
    end)
  end

  -- Slash commands
  _G.SlashCmdList["PFUIAURAANALYZER"] = function()
    if frame:IsShown() then
      frame:Hide()
    else
      if not UnitExists("target") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[AuraHider] No target selected!|r")
        return
      end
      -- Dock to pfUI GUI if open, otherwise center
      frame:ClearAllPoints()
      if pfUI.gui and pfUI.gui:IsShown() then
        frame:SetPoint("TOPLEFT", pfUI.gui, "TOPRIGHT", 5, 0)
      else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end
      frame.Update()
      frame:Show()
    end
  end
  _G.SLASH_PFUIAURAANALYZER1 = "/auraanalyzer"
  _G.SLASH_PFUIAURAANALYZER2 = "/ba"
end)