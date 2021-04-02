-- By Quaggles

local Serializer = require("Serializer");
local minizip = require("lua-minizip")
local lfs = require("lfs")
MissionEditor = {}

-- Removes items from a table if they don't satisfy a predicate
function MissionEditor.ArrayRemove(t, fnKeep)
    local j, n = 1, #t;

    for i = 1, n do
        if (fnKeep(t, i, j)) then
            -- Move i's kept value to j's position, if it's not already there.
            if (i ~= j) then
                t[j] = t[i];
                t[i] = nil;
            end
            j = j + 1; -- Increment position of where we'll place the next kept value.
        else
            t[i] = nil;
        end
    end

    return t;
end

function MissionEditor.TableLength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

-- Gets the file name out of a path
function MissionEditor.extractFileName(filePath)
    if not filePath then
        return nil
    end
    local lFilePath = filePath
    local revPath = string.reverse(lFilePath)
    local lastSlash = string.find(revPath, '[/\\]')
    if lastSlash then
        lFilePath = string.sub(lFilePath, string.len(lFilePath) - lastSlash + 2)
    end
    return lFilePath
end

-- Gets the root directory of the path
local function extractFirstDir(filePath)
    if filePath == nil then
        return nil
    end
    local firstSlash = string.find(filePath, '[/\\]')
    if firstSlash then
        filePath = string.sub(filePath, 0, firstSlash - 1)
    end
    return filePath
end

--Given a file path returns the directory it exists in
function MissionEditor.GetDirectory(str)
    return str:match("(.*[/\\])")
end

-- Returns true if string is null or empty
local function isNullOrEmpty(s)
    return s == nil or s == ''
end

local function getPath(str, sep)
    sep = sep or '/'
    return str:match("(.*" .. sep .. ")")
end

-- Extracts all files in a zip archive to a folder
local function unzExtractAll(zipFile, outputDir)
    while true do
        local filename = zipFile:unzGetCurrentFileName()
        local shortFileName = MissionEditor.extractFileName(filename)
        local dirName = extractFirstDir(filename, 1)
        -- Is Directory
        if isNullOrEmpty(shortFileName) then
            lfs.mkdir(outputDir .. filename)
        else
            -- Is file
            local content = zipFile:unzReadAllCurrentFile(false)
            if content then
                lfs.mkdir(getPath(outputDir .. filename))
                local newFile, error = io.open(outputDir .. filename, "w")
                if newFile then
                    newFile:write(content)
                    newFile:close()
                else
                    print("Error: "..error)
                end
            end
        end

        if not zipFile:unzGoToNextFile() then
            break
        end
    end
end

-- Returns a table containing all files in the directory
function MissionEditor.recursiveDir(dir, list, includeFolders)
    list = list or {}    -- use provided list or create a new one
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local ne = dir .. "/" .. entry
            if lfs.attributes(ne).mode == 'directory' then
                if includeFolders == true then
                    table.insert(list, ne)
                end
                MissionEditor.recursiveDir(ne, list, includeFolders)
            else
                table.insert(list, ne)
            end
        end
    end

    return list
end

-- Zips up a directory into an archive
local function archiveAll(zipFile, inputDir)
    for _, file in pairs(MissionEditor.recursiveDir(inputDir, {}, false)) do
        local relativePath = string.sub(file, string.len(inputDir) + 2);
        zipFile:zipAddFile(relativePath, file)
    end
end

-- Extracts the miz into a temporary folder for modification
function MissionEditor.Open(mizPath)
    print("[Opening]\t" .. mizPath)
    -- Open open mission file and execute it
    local tempDir = getPath(mizPath) .. "Temp/"
    local zipFile = minizip.unzOpen(mizPath, "r");
    unzExtractAll(zipFile, tempDir)
    zipFile:unzClose()

    -- Execute lua in miz files
    dofile(tempDir .. "mission")
    dofile(tempDir .. "options")
    dofile(tempDir .. "warehouses")
    dofile(tempDir .. "\\l10n\\DEFAULT\\dictionary")
    dofile(tempDir .. "\\l10n\\DEFAULT\\mapResource")

    return tempDir
end

function MissionEditor.SaveAs(mizPath, tempDir)
    print("[Saving]\t" .. mizPath)
    lfs.mkdir(MissionEditor.GetDirectory(mizPath))
    local newZip = minizip.zipCreate(mizPath)
    archiveAll(newZip, tempDir)
    newZip:zipClose()
end

-- Removes a directory and all files inside it
local function rmDir(dir)
    for file in lfs.dir(dir) do
        local file_path = dir .. '/' .. file
        if file ~= "." and file ~= ".." then
            if lfs.attributes(file_path, 'mode') == 'file' then
                os.remove(file_path)
            elseif lfs.attributes(file_path, 'mode') == 'directory' then
                rmDir(file_path)
            end
        end
    end
    lfs.rmdir(dir)
end

function MissionEditor.Clean(tempDir)
    print("[Cleaning]\t" .. tempDir)
    rmDir(tempDir)
end

function MissionEditor.SerializeTo(dir, name, object)
    print("[Serialize]\t" .. name .. " \tto " .. dir .. name)

    -- Write file to disk
    -- Uses ED's serializer to make sure it's compatible
    local file, error = io.open(dir .. name, "w+")
    if file then
        local serializer = Serializer.new(file)
        serializer.fout = file -- Why this is required is beyond me, Serializer.new() does this already ¯\_(ツ)_/¯
        serializer:serialize_simple2(name, object)

        file:close()
    else
        print("Error writing "..dir..name.." to disk: "..error)
    end
end

do
    return MissionEditor
end