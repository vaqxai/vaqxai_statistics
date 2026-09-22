local PANEL = {}

function PANEL:Init()
    self.mode = "bar"
    self.rows = {}
    self.unit = "count"
    self.title = ""
end

function PANEL:SetBarData(rows, unit)
    self.mode = "bar"
    self.rows = rows or {}
    self.unit = unit or "count"
    self.title = "Top results"
end

function PANEL:SetSeriesData(rows, unit, title)
    self.mode = "line"
    self.rows = rows or {}
    self.unit = unit or "count"
    self.title = title or "Trend"
end

local function rowValue(row, mode)
    return tonumber(mode == "line" and row.value or row.total) or 0
end

function PANEL:Paint(w, h)
    surface.SetDrawColor(245, 245, 245)
    surface.DrawRect(0, 0, w, h)

    draw.SimpleText(self.title, "DermaDefaultBold", 10, 8, color_black)
    if #self.rows == 0 then
        draw.SimpleText("No data for this selection", "DermaDefault", w / 2, h / 2, Color(90, 90, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local left, top, right, bottom = 56, 32, w - 12, h - 34
    surface.SetDrawColor(170, 170, 170)
    surface.DrawLine(left, top, left, bottom)
    surface.DrawLine(left, bottom, right, bottom)

    local maxValue = 0
    local minValue = 0
    for _, row in ipairs(self.rows) do
        local value = rowValue(row, self.mode)
        maxValue = math.max(maxValue, value)
        minValue = math.min(minValue, value)
    end
    if maxValue == minValue then maxValue = minValue + 1 end

    draw.SimpleText(vstats.FormatValue(maxValue, self.unit), "DermaDefault", left - 4, top, Color(80, 80, 80), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    draw.SimpleText(vstats.FormatValue(minValue, self.unit), "DermaDefault", left - 4, bottom, Color(80, 80, 80), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    local graphHeight = bottom - top
    local function yFor(value)
        return bottom - ((value - minValue) / (maxValue - minValue)) * graphHeight
    end

    surface.SetDrawColor(52, 125, 190)
    if self.mode == "bar" then
        local count = math.min(#self.rows, 12)
        local gap = 4
        local barWidth = math.max(2, ((right - left) / count) - gap)
        local zeroY = yFor(math.Clamp(0, minValue, maxValue))
        for i = 1, count do
            local row = self.rows[i]
            local x = left + (i - 1) * ((right - left) / count) + gap / 2
            local y = yFor(rowValue(row, self.mode))
            surface.DrawRect(x, math.min(y, zeroY), barWidth, math.max(1, math.abs(zeroY - y)))
            local label = row.name or row.key or ""
            if #label > 12 then label = string.sub(label, 1, 11) .. "…" end
            draw.SimpleText(label, "DermaDefault", x + barWidth / 2, bottom + 4, Color(70, 70, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    else
        local previousX, previousY
        local divisor = math.max(1, #self.rows - 1)
        for i, row in ipairs(self.rows) do
            local x = left + ((i - 1) / divisor) * (right - left)
            local y = yFor(rowValue(row, self.mode))
            if previousX then surface.DrawLine(previousX, previousY, x, y) end
            surface.DrawRect(x - 2, y - 2, 4, 4)
            previousX, previousY = x, y
        end
        local first = self.rows[1]
        local last = self.rows[#self.rows]
        draw.SimpleText(os.date("%d %b", first.bucket or 0), "DermaDefault", left, bottom + 4, Color(70, 70, 70), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(os.date("%d %b", last.bucket or 0), "DermaDefault", right, bottom + 4, Color(70, 70, 70), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
end

vgui.Register("VStatsGraph", PANEL, "DPanel")

print("[vStats] Graph (CL) Loaded.")
