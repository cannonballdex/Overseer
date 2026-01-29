local mq = require('mq')

-- try to load optional libs but don't fail startup if unavailable
pcall(require, 'lfs')
pcall(require, 'lsqlite3')

local logger = (pcall(require, 'utils/logger') and require('utils/logger')) or { info = print, warn = print, error = print }

local db = require('overseer.database')
local settings = require('overseer.overseer_settings')
local overseer = require('overseer.overseer')
local ui = require('overseer.overseerui')

-- safe TLO level check
local function get_me_level()
  local ok, lvl = pcall(function() return mq.TLO.Me.Level() end)
  return tonumber(lvl) or 0
end

if get_me_level() < 85 then
  logger.error('Overseer requires level 85+ to initiate. Ending script.')
  return
end

local args = {...}
local no_run = args[1] == 'no_run' or args[1] == '--no-run'

db.Initialize()
settings.InitializeOverseerSettings(no_run)

-- Ensure Settings.General.showUi exists and default to true
_G.Settings = rawget(_G, 'Settings') or {}
_G.Settings.General = _G.Settings.General or {}
if type(_G.Settings.General.showUi) ~= 'boolean' then
  _G.Settings.General.showUi = true
end

-- initialize UI (protected) and then register commands that rely on Settings/UI
local ok_ui, err_ui = xpcall(function() ui.InitializeUi(_G.Settings.General.showUi) end, debug.traceback)
if not ok_ui then logger.error('ui.InitializeUi failed: ' .. tostring(err_ui)) end

require 'overseer.overseer_settings_commands' -- register /mqoverseer after UI ready
logger.info('Toggle UI: /mqoverseer show or /mqoverseer hide')

-- run main safely
local ok_overseer, err_overseer = xpcall(overseer.Main, debug.traceback)
if not ok_overseer then logger.error('Error in overseer.Main: ' .. tostring(err_overseer)) end

-- main loop (localized functions)
local mq_delay, mq_doevents = mq.delay, mq.doevents
while Open do
  mq_delay(500)
  mq_doevents()
end
