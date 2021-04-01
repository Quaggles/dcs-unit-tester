local logName = 'DCS.Lua.Connector'
log.write(logName, log.INFO, "Loading")

local function runSnippetIn(env, code)
	local resultStringCode = [[
			local function serialize(svalue)
				local seenTables = {}
				local retlist = {}
				local indentLevel = 0
				local function serializeRecursive(value)
					if type(value) == "string" then return table.insert(retlist, string.format("%q", value)) end
					if type(value) ~= "table" then return table.insert(retlist, tostring(value)) end

					if seenTables[value] == true then
						   table.insert(retlist, tostring(value))
						return
					end
					seenTables[value] = true

					-- we have a table, iterate over the keys

					table.insert(retlist, "{\n")
					indentLevel = indentLevel + 4
					for k, v in pairs(value) do
						table.insert(retlist, string.rep(" ", indentLevel).."[")
						if type(k) == "table" then
							   table.insert(retlist, tostring(k))
						else
							serializeRecursive(k)
						end
						table.insert(retlist, "] = ")
						serializeRecursive(v)
						table.insert(retlist, ",\n")
					end
					indentLevel = indentLevel - 4
					table.insert(retlist, string.rep(" ", indentLevel).."}")
				end
				serializeRecursive(svalue, "    ")
				return table.concat(retlist)
			end


			local function evalAndSerializeResult(code)
				local success = false
				local result = ""
				local retstatus = ""

				local f, error_msg = loadstring(code, "Lua Console Snippet")
				if f then
					--setfenv(f, _G)
					success, result = pcall(f)
					if success then
						retstatus="success"
						result = serialize(result)
					else
						retstatus = "runtimeError"
						result = tostring(result)
					end
				else
					retstatus = "syntaxError"
					result = tostring(error_msg)
				end

				return retstatus.."\n"..result
			end

				]].."return evalAndSerializeResult("..string.format("%q", code)..")"
	local result = nil
	local success = nil

	if env == "gui" then
		result = loadstring(resultStringCode)()
		success = true
	else
		result, success = net.dostring_in(env, resultStringCode)
		--log.write("Lua Console", log.INFO, "l94: success="..tostring(success))
	end

	if not success then
		result = "dostringError\n"..tostring(env).."\n"..tostring(code).."\n"..tostring(result)
	end

	local firstNewlinePos = string.find(result, "\n")
	--log.write("Lua Console", log.INFO, "firstnewlinepos="..tostring(firstNewlinePos))

	local result_str = string.sub(result, firstNewlinePos+1)
	local status_str = string.sub(result, 1, firstNewlinePos-1)
	return result_str, status_str
end


package.path = package.path..";.\\LuaSocket\\?.lua"
package.cpath = package.cpath..";.\\LuaSocket\\?.dll"

local JSON = loadfile("Scripts\\JSON.lua")()
local socket = require("socket")

local dcsBiosLuaConsole = {}

dcsBiosLuaConsole.host = "127.0.0.1"
dcsBiosLuaConsole.listenPort = 5000
dcsBiosLuaConsole.sendPort = dcsBiosLuaConsole.listenPort + 1
dcsBiosLuaConsole.conn = socket.udp()
dcsBiosLuaConsole.conn:setsockname(dcsBiosLuaConsole.host, dcsBiosLuaConsole.listenPort)
dcsBiosLuaConsole.conn:settimeout(0)

local function step()
	local line, err = dcsBiosLuaConsole.conn:receive()
	if line then
		log.write(logName, log.INFO, DCS.getRealTime().." UDP Received: "..tostring(line))
	elseif err then
		if (err ~= "timeout") then
			log.write(logName, log.INFO, DCS.getRealTime().." UDP Error: "..tostring(err))
		end
		return
	else
		log.write(logName, log.INFO, DCS.getRealTime().." UDP Nothing Received")
		return
	end

	local message = JSON:decode(line)

	-- Construct response message
	local response_msg = {}
	response_msg.id = message.id

	local result, status

	-- Run lua command
	if message.type == 'ping' then
		status = 'success'
		result = 'pong'
		response_msg.type = "ping"
	elseif message.type == 'command' then
		result, status = runSnippetIn(message.luaEnv, message.code)
		response_msg.type = "luaResult"
	end
	response_msg.result = tostring(result)
	response_msg.status = tostring(status)
	local response_string = ""
	local function encode_response()
		response_string = JSON:encode(response_msg):gsub("\n","").."\n"
	end

	local success, result = pcall(encode_response)
	if not success then
		response_msg.status = "encodeResponseError"
		response_msg.result = tostring(result)
		encode_response()
	end
	log.write(logName, log.INFO, DCS.getRealTime().." UDP Send: "..response_string.." to "..dcsBiosLuaConsole.host..':'..dcsBiosLuaConsole.sendPort)
	dcsBiosLuaConsole.conn:sendto(response_string, dcsBiosLuaConsole.host, dcsBiosLuaConsole.sendPort)
end

local callbacks = {}
function callbacks.onSimulationFrame()
	status, err = pcall(step)
	if not status then
		log.write(logName, log.INFO, "onSimulationFrame Error: "..tostring(err))
	end
end
function callbacks.onMissionLoadBegin()
	log.write(logName, log.INFO, "onMissionLoadBegin")
end
function callbacks.onMissionLoadProgress(progress, message)
	-- log.write("DCS.Lua.Connector", log.INFO, "onMissionLoadProgress - "..progress.." - "..message)
end
function callbacks.onMissionLoadEnd()
	log.write(logName, log.INFO, "onMissionLoadEnd")
end
function callbacks.onSimulationStart()
	log.write(logName, log.INFO, "onSimulationStart")
end
function callbacks.onSimulationStop()
	log.write(logName, log.INFO, "onSimulationStop")
end

DCS.setUserCallbacks(callbacks)

log.write(logName, log.INFO, "Loaded Successfully")
