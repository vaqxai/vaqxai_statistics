-- Bar/trend chart drawn entirely with surface/draw calls (no Derma skin).
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
    surface.SetDrawColor(vstats.COLORS.panelBg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(vstats.COLORS.panelBorder)
    surface.DrawOutlinedRect(0, 0, w, h)

    local pad = vstats.Scaled(10)
    draw.SimpleText(self.title, "VStats_Header", pad, pad, vstats.COLORS.text)
    if #self.rows == 0 then
        draw.SimpleText("No data for this selection", "VStats_Body", w / 2, h / 2, vstats.COLORS.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local left, top, right, bottom = vstats.Scaled(64), vstats.Scaled(40), w - vstats.Scaled(14), h - vstats.Scaled(40)
    surface.SetDrawColor(vstats.COLORS.panelBorder)
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

    draw.SimpleText(vstats.FormatValue(maxValue, self.unit), "VStats_Small", left - vstats.Scaled(4), top, vstats.COLORS.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    draw.SimpleText(vstats.FormatValue(minValue, self.unit), "VStats_Small", left - vstats.Scaled(4), bottom, vstats.COLORS.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    local graphHeight = bottom - top
    local function yFor(value)
        return bottom - ((value - minValue) / (maxValue - minValue)) * graphHeight
    end

    surface.SetDrawColor(vstats.COLORS.accent)
    if self.mode == "bar" then
        local count = math.min(#self.rows, 12)
        local gap = vstats.Scaled(4)
        local barWidth = math.max(vstats.Scaled(2), ((right - left) / count) - gap)
        local zeroY = yFor(math.Clamp(0, minValue, maxValue))
        for i = 1, count do
            local row = self.rows[i]
            local x = left + (i - 1) * ((right - left) / count) + gap / 2
            local y = yFor(rowValue(row, self.mode))
            surface.SetDrawColor(vstats.COLORS.accent)
            surface.DrawRect(x, math.min(y, zeroY), barWidth, math.max(1, math.abs(zeroY - y)))
            local label = row.name or row.key or ""
            if #label > 12 then label = string.sub(label, 1, 11) .. "…" end
            draw.SimpleText(label, "VStats_Small", x + barWidth / 2, bottom + vstats.Scaled(4), vstats.COLORS.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    else
        local previousX, previousY
        local divisor = math.max(1, #self.rows - 1)
        for i, row in ipairs(self.rows) do
            local x = left + ((i - 1) / divisor) * (right - left)
            local y = yFor(rowValue(row, self.mode))
            if previousX then
                surface.SetDrawColor(vstats.COLORS.accent)
                surface.DrawLine(previousX, previousY, x, y)
            end
            surface.SetDrawColor(vstats.COLORS.accent)
            surface.DrawRect(x - vstats.Scaled(2), y - vstats.Scaled(2), vstats.Scaled(4), vstats.Scaled(4))
            previousX, previousY = x, y
        end
        local first = self.rows[1]
        local last = self.rows[#self.rows]
        draw.SimpleText(os.date("%d %b", first.bucket or 0), "VStats_Small", left, bottom + vstats.Scaled(4), vstats.COLORS.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(os.date("%d %b", last.bucket or 0), "VStats_Small", right, bottom + vstats.Scaled(4), vstats.COLORS.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
end

vgui.Register("VStatsGraph", PANEL, "Panel")

print("[vStats] Graph (CL) Loaded.")
