-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libtooltip ]]--
-- A pfUI library that provides additional GameTooltip information.
--
--  libtooltip:GetItemID()
--    returns the itemID of the current GameTooltip
--    `nil` when no item is displayed
--
--  libtooltip:GetItemLink()
--    returns the itemLink of the current GameTooltip
--    `nil` when no item is displayed
--
--  libtooltip:GetItemCount()
--    returns the item count (bags) of the current GameTooltip
--    `nil` when no item is displayed

-- return instantly when another libtooltip is already active
if pfUI.api.libtooltip then return end

local _
local libtooltip = CreateFrame("Frame" , "pfLibTooltip", GameTooltip)
libtooltip:SetScript("OnHide", function()
  this.itemID = nil
  this.itemLink = nil
  this.itemCount = nil
end)

-- core functions
libtooltip.GetItemID = function(self)
  if not libtooltip.itemLink then return end
  if not libtooltip.itemID then
    local _, _, itemID = string.find(libtooltip.itemLink, "item:(%d+):%d+:%d+:%d+")
    libtooltip.itemID = tonumber(itemID)
  end

  return libtooltip.itemID
end

libtooltip.GetItemLink = function(self)
  return libtooltip.itemLink
end

libtooltip.GetItemCount = function(self)
  return libtooltip.itemCount
end

-- ============================================================================
-- Spell Description Resolver (Nampower)
-- Resolves DBC description/tooltip placeholders using GetSpellRec data.
--
--  libtooltip:GetSpellTooltip(spellId)
--    returns the resolved tooltip string for a buff/debuff aura
--    e.g. "Increases Stamina by 43."
--    returns nil if GetSpellRec is unavailable or spell not found
--
--  libtooltip:GetSpellDescription(spellId)
--    returns the resolved full description string
--    e.g. "Power infuses the target increasing their Stamina by 43 for 30 min."
--    returns nil if GetSpellRec is unavailable or spell not found
--
--  libtooltip:SetSpellByID(tooltip, spellId)
--    populates a GameTooltip with name, rank, and resolved tooltip text
--    using only Nampower data (no Blizzard tooltip scanning)
-- ============================================================================

-- Duration formatter: ms -> human readable string (Blizzard style)
local function FormatDuration(ms)
  if not ms or ms <= 0 then return "0 sec" end
  local sec = ms / 1000
  if sec >= 86400 then
    local days = math.floor(sec / 86400)
    return days .. (days == 1 and " day" or " days")
  elseif sec >= 3600 then
    local hours = math.floor(sec / 3600)
    local mins = math.floor((sec - hours * 3600) / 60)
    if mins > 0 then
      return hours .. (hours == 1 and " hour" or " hours") .. " " .. mins .. " min"
    end
    return hours .. (hours == 1 and " hour" or " hours")
  elseif sec >= 60 then
    local mins = math.floor(sec / 60)
    local secs = math.floor(sec - mins * 60)
    if secs > 0 then
      return mins .. " min " .. secs .. " sec"
    end
    return mins .. " min"
  else
    sec = math.floor(sec)
    return sec .. " sec"
  end
end

-- Core resolver: replace DBC placeholders in a spell string
local function ResolveSpellString(text, rec)
  if not text or not rec then return text end

  -- Cache spell data
  local bp = rec.effectBasePoints
  local ds = rec.effectDieSides
  local amp = rec.effectAmplitude
  local ppc = rec.effectPointsPerComboPoint
  local chain = rec.effectChainTarget
  local misc = rec.effectMiscValue
  local rpl = rec.effectRealPointsPerLevel

  -- Player level for level-scaling calculations
  local playerLevel = UnitLevel and UnitLevel("player") or 60

  -- Calculate scaled spell value: basePoints + dieSides + ((playerLevel - spellLevel) * realPointsPerLevel)
  local function calcS(sBp, sDs, sRpl, sSpellLevel, n)
    if not sBp or not sBp[n] then return 0 end
    local val = sBp[n] + (sDs and sDs[n] or 1)
    if sRpl and sRpl[n] and sRpl[n] ~= 0 and sSpellLevel then
      val = val + math.floor((playerLevel - sSpellLevel) * sRpl[n])
    end
    return val
  end

  -- $s helper for current spell
  local function getS(n)
    return calcS(bp, ds, rpl, rec.spellLevel, n)
  end

  -- Duration in ms (base, no modifiers)
  local durMs
  if GetSpellDuration then
    durMs = GetSpellDuration(rec.id, 1)
  end

  -- 0) Cross-spell references: $<spellId><var><idx>
  --    e.g. $3025s1 = get $s1 from spell 3025
  text = string.gsub(text, "%$(%d%d+)([smMoStT])(%d)", function(refId, var, idx)
    refId = tonumber(refId)
    idx = tonumber(idx)
    local refOk, refRec = pcall(GetSpellRec, refId)
    if not refOk or not refRec then return "0" end
    local refBp = refRec.effectBasePoints
    local refDs = refRec.effectDieSides
    local refRpl = refRec.effectRealPointsPerLevel
    local refAmp = refRec.effectAmplitude
    if not refBp or not refBp[idx] then return "0" end
    local refS = calcS(refBp, refDs, refRpl, refRec.spellLevel, idx)
    if var == "s" then return tostring(refS)
    elseif var == "S" then return tostring(math.abs(refS))
    elseif var == "m" then return tostring(refBp[idx] + 1)
    elseif var == "M" then return tostring(refBp[idx] + (refDs and refDs[idx] or 1))
    elseif var == "o" then
      local refA = refAmp and refAmp[idx] or 0
      local refDur = GetSpellDuration and GetSpellDuration(refId, 1) or 0
      if refA > 0 and refDur > 0 then
        return tostring(math.floor((refDur / refA) * refS))
      end
      return tostring(refS)
    elseif var == "t" then
      local refA = refAmp and refAmp[idx] or 0
      if refA > 0 then return tostring(refA / 1000) end
      return "0"
    end
    return "0"
  end)

  -- 1) Handle $*N;pattern  (multiplier prefix)
  --    $*6;s1  means: (dur/amp) * $s1  OR  N * $s1
  text = string.gsub(text, "%$%*(%d+);([smMoStTeEbBhH])(%d)", function(mult, var, idx)
    mult = tonumber(mult)
    idx = tonumber(idx)
    local val = 0
    if var == "s" or var == "S" then val = getS(idx)
    elseif var == "m" then val = bp[idx] + 1
    elseif var == "M" then val = bp[idx] + (ds and ds[idx] or 1)
    end
    if var == "S" then val = math.abs(val) end
    return tostring(mult * val)
  end)

  -- 2) $/divisor;varN - division: $s1 / divisor  e.g. $/1000;s1
  text = string.gsub(text, "%$/(%d+);([smMoS])(%d)", function(divisor, var, idx)
    divisor = tonumber(divisor)
    idx = tonumber(idx)
    local val = 0
    if var == "s" or var == "S" then val = getS(idx)
    elseif var == "m" then val = (bp and bp[idx] or 0) + 1
    elseif var == "M" then val = (bp and bp[idx] or 0) + (ds and ds[idx] or 1)
    elseif var == "o" then
      local s = getS(idx)
      local a = amp and amp[idx] or 0
      val = (a > 0 and durMs and durMs > 0) and math.floor((durMs / a) * s) or s
    end
    if var == "S" then val = math.abs(val) end
    if not divisor or divisor == 0 then return tostring(val) end
    local result = val / divisor
    -- Show as integer if clean, otherwise 1 decimal
    if result == math.floor(result) then
      return tostring(math.floor(result))
    else
      return string.format("%.1f", result)
    end
  end)

  -- 3) $o1/$o2/$o3 - total over time: (dur/amp) * $s[N]
  text = string.gsub(text, "%$o(%d)", function(idx)
    idx = tonumber(idx)
    local s = getS(idx)
    local a = amp and amp[idx] or 0
    if a > 0 and durMs and durMs > 0 then
      return tostring(math.floor((durMs / a) * s))
    end
    return tostring(s)
  end)

  -- 4) $M1/$M2/$M3 - max value (with level scaling)
  text = string.gsub(text, "%$M(%d)", function(idx)
    idx = tonumber(idx)
    return tostring(getS(idx))
  end)

  -- 5) $m1/$m2/$m3 - min value (with level scaling)
  text = string.gsub(text, "%$m(%d)", function(idx)
    idx = tonumber(idx)
    return tostring(getS(idx))
  end)

  -- 6) $S1/$S2/$S3 - absolute value of $s
  text = string.gsub(text, "%$S(%d)", function(idx)
    idx = tonumber(idx)
    return tostring(math.abs(getS(idx)))
  end)

  -- 7) $s1/$s2/$s3 - base value
  text = string.gsub(text, "%$s(%d)", function(idx)
    idx = tonumber(idx)
    return tostring(getS(idx))
  end)

  -- 8) $t1/$t2/$t3 - tick interval in seconds
  text = string.gsub(text, "%$t(%d)", function(idx)
    idx = tonumber(idx)
    local a = amp and amp[idx] or 0
    if a > 0 then return tostring(a / 1000) end
    return "0"
  end)

  -- 9) $e1/$e2/$e3 - points per combo point
  text = string.gsub(text, "%$e(%d)", function(idx)
    idx = tonumber(idx)
    if ppc and ppc[idx] then return tostring(ppc[idx]) end
    return "0"
  end)

  -- 10) $h1/$h2/$h3 - chain targets
  text = string.gsub(text, "%$h(%d)", function(idx)
    idx = tonumber(idx)
    if chain and chain[idx] then return tostring(chain[idx]) end
    return "0"
  end)

  -- 11) $b1/$b2/$b3 - points per level
  text = string.gsub(text, "%$b(%d)", function(idx)
    idx = tonumber(idx)
    if rpl and rpl[idx] then return tostring(rpl[idx]) end
    return "0"
  end)

  -- 12) $d - duration
  text = string.gsub(text, "%$d", function()
    if durMs and durMs > 0 then
      return FormatDuration(durMs)
    end
    return "until cancelled"
  end)

  -- 13) $a1/$a2/$a3 - radius (index, skip for now - just remove placeholder)
  text = string.gsub(text, "%$a(%d)", function(idx)
    return ""
  end)

  -- 14) $i - max affected targets
  if rec.maxAffectedTargets and rec.maxAffectedTargets > 0 then
    text = string.gsub(text, "%$i", tostring(rec.maxAffectedTargets))
  else
    text = string.gsub(text, "%$i", "")
  end

  -- 15) $n - proc chance
  if rec.procChance and rec.procChance > 0 then
    text = string.gsub(text, "%$n", tostring(rec.procChance))
  else
    text = string.gsub(text, "%$n", "")
  end

  -- 16) $lSingular;Plural; - pick based on previous number
  text = string.gsub(text, "(%d+)(.-)%$l([^;]+);([^;]+);", function(num, between, singular, plural)
    if tonumber(num) == 1 then
      return num .. between .. singular
    else
      return num .. between .. plural
    end
  end)

  return text
end

-- Public API: get resolved tooltip text for a spell
libtooltip.GetSpellTooltip = function(self, spellId)
  if not spellId or not GetSpellRec then return nil end
  local ok, rec = pcall(GetSpellRec, spellId)
  if not ok or not rec then return nil end
  if not rec.tooltip or rec.tooltip == "" then return nil end
  return ResolveSpellString(rec.tooltip, rec)
end

-- Public API: get resolved description text for a spell
libtooltip.GetSpellDescription = function(self, spellId)
  if not spellId or not GetSpellRec then return nil end
  local ok, rec = pcall(GetSpellRec, spellId)
  if not ok or not rec then return nil end
  if not rec.description or rec.description == "" then return nil end
  return ResolveSpellString(rec.description, rec)
end

-- Format remaining time (Blizzard style):
-- >= 1h:  "X hours Y minutes remaining" (no seconds)
-- >= 1m:  "X minutes remaining" (no seconds)
-- < 1m:   "X seconds remaining"
local function FormatRemaining(sec)
  if not sec or sec <= 0 then return nil end
  if sec >= 3600 then
    local hours = math.floor(sec / 3600)
    local mins = math.floor((sec - hours * 3600) / 60)
    local str = hours .. (hours == 1 and " hour" or " hours")
    if mins > 0 then
      str = str .. " " .. mins .. (mins == 1 and " minute" or " minutes")
    end
    return str .. " remaining"
  elseif sec >= 60 then
    local mins = math.floor(sec / 60)
    return mins .. (mins == 1 and " minute" or " minutes") .. " remaining"
  else
    local s = math.floor(sec)
    return s .. (s == 1 and " second" or " seconds") .. " remaining"
  end
end

-- Public API: populate a GameTooltip with spell info from Nampower
-- tooltip:       GameTooltip frame
-- spellId:       spell ID
-- remainingSec:  (optional) remaining buff duration in seconds
-- dispelType:    (optional) "Magic", "Curse", "Poison", "Disease"
-- buffType:      (optional) "HELPFUL" or "HARMFUL"
libtooltip.SetSpellByID = function(self, tooltip, spellId, remainingSec, dispelType, buffType)
  if not spellId or not GetSpellRec then return false end
  local ok, rec = pcall(GetSpellRec, spellId)
  if not ok or not rec then return false end

  -- Resolve dispel type
  local dtype = dispelType
  if not dtype or dtype == "" then
    local dispel = rec.dispel
    if dispel == 1 then dtype = "Magic"
    elseif dispel == 2 then dtype = "Curse"
    elseif dispel == 3 then dtype = "Disease"
    elseif dispel == 4 then dtype = "Poison"
    end
  end

  -- Line 1: Name (yellow) + Rank (green) + Type (colored) all on one line
  local name = rec.name or ("Spell #" .. spellId)
  local rank = rec.rank and rec.rank ~= "" and rec.rank or nil
  local left = name
  if rank then
    left = left .. "  |cffff4444" .. rank .. "|r"
  end
  if dtype then
    local dcolor = "ffffffff"
    if dtype == "Magic" then dcolor = "ff3399ff"
    elseif dtype == "Poison" then dcolor = "ff009900"
    elseif dtype == "Curse" then dcolor = "ff9900ff"
    elseif dtype == "Disease" then dcolor = "ff996600"
    end
    tooltip:AddDoubleLine(left, "|c" .. dcolor .. dtype .. "|r", 1, 0.82, 0, 1, 1, 1)
  else
    tooltip:AddLine(left, 1, 0.82, 0)
  end

  -- Resolved tooltip text (white, wrap enabled)
  local tt = rec.tooltip and rec.tooltip ~= "" and rec.tooltip or rec.description
  if tt then
    local resolved = ResolveSpellString(tt, rec)
    if resolved and resolved ~= "" then
      tooltip:AddLine(resolved, 1, 1, 1, 1)
    end
  end

  -- Remaining time (yellow, simplified format)
  if remainingSec and remainingSec > 0 then
    local remaining = FormatRemaining(remainingSec)
    if remaining then
      tooltip:AddLine(remaining, 1, 0.82, 0)
    end
  end

  tooltip:Show()
  return true
end

pfUI.api.libtooltip = libtooltip

-- ============================================================================
-- Unit Aura SpellId Resolution
-- Maps Blizzard buff/debuff index to spellId via GetUnitField aura data
-- ============================================================================

-- Get spellId for a unit's buff by Blizzard buff index
-- Buffs occupy aura slots 1-32, but hidden auras are skipped in Blizzard API
-- unit:    unit token (e.g. "target", "player", "party1")
-- index:   Blizzard buff index (1-based, as used in UnitBuff)
-- returns: spellId or nil
libtooltip.GetUnitBuffSpellId = function(self, unit, index)
  if not GetUnitField or not index then return nil end
  local auras = GetUnitField(unit, "aura")
  if not auras then return nil end
  local visibleIdx = 0
  for slot = 1, 32 do
    local spellId = auras[slot]
    if spellId and spellId > 0 then
      -- Skip hidden auras (same as Blizzard does)
      local hidden = IsAuraHidden and IsAuraHidden(spellId)
      if not hidden then
        visibleIdx = visibleIdx + 1
        if visibleIdx == index then
          return spellId
        end
      end
    end
  end
  return nil
end

-- Get spellId for a unit's debuff by display index
-- Uses libdebuff:IterDebuffs which handles spillover correctly
-- unit:    unit token
-- index:   display debuff index (1-based, as returned by libdebuff:UnitDebuff)
-- returns: spellId or nil
libtooltip.GetUnitDebuffSpellId = function(self, unit, index)
  -- Try libdebuff first (handles spillover)
  local libdebuff = pfUI.api.libdebuff
  if libdebuff and libdebuff.IterDebuffs then
    local visibleIdx = 0
    local foundId = nil
    libdebuff:IterDebuffs(unit, function(auraSlot, spellId)
      visibleIdx = visibleIdx + 1
      if visibleIdx == index and not foundId then
        foundId = spellId
      end
    end)
    return foundId
  end
  -- Fallback: direct aura slot scan (no spillover)
  if not GetUnitField or not index then return nil end
  local auras = GetUnitField(unit, "aura")
  if not auras then return nil end
  local visibleIdx = 0
  for slot = 33, 48 do
    local spellId = auras[slot]
    if spellId and spellId > 0 then
      local hidden = IsAuraHidden and IsAuraHidden(spellId)
      if not hidden then
        visibleIdx = visibleIdx + 1
        if visibleIdx == index then
          return spellId
        end
      end
    end
  end
  return nil
end

-- Convenience: set tooltip for a unit's buff by index
-- Falls back to Blizzard SetUnitBuff if Nampower not available
libtooltip.SetUnitBuffTooltip = function(self, tooltip, unit, index)
  local spellId = self:GetUnitBuffSpellId(unit, index)
  if spellId then
    return self:SetSpellByID(tooltip, spellId)
  end
  return false
end

-- Convenience: set tooltip for a unit's debuff by index
-- Falls back to Blizzard SetUnitDebuff if Nampower not available
libtooltip.SetUnitDebuffTooltip = function(self, tooltip, unit, index)
  local spellId = self:GetUnitDebuffSpellId(unit, index)
  if spellId then
    return self:SetSpellByID(tooltip, spellId)
  end
  return false
end

-- setup item hooks
local pfHookSetHyperlink = GameTooltip.SetHyperlink
function GameTooltip.SetHyperlink(self, arg1)
  if arg1 then
    local _, _, linktype = string.find(arg1, "^(.-):(.+)$")
    if linktype == "item" then
      libtooltip.itemLink = arg1
    end
  end

  return pfHookSetHyperlink(self, arg1)
end

local pfHookSetBagItem = GameTooltip.SetBagItem
function GameTooltip.SetBagItem(self, container, slot)
  -- skip special/invalid calls to the function
  if not container or not slot then
    return pfHookSetBagItem(self, container, slot)
  end

  libtooltip.itemLink = GetContainerItemLink(container, slot)
  _, libtooltip.itemCount = GetContainerItemInfo(container, slot)
  return pfHookSetBagItem(self, container, slot)
end

local pfHookSetQuestLogItem = GameTooltip.SetQuestLogItem
function GameTooltip.SetQuestLogItem(self, itemType, index)
  libtooltip.itemLink = GetQuestLogItemLink(itemType, index)
  if not libtooltip.itemLink then return end
  return pfHookSetQuestLogItem(self, itemType, index)
end

local pfHookSetQuestItem = GameTooltip.SetQuestItem
function GameTooltip.SetQuestItem(self, itemType, index)
  libtooltip.itemLink = GetQuestItemLink(itemType, index)
  return pfHookSetQuestItem(self, itemType, index)
end

local pfHookSetLootItem = GameTooltip.SetLootItem
function GameTooltip.SetLootItem(self, slot)
  libtooltip.itemLink = GetLootSlotLink(slot)
  pfHookSetLootItem(self, slot)
end

local pfHookSetInboxItem = GameTooltip.SetInboxItem
function GameTooltip.SetInboxItem(self, mailID, attachmentIndex)
  local itemName, itemTexture, inboxItemCount, inboxItemQuality = GetInboxItem(mailID)
  libtooltip.itemLink = GetItemLinkByName(itemName)
  return pfHookSetInboxItem(self, mailID, attachmentIndex)
end

local pfHookSetInventoryItem = GameTooltip.SetInventoryItem
function GameTooltip.SetInventoryItem(self, unit, slot)
  libtooltip.itemLink = GetInventoryItemLink(unit, slot)
  return pfHookSetInventoryItem(self, unit, slot)
end

local pfHookSetLootRollItem = GameTooltip.SetLootRollItem
function GameTooltip.SetLootRollItem(self, id)
  libtooltip.itemLink = GetLootRollItemLink(id)
  return pfHookSetLootRollItem(self, id)
end

local pfHookSetMerchantItem = GameTooltip.SetMerchantItem
function GameTooltip.SetMerchantItem(self, merchantIndex)
  libtooltip.itemLink = GetMerchantItemLink(merchantIndex)
  return pfHookSetMerchantItem(self, merchantIndex)
end

local pfHookSetCraftItem = GameTooltip.SetCraftItem
function GameTooltip.SetCraftItem(self, skill, slot)
  libtooltip.itemLink = GetCraftReagentItemLink(skill, slot)
  return pfHookSetCraftItem(self, skill, slot)
end

local pfHookSetCraftSpell = GameTooltip.SetCraftSpell
function GameTooltip.SetCraftSpell(self, slot)
  libtooltip.itemLink = GetCraftItemLink(slot)
  return pfHookSetCraftSpell(self, slot)
end

local pfHookSetTradeSkillItem = GameTooltip.SetTradeSkillItem
function GameTooltip.SetTradeSkillItem(self, skillIndex, reagentIndex)
  if reagentIndex then
    libtooltip.itemLink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
  else
    libtooltip.itemLink = GetTradeSkillItemLink(skillIndex)
  end
  return pfHookSetTradeSkillItem(self, skillIndex, reagentIndex)
end

local pfHookSetAuctionItem = GameTooltip.SetAuctionItem
function GameTooltip.SetAuctionItem(self, atype, index)
  _, _, libtooltip.itemCount = GetAuctionItemInfo(atype, index)
  libtooltip.itemLink = GetAuctionItemLink(atype, index)
  return pfHookSetAuctionItem(self, atype, index)
end

local pfHookSetAuctionSellItem = GameTooltip.SetAuctionSellItem
function GameTooltip.SetAuctionSellItem(self)
  local itemName, _, itemCount = GetAuctionSellItemInfo()
  libtooltip.itemCount = itemCount
  libtooltip.itemLink = GetItemLinkByName(itemName)
  return pfHookSetAuctionSellItem(self)
end

local pfHookSetTradePlayerItem = GameTooltip.SetTradePlayerItem
function GameTooltip.SetTradePlayerItem(self, index)
  libtooltip.itemLink = GetTradePlayerItemLink(index)
  return pfHookSetTradePlayerItem(self, index)
end

local pfHookSetTradeTargetItem = GameTooltip.SetTradeTargetItem
function GameTooltip.SetTradeTargetItem(self, index)
  libtooltip.itemLink = GetTradeTargetItemLink(index)
  return pfHookSetTradeTargetItem(self, index)
end