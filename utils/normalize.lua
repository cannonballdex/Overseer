-- Small normalization / parsing helpers used by Overseer
local M = {}

-- Trim whitespace from both ends
local function trim(s)
    if s == nil then return nil end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

-- Try to coerce a value to number; returns number or nil
function M.to_number(value)
    if value == nil then return nil end
    local n = tonumber(value)
    if n then return n end
    -- If it's a string that contains non-numeric chars, try to extract numeric prefix
    local s = tostring(value)
    s = trim(s)
    local found = s:match("([+-]?%d+%.?%d*)")
    if found then
        return tonumber(found)
    end
    return nil
end

-- Parse a percent-like string and return numeric percent (e.g., "62%", " 62 % ", "62.5%") or nil
function M.parse_percent(s)
    if s == nil then return nil end
    local str = tostring(s)
    str = trim(str)
    -- Remove trailing percent sign if present
    str = str:gsub("%%", "")
    -- Extract numeric portion (handles integers and decimals)
    local found = str:match("([+-]?%d+%.?%d*)")
    if not found then return nil end
    return tonumber(found)
end

return M