-- Minimal drop-down control drawn entirely with surface/draw calls (no Derma
-- skin), so it scales cleanly on high resolution displays.
local PANEL = {}

function PANEL:Init()
    self.choices = {}
    self.selectedID = nil
    self.selectedLabel = ""
    self:SetCursor("hand")
    self:SetMouseInputEnabled(true)
end

-- The open menu is a separate top-level popup (not a child of this panel), so
-- it must be cleaned up explicitly, otherwise closing the window while a
-- dropdown is open would leave it behind holding the popup/cursor state.
function PANEL:OnRemove()
    if IsValid(self.menu) then self.menu:Remove() end
end

-- Sets the available choices ({ {id=, label=}, ... }). If selectID is given,
-- selects it without firing OnSelect; otherwise keeps/falls back to the first entry.
function PANEL:SetChoices(choices, selectID)
    self.choices = choices or {}
    if selectID ~= nil then
        self:SelectByID(selectID, true)
    elseif not self.selectedID then
        local first = self.choices[1]
        if first then self:SelectByID(first.id, true) end
    end
end

function PANEL:SelectByID(id, silent)
    self.selectedID = id
    self.selectedLabel = ""
    for _, choice in ipairs(self.choices) do
        if choice.id == id then
            self.selectedLabel = choice.label
            break
        end
    end
    if not silent and self.OnSelect then self:OnSelect(id) end
end

function PANEL:Paint(w, h)
    surface.SetDrawColor(vstats.COLORS.panelBg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(vstats.COLORS.panelBorder)
    surface.DrawOutlinedRect(0, 0, w, h)

    local pad = vstats.Scaled(8)
    draw.SimpleText(self.selectedLabel, "VStats_Body", pad, h / 2, vstats.COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    local cx, cy = w - vstats.Scaled(14), h / 2
    local s = vstats.Scaled(4)
    surface.SetDrawColor(vstats.COLORS.textDim)
    surface.SetMaterial(vstats.WHITE_MATERIAL)
    surface.DrawPoly({
        { x = cx - s, y = cy - s / 2 },
        { x = cx + s, y = cy - s / 2 },
        { x = cx, y = cy + s },
    })
end

function PANEL:OnMousePressed()
    self:OpenMenu()
end

function PANEL:OpenMenu()
    if IsValid(self.menu) then
        self.menu:Remove()
        return
    end

    -- Invisible full-screen catcher: any click outside the option rows closes
    -- the menu. Rows are children so they consume clicks before the catcher does.
    local catcher = vgui.Create("EditablePanel")
    catcher:SetSize(ScrW(), ScrH())
    catcher:SetPos(0, 0)
    catcher:MakePopup()
    catcher:SetKeyboardInputEnabled(false)
    catcher.Paint = function() end
    catcher.OnMousePressed = function() catcher:Remove() end
    self.menu = catcher

    local rowHeight = vstats.Scaled(26)
    local x, y = self:LocalToScreen(0, self:GetTall())
    local width = math.max(self:GetWide(), vstats.Scaled(160))
    local height = #self.choices * rowHeight

    local list = vgui.Create("EditablePanel", catcher)
    list:SetPos(x, y)
    list:SetSize(width, height)
    list.Paint = function(_, w, h)
        surface.SetDrawColor(vstats.COLORS.panelBg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(vstats.COLORS.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    for i, choice in ipairs(self.choices) do
        local row = list:Add("EditablePanel")
        row:SetPos(1, (i - 1) * rowHeight)
        row:SetSize(width - 2, rowHeight)
        row:SetCursor("hand")
        row:SetMouseInputEnabled(true)
        row.Paint = function(rowPanel, w, h)
            if choice.id == self.selectedID or rowPanel:IsHovered() then
                surface.SetDrawColor(vstats.COLORS.rowSelected)
                surface.DrawRect(0, 0, w, h)
            end
            draw.SimpleText(choice.label, "VStats_Body", vstats.Scaled(8), h / 2, vstats.COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        row.OnMousePressed = function()
            self:SelectByID(choice.id)
            catcher:Remove()
        end
    end
end

vgui.Register("VStatsDropdown", PANEL, "EditablePanel")

print("[vStats] Dropdown (CL) Loaded.")
