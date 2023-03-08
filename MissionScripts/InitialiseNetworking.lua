-- Now initialised in MissionScripting.lua
--[[
package.path  = package.path..";.\\LuaSocket\\?.lua"
package.cpath = package.cpath..";.\\LuaSocket\\?.dll"
socket = require("socket")
]]
if socket ~= nil then
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
            socket.try(dutExportSocket:send(tostring(message)..";"))
        end
    end
    Output = socket.protect(Output)
    function Assert(message)
        if socket ~= nil and dutExportSocket ~= nil then
            socket.try(dutExportSocket:send("DUT_ASSERSION="..tostring(message)..";"))
        end
    end
    Assert = socket.protect(Assert)
else
    trigger.action.outText("DCS Unit Tester Mod not installed in your DCS installation, if you're doing local development/recording tracks this is fine", 10, false)
    function Output(message)
        trigger.action.outText("Output: "..tostring(message)..";", 5, false)
    end
    function Assert(message)
		error("\n\n\n\n\n\n\n\nThis is not an error, this window shows you the test result when the mod isn't installed\n\nTest Result: "..tostring(message).."\n\n\n\n\n\n\n\n")
        trigger.action.outText("DUT_ASSERSION="..tostring(message)..";", 5, false)
    end
end