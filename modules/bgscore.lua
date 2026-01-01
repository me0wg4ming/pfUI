pfUI:RegisterModule("bgscore", "vanilla", function ()
  local bgframe = WorldStateAlwaysUpFrame
  if not bgframe then
    bgframe = CreateFrame("Frame", "WorldStateAlwaysUpFrame", UIParent)
    bgframe:SetWidth(200)
    bgframe:SetHeight(25)
    bgframe:SetPoint("TOP", UIParent, "TOP", 0, -100)
  end

  local mover = CreateFrame("Frame", "pfUIBGScoreMover", UIParent)
  mover:SetWidth(220)
  mover:SetHeight(30)
  mover:SetPoint("TOP", UIParent, "TOP", 0, -100)
  mover:SetFrameStrata("DIALOG")
  mover:SetMovable(true)
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", function() mover:StartMoving() end)
  mover:SetScript("OnDragStop", function()
    mover:StopMovingOrSizing()
    local x = mover:GetLeft()
    local y = mover:GetTop()
    pfUI_config = pfUI_config or {}
    pfUI_config.positions = pfUI_config.positions or {}
    pfUI_config.positions["WorldStateAlwaysUpFrame"] = { x = x, y = y }
    bgframe:ClearAllPoints()
    bgframe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccBG Score Frame|r position saved.")
  end)
  mover:Hide()

  pfUI.api.CreateBackdrop(mover, nil, nil, .8)

  -- Title label
  local title = mover:CreateFontString(nil, "OVERLAY")
  title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
  title:SetText("Battleground Frames")
  title:SetPoint("TOP", mover, "TOP", 0, -2)

  -- BG score preview text
  local bgscore = mover:CreateFontString(nil, "OVERLAY")
  bgscore:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  bgscore:SetText("|cff3399ffAlliance: 123|r  |  |cffff4444Horde: 456|r")
  bgscore:SetPoint("BOTTOM", mover, "BOTTOM", 0, 2)

  mover.label = "BG Score"
  pfUI.unlock.frames = pfUI.unlock.frames or {}
  table.insert(pfUI.unlock.frames, mover)

  local pos = pfUI_config and pfUI_config.positions and pfUI_config.positions["WorldStateAlwaysUpFrame"]
  if pos then
    bgframe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  end

  local origShow = pfUI.unlock.Show
  local origHide = pfUI.unlock.Hide
  pfUI.unlock.Show = function(self) origShow(self); mover:Show() end
  pfUI.unlock.Hide = function(self) origHide(self); mover:Hide(); bgframe:Show() end
end)
