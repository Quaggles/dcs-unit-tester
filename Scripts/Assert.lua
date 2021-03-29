-- Make this code on mission end trigger
-- If there are any undamaged units on red team
for i, group in pairs(coalition.getGroups(1)) do
    for i, unit in pairs(group:getUnits()) do
        local life = unit:getLife()
        local life0 = unit:getLife0()
        Output("G: "..group:getName().." U: "..unit:getName()..' - life: '..life.."/"..life0)
        if life >= life0 then
            Assert(false);
            return
        end
    end
end
Assert(true);