--- @type Mq
local mq = require('mq')
local lfs = require('lfs')
local ffi = require("ffi")

ffi.cdef[[
int CreateDirectoryA(const char *lpPathName, unsigned int *fdwSound);
]]
local winfs = ffi.load("Kernel32")

local actions = {}

function actions.rename(current_filename, target_filename)
    os.rename(current_filename, target_filename)
end

function actions.file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

function actions.create_dir(directoryPath)
    local attr = lfs.attributes(directoryPath)
    if not (attr and attr.mode == "directory") then
        winfs.CreateDirectoryA(directoryPath, nil)
    end
end

function actions.ensure_dir(directoryPath)
    local attr = lfs.attributes(directoryPath)
    if not (attr and attr.mode == "directory") then
        winfs.CreateDirectoryA(directoryPath, nil)
    end
end

function actions.ensure_config_dir()
    actions.ensure_dir(actions.get_config_dir())
	-- local configDir = actions.get_config_dir()
	-- if (actions.file_exists(configDir)) then return end
	-- actions.create_dir(configDir)
end

function actions.get_lua_dir()
    return string.format('%s\\overseer', mq.luaDir):gsub('\\', '/'):lower()
end

function actions.get_lua_file_path(filename)
    return string.format('%s/%s', actions.get_lua_dir(), filename)
end

function actions.get_config_dir()
    return string.format('%s\\overseer', mq.configDir):gsub('\\', '/'):lower()
end

function actions.get_config_file_path(filename)
    return string.format('%s\\%s', actions.get_config_dir(), filename)
end

function actions.get_root_config_dir()
    return string.format('%s', mq.configDir):gsub('\\', '/'):lower()
end

function actions.get_root_config_file_path(filename)
    return string.format('%s\\%s', actions.get_root_config_dir(), filename)
end

return actions