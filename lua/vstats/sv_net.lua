util.AddNetworkString("vstats_open")
util.AddNetworkString("vstats_request_report")
util.AddNetworkString("vstats_report_data")

net.Receive("vstats_request_report", function(_, ply)
    if not vstats.HasAccess(ply) then return end

    local category = net.ReadString()
    local range = net.ReadString()
    local selected = net.ReadString()
    local source = net.ReadString()
    if #category > 64 or #range > 16 or #selected > 128 or #source > 128 then return end

    local report = vstats.BuildReport(category, range, selected, source)
    if not report then return end

    local json = util.TableToJSON(report) or "{}"
    net.Start("vstats_report_data")
    net.WriteString(json)
    net.Send(ply)
end)

hook.Add("PlayerSay", "vstats_ChatCommand", function(ply, text)
    if string.Trim(string.lower(text)) ~= "!vstats" then return end

    if vstats.HasAccess(ply) then
        net.Start("vstats_open")
        net.Send(ply)
    end
    return ""
end)

concommand.Add("vstats_force_flush", function(ply)
    if IsValid(ply) then return end

    vstats.FlushAccumulators()
    print("[vStats] Forced flush completed.")
end)

concommand.Add("vstats_print_money_sources", function(ply)
    if IsValid(ply) then return end
    vstats.PrintMoneySourceDebug()
end)

concommand.Add("vstats_print_xp_sources", function(ply)
    if IsValid(ply) then return end
    vstats.PrintXPSourceDebug()
end)

print("[vStats] Net (SV) Loaded.")
