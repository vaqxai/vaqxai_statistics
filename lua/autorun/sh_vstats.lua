AddCSLuaFile()

vstats = vstats or {}

AddCSLuaFile("vstats/sh_config.lua")
include("vstats/sh_config.lua")

if SERVER then
    include("vstats/sv_sqlinit.lua")
    include("vstats/sv_net.lua")
    include("vstats/sv_hooks.lua")
    include("vstats/sv_util.lua")

    AddCSLuaFile("vstats/cl_net.lua")
    AddCSLuaFile("vstats/cl_hooks.lua")
    AddCSLuaFile("vstats/cl_util.lua")
    AddCSLuaFile("vstats/cl_theme.lua")
    AddCSLuaFile("vstats/cl_dropdown.lua")
    AddCSLuaFile("vstats/cl_list.lua")
    AddCSLuaFile("vstats/cl_graph.lua")
    AddCSLuaFile("vstats/cl_panel.lua")
end

if CLIENT then
    include("vstats/cl_util.lua")
    include("vstats/cl_theme.lua")
    include("vstats/cl_dropdown.lua")
    include("vstats/cl_list.lua")
    include("vstats/cl_graph.lua")
    include("vstats/cl_panel.lua")
    include("vstats/cl_net.lua")
    include("vstats/cl_hooks.lua")
end

print("[vStats] Loader finished.")
