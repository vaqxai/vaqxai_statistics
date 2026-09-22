local TABLES = {
    "CREATE TABLE IF NOT EXISTS vstats_job_playtime (job TEXT, bucket INTEGER, seconds INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_job_income (job TEXT, bucket INTEGER, amount INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_job_spend (job TEXT, bucket INTEGER, amount INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_job_population (job TEXT, bucket INTEGER, count INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_job_income_source (job TEXT, source TEXT, bucket INTEGER, amount INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_job_spend_source (job TEXT, source TEXT, bucket INTEGER, amount INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_xp_earned (job TEXT, category TEXT, source TEXT, bucket INTEGER, amount REAL)",
    "CREATE TABLE IF NOT EXISTS vstats_weapon_kills (weapon TEXT, bucket INTEGER, kills INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_weapon_damage (weapon TEXT, bucket INTEGER, damage REAL)",
    "CREATE TABLE IF NOT EXISTS vstats_weapon_playtime (weapon TEXT, bucket INTEGER, seconds INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_vehicle_activity (vehicle TEXT, bucket INTEGER, bought INTEGER, sold INTEGER, gotten INTEGER, retrieved INTEGER)",
    "CREATE TABLE IF NOT EXISTS vstats_ticket_reasons (reason TEXT, bucket INTEGER, issued INTEGER, player_tickets INTEGER, vehicle_tickets INTEGER)",

    "CREATE INDEX IF NOT EXISTS idx_vstats_job_playtime ON vstats_job_playtime(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_income ON vstats_job_income(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_spend ON vstats_job_spend(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_population ON vstats_job_population(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_income_source ON vstats_job_income_source(source, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_income_source_job ON vstats_job_income_source(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_spend_source ON vstats_job_spend_source(source, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_job_spend_source_job ON vstats_job_spend_source(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_xp_category ON vstats_xp_earned(category, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_xp_job ON vstats_xp_earned(job, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_xp_source ON vstats_xp_earned(source, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_weapon_kills ON vstats_weapon_kills(weapon, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_weapon_damage ON vstats_weapon_damage(weapon, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_weapon_playtime ON vstats_weapon_playtime(weapon, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_vehicle_activity ON vstats_vehicle_activity(vehicle, bucket)",
    "CREATE INDEX IF NOT EXISTS idx_vstats_ticket_reasons ON vstats_ticket_reasons(reason, bucket)",
}

local function ensureColumn(tableName, columnName, definition)
    local columns = sql.Query("PRAGMA table_info(" .. tableName .. ")") or {}
    for _, column in ipairs(columns) do
        if column.name == columnName then return end
    end

    local result = sql.Query(string.format(
        "ALTER TABLE %s ADD COLUMN %s %s",
        tableName, columnName, definition
    ))
    if result == false then
        print("[vStats] SQL migration error: " .. sql.LastError())
    end
end

function vstats.InitDB()
    for _, query in ipairs(TABLES) do
        local result = sql.Query(query)
        if result == false then
            print("[vStats] SQL Init error: " .. sql.LastError() .. " (" .. query .. ")")
        end
    end

    ensureColumn("vstats_vehicle_activity", "retrieved", "INTEGER DEFAULT 0")
end

hook.Add("PostGamemodeLoaded", "vstats_InitDB", function()
    vstats.InitDB()
end)

-- Autorun reloads can happen after PostGamemodeLoaded has already fired.
-- Running the idempotent schema setup here keeps testing/reloads functional.
vstats.InitDB()

print("[vStats] SQL Init Loaded.")
