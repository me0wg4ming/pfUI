pfUI:RegisterModule("rangedisplay", "vanilla:tbc", function()
  if not GetUnitField then return end

  local f = CreateFrame("Frame", "pfRangeDisplay", UIParent)
  f:SetWidth(90)
  f:SetHeight(20)
  f:SetFrameStrata("MEDIUM")
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -100)

  CreateBackdrop(f, nil, true)
  CreateBackdropShadow(f)
  UpdateMovable(f)

  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")
  f.text:SetPoint("CENTER", f, "CENTER")
  f.text:SetTextColor(1, 1, 1, 1)
  f.text:SetText("--")

  -- color thresholds: { maxDist, r, g, b }
  local thresholds = {
    {  5, 0.0, 0.0, 1.0 },  -- melee (blue)
    {  8, 0.2, 0.5, 1.0 },  -- close melee (light blue)
    { 20, 0.3, 0.7, 1.0 },  -- short range (sky blue)
    { 30, 0.0, 0.9, 0.0 },  -- mid range (green)
    { 35, 0.7, 0.9, 0.0 },  -- yellow-green
    { 41, 1.0, 1.0, 0.0 },  -- yellow
  }                          -- >41: red

  local function GetColor(distance)
    for i = 1, table.getn(thresholds) do
      if distance <= thresholds[i][1] then
        return thresholds[i][2], thresholds[i][3], thresholds[i][4]
      end
    end
    return 1.0, 0.2, 0.2
  end

  -- Use a separate always-running scanner frame for OnUpdate
  -- (the display frame itself is shown/hidden, so its OnUpdate would stop firing)
  local throttle = 0
  local scanner = CreateFrame("Frame")
  scanner:SetScript("OnUpdate", function()
    throttle = throttle + arg1
    if throttle < 0.05 then return end
    throttle = 0

    if not UnitExists("target") then
      f.text:SetText("--")
      f.text:SetTextColor(1, 1, 1, 1)
      f:Hide()
      return
    end

    f:Show()

    local distance = UnitXP("distanceBetween", "player", "target")
    if not distance then
      f.text:SetText("--")
      f.text:SetTextColor(1, 1, 1, 1)
      return
    end

    -- line of sight: dim text when out of LoS
    local los = UnitXP("inSight", "player", "target")
    local alpha = (los == false) and 0.5 or 1.0
    f.text:SetAlpha(alpha)

    local r, g, b = GetColor(distance)
    f.text:SetTextColor(r, g, b, 1)
    f.text:SetText(string.format("%.1f yd", distance))
  end)
end)