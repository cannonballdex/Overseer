-- Lightweight time parsing utilities for Overseer
local M = {}

-- Parse a duration string like "1h:30m:10s" into total seconds
function M.ParseDurationSeconds(duration)
    if not duration then return 0 end
    local totalSeconds = 0
    for index = 1, 4 do
        local ourSplit = string.split and string.split(duration, ':') or (function()
            local t = {}
            for piece in string.gmatch(duration, '[^:]+') do table.insert(t, piece) end
            return t
        end)()
        local currentItem = ourSplit[index]
        if (currentItem ~= nil) then
            local len = #currentItem
            local currentUnit = string.sub(currentItem, len, len)
            local currentAmount = tonumber(string.sub(currentItem, 1, -2)) or 0
            if (currentUnit == "h") then
                totalSeconds = totalSeconds + currentAmount * 3600
            elseif (currentUnit == "m") then
                totalSeconds = totalSeconds + currentAmount * 60
            elseif (currentUnit == "s") then
                totalSeconds = totalSeconds + currentAmount
            end
        end
    end
    return totalSeconds
end

-- Parse a duration string like "1h:30m:10s" into minutes (same semantics as previous ParseDuration in overseer)
function M.ParseDuration(duration)
    local totalMinutes = 0
    local ourSplit = {}
    for piece in string.gmatch(duration or '', '[^:]+') do table.insert(ourSplit, piece) end
    for index = 1, 4 do
        local currentItem = ourSplit[index]
        if (currentItem ~= nil) then
            local len = #currentItem
            local currentUnit = string.sub(currentItem, len, len)
            local currentAmount = tonumber(string.sub(currentItem, 1, -2)) or 0
            if (currentUnit == "h") then
                totalMinutes = totalMinutes + currentAmount * 60
            elseif (currentUnit == "m") then
                totalMinutes = totalMinutes + currentAmount
            elseif (currentUnit == "s") then
                if (totalMinutes == 0) then
                    return 1
                end
            end
        end
    end
    if (totalMinutes > 0) then totalMinutes = totalMinutes + 1 end
    return totalMinutes
end

return M