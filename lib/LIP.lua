-- Lightweight INI Parser (type-safe variables) by Cannonballdex 2024-04-18 - MIT License
local LIP = {}

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function is_number_str(s)
    return type(s) == "string" and s:match("^%s*[+-]?%d+%.?%d*%s*$")
end

--- load(fileName) -> table
function LIP.load(fileName)
    assert(type(fileName) == "string", 'Parameter "fileName" must be a string.')
    local file = assert(io.open(fileName, "rb"), "Error loading file: " .. fileName)
    local data = {}
    local section = "_global"           -- always a string (do not convert to number)
    data[section] = {}

    for rawLine in file:lines() do
        local line = rawLine

        if line:sub(1,3) == "\239\187\191" then
            line = line:sub(4)
        end

        line = trim(line)

        if line == "" or line:match("^%s*[;#]") then
            -- skip blank or comment lines
        else
            local sec = line:match("^%[([^%[%]]+)%]$")
            if sec then
                sec = trim(sec)
                -- keep section as a string; if you need numeric form, parse to a separate local
                section = sec
                data[section] = data[section] or {}
            else
                local k, v = line:match("^([^=]+)=(.*)$")
                if k and v ~= nil then
                    k = trim(k)
                    v = trim(v)

                    -- remove trailing inline comment conservatively
                    v = v:gsub("%s+[;#].*$", "")

                    -- convert value
                    local low = v:lower()
                    local val
                    if low == "true" then
                        val = true
                    elseif low == "false" then
                        val = false
                    elseif is_number_str(v) then
                        val = tonumber(v)
                    else
                        local quoted = v:match("^(['\"])(.*)%1$")
                        if quoted then
                            val = v:match("^(['\"])(.*)%1$") -- keep inner
                        else
                            val = v
                        end
                    end

                    -- keep key as a string in the section table (avoid reusing same variable with different types)
                    local key = k
                    -- if callers prefer numeric keys, caller can call tonumber on key, but we still keep it a string to avoid linter/type flips
                    -- if you want to store numeric keys as numbers, use a separate numeric variable
                    local key_num = nil
                    if is_number_str(k) then
                        key_num = tonumber(k)
                    end

                    if key_num ~= nil then
                        -- If you prefer numeric keys, one explicit place to set them:
                        -- data[section][key_num] = val
                        -- But to avoid mixed-type variable problems we keep string keys by default:
                        data[section][key] = val
                    else
                        data[section][key] = val
                    end
                end
            end
        end
    end

    file:close()
    return data
end

--- save(fileName, data[, opts])
function LIP.save(fileName, data, opts)
    assert(type(fileName) == "string", 'Parameter "fileName" must be a string.')
    assert(type(data) == "table", 'Parameter "data" must be a table.')
    opts = opts or {}
    local sort_output = opts.sort == true

    local file = assert(io.open(fileName, "wb"), "Error opening file for write: " .. fileName)

    local sections = {}
    for s in pairs(data) do table.insert(sections, s) end
    if sort_output then table.sort(sections, function(a,b) return tostring(a) < tostring(b) end) end

    local function write_section(sec)
        file:write(("[%s]\n"):format(tostring(sec)))
        local t = data[sec] or {}
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        if sort_output then table.sort(keys, function(a,b) return tostring(a) < tostring(b) end) end
        for _, k in ipairs(keys) do
            local v = t[k]
            local vs
            if type(v) == "boolean" then
                vs = v and "true" or "false"
            elseif type(v) == "number" then
                vs = tostring(v)
            else
                vs = tostring(v)
                if vs:match("[\n\r]") or vs:match("^%s") or vs:match("%s$") or vs:match("[;%#]") then
                    vs = '"' .. vs:gsub('"', '\\"') .. '"'
                end
            end
            file:write(("%s=%s\n"):format(tostring(k), vs))
        end
        file:write("\n")
    end

    if data["_global"] then
        write_section("_global")
    end

    for _, s in ipairs(sections) do
        if s ~= "_global" then
            write_section(s)
        end
    end

    file:close()
end

return LIP