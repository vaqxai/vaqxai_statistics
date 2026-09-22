function vstats.RequestReport(category, range, selected, source)
    if not vstats.HasAccess or not vstats.HasAccess(LocalPlayer()) then return end

    net.Start("vstats_request_report")
    net.WriteString(category or "job_playtime")
    net.WriteString(range or "24h")
    net.WriteString(selected or "")
    net.WriteString(source or "")
    net.SendToServer()
end

net.Receive("vstats_open", function()
    -- The server only sends this message after its authoritative access check.
    vstats.OpenMainPanel()
end)

net.Receive("vstats_report_data", function()
    local report = util.JSONToTable(net.ReadString() or "")
    if not istable(report) or not IsValid(vstats.MainPanel) then return end
    vstats.MainPanel:ApplyReport(report)
end)

concommand.Add("vstats_open", function()
    if vstats.HasAccess and vstats.HasAccess(LocalPlayer()) then vstats.OpenMainPanel() end
end)

print("[vStats] Net (CL) Loaded.")
