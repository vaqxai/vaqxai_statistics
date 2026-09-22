-- In-memory accumulators, flushed to the DB every vstats.FLUSH_INTERVAL seconds.
vstats._acc = {
    job_playtime = {},
    job_income = {},
    job_spend = {},
    job_income_source = {},
    job_spend_source = {},
    xp_earned = {},
    weapon_kills = {},
    weapon_damage = {},
    weapon_playtime = {},
    vehicle_activity = {},
    ticket_reasons = {},
}

function vstats.GetBucket(t)
    t = t or os.time()
    return math.floor(t / vstats.FLUSH_INTERVAL) * vstats.FLUSH_INTERVAL
end

function vstats.GetJobName(teamID)
    local job = RPExtraTeams and RPExtraTeams[teamID]
    if job and job.name then return job.name end
    return team.GetName(teamID) or ("team_" .. tostring(teamID))
end

function vstats.PrettyWeaponName(class)
    local stored = weapons.GetStored(class)
    if stored and stored.PrintName then return stored.PrintName end

    local name = string.gsub(class, "^m9k_", "")
    name = string.gsub(name, "_", " ")
    return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

function vstats.PrettyVehicleName(vehicleID)
    if RCD and RCD.GetVehicleInfo then
        local vehicle = RCD.GetVehicleInfo(tonumber(vehicleID))
        if istable(vehicle) then
            return vehicle.name or vehicle.class or ("Vehicle #" .. tostring(vehicleID))
        end
    end
    return "Vehicle #" .. tostring(vehicleID)
end

function vstats.IsTrackedWeapon(class)
    if not isstring(class) or class == "" then return false end

    class = string.lower(class)
    if vstats.WEAPON_EXCLUSIONS[class] then return false end
    for _, prefix in ipairs(vstats.WEAPON_EXCLUDED_PREFIXES) do
        if string.StartWith(class, prefix) then return false end
    end
    return true
end

vstats._moneySourceDebug = vstats._moneySourceDebug or {}
vstats._moneySourceDebugCount = vstats._moneySourceDebugCount or 0

local function classifyMoneyPath(path)
    if string.find(path, "/sam/", 1, true) or string.StartWith(path, "sam/")
        or string.find(path, "sam-160", 1, true) then return "admin" end

    if string.find(path, "darkrp", 1, true) then
        if string.find(path, "salary", 1, true) or string.find(path, "payday", 1, true) then
            return "salary"
        end
        return "darkrp"
    end

    local addon = string.match(path, "addons/([^/]+)/lua/")
    if addon then
        if string.find(addon, "printer", 1, true) or string.find(path, "printer", 1, true) then
            return "printer:" .. addon
        end
        return "script:" .. addon
    end

    -- GMod commonly exposes only the mounted LUA-relative path. Use its
    -- namespace (or entity/SWEP class) as the stable low-cardinality source.
    local mounted = string.match(path, "lua/(.+)") or path
    mounted = string.gsub(mounted, "^/+", "")
    local root, second = string.match(mounted, "^([^/]+)/?([^/]*)")
    if not root or root == "" or root == "[c]" then return "other" end

    local label = root
    if (root == "entities" or root == "weapons") and second ~= "" then
        label = second
    elseif root == "autorun" and second ~= "" then
        label = string.StripExtension(second)
    elseif root == "includes" then
        return "other"
    end

    if string.find(path, "printer", 1, true) or string.find(label, "printer", 1, true) then
        return "printer:" .. label
    end
    return "script:" .. label
end

local function rememberMoneySource(path, source)
    if vstats._moneySourceDebug[path] then return end
    if vstats._moneySourceDebugCount >= 100 then return end

    vstats._moneySourceDebug[path] = source
    vstats._moneySourceDebugCount = vstats._moneySourceDebugCount + 1
end

local function isMoneyBridgePath(path)
    return string.find(path, "zclib/util/sh_money.lua", 1, true) ~= nil
        or string.find(path, "zclib/util/sv_money.lua", 1, true) ~= nil
end

-- Produces a bounded source tag from the Lua caller. It deliberately stores
-- only the classification in SQLite, never the file/function/stack trace.
function vstats.GetMoneySource(stackLevel)
    local path = ""
    local firstLevel = stackLevel or 3

    for level = firstLevel, firstLevel + 6 do
        local info = debug.getinfo(level, "S")
        if not info then break end

        local candidate = info.source or info.short_src or ""
        candidate = string.lower(string.Replace(string.gsub(candidate, "^@", ""), "\\", "/"))
        if candidate ~= "" and not string.find(candidate, "vstats/", 1, true)
            and candidate ~= "=[c]" and not isMoneyBridgePath(candidate) then
            path = candidate
            break
        end
    end

    local source = classifyMoneyPath(path)
    rememberMoneySource(path ~= "" and path or "<unknown>", source)
    return source
end

function vstats.PrintMoneySourceDebug()
    print("[vStats] Observed money caller classifications:")
    print("[vStats] addMoney wrapper installed: " .. tostring(vstats._addMoneyWrapped == true))
    if vstats._moneySourceDebugCount == 0 then
        print("[vStats] No addMoney calls have been observed since this Lua state started.")
        return
    end
    for path, source in SortedPairs(vstats._moneySourceDebug) do
        print(string.format("[vStats] %s -> %s", path, source))
    end
end

function vstats.FindConfig(list, id)
    for _, item in ipairs(list) do
        if item.id == id then return item end
    end
end

local function addTo(acc, key, amount)
    acc[key] = (acc[key] or 0) + amount
end

function vstats.RecordJobPlaytime(job, seconds)
    if not job or seconds <= 0 then return end
    addTo(vstats._acc.job_playtime, job, seconds)
end

-- Completed job segments are appended immediately so a team change is visible
-- in reports without waiting for the periodic aggregate flush.
function vstats.WriteJobPlaytime(job, seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if not job or seconds <= 0 then return end

    local result = sql.Query(string.format(
        "INSERT INTO vstats_job_playtime (job, bucket, seconds) VALUES (%s, %d, %d)",
        sql.SQLStr(job), vstats.GetBucket(), seconds
    ))
    if result == false then
        ErrorNoHalt("[vStats] SQL job playtime error: " .. sql.LastError() .. "\n")
    end
end

local function addNested(acc, first, second, amount)
    acc[first] = acc[first] or {}
    addTo(acc[first], second, amount)
end

function vstats.RecordJobIncome(job, amount, source)
    if not job or amount <= 0 then return end
    addTo(vstats._acc.job_income, job, amount)
    addNested(vstats._acc.job_income_source, job, source or "other", amount)
end

function vstats.RecordJobSpend(job, amount, source)
    if not job or amount <= 0 then return end
    addTo(vstats._acc.job_spend, job, amount)
    addNested(vstats._acc.job_spend_source, job, source or "other", amount)
end

function vstats.RecordXP(job, category, source, amount)
    if not job or not category or not isnumber(amount) or amount <= 0 then return end

    local key = job .. "\31" .. category
    addNested(vstats._acc.xp_earned, key, source or "script", amount)
end

function vstats.RecordWeaponKill(class, n)
    addTo(vstats._acc.weapon_kills, class, n or 1)
end

function vstats.RecordWeaponDamage(class, amount)
    if not class or not isnumber(amount) or amount <= 0 then return end
    addTo(vstats._acc.weapon_damage, class, amount)
end

function vstats.RecordWeaponPlaytime(class, seconds)
    if seconds <= 0 then return end
    addTo(vstats._acc.weapon_playtime, class, seconds)
end

function vstats.RecordVehicleActivity(vehicleID, activity)
    vehicleID = tostring(vehicleID or "")
    if vehicleID == "" or (activity ~= "bought" and activity ~= "sold" and activity ~= "gotten" and activity ~= "retrieved") then return end

    vstats._acc.vehicle_activity[vehicleID] = vstats._acc.vehicle_activity[vehicleID] or {
        bought = 0,
        sold = 0,
        gotten = 0,
        retrieved = 0,
    }
    vstats._acc.vehicle_activity[vehicleID][activity] = vstats._acc.vehicle_activity[vehicleID][activity] + 1
end


function vstats.RecordTicketReasons(reasons, targetType)
    if not istable(reasons) then return end
    if targetType ~= "player" and targetType ~= "vehicle" then return end

    local validReasons = {}
    for _, configured in pairs((Realistic_Police and Realistic_Police.FiningPolice) or {}) do
        if isstring(configured.Name) then validReasons[configured.Name] = true end
    end

    local seen = {}
    for _, reason in ipairs(reasons) do
        reason = string.Trim(tostring(reason or ""))
        if validReasons[reason] and not seen[reason] then
            seen[reason] = true
            vstats._acc.ticket_reasons[reason] = vstats._acc.ticket_reasons[reason] or {
                issued = 0,
                player_tickets = 0,
                vehicle_tickets = 0,
            }
            local counts = vstats._acc.ticket_reasons[reason]
            counts.issued = counts.issued + 1
            counts[targetType .. "_tickets"] = counts[targetType .. "_tickets"] + 1
        end
    end
end

local function flushTable(tableName, keyColumn, valueColumn, acc, bucket)
    for key, value in pairs(acc) do
        if value and value ~= 0 then
            local result = sql.Query(string.format(
                "INSERT INTO %s (%s, bucket, %s) VALUES (%s, %d, %d)",
                tableName, keyColumn, valueColumn,
                sql.SQLStr(key), bucket, math.floor(value)
            ))
            if result == false then
                ErrorNoHalt("[vStats] SQL flush error: " .. sql.LastError() .. "\n")
            end
        end
    end
end

local function samplePopulation(bucket)
    local counts = {}
    for _, ply in ipairs(player.GetAll()) do
        local job = vstats.GetJobName(ply:Team())
        counts[job] = (counts[job] or 0) + 1
    end

    for job, count in pairs(counts) do
        sql.Query(string.format(
            "INSERT INTO vstats_job_population (job, bucket, count) VALUES (%s, %d, %d)",
            sql.SQLStr(job), bucket, count
        ))
    end
end

local function flushMoneySources(tableName, acc, bucket)
    for job, sources in pairs(acc) do
        for source, amount in pairs(sources) do
            if amount ~= 0 then
                sql.Query(string.format(
                    "INSERT INTO %s (job, source, bucket, amount) VALUES (%s, %s, %d, %d)",
                    tableName, sql.SQLStr(job), sql.SQLStr(source), bucket, math.floor(amount)
                ))
            end
        end
    end
end

local function flushXP(acc, bucket)
    for key, sources in pairs(acc) do
        local separator = string.find(key, "\31", 1, true)
        local job = string.sub(key, 1, separator - 1)
        local category = string.sub(key, separator + 1)

        for source, amount in pairs(sources) do
            if amount ~= 0 then
                sql.Query(string.format(
                    "INSERT INTO vstats_xp_earned (job, category, source, bucket, amount) VALUES (%s, %s, %s, %d, %.4f)",
                    sql.SQLStr(job), sql.SQLStr(category), sql.SQLStr(source), bucket, amount
                ))
            end
        end
    end
end

local function flushVehicleActivity(acc, bucket)
    for vehicleID, counts in pairs(acc) do
        sql.Query(string.format(
            "INSERT INTO vstats_vehicle_activity (vehicle, bucket, bought, sold, gotten, retrieved) VALUES (%s, %d, %d, %d, %d, %d)",
            sql.SQLStr(vehicleID), bucket, counts.bought, counts.sold, counts.gotten, counts.retrieved
        ))
    end
end

local function flushTicketReasons(acc, bucket)
    for reason, counts in pairs(acc) do
        sql.Query(string.format(
            "INSERT INTO vstats_ticket_reasons (reason, bucket, issued, player_tickets, vehicle_tickets) VALUES (%s, %d, %d, %d, %d)",
            sql.SQLStr(reason), bucket, counts.issued, counts.player_tickets, counts.vehicle_tickets
        ))
    end
end

-- Adds each online player's elapsed time on their current job to the playtime
-- accumulator and resets their checkpoint. Called before every flush (and on
-- disconnect/team-change) so long, uninterrupted sessions still get counted.
function vstats.CheckpointPlaytime()
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if ply.vstats_jobSince then
            local job = vstats.GetJobName(ply.vstats_job)
            vstats.RecordJobPlaytime(job, now - ply.vstats_jobSince)
            ply.vstats_jobSince = now
        end
    end
end

function vstats.FlushAccumulators()
    vstats.CheckpointPlaytime()

    local bucket = vstats.GetBucket()

    flushTable("vstats_job_playtime", "job", "seconds", vstats._acc.job_playtime, bucket)
    flushTable("vstats_job_income", "job", "amount", vstats._acc.job_income, bucket)
    flushTable("vstats_job_spend", "job", "amount", vstats._acc.job_spend, bucket)
    flushMoneySources("vstats_job_income_source", vstats._acc.job_income_source, bucket)
    flushMoneySources("vstats_job_spend_source", vstats._acc.job_spend_source, bucket)
    flushXP(vstats._acc.xp_earned, bucket)
    flushTable("vstats_weapon_kills", "weapon", "kills", vstats._acc.weapon_kills, bucket)
    flushTable("vstats_weapon_damage", "weapon", "damage", vstats._acc.weapon_damage, bucket)
    flushTable("vstats_weapon_playtime", "weapon", "seconds", vstats._acc.weapon_playtime, bucket)
    flushVehicleActivity(vstats._acc.vehicle_activity, bucket)
    flushTicketReasons(vstats._acc.ticket_reasons, bucket)
    samplePopulation(bucket)

    vstats._acc.job_playtime = {}
    vstats._acc.job_income = {}
    vstats._acc.job_spend = {}
    vstats._acc.job_income_source = {}
    vstats._acc.job_spend_source = {}
    vstats._acc.xp_earned = {}
    vstats._acc.weapon_kills = {}
    vstats._acc.weapon_damage = {}
    vstats._acc.weapon_playtime = {}
    vstats._acc.vehicle_activity = {}
    vstats._acc.ticket_reasons = {}
end

-- Returns {{key=..., total=...}, ...} sorted descending, for rows with bucket >= sinceTimestamp
-- (sinceTimestamp may be nil for "all time").
function vstats.QueryTotals(tableName, keyColumn, valueColumn, sinceTimestamp)
    local where = ""
    if sinceTimestamp then
        where = " WHERE bucket >= " .. math.floor(sinceTimestamp)
    end

    local query = string.format(
        "SELECT %s AS key, SUM(%s) AS total FROM %s%s GROUP BY %s ORDER BY total DESC",
        keyColumn, valueColumn, tableName, where, keyColumn
    )

    local result = sql.Query(query)
    if not result then return {} end

    local rows = {}
    for _, row in ipairs(result) do
        rows[#rows + 1] = { key = row.key, total = tonumber(row.total) or 0 }
    end
    return rows
end

-- Picks a display-bucket size (seconds) so a time-series graph doesn't get thousands of points.
function vstats.PickGroupSeconds(rangeSeconds)
    if not rangeSeconds or rangeSeconds > 2592000 then return 604800 end -- weekly, for "all time" / >30d
    if rangeSeconds > 86400 then return 86400 end -- daily, for up to 30d
    return 3600 -- hourly, for up to 1d
end

-- Returns {{bucket=groupedBucket, value=...}, ...} ordered ascending by bucket, for a single key.
function vstats.QuerySeries(tableName, keyColumn, valueColumn, keyValue, sinceTimestamp, groupSeconds)
    local where = "WHERE " .. keyColumn .. " = " .. sql.SQLStr(keyValue)
    if sinceTimestamp then
        where = where .. " AND bucket >= " .. math.floor(sinceTimestamp)
    end

    local query = string.format(
        "SELECT (bucket - (bucket %% %d)) AS g, SUM(%s) AS total FROM %s %s GROUP BY g ORDER BY g ASC",
        groupSeconds, valueColumn, tableName, where
    )

    local result = sql.Query(query)
    if not result then return {} end

    local rows = {}
    for _, row in ipairs(result) do
        rows[#rows + 1] = { bucket = tonumber(row.g) or 0, value = tonumber(row.total) or 0 }
    end
    return rows
end


local REPORTS = {
    job_playtime = { tableName = "vstats_job_playtime", key = "job", value = "seconds", aggregate = "SUM" },
    job_income = { tableName = "vstats_job_income", key = "job", value = "amount", aggregate = "SUM" },
    job_spend = { tableName = "vstats_job_spend", key = "job", value = "amount", aggregate = "SUM" },
    money_income_source = { tableName = "vstats_job_income_source", key = "source", value = "amount", aggregate = "SUM" },
    money_spend_source = { tableName = "vstats_job_spend_source", key = "source", value = "amount", aggregate = "SUM" },
    xp_category = { tableName = "vstats_xp_earned", key = "category", value = "amount", aggregate = "SUM" },
    xp_job = { tableName = "vstats_xp_earned", key = "job", value = "amount", aggregate = "SUM" },
    xp_source = { tableName = "vstats_xp_earned", key = "source", value = "amount", aggregate = "SUM" },
    weapon_kills = { tableName = "vstats_weapon_kills", key = "weapon", value = "kills", aggregate = "SUM" },
    weapon_damage = { tableName = "vstats_weapon_damage", key = "weapon", value = "damage", aggregate = "SUM" },
    weapon_playtime = { tableName = "vstats_weapon_playtime", key = "weapon", value = "seconds", aggregate = "SUM" },
    vehicle_bought = { tableName = "vstats_vehicle_activity", key = "vehicle", value = "bought", aggregate = "SUM" },
    vehicle_sold = { tableName = "vstats_vehicle_activity", key = "vehicle", value = "sold", aggregate = "SUM" },
    vehicle_gotten = { tableName = "vstats_vehicle_activity", key = "vehicle", value = "gotten", aggregate = "SUM" },
    vehicle_retrieved = { tableName = "vstats_vehicle_activity", key = "vehicle", value = "retrieved", aggregate = "SUM" },
    ticket_reasons = { tableName = "vstats_ticket_reasons", key = "reason", value = "issued", aggregate = "SUM" },
    ticket_player_reasons = { tableName = "vstats_ticket_reasons", key = "reason", value = "player_tickets", aggregate = "SUM" },
    ticket_vehicle_reasons = { tableName = "vstats_ticket_reasons", key = "reason", value = "vehicle_tickets", aggregate = "SUM" },
}

local function timeWhere(sinceTimestamp, prefix)
    if not sinceTimestamp then return "" end
    return string.format(" AND %sbucket >= %d", prefix or "", math.floor(sinceTimestamp))
end

local function queryRows(query, series)
    local result = sql.Query(query)
    if result == false then
        ErrorNoHalt("[vStats] SQL report error: " .. sql.LastError() .. "\n")
        return {}
    end
    if not result then return {} end

    local rows = {}
    for _, row in ipairs(result) do
        if series then
            rows[#rows + 1] = { bucket = tonumber(row.grouped_bucket) or 0, value = tonumber(row.value) or 0 }
        else
            rows[#rows + 1] = { key = row.key, total = tonumber(row.total) or 0 }
        end
    end
    return rows
end

local function simpleTotals(def, sinceTimestamp, extraWhere)
    local query = string.format(
        "SELECT %s AS key, %s(%s) AS total FROM %s WHERE 1=1%s GROUP BY %s HAVING total != 0 ORDER BY total DESC",
        def.key, def.aggregate, def.value, def.tableName,
        timeWhere(sinceTimestamp) .. (extraWhere or ""), def.key
    )
    return queryRows(query, false)
end

local function simpleSeries(def, selectedKey, sinceTimestamp, groupSeconds, extraWhere)
    local query = string.format(
        "SELECT (bucket - (bucket %% %d)) AS grouped_bucket, %s(%s) AS value FROM %s WHERE %s = %s%s GROUP BY grouped_bucket ORDER BY grouped_bucket ASC",
        groupSeconds, def.aggregate, def.value, def.tableName, def.key, sql.SQLStr(selectedKey),
        timeWhere(sinceTimestamp) .. (extraWhere or "")
    )
    return queryRows(query, true)
end

local function ratioTotals(numeratorTable, numeratorValue, denominatorTable, denominatorValue, keyColumn, sinceTimestamp, multiplier, numeratorWhere)
    local filter = timeWhere(sinceTimestamp)
    local numeratorFilter = filter .. (numeratorWhere or "")
    local query = string.format([[
        SELECT n.key AS key, (n.total * %d * 1.0 / d.total) AS total
        FROM (SELECT %s AS key, SUM(%s) AS total FROM %s WHERE 1=1%s GROUP BY %s) n
        JOIN (SELECT %s AS key, SUM(%s) AS total FROM %s WHERE 1=1%s GROUP BY %s) d ON d.key = n.key
        WHERE d.total > 0 ORDER BY total DESC
    ]], multiplier, keyColumn, numeratorValue, numeratorTable, numeratorFilter, keyColumn,
        keyColumn, denominatorValue, denominatorTable, filter, keyColumn)
    return queryRows(query, false)
end

local function ratioSeries(numeratorTable, numeratorValue, denominatorTable, denominatorValue, keyColumn, selectedKey, sinceTimestamp, groupSeconds, multiplier, numeratorWhere)
    local escaped = sql.SQLStr(selectedKey)
    local filter = timeWhere(sinceTimestamp)
    local numeratorFilter = filter .. (numeratorWhere or "")
    local query = string.format([[
        SELECT n.grouped_bucket AS grouped_bucket, (n.total * %d * 1.0 / d.total) AS value
        FROM (SELECT (bucket - (bucket %% %d)) AS grouped_bucket, SUM(%s) AS total FROM %s WHERE %s = %s%s GROUP BY grouped_bucket) n
        JOIN (SELECT (bucket - (bucket %% %d)) AS grouped_bucket, SUM(%s) AS total FROM %s WHERE %s = %s%s GROUP BY grouped_bucket) d ON d.grouped_bucket = n.grouped_bucket
        WHERE d.total > 0 ORDER BY n.grouped_bucket ASC
    ]], multiplier, groupSeconds, numeratorValue, numeratorTable, keyColumn, escaped, numeratorFilter,
        groupSeconds, denominatorValue, denominatorTable, keyColumn, escaped, filter)
    return queryRows(query, true)
end

local function netProfitTotals(sinceTimestamp, incomeTable, spendTable, keyColumn, extraWhere)
    local filter = timeWhere(sinceTimestamp) .. (extraWhere or "")
    local query = string.format([[
        SELECT key, SUM(total) AS total FROM (
            SELECT %s AS key, SUM(amount) AS total FROM %s WHERE 1=1%s GROUP BY %s
            UNION ALL
            SELECT %s AS key, -SUM(amount) AS total FROM %s WHERE 1=1%s GROUP BY %s
        ) GROUP BY key ORDER BY total DESC
    ]], keyColumn, incomeTable, filter, keyColumn, keyColumn, spendTable, filter, keyColumn)
    return queryRows(query, false)
end

local function netProfitSeries(selectedKey, sinceTimestamp, groupSeconds, incomeTable, spendTable, keyColumn, extraWhere)
    local escaped = sql.SQLStr(selectedKey)
    local filter = timeWhere(sinceTimestamp) .. (extraWhere or "")
    local query = string.format([[
        SELECT grouped_bucket, SUM(value) AS value FROM (
            SELECT (bucket - (bucket %% %d)) AS grouped_bucket, SUM(amount) AS value FROM %s WHERE %s = %s%s GROUP BY grouped_bucket
            UNION ALL
            SELECT (bucket - (bucket %% %d)) AS grouped_bucket, -SUM(amount) AS value FROM %s WHERE %s = %s%s GROUP BY grouped_bucket
        ) GROUP BY grouped_bucket ORDER BY grouped_bucket ASC
    ]], groupSeconds, incomeTable, keyColumn, escaped, filter,
        groupSeconds, spendTable, keyColumn, escaped, filter)
    return queryRows(query, true)
end

local function populationTotals(sinceTimestamp)
    local filter = timeWhere(sinceTimestamp)
    local query = string.format([[
        SELECT population.job AS key, (SUM(population.count) * 1.0 / samples.total) AS total
        FROM (
            SELECT job, bucket, AVG(count) AS count FROM vstats_job_population
            WHERE 1=1%s GROUP BY job, bucket
        ) population
        CROSS JOIN (SELECT COUNT(DISTINCT bucket) AS total FROM vstats_job_population WHERE 1=1%s) samples
        WHERE samples.total > 0
        GROUP BY population.job ORDER BY total DESC
    ]], filter, filter)
    return queryRows(query, false)
end

local function populationSeries(selectedKey, sinceTimestamp, groupSeconds)
    local filter = timeWhere(sinceTimestamp)
    local query = string.format([[
        SELECT samples.grouped_bucket AS grouped_bucket,
            (COALESCE(selected.total, 0) * 1.0 / samples.total) AS value
        FROM (
            SELECT (bucket - (bucket %% %d)) AS grouped_bucket, COUNT(DISTINCT bucket) AS total
            FROM vstats_job_population WHERE 1=1%s GROUP BY grouped_bucket
        ) samples
        LEFT JOIN (
            SELECT (bucket - (bucket %% %d)) AS grouped_bucket, SUM(count) AS total FROM (
                SELECT bucket, AVG(count) AS count FROM vstats_job_population
                WHERE job = %s%s GROUP BY bucket
            ) GROUP BY grouped_bucket
        ) selected ON selected.grouped_bucket = samples.grouped_bucket
        ORDER BY samples.grouped_bucket ASC
    ]], groupSeconds, filter, groupSeconds, sql.SQLStr(selectedKey), filter)
    return queryRows(query, true)
end

local function queryMoneySources()
    local result = sql.Query([[
        SELECT source FROM (
            SELECT DISTINCT source FROM vstats_job_income_source
            UNION
            SELECT DISTINCT source FROM vstats_job_spend_source
        ) ORDER BY source ASC
    ]]) or {}

    local sources = {}
    for _, row in ipairs(result) do
        if isstring(row.source) and row.source ~= "" then sources[#sources + 1] = row.source end
    end
    return sources
end

function vstats.BuildReport(categoryID, rangeID, selectedKey, sourceFilter)
    local category = vstats.FindConfig(vstats.CATEGORIES, categoryID)
    local range = vstats.FindConfig(vstats.RANGES, rangeID)
    if not category or not range then return nil end

    sourceFilter = category.unit == "money" and tostring(sourceFilter or "") or ""
    local sourceWhere = sourceFilter ~= "" and (" AND source = " .. sql.SQLStr(sourceFilter)) or ""

    local sinceTimestamp = range.seconds and (os.time() - range.seconds) or nil
    local groupSeconds = vstats.PickGroupSeconds(range.seconds)
    local totals
    local series = {}

    if REPORTS[categoryID] then
        local reportDefinition = REPORTS[categoryID]
        local reportWhere = ""
        if sourceFilter ~= "" then
            if categoryID == "job_income" then
                reportDefinition = { tableName = "vstats_job_income_source", key = "job", value = "amount", aggregate = "SUM" }
                reportWhere = sourceWhere
            elseif categoryID == "job_spend" then
                reportDefinition = { tableName = "vstats_job_spend_source", key = "job", value = "amount", aggregate = "SUM" }
                reportWhere = sourceWhere
            elseif categoryID == "money_income_source" or categoryID == "money_spend_source" then
                reportWhere = sourceWhere
            end
        end

        totals = simpleTotals(reportDefinition, sinceTimestamp, reportWhere)
        if selectedKey and selectedKey ~= "" then
            series = simpleSeries(reportDefinition, selectedKey, sinceTimestamp, groupSeconds, reportWhere)
        end
    elseif categoryID == "job_population" then
        totals = populationTotals(sinceTimestamp)
        if selectedKey and selectedKey ~= "" then
            series = populationSeries(selectedKey, sinceTimestamp, groupSeconds)
        end
    elseif categoryID == "job_netprofit" then
        local incomeTable = sourceFilter ~= "" and "vstats_job_income_source" or "vstats_job_income"
        local spendTable = sourceFilter ~= "" and "vstats_job_spend_source" or "vstats_job_spend"
        totals = netProfitTotals(sinceTimestamp, incomeTable, spendTable, "job", sourceWhere)
        if selectedKey and selectedKey ~= "" then
            series = netProfitSeries(selectedKey, sinceTimestamp, groupSeconds,
                incomeTable, spendTable, "job", sourceWhere)
        end
    elseif categoryID == "money_net_source" then
        totals = netProfitTotals(sinceTimestamp,
            "vstats_job_income_source", "vstats_job_spend_source", "source", sourceWhere)
        if selectedKey and selectedKey ~= "" then
            series = netProfitSeries(selectedKey, sinceTimestamp, groupSeconds,
                "vstats_job_income_source", "vstats_job_spend_source", "source", sourceWhere)
        end
    elseif categoryID == "job_income_per_hour" then
        local incomeTable = sourceFilter ~= "" and "vstats_job_income_source" or "vstats_job_income"
        totals = ratioTotals(incomeTable, "amount", "vstats_job_playtime", "seconds", "job", sinceTimestamp, 3600, sourceWhere)
        if selectedKey and selectedKey ~= "" then
            series = ratioSeries(incomeTable, "amount", "vstats_job_playtime", "seconds", "job", selectedKey, sinceTimestamp, groupSeconds, 3600, sourceWhere)
        end
    elseif categoryID == "weapon_kills_per_hour" then
        totals = ratioTotals("vstats_weapon_kills", "kills", "vstats_weapon_playtime", "seconds", "weapon", sinceTimestamp, 3600)
        if selectedKey and selectedKey ~= "" then
            series = ratioSeries("vstats_weapon_kills", "kills", "vstats_weapon_playtime", "seconds", "weapon", selectedKey, sinceTimestamp, groupSeconds, 3600)
        end
    elseif categoryID == "weapon_damage_per_hour" then
        totals = ratioTotals("vstats_weapon_damage", "damage", "vstats_weapon_playtime", "seconds", "weapon", sinceTimestamp, 3600)
        if selectedKey and selectedKey ~= "" then
            series = ratioSeries("vstats_weapon_damage", "damage", "vstats_weapon_playtime", "seconds", "weapon", selectedKey, sinceTimestamp, groupSeconds, 3600)
        end
    elseif categoryID == "job_xp_per_hour" then
        totals = ratioTotals("vstats_xp_earned", "amount", "vstats_job_playtime", "seconds", "job", sinceTimestamp, 3600)
        if selectedKey and selectedKey ~= "" then
            series = ratioSeries("vstats_xp_earned", "amount", "vstats_job_playtime", "seconds", "job", selectedKey, sinceTimestamp, groupSeconds, 3600)
        end
    else
        return nil
    end

    for _, row in ipairs(totals) do
        row.name = string.StartWith(categoryID, "weapon_") and vstats.PrettyWeaponName(row.key) or row.key
        if string.find(categoryID, "source", 1, true) then
            row.name = string.Replace(row.name, ":", ": ")
        elseif string.StartWith(categoryID, "vehicle_") then
            row.name = vstats.PrettyVehicleName(row.key)
        end
    end

    return {
        category = categoryID,
        range = rangeID,
        selected = selectedKey or "",
        source = sourceFilter,
        sources = category.unit == "money" and queryMoneySources() or {},
        totals = totals,
        series = series,
    }
end

print("[vStats] Util (SV) Loaded.")
