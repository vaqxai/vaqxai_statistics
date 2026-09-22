-- Scrollable Name/Total list drawn entirely with surface/draw calls inside a
-- single Paint (no child rows, no Derma skin), so it scales cleanly on high
-- resolution displays and doesn't rely on DListView's bitmap chrome.
local PANEL = {}

function PANEL:Init()
    self.rows = {}
    self.unit = "count"
    self.selectedKey = nil
    self.scroll = 0
    self.rowHeight = vstats.Scaled(28)
    self:SetMouseInputEnabled(true)
end

function PANEL:SetRows(rows, unit)
    self.rows = rows or {}
    self.unit = unit or "count"
    self.scroll = math.Clamp(self.scroll, 0, self:MaxScroll())
end

function PANEL:MaxScroll()
    return math.max(0, #self.rows * self.rowHeight - self:GetTall())
end

function PANEL:OnMouseWheeled(delta)
    self.scroll = math.Clamp(self.scroll - delta * self.rowHeight * 2, 0, self:MaxScroll())
end

function PANEL:RowAt(localY)
    local index = math.floor((localY + self.scroll) / self.rowHeight) + 1
    return self.rows[index]
end

function PANEL:OnMousePressed()
    local _, my = self:CursorPos()
    local row = self:RowAt(my)
    if not row then return end

    if self.selectedKey == row.key then
        self.selectedKey = nil
    else
        self.selectedKey = row.key
    end
    if self.OnRowSelected then self:OnRowSelected(self.selectedKey) end
end

function PANEL:Paint(w, h)
    surface.SetDrawColor(vstats.COLORS.panelBg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(vstats.COLORS.panelBorder)
    surface.DrawOutlinedRect(0, 0, w, h)

    if #self.rows == 0 then
        draw.SimpleText("No data for this selection", "VStats_Body", w / 2, h / 2, vstats.COLORS.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local firstIndex = math.max(1, math.floor(self.scroll / self.rowHeight) + 1)
    local lastIndex = math.min(#self.rows, math.ceil((self.scroll + h) / self.rowHeight) + 1)
    local pad = vstats.Scaled(10)

    for i = firstIndex, lastIndex do
        local row = self.rows[i]
        local y = (i - 1) * self.rowHeight - self.scroll

        if row.key == self.selectedKey then
            surface.SetDrawColor(vstats.COLORS.rowSelected)
            surface.DrawRect(0, y, w, self.rowHeight)
        end

        draw.SimpleText(row.name or row.key or "Unknown", "VStats_Body", pad, y + self.rowHeight / 2, vstats.COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(vstats.FormatValue(row.total, self.unit), "VStats_Body", w - pad, y + self.rowHeight / 2, vstats.COLORS.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local maxScroll = self:MaxScroll()
    if maxScroll > 0 then
        local contentHeight = #self.rows * self.rowHeight
        local barHeight = math.max(vstats.Scaled(20), h * h / contentHeight)
        local barY = (h - barHeight) * (self.scroll / maxScroll)
        surface.SetDrawColor(vstats.COLORS.accent)
        surface.DrawRect(w - vstats.Scaled(4), barY, vstats.Scaled(4), barHeight)
    end
end

vgui.Register("VStatsList", PANEL, "Panel")

print("[vStats] List (CL) Loaded.")
