-- Plain surface/draw based theme, deliberately not using any Derma skin so
-- sizes and fonts scale correctly on high resolution (4K+) displays, where
-- Derma's bitmap-based skin chrome and fixed font sizes do not.
vstats.UIScale = math.Clamp(ScrH() / 1080, 0.85, 3)

function vstats.Scaled(n)
    return math.floor(n * vstats.UIScale)
end

surface.CreateFont("VStats_Title", { font = "Tahoma", size = vstats.Scaled(20), weight = 700, antialias = true })
surface.CreateFont("VStats_Header", { font = "Tahoma", size = vstats.Scaled(16), weight = 600, antialias = true })
surface.CreateFont("VStats_Body", { font = "Tahoma", size = vstats.Scaled(15), weight = 400, antialias = true })
surface.CreateFont("VStats_Small", { font = "Tahoma", size = vstats.Scaled(13), weight = 400, antialias = true })

-- Flat white material so surface.DrawPoly renders a solid tinted shape
-- instead of whatever texture happens to still be bound from elsewhere.
vstats.WHITE_MATERIAL = Material("vgui/white")

vstats.COLORS = {
    windowBg = Color(32, 34, 38),
    titlebar = Color(24, 26, 30),
    titleText = Color(235, 235, 235),
    panelBg = Color(44, 47, 52),
    panelBorder = Color(62, 65, 70),
    text = Color(225, 225, 225),
    textDim = Color(160, 160, 165),
    accent = Color(88, 150, 220),
    rowSelected = Color(70, 96, 130),
}

print("[vStats] Theme (CL) Loaded.")
