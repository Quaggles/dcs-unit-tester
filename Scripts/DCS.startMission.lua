-- Used by dcs-unit-tester to start tracks in DCS
local function ends_with(str, ending)
	return ending == "" or str:sub(-#ending) == ending
end

function DCS.startMission(filename)
   local command = 'mission'
   if ends_with(filename, '.trk') then
		command = 'track'
	end
    return _G.module_mission.play({ file = filename, command = command}, '', filename)
end

return DCS.startMission('track.trk')