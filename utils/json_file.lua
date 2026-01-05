local Json = require("utils/json")
local ioutil = require('utils/io_utils')

local json_file = {}

json_file.saveTable = function(t, fileName)
  local filePath = ioutil.get_lua_file_path(fileName)
  local file = io.open(filePath, "w")

  if file then
    local contents = Json.encode(t)
    file:write(contents)
    io.close(file)
    return true
  else
    return false
  end
end

json_file.loadTable = function(fileName)
  local filePath = ioutil.get_lua_file_path(fileName)
  local myTable = {}
  local file = io.open(filePath, "r")

  if file then
    -- read all contents of file into a string
    local contents = file:read("*a")
    myTable = Json.decode(contents);
    io.close(file)
    return myTable
  end

  return nil
end

return json_file
