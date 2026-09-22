vstats.FLUSH_INTERVAL = 900 -- seconds between bucket flushes (15 min)
vstats.WEAPON_SCAN_INTERVAL = 60 -- seconds between weapon-inventory scans
vstats.PERMISSION = "vstats_view"

-- These utility SWEPs are intentionally excluded from weapon balance data.
-- Add server-specific non-combat tools here if they appear in reports.
vstats.WEAPON_EXCLUSIONS = {
    gmod_camera = true,
    gmod_tool = true,
    weapon_physgun = true,
    weapon_physcannon = true,
    weapon_keypadchecker = true,
    arrest_stick = true,
    unarrest_stick = true,
    lockpick = true,
    door_ram = true,
    keys = true,
    pocket = true,
    weaponchecker = true,
    dradio = true,
    wykrywacz_metalu = true,
    weapon_rpt_finebook = true,
    weapon_rpt_handcuff = true,
    climb_swep2 = true,
    zld_constructor = true,
    beekeeping_smoker_swep = true,
    beekeeping_vacuum_swep = true,
    zgw_shovel = true,
    zgw_sieve = true,
    zrms_builder = true,
    ztm_trashcollector = true,
    zgo2_multitool = true,
    zgo2_backpack = true,
}

vstats.WEAPON_EXCLUDED_PREFIXES = {
    "gmod_",
    "weapon_admin_",
}

-- Money sources that should never be recorded as job income/spend. The
-- character creator grants starting money on every character load, which
-- would otherwise show up as astronomical, meaningless "earnings". Matched
-- by prefix since the addon's folder name embeds its version number.
vstats.MONEY_SOURCE_EXCLUDED_PREFIXES = {
    "script:advanced_character_creator",
}

function vstats.IsExcludedMoneySource(source)
    if not isstring(source) then return false end
    for _, prefix in ipairs(vstats.MONEY_SOURCE_EXCLUDED_PREFIXES) do
        if string.StartWith(source, prefix) then return true end
    end
    return false
end

vstats.RANGES = {
    { id = "24h", label = "Last 24 hours", seconds = 86400 },
    { id = "7d", label = "Last 7 days", seconds = 604800 },
    { id = "30d", label = "Last 30 days", seconds = 2592000 },
    { id = "all", label = "All time", seconds = nil },
}

vstats.CATEGORIES = {
    { id = "job_playtime", label = "Job Playtime", unit = "seconds" },
    { id = "job_income", label = "Job Income", unit = "money" },
    { id = "job_spend", label = "Job Spend", unit = "money" },
    { id = "job_netprofit", label = "Job Net Profit", unit = "money" },
    { id = "money_income_source", label = "Income by Source", unit = "money" },
    { id = "money_spend_source", label = "Spend by Source", unit = "money" },
    { id = "money_net_source", label = "Net Money by Source", unit = "money" },
    { id = "job_population", label = "Job Population (avg)", unit = "count" },
    { id = "job_income_per_hour", label = "Job $ / Hour", unit = "money" },
    { id = "xp_category", label = "XP by Category", unit = "xp" },
    { id = "xp_job", label = "XP by Job", unit = "xp" },
    { id = "xp_source", label = "XP by Source", unit = "xp" },
    { id = "job_xp_per_hour", label = "Job XP / Hour", unit = "xp_rate" },
    { id = "weapon_kills", label = "Weapon Kills", unit = "count" },
    { id = "weapon_damage", label = "Weapon PvP Damage", unit = "count" },
    { id = "weapon_playtime", label = "Weapon Playtime", unit = "seconds" },
    { id = "weapon_kills_per_hour", label = "Weapon Kills / Hour", unit = "rate" },
    { id = "weapon_damage_per_hour", label = "Weapon Damage / Hour", unit = "rate" },
    { id = "vehicle_bought", label = "Vehicles Bought", unit = "count" },
    { id = "vehicle_sold", label = "Vehicles Sold", unit = "count" },
    { id = "vehicle_gotten", label = "Vehicles Gotten (Free/Admin)", unit = "count" },
    { id = "vehicle_retrieved", label = "Vehicles Retrieved", unit = "count" },
    { id = "ticket_reasons", label = "Police Tickets by Reason", unit = "count" },
    { id = "ticket_player_reasons", label = "Player Tickets by Reason", unit = "count" },
    { id = "ticket_vehicle_reasons", label = "Vehicle Tickets by Reason", unit = "count" },
}

local function registerSAMPermission()
    if not sam or not sam.permissions or not sam.permissions.add then return false end

    sam.permissions.add(vstats.PERMISSION, "Vaqxai Statistics", "superadmin")
    return true
end

if not registerSAMPermission() then
    hook.Add("Initialize", "vstats_RegisterSAMPermission", function()
        registerSAMPermission()
        hook.Remove("Initialize", "vstats_RegisterSAMPermission")
    end)
end

function vstats.HasAccess(ply)
    return IsValid(ply)
        and isfunction(ply.HasPermission)
        and ply:HasPermission(vstats.PERMISSION)
end

print("[vStats] Config Loaded.")
