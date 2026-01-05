local function ensure_package(package_name, require_name)
    local status, lib = pcall(require, require_name)
    if status then
        return lib
    end

    local packageMan = require('mq/PackageMan')
    return packageMan.InstallAndLoad(package_name, require_name)
end

ensure_package('luafilesystem', 'lfs')
ensure_package('lsqlite3', 'lsqlite3')

--- @type Mq
local mq = require('mq')
local db = require('overseer.database')
local settings = require 'overseer.overseer_settings'
local overseer = require 'overseer.overseer'
local ui = require 'overseer.overseerui'
local logger = require('utils/logger')
require 'overseer.overseer_settings_commands'

if (mq.TLO.Me.Level() < 85) then
    logger.error('Overseer requires level 85+ to initiate. Ending script.')
    return
end

local args = {...}
local no_run = args[1] == 'no_run'

db.Initialize()

settings.InitializeOverseerSettings(no_run)

ui.InitializeUi(Settings.General.showUi)
overseer.Main()

while Open do
    mq.delay(500)
    mq.doevents()
end
