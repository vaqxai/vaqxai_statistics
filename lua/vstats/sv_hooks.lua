-- Wrap Player:addMoney once, so every money source (salary, crafting, selling,
-- printers, etc.) gets attributed to the player's current job automatically.
-- DarkRP may define addMoney after addon autoruns, so installation is retried.
local function installAddMoneyWrapper()
    if vstats._addMoneyWrapped then return true end

    local PLYMETA = FindMetaTable("Player")
    local oldAddMoney = PLYMETA.addMoney
    if not oldAddMoney then return false end

    function PLYMETA:addMoney(amount, ...)
        local source = vstats.GetMoneySource(3)
        local result = oldAddMoney(self, amount, ...)

        if isnumber(amount) and amount ~= 0 and not vstats.IsExcludedMoneySource(source) then
            local job = vstats.GetJobName(self:Team())
            if amount > 0 then
                vstats.RecordJobIncome(job, amount, source)
            else
                vstats.RecordJobSpend(job, -amount, source)
            end
        end

        return result
    end

    vstats._addMoneyWrapped = true
    timer.Remove("vstats_install_addmoney")
    print("[vStats] Player:addMoney tracking installed.")
    return true
end

installAddMoneyWrapper()

hook.Add("PostGamemodeLoaded", "vstats_InstallAddMoneyWrapper", function()
    installAddMoneyWrapper()
end)

timer.Create("vstats_install_addmoney", 1, 0, function()
    if installAddMoneyWrapper() then timer.Remove("vstats_install_addmoney") end
end)

hook.Add("PlayerInitialSpawn", "vstats_PlayerInitialSpawn", function(ply)
    ply.vstats_job = ply:Team()
    ply.vstats_jobSince = CurTime()
end)

hook.Add("OnPlayerChangedTeam", "vstats_OnPlayerChangedTeam", function(ply, before, after)
    if ply.vstats_jobSince then
        vstats.WriteJobPlaytime(vstats.GetJobName(before), CurTime() - ply.vstats_jobSince)
    end
    ply.vstats_job = after
    ply.vstats_jobSince = CurTime()
end)

hook.Add("PlayerDisconnect", "vstats_PlayerDisconnect", function(ply)
    if ply.vstats_jobSince then
        vstats.WriteJobPlaytime(vstats.GetJobName(ply.vstats_job), CurTime() - ply.vstats_jobSince)
        ply.vstats_jobSince = nil
    end
end)

local function resolveWeaponClass(inflictor, attacker)
    local class
    if IsValid(inflictor) then
        class = inflictor:GetClass()
        if not inflictor:IsWeapon() and not weapons.GetStored(class) then
            class = nil
        end
    end

    if (not class or not vstats.IsTrackedWeapon(class)) and IsValid(attacker:GetActiveWeapon()) then
        class = attacker:GetActiveWeapon():GetClass()
    end

    if vstats.IsTrackedWeapon(class) then return class end
end

hook.Add("PlayerDeath", "vstats_PlayerDeath", function(victim, inflictor, attacker)
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end

    local class = resolveWeaponClass(inflictor, attacker)
    if class then vstats.RecordWeaponKill(class) end
end)

hook.Add("EntityTakeDamage", "vstats_WeaponDamage", function(target, damageInfo)
    if not IsValid(target) or not target:IsPlayer() then return end

    local attacker = damageInfo:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == target then return end

    local class = resolveWeaponClass(damageInfo:GetInflictor(), attacker)
    if class then vstats.RecordWeaponDamage(class, damageInfo:GetDamage()) end
end)

hook.Add("ShutDown", "vstats_ShutDown", function()
    vstats.FlushAccumulators()
end)

timer.Create("vstats_weapon_scan", vstats.WEAPON_SCAN_INTERVAL, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        for _, wep in ipairs(ply:GetWeapons()) do
            local class = wep:GetClass()
            if vstats.IsTrackedWeapon(class) then
                vstats.RecordWeaponPlaytime(class, vstats.WEAPON_SCAN_INTERVAL)
            end
        end
    end
end)

hook.Add("vlevels_XPAwarded", "vstats_RecordXP", function(ply, category, amount, source)
    if not IsValid(ply) then return end
    vstats.RecordXP(vstats.GetJobName(ply:Team()), category, source, amount)
end)

hook.Add("RCD:VehicleAcquired", "vstats_VehicleAcquired", function(_, _, vehicleID, acquisition)
    vstats.RecordVehicleActivity(vehicleID, acquisition == "bought" and "bought" or "gotten")
end)

hook.Add("RCD:SellVehicle", "vstats_VehicleSold", function(_, _, vehicleID)
    vstats.RecordVehicleActivity(vehicleID, "sold")
end)

hook.Add("RCD:VehicleRetrieved", "vstats_VehicleRetrieved", function(_, _, vehicleID)
    vstats.RecordVehicleActivity(vehicleID, "retrieved")
end)

hook.Add("RealisticPolice:FinePlayer", "vstats_PlayerTicket", function(_, _, reasons)
    vstats.RecordTicketReasons(reasons, "player")
end)

hook.Add("RealisticPolice:FineVehicle", "vstats_VehicleTicket", function(_, _, reasons)
    vstats.RecordTicketReasons(reasons, "vehicle")
end)

timer.Create("vstats_flush", vstats.FLUSH_INTERVAL, 0, function()
    vstats.FlushAccumulators()
end)

print("[vStats] Hooks (SV) Loaded.")
