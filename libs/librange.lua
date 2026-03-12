-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ librange ]]--
-- A pfUI library that detects and caches distance to units.
-- Requires Nampower.
--
--  librange:UnitInSpellRange(unit)
--    Returns `1` if the unit is within 40y range, nil otherwise
--

-- return instantly when another librange is already active
if pfUI.api.librange then return end

local librange = CreateFrame("Frame", "pfRangecheck", UIParent)

-- Healing Touch Rank 1 (SpellID 5185) has 40yd range and works for all classes
-- regardless of whether the spell is in the player's spellbook.
function librange:UnitInSpellRange(unit)
  -- UnitXP precise distance check (most accurate)
  if pfUI.api.HasUnitXP() then
    local success, distance = pcall(UnitXP, "distanceBetween", "player", unit)
    if success and distance then
      return distance <= 40 and 1 or nil
    end
  end

  -- Nampower: IsSpellInRange with fixed SpellID, works for all classes
  local result = IsSpellInRange(5185, unit)
  return result == 1 and 1 or nil
end

-- add librange to pfUI API
pfUI.api.librange = librange

-- NOTE: reattack block removed for projectile bug testing