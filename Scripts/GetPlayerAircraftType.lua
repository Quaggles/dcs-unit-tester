-- Some magic code to find the current directory of this script
pwd = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]]
package.path = pwd .."?.lua;"..package.path

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
	package.path = package.path .. ";"..dcsDir.."MissionEditor/modules/?.lua"
end
local base = _G
local lfs = require("lfs")
local minizip = require("lua-minizip")

local function GetFileName(url)
    return url:match("(.+)%..+")
end

function FileExists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

if arg[2] == nil then
    if (lfs.attributes(arg[2]) == nil) then
        print("Argument 2 Track Path points to folder that doesn't exist")
        return 1
    end
    print("Missing argument 2, Track Path")
    return 1

else
    trackPath = arg[2]
end

-- Copied from dictionary.lua
function extractFileName(filePath)
    if not filePath then
        return nil
    end
    local lFilePath =  filePath   
    local revPath = base.string.reverse(lFilePath)
    local lastSlash = base.string.find(revPath, '[/\\]')
	if lastSlash then 
		lFilePath = base.string.sub(lFilePath, base.string.len(lFilePath) - lastSlash + 2)
    end
	return lFilePath
end

function extractFirstDir(filePath)
    if filePath == nil then
		return nil
	end
    local firstSlash = base.string.find(filePath, '[/\\]')
	if firstSlash then 
		filePath = base.string.sub(filePath, 0, firstSlash-1)
    end
	return filePath
end

function findDir(filePath, dir)
    return base.string.find(base.string.upper(filePath), dir) ~= nil
end

function extractSecondDir(filePath)
    if filePath == nil then
		return nil
	end
    local firstSlash = base.string.find(filePath, '[/\\]')
	if firstSlash then 
		filePath = base.string.sub(filePath, firstSlash+1)
    end
    local firstSlash = base.string.find(filePath, '[/\\]')
	if firstSlash then 
		filePath = base.string.sub(filePath, 1, firstSlash-1)
    end
	return filePath
end

function getMissionPlayerAircraft(a_fileName)
    local zipFile = minizip.unzOpen(a_fileName, 'rb')
    if not zipFile then
        return nil
    end
    local misStr
    if zipFile:unzLocateFile('mission') then
        misStr = zipFile:unzReadAllCurrentFile(false)
    end
	
	if misStr == nil then
		return nil
	end
    local funD = base.loadstring(misStr)
    local envD = { }
    base.setfenv(funD, envD)
    
    status, err = base.pcall(funD)
    if not status then 
        --base.print("----status, err=",status, err)
        return nil
    end

    local mission = envD.mission

    -- Get player aircraft type
    for coalitionName, coalition in pairs(mission.coalition) do
        for _, country in ipairs(coalition.country) do
            if country.helicopter ~= nil then
                -- Skip if no helicopters
                for _, groups in pairs(country.helicopter) do
                    for _, group in ipairs(groups) do
                        for _, unit in ipairs(group.units) do
                            if unit.skill == "Player" then
                                return unit.type
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
                                return unit.type
                            end
                        end
                    end
                end
            end
        end
    end
    zipFile:unzClose()
    return nil
end
-- End copied from dictionary.lua

local description = getMissionPlayerAircraft(trackPath)
print(description)