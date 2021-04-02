package.path  = package.path..";.\\LuaSocket\\?.lua"
package.cpath = package.cpath..";.\\LuaSocket\\?.dll"

local socket = require("socket")
local connection = socket.connect("localhost", 1337)
local dutExportSocket
if connection ~= nil then
    dutExportSocket = socket.try(connection)
    if dutExportSocket ~= nil then
        dutExportSocket:setoption("tcp-nodelay", true)
    end
end

function Output(message)
    if socket ~= nil and dutExportSocket ~= nil then
        socket.try(dutExportSocket:send(tostring(message)))
    end
end

function Assert(message)
    if socket ~= nil and dutExportSocket ~= nil then
        socket.try(dutExportSocket:send("DUT_ASSERSION="..tostring(message)))
    end
end