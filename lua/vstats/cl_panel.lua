-- Main statistics window. Built on plain Panel/EditablePanel with everything
-- self-painted via surface/draw calls (see cl_theme.lua, cl_dropdown.lua,
-- cl_list.lua, cl_graph.lua) instead of Derma's skinned controls, so it scales
-- correctly on high resolution (4K+) displays.
local PANEL = {}

function PANEL:Init()
    self:SetSize(math.Round(ScrW() * 0.7), math.Round(ScrH() * 0.75))
    self:Center()
    self:MakePopup()

    self.categoryID = vstats.CATEGORIES[1].id
    self.rangeID = vstats.RANGES[1].id
    self.selectedKey = ""
    self.sourceID = ""
    self.sourceOptionsKey = nil

    self:BuildTitleBar()
    self:BuildFilters()
    self:BuildBody()

    self.Paint = function(_, w, h)
        surface.SetDrawColor(vstats.COLORS.windowBg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(vstats.COLORS.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    timer.Simple(0, function()
        if IsValid(self) then self:RefreshReport() end
    end)
end

function PANEL:BuildTitleBar()
    local barHeight = vstats.Scaled(34)

    local titlebar = self:Add("EditablePanel")
    titlebar:Dock(TOP)
    titlebar:SetTall(barHeight)
    titlebar:SetDraggable(true)
    titlebar:SetDragParent(self)
    titlebar.Paint = function(_, w, h)
        surface.SetDrawColor(vstats.COLORS.titlebar)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("Server Balance Statistics", "VStats_Title", vstats.Scaled(10), h / 2, vstats.COLORS.titleText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local closeButton = titlebar:Add("EditablePanel")
    closeButton:Dock(RIGHT)
    closeButton:SetWide(barHeight)
    closeButton:SetCursor("hand")
    closeButton.Paint = function(btn, w, h)
        if btn:IsHovered() then
            surface.SetDrawColor(200, 60, 60, 255)
            surface.DrawRect(0, 0, w, h)
        end
        surface.SetDrawColor(vstats.COLORS.titleText)
        local pad = w * 0.32
        surface.DrawLine(pad, pad, w - pad, h - pad)
        surface.DrawLine(w - pad, pad, pad, h - pad)
    end
    closeButton.OnMousePressed = function() self:Remove() end
end

function PANEL:BuildFilters()
    local filters = self:Add("EditablePanel")
    filters:Dock(TOP)
    filters:SetTall(vstats.Scaled(40))
    filters:DockPadding(vstats.Scaled(8), vstats.Scaled(6), vstats.Scaled(8), vstats.Scaled(6))
    filters.Paint = function(_, w, h)
        surface.SetDrawColor(vstats.COLORS.windowBg)
        surface.DrawRect(0, 0, w, h)
    end

    self.category = filters:Add("VStatsDropdown")
    self.category:Dock(LEFT)
    self.category:SetWide(vstats.Scaled(260))
    self.category:DockMargin(0, 0, vstats.Scaled(8), 0)

    local categoryChoices = {}
    for _, item in ipairs(vstats.CATEGORIES) do
        categoryChoices[#categoryChoices + 1] = { id = item.id, label = item.label }
    end
    self.category:SetChoices(categoryChoices, self.categoryID)
    self.category.OnSelect = function(_, id)
        self.categoryID = id
        self.selectedKey = ""

        local category = vstats.FindConfig(vstats.CATEGORIES, id)
        local isMoney = category and category.unit == "money"
        if not isMoney then
            self.sourceID = ""
            self.sourceOptionsKey = nil
            self.source:SetChoices({ { id = "", label = "All money sources" } }, "")
        end
        self.source:SetVisible(isMoney)
        self:RefreshReport()
    end

    self.range = filters:Add("VStatsDropdown")
    self.range:Dock(LEFT)
    self.range:SetWide(vstats.Scaled(180))
    self.range:DockMargin(0, 0, vstats.Scaled(8), 0)

    local rangeChoices = {}
    for _, item in ipairs(vstats.RANGES) do
        rangeChoices[#rangeChoices + 1] = { id = item.id, label = item.label }
    end
    self.range:SetChoices(rangeChoices, self.rangeID)
    self.range.OnSelect = function(_, id)
        self.rangeID = id
        self:RefreshReport()
    end

    self.source = filters:Add("VStatsDropdown")
    self.source:Dock(LEFT)
    self.source:SetWide(vstats.Scaled(240))
    self.source:DockMargin(0, 0, vstats.Scaled(8), 0)
    self.source:SetChoices({ { id = "", label = "All money sources" } }, "")
    self.source:SetVisible(false)
    self.source.OnSelect = function(_, id)
        self.sourceID = id or ""
        self.selectedKey = ""
        self:RefreshReport()
    end

    self.status = filters:Add("EditablePanel")
    self.status:Dock(FILL)
    self.status.text = "Loading…"
    self.status.Paint = function(status, w, h)
        draw.SimpleText(status.text, "VStats_Small", 0, h / 2, vstats.COLORS.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

function PANEL:BuildBody()
    local body = self:Add("EditablePanel")
    body:Dock(FILL)
    body:DockPadding(vstats.Scaled(8), vstats.Scaled(8), vstats.Scaled(8), vstats.Scaled(8))
    body.Paint = function(_, w, h)
        surface.SetDrawColor(vstats.COLORS.windowBg)
        surface.DrawRect(0, 0, w, h)
    end

    self.list = body:Add("VStatsList")
    self.list:Dock(LEFT)
    self.list:SetWide(math.min(vstats.Scaled(440), self:GetWide() * 0.42))
    self.list:DockMargin(0, 0, vstats.Scaled(8), 0)
    self.list.OnRowSelected = function(_, key)
        self.selectedKey = key or ""
        self:RefreshReport()
    end

    self.graph = body:Add("VStatsGraph")
    self.graph:Dock(FILL)
end

function PANEL:RefreshReport()
    self.status.text = "Loading…"
    vstats.RequestReport(self.categoryID, self.rangeID, self.selectedKey, self.sourceID)
end

function PANEL:ApplyReport(report)
    if report.category ~= self.categoryID or report.range ~= self.rangeID
        or (report.selected or "") ~= self.selectedKey or (report.source or "") ~= self.sourceID then return end

    local category = vstats.FindConfig(vstats.CATEGORIES, self.categoryID)
    if not category then return end

    local usesMoneySources = category.unit == "money"
    self.source:SetVisible(usesMoneySources)
    if usesMoneySources then
        local optionsKey = table.concat(report.sources or {}, "\31")
        if self.sourceOptionsKey ~= optionsKey then
            self.sourceOptionsKey = optionsKey
            local choices = { { id = "", label = "All money sources" } }
            for _, source in ipairs(report.sources or {}) do
                choices[#choices + 1] = { id = source, label = string.Replace(source, ":", ": ") }
            end
            self.source:SetChoices(choices, self.sourceID)
        end
    end

    self.list:SetRows(report.totals or {}, category.unit)
    self.list.selectedKey = self.selectedKey ~= "" and self.selectedKey or nil

    self.status.text = string.format("%d results", #(report.totals or {}))

    if self.selectedKey ~= "" then
        local title = self.selectedKey
        for _, row in ipairs(report.totals or {}) do
            if row.key == self.selectedKey then title = row.name or row.key break end
        end
        self.graph:SetSeriesData(report.series or {}, category.unit, title .. " trend")
    else
        self.graph:SetBarData(report.totals or {}, category.unit)
    end
end

vgui.Register("VStatsMainPanel", PANEL, "EditablePanel")

function vstats.OpenMainPanel()
    if IsValid(vstats.MainPanel) then
        vstats.MainPanel:Remove()
    end
    vstats.MainPanel = vgui.Create("VStatsMainPanel")
end

print("[vStats] Panel (CL) Loaded.")
