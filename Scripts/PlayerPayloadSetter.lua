-- Some magic code to find the current directory of this script
pwd = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]]
package.path = pwd .."?.lua;"..package.path

local lfs = require("lfs")

if arg[1] == nil then
    print("Missing argument 1, DCS Path")
    return 1
else
    if (lfs.attributes(arg[1]) == nil) then
        print("Argument 1 DCS Path points to folder that doesn't exist")
        return 1
    end
	dcsDir = arg[1]
	package.path = package.path .. ";"..dcsDir.."Scripts/?.lua"
end

if arg[2] == nil then
    if (lfs.attributes(arg[2]) == nil) then
        print("Argument 2 Track Directory points to folder that doesn't exist")
        return 1
    end
    print("Missing argument 2, Track Directory")
    return 1

else
    searchDirectory = arg[2]
    --searchDirectory="C:\\Users\\Quaggles\\Git\\DCS\\dcs-unit-tests\\FA-18C"
end

missionEditor = require "MissionEditor"

local function GetFileName(url)
    return url:match("(.+)%..+")
end

function FileExists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local function GetParentPath(path)
    return path:match('(.*)\/[^\/]*$')
end

function SetProperty(coalitionName, unit, payload)
    if unit.skill == "Player" then
        -- Overwrite all payload items that are supplied
        for k,v in pairs(payload) do
            for k2,v2 in pairs(unit.payload) do
                if (k == k2) then
                    unit.payload[k2] = v;
                end
            end
        end
    end
end

function PropertySetter(payload)
    for coalitionName, coalition in pairs(mission.coalition) do
        for _, country in ipairs(coalition.country) do
            if country.helicopter ~= nil then
                -- Skip if no helicopters
                for _, groups in pairs(country.helicopter) do
                    for _, group in ipairs(groups) do
                        for _, unit in ipairs(group.units) do
                            SetProperty(coalitionName, unit, payload)
                        end
                    end
                end
            end
            if country.plane ~= nil then
                -- Skip if no planes
                for _, groups in pairs(country.plane) do
                    for _, group in ipairs(groups) do
                        for _, unit in ipairs(group.units) do
                            SetProperty(coalitionName, unit, payload)
                        end
                    end
                end
            end
        end
    end
end

function UnitTypeSetter(unitType)
    for coalitionName, coalition in pairs(mission.coalition) do
        for _, country in ipairs(coalition.country) do
            if country.helicopter ~= nil then
                -- Skip if no helicopters
                for _, groups in pairs(country.helicopter) do
                    for _, group in ipairs(groups) do
                        for _, unit in ipairs(group.units) do
                            if unit.skill == "Player" then
                                unit.type = unitType
                            end
                        end
                    end
                end
            end
            if country.plane ~= nil then
                -- Skip if no planes
                for _, groups in pairs(country.plane) do
                    for _, group in ipairs(groups) do
                        for _, unit in ipairs(group.units) do
                            if unit.skill == "Player" then
                                unit.type = unitType
                            end
                        end
                    end
                end
            end
        end
    end
end

for _, file in pairs(missionEditor.recursiveDir(searchDirectory, nil, false)) do
    -- Generate payload variants
    if file:match('.base.trk$') then
        local parentPath = GetParentPath(file)
        local payloadPath = ""
        if (FileExists(parentPath.."/payloads.lua")) then
            payloadPath = parentPath
        else
            payloadPath = GetParentPath(parentPath)
        end
        if FileExists(payloadPath.."/payloads.lua") then
            dofile(payloadPath.."/payloads.lua")
        end
        tempDir = missionEditor.Open(file)
        for k, v in pairs(payloads) do
            PropertySetter(v)
            MissionEditor.SerializeTo(tempDir, 'mission', mission)
            local newFileName = k..".trk"
            MissionEditor.SaveAs(parentPath..'/'..newFileName, tempDir)
        end
        missionEditor.Clean(tempDir)
    end
    -- Generate Load Tests
    if file:match('.base.aircraft.trk$') then
        local parentPath = GetParentPath(file)
        if (FileExists(parentPath.."/PlayableAircraftTypes.lua")) then
            dofile(parentPath.."/PlayableAircraftTypes.lua")
        end
        tempDir = missionEditor.Open(file)
        for k,v in pairs(types) do
            UnitTypeSetter(v)
            MissionEditor.SerializeTo(tempDir, 'mission', mission)
            local newFileName = "LoadTest."..v..".trk"
            MissionEditor.SaveAs(parentPath..'/'..newFileName, tempDir)
        end
        missionEditor.Clean(tempDir)
    end
    if file:match('.base.helicopter.trk$') then
        local parentPath = GetParentPath(file)
        if (FileExists(parentPath.."/PlayableHelicoptersTypes.lua")) then
            dofile(parentPath.."/PlayableHelicoptersTypes.lua")
        end
        tempDir = missionEditor.Open(file)
        for k,v in pairs(types) do
            UnitTypeSetter(v)
            MissionEditor.SerializeTo(tempDir, 'mission', mission)
            local newFileName = "LoadTest."..v..".trk"
            MissionEditor.SaveAs(parentPath..'/'..newFileName, tempDir)
        end
        missionEditor.Clean(tempDir)
    end
end
print('Complete')