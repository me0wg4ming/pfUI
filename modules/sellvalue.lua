pfUI:RegisterModule("sellvalue", "vanilla:tbc", function ()
  local function AddVendorPrices(frame, id, count)
    if not id then return end
    local sell, buy

    if GetItemStatsField then
      sell = GetItemStatsField(id, "sellPrice") or 0
      buy  = GetItemStatsField(id, "buyPrice")  or 0
    elseif pfSellData[id] then
      local _, _, s, b = strfind(pfSellData[id], "(.*),(.*)")
      sell = tonumber(s)
      buy  = tonumber(b)
    else
      return
    end

    if sell == 0 then return end

    if not MerchantFrame:IsShown() then
      SetTooltipMoney(frame, sell * count)
    end

    if IsShiftKeyDown() or C.tooltip.vendor.showalways == "1" then
      frame:AddLine(" ")

      if count > 1 then
        frame:AddDoubleLine(T["Sell"] .. ":", CreateGoldString(sell) .. "|cff555555  //  " .. CreateGoldString(sell*count), 1, 1, 1)
      else
        frame:AddDoubleLine(T["Sell"] .. ":", CreateGoldString(sell * count), 1, 1, 1)
      end

      if MerchantFrame:IsShown() and buy > 0 then
        local _, _, merchantCount = GetMerchantItemInfo(id)
        merchantCount = merchantCount or 1
        frame:AddDoubleLine(T["Buy"] .. ":", CreateGoldString(buy * merchantCount), 1, 1, 1)
      end
    end
    frame:Show()
  end

  pfUI.sellvalue = CreateFrame("Frame", "pfGameTooltip", GameTooltip)
  pfUI.sellvalue:SetScript("OnShow", function()
    if libtooltip:GetItemLink() then
      local id = libtooltip:GetItemID()
      local count = tonumber(libtooltip:GetItemCount()) or 1
      AddVendorPrices(GameTooltip, id, math.max(count, 1))
    end
  end)

  local HookSetItemRef = SetItemRef
  _G.SetItemRef = function(link, text, button)
    local item, _, id = string.find(link, "item:(%d+):.*")
    HookSetItemRef(link, text, button)
    if not IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() and item then
      AddVendorPrices(ItemRefTooltip, tonumber(id), 1)
    end
  end
end)