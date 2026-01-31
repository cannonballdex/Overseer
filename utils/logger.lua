--- @type Mq
local mq = require('mq')

local actions = {}

-- TODO: Determine name automatically
local app_name = 'Overseer'
local logLeader = '\ar[\ag'..app_name..'.lua\ar]\aw '

--- Initialize log level:
-- If Settings.General.logLevel already exists (saved preference), honor it.
-- Otherwise default to Off (1) to avoid noisy trace output during startup.
local logLevel = 1
if type(_G.Settings) == 'table' and _G.Settings.General and type(_G.Settings.General.logLevel) == 'number' then
    logLevel = _G.Settings.General.logLevel
end

function actions.get_log_level() return logLevel end

function actions.set_log_level(level) logLevel = level end

function actions.error(format, ...)
	if (logLevel < 2) then
		return
	end
    local output = string.format(format, ...)
	mq.parse(string.format('/mqlog [%s] %s', mq.TLO.Me.Name(), output))
	printf('%s \ar %s', logLeader, output)
end

function actions.warning(format, ...)
	if (logLevel < 3) then
		return
	end
    local output = string.format(format, ...)
	mq.parse(string.format('/mqlog [%s] %s', mq.TLO.Me.Name(), output))
	printf('%s \aw %s', logLeader, output)
end

function actions.info(format, ...)
	if (logLevel < 4) then
		return
	end
    local output = string.format(format, ...)
	mq.parse(string.format('/mqlog [%s] %s', mq.TLO.Me.Name(), output))
	printf('%s \ao %s', logLeader, output)
end

function actions.debug(format, ...)
	if (logLevel < 5) then
		return
	end
    local output = string.format(format, ...)
	mq.cmd(string.format('/mqlog [%s] %s', mq.TLO.Me.Name(), output))
	printf('%s \ag %s', logLeader, output)
end

function actions.trace(format, ...)
	if (logLevel < 6) then
		return
	end
    local output = string.format(format, ...)
	mq.cmd(string.format('/mqlog [%s] %s', mq.TLO.Me.Name(), output))
	printf('%s \ay %s', logLeader, output)
end

function actions.output_test_logs()
	actions.error("Test Error")
	actions.warning("Test Warning")
	actions.info("Test Normal")
	actions.debug("Test Debug")
	actions.trace("Test Trace")
end

-- Alias common require names to ensure there's only one logger instance.
local _aliases = {
	'utils/logger',
	'utils.logger',
	'overseer.utils.logger',
	'overseer/utils/logger',
	'overseer.logger',
	'overseer/logger',
}
for _, name in ipairs(_aliases) do
	if not package.loaded[name] then
		package.loaded[name] = actions
	end
end

return actions
