local PANEL = {}

function PANEL:Init()
    self:SetTitle("Server Balance Statistics")
    self:SetSize(math.min(ScrW() - 80, 1100), math.min(ScrH() - 80, 760))
    self:Center()
    self:MakePopup()
    self:ShowCloseButton(true)

    self.categoryID = vstats.CATEGORIES[1].id
    self.rangeID = vstats.RANGES[1].id
    self.selectedKey = ""
    self.sourceID = ""
    self.sourceOptionsKey = nil
    self.updatingSourceChoices = false

    local filters = self:Add("DPanel")
    filters:Dock(TOP)
    filters:SetTall(32)

    self.category = filters:Add("DComboBox")
    self.category:Dock(LEFT)
    self.category:SetWide(250)
    self.category:DockMargin(0, 0, 8, 4)
    for _, item in ipairs(vstats.CATEGORIES) do self.category:AddChoice(item.label, item.id) end
    self.category:ChooseOptionID(1)
    self.category.OnSelect = function(_, _, _, id)
        self.categoryID = id
        self.selectedKey = ""
        local category = vstats.FindConfig(vstats.CATEGORIES, id)
        if not category or category.unit ~= "money" then
            self.sourceID = ""
            if IsValid(self.source) then
                self.updatingSourceChoices = true
                self.source:ChooseOptionID(1)
                self.updatingSourceChoices = false
            end
        end
        if IsValid(self.source) then self.source:SetVisible(category and category.unit == "money") end
        self:RefreshReport()
    end

    self.range = filters:Add("DComboBox")
    self.range:Dock(LEFT)
    self.range:SetWide(180)
    self.range:DockMargin(0, 0, 8, 4)
    for _, item in ipairs(vstats.RANGES) do self.range:AddChoice(item.label, item.id) end
    self.range:ChooseOptionID(1)
    self.range.OnSelect = function(_, _, _, id)
        self.rangeID = id
        self:RefreshReport()
    end

    self.source = filters:Add("DComboBox")
    self.source:Dock(LEFT)
    self.source:SetWide(240)
    self.source:DockMargin(0, 0, 8, 4)
    self.source:AddChoice("All money sources", "")
    self.source:ChooseOptionID(1)
    self.source:SetVisible(false)
    self.source.OnSelect = function(_, _, _, id)
        if self.updatingSourceChoices then return end
        self.sourceID = id or ""
        self.selectedKey = ""
        self:RefreshReport()
    end

    self.status = filters:Add("DLabel")
    self.status:Dock(FILL)
    self.status:SetText("Loading…")

    self.list = self:Add("DListView")
    self.list:Dock(LEFT)
    self.list:SetWide(math.min(440, self:GetWide() * 0.42))
    self.list:DockMargin(0, 0, 8, 0)
    self.list:SetMultiSelect(false)
    self.list:AddColumn("Name")
    self.list:AddColumn("Total")
    self.list.OnRowSelected = function(_, _, line)
        local key = line.vstatsKey or ""
        if key ~= "" and key == self.selectedKey then
            -- Clicking the already-selected row toggles back to the bar chart.
            self.selectedKey = ""
            self.list:ClearSelection()
        else
            self.selectedKey = key
        end
        self:RefreshReport()
    end

    self.graph = self:Add("VStatsGraph")
    self.graph:Dock(FILL)

    timer.Simple(0, function()
        if IsValid(self) then self:RefreshReport() end
    end)
end

function PANEL:RefreshReport()
    self.status:SetText("Loading…")
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
            self.updatingSourceChoices = true
            self.source:Clear()

            local selectedOption = 1
            self.source:AddChoice("All money sources", "")
            for index, source in ipairs(report.sources or {}) do
                local label = string.Replace(source, ":", ": ")
                self.source:AddChoice(label, source)
                if self.sourceID == source then selectedOption = index + 1 end
            end
            self.source:ChooseOptionID(selectedOption)
            self.updatingSourceChoices = false
        end
    end

    self.list:Clear()
    for _, row in ipairs(report.totals or {}) do
        local line = self.list:AddLine(row.name or row.key or "Unknown", vstats.FormatValue(row.total, category.unit))
        line.vstatsKey = row.key
    end

    self.status:SetText(string.format("%d results", #(report.totals or {})))
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

vgui.Register("VStatsMainPanel", PANEL, "DFrame")

function vstats.OpenMainPanel()
    if IsValid(vstats.MainPanel) then
        vstats.MainPanel:Remove()
    end
    vstats.MainPanel = vgui.Create("VStatsMainPanel")
end

print("[vStats] Panel (CL) Loaded.")
