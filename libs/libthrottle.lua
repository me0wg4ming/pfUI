-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- return instantly when another libthrottle is already active
if pfUI.api.libthrottle then return end

-- Create libthrottle namespace
local libthrottle = CreateFrame("Frame", "pfLibThrottle")
pfUI.api.libthrottle = libthrottle

-- Preset definitions (FPS -> seconds)
libthrottle.presets = {
  ["very_slow"] = { fps = 2,  delay = 0.5 },
  ["slow"]      = { fps = 5,  delay = 0.2 },
  ["normal"]    = { fps = 10, delay = 0.1 },
  ["fast"]      = { fps = 20, delay = 0.05 },
  ["very_fast"] = { fps = 30, delay = 0.033 },
  ["fastest"]   = { fps = 50, delay = 0.02 },
}

-- Localized preset names
libthrottle.presetNames = {
  ["very_slow"] = "Very Slow (2 FPS)",
  ["slow"]      = "Slow (5 FPS)",
  ["normal"]    = "Normal (10 FPS)",
  ["fast"]      = "Fast (20 FPS)",
  ["very_fast"] = "Very Fast (30 FPS)",
  ["fastest"]   = "Fastest (50 FPS)",
  ["custom"]    = "Custom",
}

-- Default throttle categories
libthrottle.defaults = {
  nameplates           = "custom",
  nameplates_target    = "custom",
  nameplates_mass      = "custom",
  tooltip_cursor       = "custom",
  chat_tab             = "custom",
}

-- Convert FPS to throttle delay in seconds
function libthrottle:FpsToDelay(fps)
  if not fps or fps <= 0 then return 0.1 end
  return 1 / fps
end

-- Convert delay to FPS
function libthrottle:DelayToFps(delay)
  if not delay or delay <= 0 then return 10 end
  return math.floor(1 / delay)
end

-- Get throttle delay for a category
-- Returns: delay in seconds
function libthrottle:Get(category)
  local configValue = _G.pfUI_throttle and _G.pfUI_throttle[category]
  if not configValue then
    configValue = self.defaults[category] or "normal"
  end
  
  -- Check if it's a preset name
  local preset = self.presets[configValue]
  if preset then
    return preset.delay
  end
  
  -- If it's "custom", read from the _custom field
  if configValue == "custom" then
    local customFps = tonumber(_G.pfUI_throttle[category .. "_custom"])
    if customFps then
      return self:FpsToDelay(customFps)
    end
  end
  
  -- Fallback to normal preset
  return self.presets["normal"].delay
end

-- Get FPS value for a category (for display purposes)
function libthrottle:GetFps(category)
  local delay = self:Get(category)
  return self:DelayToFps(delay)
end

-- Get preset name for a category
function libthrottle:GetPreset(category)
  local configValue = _G.pfUI_throttle and _G.pfUI_throttle[category]
  if not configValue then
    return self.defaults[category] or "normal"
  end
  
  -- Check if it's a known preset
  if self.presets[configValue] then
    return configValue
  end
  
  -- Must be a custom value
  return "custom"
end

-- Check if a category is using custom FPS
function libthrottle:IsCustom(category)
  return self:GetPreset(category) == "custom"
end

-- Set throttle for a category
function libthrottle:Set(category, value)
  if not _G.pfUI_throttle then _G.pfUI_throttle = {} end
  
  -- Validate preset
  if type(value) == "string" and self.presets[value] then
    _G.pfUI_throttle[category] = value
    return true
  end
  
  -- If it's "custom", keep it
  if value == "custom" then
    _G.pfUI_throttle[category] = value
    return true
  end
  
  return false
end

-- Reset a category to its default value
function libthrottle:ResetToDefault(category)
  local default = self.defaults[category]
  if default then
    if not _G.pfUI_throttle then _G.pfUI_throttle = {} end
    _G.pfUI_throttle[category] = default
    return true
  end
  return false
end

-- Reset all categories to defaults
function libthrottle:ResetAllToDefaults()
  if not _G.pfUI_throttle then _G.pfUI_throttle = {} end
  for category, default in pairs(self.defaults) do
    _G.pfUI_throttle[category] = default
  end
end

-- Initialize - set defaults if config doesn't exist
libthrottle:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    if not _G.pfUI_throttle then
      _G.pfUI_throttle = {}
    end
    
    -- Set defaults for any missing categories
    for category, default in pairs(libthrottle.defaults) do
      if not _G.pfUI_throttle[category] then
        _G.pfUI_throttle[category] = default
      end
    end
    
    -- Set defaults for custom fields if missing
    if not _G.pfUI_throttle.nameplates_target_custom then _G.pfUI_throttle.nameplates_target_custom = "50" end
    if not _G.pfUI_throttle.nameplates_custom then _G.pfUI_throttle.nameplates_custom = "10" end
    if not _G.pfUI_throttle.nameplates_mass_custom then _G.pfUI_throttle.nameplates_mass_custom = "7" end
    if not _G.pfUI_throttle.tooltip_cursor_custom then _G.pfUI_throttle.tooltip_cursor_custom = "10" end
    if not _G.pfUI_throttle.chat_tab_custom then _G.pfUI_throttle.chat_tab_custom = "10" end
    
    this:UnregisterEvent("PLAYER_ENTERING_WORLD")
  end
end)

libthrottle:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Export to pfUI namespace for easier access
pfUI.throttle = libthrottle
