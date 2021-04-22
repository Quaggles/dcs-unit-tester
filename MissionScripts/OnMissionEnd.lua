-- If there are any undamaged units on red team
local failed = false
for i, group in pairs(coalition.getGroups(1)) do
    for i, unit in pairs(group:getUnits()) do
        local life = unit:getLife()
        local life0 = unit:getLife0()
        Output("G: "..group:getName().." U: "..unit:getName()..' - life: '..life.."/"..life0)
        if life >= life0 then
			if failed == false then
				Assert(false);
			end
			failed = true
        end
    end
end
if failed == false then
	Assert(true);
end