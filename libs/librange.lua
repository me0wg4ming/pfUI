-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ librange ]]--
-- A pfUI library that detects and caches distance to units.
-- Requires Nampower.
--
--  librange:UnitInSpellRange(unit)
--    Returns `1` if the unit is within 40y range, nil otherwise
--
--  librange:UnitInDispelRange(unit)
--    Returns `1` if the unit is within 30y dispel range, nil otherwise
--
-- Spell IDs used as range proxies (work for all classes via Nampower):
--   5185  = Healing Touch Rank 1  (~40yd)
--   552   = Abolish Disease        (~30yd)
--   14325 = Hunter's Mark          (~100yd)
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

-- Abolish Disease (SpellID 552) has 30yd range — used as dispel range proxy
function librange:UnitInDispelRange(unit)
  local result = IsSpellInRange(552, unit)
  return result == 1 and 1 or nil
end

-- Hunter's Mark (SpellID 14325) has 100yd range — used as inspect range proxy
function librange:UnitInInspectRange(unit)
  local result = IsSpellInRange(14325, unit)
  return result == 1 and 1 or nil
end

-- add librange to pfUI API
pfUI.api.librange = librange