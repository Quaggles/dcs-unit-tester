function DCS.startMissionMultiplayer(filename)
    local cfg = 
    {
        ["description"] = "",
        ["require_pure_textures"] = true,
        ["listStartIndex"] = 1,
        ["advanced"] = 
        {
            ["allow_change_tailno"] = true,
            ["allow_ownship_export"] = true,
            ["allow_object_export"] = true,
            ["pause_on_load"] = true,
            ["allow_sensor_export"] = true,
            ["event_Takeoff"] = true,
            ["pause_without_clients"] = false,
            ["client_outbound_limit"] = 0,
            ["client_inbound_limit"] = 0,
            ["server_can_screenshot"] = false,
            ["allow_players_pool"] = true,
            ["voice_chat_server"] = true,
            ["allow_change_skin"] = true,
            ["event_Connect"] = true,
            ["event_Ejecting"] = true,
            ["event_Kill"] = true,
            ["event_Crash"] = true,
            ["event_Role"] = true,
            ["resume_mode"] = 1,
            ["maxPing"] = 0,
            ["allow_trial_only_clients"] = false,
            ["allow_dynamic_radio"] = true,
        }, -- end of ["advanced"]
        ["port"] = "10308",
        ["mode"] = 0,
        ["bind_address"] = "",
        ["isPublic"] = false,
        ["listShuffle"] = false,
        ["lastSelectedMission"] = filename,
        ["version"] = 1,
        ["password"] = "test",
        ["listLoop"] = false,
        ["name"] = "DCS Unit Tester",
        ["require_pure_scripts"] = false,
        ["require_pure_models"] = true,
        ["missionList"] = 
        {
            [1] = filename,
        }, -- end of ["missionList"]
        ["require_pure_clients"] = true,
        ["maxPlayers"] = 16,
    } -- end of cfg
    return _G.net.start_server(cfg)
end


return DCS.startMissionMultiplayer('{missionPath}')