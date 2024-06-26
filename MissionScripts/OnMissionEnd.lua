-- If there are any undamaged units on red team
local failed = false
for i, group in pairs(coalition.getGroups(1)) do
    for i, unit in pairs(group:getUnits()) do
        local life = unit:getLife()
        local life0 = unit:getLife0()
        Output("G: "..group:getName().." U: "..unit:getName()..' - life: '..life.."/"..life0)
        if life >= life0 then
			failed = true
        end
    end
end
-- If there are any undamaged statics on red team
for i, static in pairs(coalition.getStaticObjects(1)) do
    local life = static:getLife()
    local life0 = static:getDesc().life
    Output("S: "..static:getName()..' - life: '..life.."/"..life0)
    if life >= life0 then
        failed = true
    end
end
Assert(failed == false);