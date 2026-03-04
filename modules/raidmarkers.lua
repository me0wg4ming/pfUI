pfUI:RegisterModule("raidmarkers", "vanilla:tbc", function ()
  -- Requires mark1-mark8 unit tokens (Turtle WoW / Nampower)
  if not UnitExists("mark1") and not UnitExists("mark8") then
    if not pcall(function() UnitExists("mark1") end) then return end
  end

  local rawborder, border = GetBorderSize()

  -- Parse color strings "r,g,b,a" into components
  local function ParseColor(str, dr, dg, db, da)
    if not str or str == "" then return dr, dg, db, da end
    local _, _, r, g, b, a = string.find(str, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
    if r then
      return tonumber(r) or dr, tonumber(g) or dg, tonumber(b) or db, tonumber(a) or da
    end
    return dr, dg, db, da
  end

  local markerOrder = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull, cross, square, moon, triangle, diamond, circle, star
  local markerTokens = {}
  for i = 1, 8 do markerTokens[i] = "mark" .. i end

  -- Default colors per marker
  local defaultColors = {
    [1] = { 1.0, 0.9, 0.0, 1 },    -- star: yellow
    [2] = { 1.0, 0.5, 0.0, 1 },    -- circle: orange
    [3] = { 0.8, 0.0, 0.8, 1 },    -- diamond: purple
    [4] = { 0.0, 0.8, 0.0, 1 },    -- triangle: green
    [5] = { 0.7, 0.7, 0.7, 1 },    -- moon: silver
    [6] = { 0.0, 0.4, 0.9, 1 },    -- square: blue
    [7] = { 0.9, 0.0, 0.0, 1 },    -- cross: red
    [8] = { 1.0, 1.0, 1.0, 1 },    -- skull: white
  }

  local markerConfigKeys = {
    [1] = "raidmarkercolor_star",
    [2] = "raidmarkercolor_circle",
    [3] = "raidmarkercolor_diamond",
    [4] = "raidmarkercolor_triangle",
    [5] = "raidmarkercolor_moon",
    [6] = "raidmarkercolor_square",
    [7] = "raidmarkercolor_cross",
    [8] = "raidmarkercolor_skull",
  }

  local markerColors = {}
  for i = 1, 8 do
    local d = defaultColors[i]
    local r, g, b, a = ParseColor(C.unitframes[markerConfigKeys[i]], d[1], d[2], d[3], d[4])
    markerColors[i] = { r, g, b, a }
  end

  local FALLBACK_INTERVAL = 1.0  -- safety net for units that come into range after marker was set
  local elapsed = 0
  local isUnlocked = false
  local ROW_HEIGHT = tonumber(C.unitframes.raidmarkerheight) or 14
  local BAR_WIDTH = tonumber(C.unitframes.raidmarkerwidth) or 80
  local GROW = C.unitframes.raidmarkergrow or "down"
  local rm_texture = C.unitframes.raidmarkertexture or "Interface\\AddOns\\pfUI\\img\\bar"
  local rm_fontsize = tonumber(C.unitframes.raidmarkerfontsize) or 12
  local rm_showpct = C.unitframes.raidmarkershowpct ~= "0"
  local rm_showname = C.unitframes.raidmarkershowname ~= "0"
  local rm_showportrait = C.unitframes.raidmarkershowportrait ~= "0"
  local PORTRAIT_SIZE = ROW_HEIGHT

  -- Cache for shortened names: markerIndex -> { name, short }
  local nameCache = {}

  local function ShortenName(name, row)
    if not name or name == "" then return "" end
    local barWidth = row.health:GetWidth()
    if barWidth < 1 then barWidth = BAR_WIDTH end
    local available = barWidth - 4
    if rm_showpct then available = available - 32 end
    if available < 10 then return nil end
    row.nametext:SetText(name)
    if row.nametext:GetStringWidth() <= available then return name end
    for len = strlen(name) - 1, 1, -1 do
      local short = strsub(name, 1, len) .. "."
      row.nametext:SetText(short)
      if row.nametext:GetStringWidth() <= available then return short end
    end
    return strsub(name, 1, 1) .. "."
  end

  local TOTAL_ROW_WIDTH = BAR_WIDTH + 20 + (rm_showportrait and (PORTRAIT_SIZE + 2) or 0)

  -- Container frame
  pfUI.raidmarkers = CreateFrame("Frame", "pfMarkerTracker", UIParent)
  pfUI.raidmarkers:SetFrameStrata("MEDIUM")
  if GROW == "up" then
    pfUI.raidmarkers:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 200)
  else
    pfUI.raidmarkers:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
  end
  pfUI.raidmarkers:SetWidth(TOTAL_ROW_WIDTH)
  pfUI.raidmarkers:SetHeight(8 * (ROW_HEIGHT + 1) + border * 2 - 1)
  pfUI.raidmarkers:Hide()

  CreateBackdrop(pfUI.raidmarkers)
  CreateBackdropShadow(pfUI.raidmarkers)
  UpdateMovable(pfUI.raidmarkers)

  pfUI.raidmarkers:SetScript("OnMouseUp", function()
    if pfUI.unlock and pfUI.unlock:IsShown() then
      this:StopMovingOrSizing()
      local _, _, _, x, y = this:GetPoint()
      this:ClearAllPoints()
      this:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", math.floor(x + 0.5), math.floor(y + 0.5))
      C.position["pfMarkerTracker"] = C.position["pfMarkerTracker"] or {}
      C.position["pfMarkerTracker"]["anchor"] = "BOTTOMRIGHT"
      C.position["pfMarkerTracker"]["xpos"] = math.floor(x + 0.5)
      C.position["pfMarkerTracker"]["ypos"] = math.floor(y + 0.5)
    end
  end)

  -- Create 8 marker rows
  pfUI.raidmarkers.rows = {}
  for idx = 1, 8 do
    local i = markerOrder[idx]

    local row = CreateFrame("Button", nil, pfUI.raidmarkers)
    row:SetWidth(TOTAL_ROW_WIDTH)
    row:SetHeight(ROW_HEIGHT)
    row:Hide()

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function()
      TargetUnit(markerTokens[this.markerIndex])
    end)

    -- raid icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ROW_HEIGHT)
    row.icon:SetHeight(ROW_HEIGHT)
    row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.icon:SetTexture(pfUI.media["img:raidicons"])
    SetRaidTargetIconTexture(row.icon, i)

    -- portrait (right side)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetWidth(PORTRAIT_SIZE)
    row.portrait:SetHeight(PORTRAIT_SIZE)
    row.portrait:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    row.portrait:SetTexCoord(.1, .9, .1, .9)
    if not rm_showportrait then row.portrait:Hide() end

    -- health bar
    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    if rm_showportrait then
      row.health:SetPoint("RIGHT", row.portrait, "LEFT", -2, 0)
    else
      row.health:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    end
    row.health:SetHeight(ROW_HEIGHT)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    row.health:SetStatusBarTexture(rm_texture)
    local c = markerColors[i]
    row.health:SetStatusBarColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, c[4] or 0.9)

    -- name text (left)
    row.nametext = row.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nametext:SetPoint("LEFT", row.health, "LEFT", 2, 0)
    row.nametext:SetFont(pfUI.font_default, rm_fontsize, "OUTLINE")
    row.nametext:SetTextColor(1, 1, 1, 1)
    row.nametext:SetJustifyH("LEFT")
    row.nametext:SetText("")
    if not rm_showname then row.nametext:Hide() end

    -- hp text (right)
    row.hptext = row.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.hptext:SetPoint("RIGHT", row.health, "RIGHT", -2, 0)
    row.hptext:SetFont(pfUI.font_default, rm_fontsize, "OUTLINE")
    row.hptext:SetTextColor(1, 1, 1, 1)
    row.hptext:SetJustifyH("RIGHT")
    row.hptext:SetText("")
    if not rm_showpct then row.hptext:Hide() end

    CreateBackdrop(row.health)

    row.markerIndex = i
    row.label = "mark"  -- enables /pfcast mouseover support via GetMouseFocus()
    row.id = i
    pfUI.raidmarkers.rows[i] = row
  end

  local function UpdateDisplay()
    if isUnlocked then return end
    local anyActive = false
    local visibleCount = 0
    local prevRow

    for idx = 1, 8 do
      local i = markerOrder[idx]
      local row = pfUI.raidmarkers.rows[i]
      local token = markerTokens[i]

      if UnitExists(token) and not UnitIsDead(token) then
        local hp = UnitHealth(token)
        local maxhp = UnitHealthMax(token)

        if hp and maxhp and maxhp > 0 and hp > 0 then
          local pct = hp / maxhp
          row.health:SetValue(pct)

          if rm_showname then
            local name = UnitName(token)
            local cached = nameCache[i]
            if not cached or cached.name ~= name then
              local short = ShortenName(name, row)
              if short then
                nameCache[i] = { name = name, short = short }
              end
            end
            row.nametext:SetText(nameCache[i] and nameCache[i].short or "")
          end

          if rm_showpct then
            row.hptext:SetText(math.floor(pct * 100) .. "%")
          end

          if rm_showportrait then
            SetPortraitTexture(row.portrait, token)
          end

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
        else
          row:Hide()
        end
      else
        nameCache[i] = nil
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

  -- Unlock mode: show fixed 1-row placeholder so positioning works correctly
  if pfUI.unlock then
    local origShow = pfUI.unlock:GetScript("OnShow")
    pfUI.unlock:SetScript("OnShow", function()
      if origShow then origShow() end
      isUnlocked = true
      -- hide all rows, show container at 1-row height as drag handle
      for i = 1, 8 do
        pfUI.raidmarkers.rows[i]:Hide()
      end
      pfUI.raidmarkers:SetHeight(ROW_HEIGHT + border * 2)
      pfUI.raidmarkers:Show()
    end)

    local origHide = pfUI.unlock:GetScript("OnHide")
    pfUI.unlock:SetScript("OnHide", function()
      if origHide then origHide() end
      isUnlocked = false
      UpdateDisplay()
    end)
  end

  -- Event-driven scanner frame
  local scanner = CreateFrame("Frame")

  -- RAID_TARGET_UPDATE: fires when a raid marker is set/cleared
  -- PLAYER_ENTERING_WORLD: fires on login, reload, and zone transitions
  -- UNIT_HEALTH/UNIT_MAXHEALTH: fires on HP changes for real-time bar updates
  scanner:RegisterEvent("RAID_TARGET_UPDATE")
  scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
  scanner:RegisterEvent("UNIT_HEALTH")
  scanner:RegisterEvent("UNIT_MAXHEALTH")

  scanner:SetScript("OnEvent", function()
    UpdateDisplay()
  end)

  -- Fallback poll at 1s: catches units that come into range AFTER a marker was set
  -- (no event fires for that case, so we need this safety net)
  scanner:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < FALLBACK_INTERVAL then return end
    elapsed = 0
    UpdateDisplay()
  end)
end)