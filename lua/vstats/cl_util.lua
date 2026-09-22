function vstats.FindConfig(list, id)
    for _, item in ipairs(list) do
        if item.id == id then return item end
    end
end

function vstats.FormatSeconds(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    local hours = math.floor(value / 3600)
    local minutes = math.floor((value % 3600) / 60)
    return string.format("%dh %dm", hours, minutes)
end

function vstats.FormatValue(value, unit)
    value = tonumber(value) or 0
    if unit == "seconds" then return vstats.FormatSeconds(value) end
    if unit == "money" then
        if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(math.Round(value)) end
        return "$" .. string.Comma(math.Round(value))
    end
    if unit == "rate" then return string.format("%.2f / h", value) end
    if unit == "xp_rate" then return string.format("%.2f XP / h", value) end
    if unit == "xp" then return string.Comma(math.Round(value)) .. " XP" end
    if unit == "count" and value % 1 ~= 0 then return string.format("%.2f", value) end
    return string.Comma(math.Round(value))
end

print("[vStats] Util (CL) Loaded.")
