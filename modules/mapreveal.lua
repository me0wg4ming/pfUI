pfUI:RegisterModule("mapreveal", "vanilla", function ()
  if Cartographer then return end
  if METAMAP_TITLE then return end

  pfUI.mapreveal = {}
  function pfUI.mapreveal:UpdateConfig()
    WorldMapFrame_Update()
  end

  pfUI.mapreveal.onmap = CreateFrame("CheckButton", "pfUI_mapreveal_onmap", WorldMapFrame, "UICheckButtonTemplate")
  pfUI.mapreveal.onmap:SetNormalTexture("")
  pfUI.mapreveal.onmap:SetPushedTexture("")
  pfUI.mapreveal.onmap:SetHighlightTexture("")
  pfUI.mapreveal.onmap.text = _G["pfUI_mapreveal_onmapText"]
  CreateBackdrop(pfUI.mapreveal.onmap, nil, true)
  pfUI.mapreveal.onmap:SetWidth(14)
  pfUI.mapreveal.onmap:SetHeight(14)
  pfUI.mapreveal.onmap:SetPoint("LEFT", WorldMapZoomOutButton, "RIGHT", 20, 0)
  pfUI.mapreveal.onmap.text:SetPoint("LEFT", pfUI.mapreveal.onmap, "RIGHT", 2, 0)
  pfUI.mapreveal.onmap.text:SetText(T["Reveal Unexplored Areas"])
  pfUI.mapreveal.onmap:SetScript("OnShow", function()
    this:SetChecked(C.appearance.worldmap.mapreveal == "1")
  end)
  pfUI.mapreveal.onmap:SetScript("OnClick", function ()
    if this:GetChecked() then
      C.appearance.worldmap.mapreveal = "1"
    else
      C.appearance.worldmap.mapreveal = "0"
    end
    pfUI.mapreveal:UpdateConfig()
  end)

  local function unpack_hash(prefix, hash)
    local _, stored_prefix, textureName, textureWidth, textureHeight, offsetX, offsetY, mapPointX, mapPointY, name
    _, _, stored_prefix, textureName, textureWidth, textureHeight, offsetX, offsetY = string.find(hash, "^([|]?)([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)")
    if (not textureName or not offsetY) then
      return
    end
    if (offsetY) then
      _, _, mapPointX, mapPointY = string.find(hash,"^[|]?[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:([^:]+):([^:]+)")
    end
    if (not mapPointY) then
      mapPointX = 0 mapPointY = 0
    end
    if (stored_prefix ~= "|") then
      name = textureName
      textureName = string.format("%s%s",prefix,textureName)
    end
    return textureName, textureWidth + 0, textureHeight + 0, offsetX + 0, offsetY + 0, mapPointX + 0, mapPointY + 0, name
  end

  local explores = {}
  local explorecaches = {}
  local alreadyknown = {} -- per-zone accumulator: { [zone] = { [texName] = true } }

  -- Own texture pool - separate from Blizzard's WorldMapOverlay textures
  local pfOverlays = {}
  local pfOverlayMax = 0

  local function pfGetOverlay(idx)
    if not pfOverlays[idx] then
      pfOverlays[idx] = WorldMapDetailFrame:CreateTexture("pfReveal"..idx, "BORDER")
    end
    return pfOverlays[idx]
  end

  local exploreEnter = function()
    WorldMapTooltip:ClearLines()
    WorldMapTooltip:SetOwner(this, "ANCHOR_TOP")
    WorldMapTooltip:AddLine(T["Exploration Point"]..":", .3, 1, .8)
    WorldMapTooltip:AddLine(this.name, 1, 1, 1)
    WorldMapTooltip:Show()

    if not explorecaches[this.name] then return end
    if C.appearance.worldmap.mapreveal == "0" then return end
    for texture in pairs(explorecaches[this.name]) do
      texture:SetVertexColor(1,1,1,1)
    end
  end

  local exploreLeave = function()
    WorldMapTooltip:Hide()
    if not explorecaches[this.name] then return end
    if C.appearance.worldmap.mapreveal == "0" then return end
    local r,g,b,a = GetStringColor(C.appearance.worldmap.mapreveal_color)
    for texture in pairs(explorecaches[this.name]) do
      texture:SetVertexColor(r,g,b,a)
    end
  end

  -- overlay data with lazy init
  local overlayData = setmetatable(pfMapOverlayData, {__index = function(t,k)
    local v = {}
    rawset(t,k,v)
    return v
  end})

  local function pfWorldMapFrame_Update()
    -- clear stale caches
    for k in pairs(explorecaches) do explorecaches[k] = nil end

    -- hide all our textures from last frame
    for i = 1, pfOverlayMax do
      pfOverlays[i]:Hide()
    end

    local r,g,b,a = GetStringColor(C.appearance.worldmap.mapreveal_color)
    local mapFileName = GetMapInfo()
    if not mapFileName then mapFileName = "World" end

    local prefix = string.format("Interface\\WorldMap\\%s\\", mapFileName)
    local numOverlays = GetNumMapOverlays()

    -- accumulate explored overlays per zone (never clear, only add)
    if not alreadyknown[mapFileName] then alreadyknown[mapFileName] = {} end
    for i = 1, numOverlays do
      local texName = GetMapOverlayInfo(i)
      if texName then alreadyknown[mapFileName][string.upper(texName)] = true end
    end

    local zoneKnown = alreadyknown[mapFileName]

    -- hide explore icons
    for _, frame in pairs(explores) do frame:Hide() end

    local zoneData = overlayData[mapFileName]
    local textureCount = 0

    for i, hash in ipairs(zoneData) do
      local textureName, textureWidth, textureHeight, offsetX, offsetY, mapPointX, mapPointY, name = unpack_hash(prefix, hash)
      if not textureName then break end

      -- explore magnifying glass icon
      explores[i] = explores[i] or CreateFrame("Frame", nil, WorldMapDetailFrame)
      local explore = explores[i]
      explore:SetWidth(16)
      explore:SetHeight(16)
      explore:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", offsetX + textureWidth/2, -offsetY - textureHeight/2)
      explore:SetScript("OnEnter", exploreEnter)
      explore:SetScript("OnLeave", exploreLeave)
      explore:EnableMouse(true)
      explore:SetFrameLevel(255)
      explore.name = mapFileName .. " (" .. name .. ")"
      explore.tex = explore.tex or explore:CreateTexture("", "OVERLAY")
      explore.tex:SetBlendMode("ADD")
      explore.tex:SetTexCoord(.08, .92, .08, .92)
      explore.tex:SetAllPoints()

      if C.appearance.worldmap.mapexploration == "1" and not zoneKnown[string.upper(textureName)] then
        explore.tex:SetTexture("Interface\\WorldMap\\WorldMap-MagnifyingGlass")
        explore:Show()
      else
        explore:Hide()
      end

      -- render overlay texture tiles on BORDER draw layer
      -- Blizzard's explored overlays on ARTWORK draw on top of BORDER
      if C.appearance.worldmap.mapreveal == "1" then
        local numH = math.ceil(textureWidth / 256)
        local numV = math.ceil(textureHeight / 256)
        local texPixW, texFileW, texPixH, texFileH

        for j = 1, numV do
          if j < numV then
            texPixH = 256
            texFileH = 256
          else
            texPixH = mod(textureHeight, 256)
            if texPixH == 0 then texPixH = 256 end
            texFileH = 16
            while texFileH < texPixH do texFileH = texFileH * 2 end
          end

          for k = 1, numH do
            textureCount = textureCount + 1
            local tex = pfGetOverlay(textureCount)

            if k < numH then
              texPixW = 256
              texFileW = 256
            else
              texPixW = mod(textureWidth, 256)
              if texPixW == 0 then texPixW = 256 end
              texFileW = 16
              while texFileW < texPixW do texFileW = texFileW * 2 end
            end

            tex:SetWidth(texPixW)
            tex:SetHeight(texPixH)
            tex:SetTexCoord(0, texPixW/texFileW, 0, texPixH/texFileH)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", offsetX + 256*(k-1), -(offsetY + 256*(j-1)))
            tex:SetTexture(string.format("%s%s", textureName, ((j-1)*numH + k)))

            explorecaches[name] = explorecaches[name] or {}
            explorecaches[name][tex] = true

            tex:SetVertexColor(r,g,b,a)
            tex:Show()
          end
        end
      end
    end

    pfOverlayMax = math.max(pfOverlayMax, textureCount)
  end

  -- hook WorldMapFrame_Update
  local origUpdate = _G.WorldMapFrame_Update
  _G.WorldMapFrame_Update = function(...)
    origUpdate(unpack(arg))
    pfWorldMapFrame_Update()
  end

end)