--- @type Mq
local mq = require('mq')
local logger = require('overseer.utils.logger')

local actions = {}
local useDelay = false
local delayMinMs = 0
local delayMaxMs = 0

local function Delay()
	if (useDelay ~= true or delayMinMs <= 0) then return end
	if (delayMaxMs < delayMinMs) then delayMaxMs = delayMinMs end
	local randomMs = delayMinMs + math.random() * (delayMaxMs - delayMinMs)

	mq.delay(randomMs)
end

function actions.InspectItem(itemName)
	local item = mq.TLO.FindItem(itemName)
	if (item.ID() == nil) then return end

	actions.CloseAllWindowsOfType('ItemDisplayWindow')
	item.Inspect()
	actions.WaitForWindow('ItemDisplayWindow')
end

function actions.CloseAllWindowsOfType(window_name)
	while(mq.TLO.Window(window_name).Open() == true) do
		mq.TLO.Window(window_name).DoClose()
		mq.delay(100, function() return mq.TLO.Window(window_name).Open() == false end)
	end
end

function actions.set_delays(newUseDelay, minDelay, maxDelay)
	useDelay = newUseDelay
	delayMinMs = minDelay
	delayMaxMs = maxDelay

	if (useDelay ~= true or delayMinMs == 0) then return end

	logger.info('UI Delays Enabled: \ay%d \ao-\ay %d', minDelay, maxDelay)
	math.randomseed(os.clock()*math.random(15020209090,95020209090))
end

function actions.action(action)
	Delay()
	action()
end

function actions.autoinventory(wait_for_cursor_item)
	if (wait_for_cursor_item == true) then
		mq.delay(1000, function() return mq.TLO.Cursor.ID() ~= nil end)
	end

	while(mq.TLO.Cursor.ID() ~= nil) do
		actions.cmd('/autoinv')
		mq.delay(100, function() return mq.TLO.Cursor.ID() == nil end)
	end
end

function actions.leftmouseup(window_name)
	Delay()
	mq.TLO.Window(window_name).LeftMouseUp()
end

function actions.cmd(command)
	Delay()
	mq.cmd(command)
end

function actions.cmdf(command, ...)
	Delay()
	mq.cmdf(command, ...)
end

function actions.notify(command)
	Delay()
	mq.cmd.notify(command)
end

function actions.notifyf(command, ...)
	Delay()
	mq.cmdf.notify(command, ...)
end

function actions.click_confirmation_yes()
	actions.WaitForWindow('ConfirmationDialogBox')
	actions.cmd('/yes')
end

function actions.WaitForWindow(window_name, delay_time)
	if (delay_time == nil) then delay_time = 5000 end
	mq.delay(delay_time, function() return mq.TLO.Window(window_name).Open() end)
end

return actions
