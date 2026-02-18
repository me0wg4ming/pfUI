pfUI:RegisterModule("raidmarkers", "vanilla:tbc", function ()
  -- Requires Nampower for GetUnitField with GUIDs
  if not GetUnitField then return end

  local rawborder, border = GetBorderSize()

  local markerOrder = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull, cross, square, moon, triangle, diamond, circle, star
  local markerColors = {
    [1] = { 1.0, 0.9, 0.0 },    -- star: yellow
    [2] = { 1.0, 0.5, 0.0 },    -- circle: orange
    [3] = { 0.8, 0.0, 0.8 },    -- diamond: purple
    [4] = { 0.0, 0.8, 0.0 },    -- triangle: green
    [5] = { 0.7, 0.7, 0.7 },    -- moon: silver
    [6] = { 0.0, 0.4, 0.9 },    -- square: blue
    [7] = { 0.9, 0.0, 0.0 },    -- cross: red
    [8] = { 1.0, 1.0, 1.0 },    -- skull: white
  }

  -- GUID cache: markerIndex -> { guid }
  local markerGUIDs = {}
  local UPDATE_INTERVAL = 0.1
  local VALIDATE_INTERVAL = 1.0
  local elapsed = 0
  local validateElapsed = 0
  local ROW_HEIGHT = tonumber(C.unitframes.raidmarkerheight) or 14
  local BAR_WIDTH = tonumber(C.unitframes.raidmarkerwidth) or 80
  local GROW = C.unitframes.raidmarkergrow or "down"

  -- Container frame
  pfUI.raidmarkers = CreateFrame("Frame", "pfRaidMarkers", UIParent)
  pfUI.raidmarkers:SetFrameStrata("MEDIUM")
  if GROW == "up" then
    pfUI.raidmarkers:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 200)
  else
    pfUI.raidmarkers:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
  end
  pfUI.raidmarkers:SetWidth(BAR_WIDTH + 20)
  pfUI.raidmarkers:SetHeight(8 * (ROW_HEIGHT + 1) + border * 2 - 1)
  pfUI.raidmarkers:Hide()

  CreateBackdrop(pfUI.raidmarkers)
  CreateBackdropShadow(pfUI.raidmarkers)
  UpdateMovable(pfUI.raidmarkers)

  -- After dragging, force anchor back to BOTTOMRIGHT
  pfUI.raidmarkers:SetScript("OnMouseUp", function()
    if pfUI.unlock and pfUI.unlock:IsShown() then
      this:StopMovingOrSizing()
      local _, _, _, x, y = this:GetPoint()
      this:ClearAllPoints()
      this:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", math.floor(x + 0.5), math.floor(y + 0.5))
      C.position["pfRaidMarkers"] = C.position["pfRaidMarkers"] or {}
      C.position["pfRaidMarkers"]["anchor"] = "BOTTOMRIGHT"
      C.position["pfRaidMarkers"]["xpos"] = math.floor(x + 0.5)
      C.position["pfRaidMarkers"]["ypos"] = math.floor(y + 0.5)
    end
  end)

  -- Create 8 marker rows
  pfUI.raidmarkers.rows = {}
  for idx = 1, 8 do
    local i = markerOrder[idx]

    local row = CreateFrame("Button", nil, pfUI.raidmarkers)
    row:SetWidth(BAR_WIDTH + 20)
    row:SetHeight(ROW_HEIGHT)
    row:Hide()

    -- click to target via GUID
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function()
      local data = markerGUIDs[this.markerIndex]
      if data and data.guid and TargetUnit then
        TargetUnit(data.guid)
      end
    end)

    -- raid icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ROW_HEIGHT)
    row.icon:SetHeight(ROW_HEIGHT)
    row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.icon:SetTexture(pfUI.media["img:raidicons"])
    SetRaidTargetIconTexture(row.icon, i)

    -- health bar
    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    row.health:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    row.health:SetHeight(ROW_HEIGHT)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    row.health:SetStatusBarTexture(pfUI.media["img:bar"])
    local c = markerColors[i]
    row.health:SetStatusBarColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 0.9)

    -- hp % text centered on bar
    row.hptext = row.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.hptext:SetPoint("CENTER", row.health, "CENTER", 0, 0)
    row.hptext:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    row.hptext:SetTextColor(1, 1, 1, 1)
    row.hptext:SetText("")

    CreateBackdrop(row.health)

    row.markerIndex = i
    pfUI.raidmarkers.rows[i] = row
  end

  local scanTokens = { "target", "mouseover", "pettarget", "player" }
  for i = 1, 40 do
    table.insert(scanTokens, "raid" .. i)
    table.insert(scanTokens, "raid" .. i .. "target")
  end
  for i = 1, 4 do
    table.insert(scanTokens, "party" .. i)
    table.insert(scanTokens, "party" .. i .. "target")
  end

  local function RegisterGUID(icon, guid)
    for k = 1, 8 do
      if k ~= icon and markerGUIDs[k] and markerGUIDs[k].guid == guid then
        markerGUIDs[k] = nil
      end
    end
    markerGUIDs[icon] = { guid = guid }
  end

  local function ScanMarkedUnits(validate)
    -- Token scan: pick up any newly visible marked units
    for _, token in pairs(scanTokens) do
      if UnitExists(token) and not UnitIsDead(token) then
        local icon = GetRaidTargetIndex(token)
        if icon and icon > 0 and icon <= 8 then
          local _, guid = UnitExists(token)
          if guid then
            RegisterGUID(icon, guid)
          end
        end
      end
    end

    -- GUID pool scan: check all known GUIDs from libdebuff for raid markers
    -- This catches out-of-range units that have been marked
    if pfUI.libdebuff_objects_guid then
      for guid in pairs(pfUI.libdebuff_objects_guid) do
        local icon = GetRaidTargetIndex(guid)
        if icon and icon > 0 and icon <= 8 then
          RegisterGUID(icon, guid)
        end
      end
    end

    -- Validate cached GUIDs: only remove if unit is visible AND marker changed
    -- If unit is out of range (UnitExists=false), keep the cached entry
    if validate then
      for k = 1, 8 do
        if markerGUIDs[k] then
          local guid = markerGUIDs[k].guid
          if UnitExists(guid) then
            local icon = GetRaidTargetIndex(guid)
            if icon and icon ~= k then
              markerGUIDs[k] = nil
              if icon > 0 and icon <= 8 then
                RegisterGUID(icon, guid)
              end
            end
          end
        end
      end
    end
  end

  local function UpdateDisplay()
    local anyActive = false
    local visibleCount = 0
    local prevRow

    for idx = 1, 8 do
      local i = markerOrder[idx]
      local row = pfUI.raidmarkers.rows[i]
      local data = markerGUIDs[i]

      if data then
        local hp = GetUnitField(data.guid, "health")
        local maxhp = GetUnitField(data.guid, "maxHealth")

        if hp and maxhp and maxhp > 0 and hp > 0 then
          local pct = hp / maxhp
          row.health:SetValue(pct)
          row.hptext:SetText(math.floor(pct * 100) .. "%")

          row:ClearAllPoints()
          if GROW == "up" then
            if prevRow then
              row:SetPoint("BOTTOM", prevRow, "TOP", 0, 1)
            else
              row:SetPoint("BOTTOM", pfUI.raidmarkers, "BOTTOM", 0, border)
            end
          else
            if prevRow then
              row:SetPoint("TOP", prevRow, "BOTTOM", 0, -1)
            else
              row:SetPoint("TOP", pfUI.raidmarkers, "TOP", 0, -border)
            end
          end
          row:Show()
          prevRow = row
          anyActive = true
          visibleCount = visibleCount + 1
        elseif UnitIsDead(data.guid) then
          -- Dead: remove from cache
          markerGUIDs[i] = nil
          row:Hide()
        else
          -- out of range: keep GUID but hide the row
          row:Hide()
        end
      else
        row:Hide()
      end
    end

    if anyActive then
      pfUI.raidmarkers:SetHeight(visibleCount * (ROW_HEIGHT + 1) + border * 2 - 1)
      pfUI.raidmarkers:Show()
    elseif not (pfUI.unlock and pfUI.unlock:IsShown()) then
      pfUI.raidmarkers:Hide()
    end
  end

  -- Events
  local events = CreateFrame("Frame")
  events:RegisterEvent("RAID_TARGET_UPDATE")
  events:RegisterEvent("PLAYER_TARGET_CHANGED")
  events:RegisterEvent("PLAYER_LOGIN")
  events:RegisterEvent("UNIT_DIED")
  events:RegisterEvent("RAID_ROSTER_UPDATE")
  events:RegisterEvent("PARTY_MEMBERS_CHANGED")

  -- Rescan when unlock mode closes
  if pfUI.unlock then
    local orig = pfUI.unlock:GetScript("OnHide")
    pfUI.unlock:SetScript("OnHide", function()
      if orig then orig() end
      ScanMarkedUnits(false)
      UpdateDisplay()
    end)
  end

  events:SetScript("OnEvent", function()
    if event == "UNIT_DIED" then
      for k = 1, 8 do
        if markerGUIDs[k] and markerGUIDs[k].guid == arg1 then
          markerGUIDs[k] = nil
        end
      end
      UpdateDisplay()
    elseif event == "RAID_TARGET_UPDATE" then
      ScanMarkedUnits(true)
      UpdateDisplay()
    else
      -- PLAYER_LOGIN, PLAYER_TARGET_CHANGED, RAID_ROSTER_UPDATE, PARTY_MEMBERS_CHANGED
      ScanMarkedUnits(false)
      UpdateDisplay()
    end
  end)

  -- Throttled OnUpdate for live HP tracking + periodic validation
  pfUI.raidmarkers:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    validateElapsed = validateElapsed + arg1

    -- Every second: validate cached GUIDs
    if validateElapsed >= VALIDATE_INTERVAL then
      validateElapsed = 0
      for k = 1, 8 do
        if markerGUIDs[k] then
          local guid = markerGUIDs[k].guid
          if UnitExists(guid) then
            local icon = GetRaidTargetIndex(guid)
            if icon and icon ~= k then
              markerGUIDs[k] = nil
              if icon > 0 and icon <= 8 then
                RegisterGUID(icon, guid)
              end
            elseif not icon then
              markerGUIDs[k] = nil
            end
          end
        end
      end
    end

    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    UpdateDisplay()
  end)
end)