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

function getMissionDescription(a_fileName, a_locale, a_needTask, a_needTheatre)
    local zipFile = minizip.unzOpen(a_fileName, 'rb')
    if not zipFile then
        return ''
    end
    local misStr
    if zipFile:unzLocateFile('mission') then
        misStr = zipFile:unzReadAllCurrentFile(false)
    end
	
	if misStr == nil then
		return ''
	end
    local funD = base.loadstring(misStr)
    local envD = { }
    base.setfenv(funD, envD)
    
    status, err = base.pcall(funD)
    if not status then 
        --base.print("----status, err=",status, err)
        return " "
    end

    local mission = envD.mission
    local description = mission.descriptionText 
    local requiredModules = mission.requiredModules or {}
	local task = nil
	local theatre = nil
	local unitType = nil
	local sortie = mission.sortie
	if a_needTask == true then
		local tmp = getPlayerTaskCountrySide(mission)
		task = tmp.task
		unitType = tmp.unitType
	end
	if a_needTheatre then
		theatre = mission.theatre 
	end
    
    zipFile:unzGoToFirstFile()
    
    local dictionary = {DEFAULT = {}}

    while true do
        local filename = zipFile:unzGetCurrentFileName()        
        local shortFileName = extractFileName(filename)
        local dirName = extractFirstDir(filename, 1)
        if shortFileName == 'dictionary' and dirName == 'l10n' then
            local nameDict = extractSecondDir(filename)            
            local dict = zipFile:unzReadAllCurrentFile(false)
            
            if dict then
                local fun, errStr = base.loadstring(dict)
                if not fun then
                    print("error loading dictionary", errStr)
                    return false
                end
                
                local env = { }
                base.setfenv(fun, env)
                fun()
       
                dictionary[nameDict] = env.dictionary
            end    
        end
        if not zipFile:unzGoToNextFile() then
			break
		end
    end    
        
    zipFile:unzClose()
    
    local lang = base.string.upper(a_locale)
    
    if dictionary[lang] and dictionary[lang][description] ~= nil and dictionary[lang][sortie] ~= nil then
        return dictionary[lang][description], requiredModules, task, theatre,unitType, dictionary[lang][sortie]
    elseif dictionary["DEFAULT"] and dictionary["DEFAULT"][description] ~= nil and dictionary["DEFAULT"][sortie] ~= nil then
        return dictionary["DEFAULT"][description], requiredModules, task, theatre,unitType, dictionary["DEFAULT"][sortie]
    else    
        return description, requiredModules, task, theatre, unitType, sortie
    end
end
-- End copied from dictionary.lua

local description = getMissionDescription(trackPath, "DEFAULT")
print(description)