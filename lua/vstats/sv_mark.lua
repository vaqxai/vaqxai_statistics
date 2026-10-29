-- "Since last balancing" range: starts at the latest vaqxai_balancing change,
-- so before/after data can be compared without deleting anything.
-- It moves automatically on every balance change; it can also be set by hand
-- with `!vstats mark 2026-10-23 20:00` / `!vstats mark now` in chat or
-- `vstats_mark "2026-10-23 20:00"` in console (until the next balance change).
-- Times are in vstats.TIME_OFFSET_HOURS (server clock is UTC).

vstats.MARK_FILE = "vstats/mark.txt"
vstats.BALANCE_LOG_FILE = "vaqxai_balancing/changes.txt"

-- mark.txt holds "<timestamp>" or "<timestamp> manual".
local function loadMark()
    local raw = file.Read(vstats.MARK_FILE, "DATA") or ""
    local ts, manual = string.match(raw, "^%s*(%d+)%s*(%a*)")
    return tonumber(ts), manual == "manual"
end

-- Time of the newest line in vbal's change log ("[YYYY-MM-DD HH:MM:SS] ...",
-- written with os.date, i.e. server-local time).
local function lastBalanceChange()
    local raw = file.Read(vstats.BALANCE_LOG_FILE, "DATA")
    if not raw then return nil end

    local last
    for y, mo, d, h, mi, sec in string.gmatch(raw, "%[(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)%]") do
        last = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) })
    end
    return last
end

if not vstats.MarkTime then
    vstats.MarkTime, vstats.MarkManual = loadMark()
end

local function offsetSeconds()
    return (vstats.TIME_OFFSET_HOURS or 0) * 3600
end

function vstats.FormatLocalTime(timestamp)
    return os.date("!%Y-%m-%d %H:%M", timestamp + offsetSeconds())
end

-- Parses "YYYY-MM-DD HH:MM" (local, per TIME_OFFSET_HOURS) or "now".
function vstats.ParseLocalTime(text)
    text = string.Trim(text or "")
    if string.lower(text) == "now" then return os.time() end

    local y, mo, d, h, mi = string.match(text, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s+(%d%d?):(%d%d)$")
    if not y then return nil end

    -- os.time treats the table as server-local time, which is UTC here;
    -- measure the server's own offset so this stays right on any host.
    local now = os.time()
    local serverOffset = os.difftime(now, os.time(os.date("!*t", now)))
    local utc = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = 0 }) + serverOffset
    return utc - offsetSeconds()
end

-- Flushes are not aligned to buckets, so a bucket labelled B can hold data
-- from up to one interval before B. Only buckets starting one full interval
-- after the mark are guaranteed to contain post-mark data alone.
function vstats.MarkSince()
    if not vstats.MarkTime then return nil end
    return vstats.MarkTime + vstats.FLUSH_INTERVAL
end

function vstats.MarkLabel()
    if not vstats.MarkTime then return "Since last balancing (none)" end
    if vstats.MarkManual then
        return "Since mark (" .. vstats.FormatLocalTime(vstats.MarkTime) .. ")"
    end
    return "Since last balancing (" .. vstats.FormatLocalTime(vstats.MarkTime) .. ")"
end

local function markLabelLua()
    return string.format(
        [[local R=vstats and vstats.RANGES if R then local m for _,r in ipairs(R) do if r.id=="mark" then m=r end end if not m then m={id="mark"} R[#R+1]=m end m.label=%q end]],
        vstats.MarkLabel()
    )
end

function vstats.SyncMarkLabel(target)
    local code = markLabelLua()
    RunString(code, "vstats_mark_label")
    if IsValid(target) then
        target:SendLua(code)
    else
        BroadcastLua(code)
    end
end

function vstats.SetMark(timestamp, manual)
    vstats.MarkTime = timestamp
    vstats.MarkManual = manual == true
    file.CreateDir("vstats")
    file.Write(vstats.MARK_FILE, tostring(timestamp) .. (manual and " manual" or ""))
    vstats.SyncMarkLabel()
end

-- A retune logs many changes at once; move the mark once, to the last of them.
hook.Add("vbal_BalanceChanged", "vstats_MarkFollowsBalance", function(timestamp)
    vstats.PendingBalanceMark = timestamp
    timer.Create("vstats_MarkFollowsBalance", 5, 1, function()
        vstats.SetMark(vstats.PendingBalanceMark)
    end)
end)

local function handleMark(ply, text, reply)
    if IsValid(ply) and not vstats.HasAccess(ply) then return end

    local timestamp = vstats.ParseLocalTime(text)
    if not timestamp then
        reply("[vStats] Usage: mark YYYY-MM-DD HH:MM  or  mark now")
        return
    end

    vstats.SetMark(timestamp, true)
    reply("[vStats] Mark set to " .. vstats.FormatLocalTime(timestamp)
        .. " (counts data from " .. vstats.FormatLocalTime(vstats.MarkSince()) .. ")")
end

concommand.Add("vstats_mark", function(ply, _, _, argStr)
    handleMark(ply, string.gsub(argStr or "", "\"", ""), function(msg)
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
    end)
end)

hook.Add("PlayerSay", "vstats_MarkCommand", function(ply, text)
    local arg = string.match(text, "^!vstats%s+mark%s*(.*)$")
    if not arg then return end
    handleMark(ply, arg, function(msg) ply:ChatPrint(msg) end)
    return ""
end)

hook.Add("PlayerInitialSpawn", "vstats_MarkLabel", function(ply)
    timer.Simple(10, function()
        if IsValid(ply) then vstats.SyncMarkLabel(ply) end
    end)
end)

-- Catch up with balance changes made while this file wasn't tracking them.
local lastChange = lastBalanceChange()
if lastChange and (not vstats.MarkTime or lastChange > vstats.MarkTime) then
    vstats.SetMark(lastChange)
else
    vstats.SyncMarkLabel()
end

print("[vStats] Mark Loaded.")
