-- overseer/utils/ui.lua
-- Defensive UI / window helper utilities for Overseer

local mq = require('mq')
local mqutils = require('utils.mq_utils')

-- Resolve a logger: prefer explicit module, then _G.logger, then no-op
local logger
do
    local ok, mod = pcall(require, 'utils.logger')
    if ok and mod then
        logger = mod
    else
        logger = (_G and _G.logger) or {
            trace = function() end,
            debug = function() end,
            info = function() end,
            warning = function() end,
            error = function() end,
        }
    end
end

local M = {}

-- Allow overseer.lua (or other startup code) to inject the real logger
function M.set_logger(l)
    if l and type(l) == 'table' then logger = l end
end

-- Click an available quest node and wait until the title updates
function M.SelectAvailableQuestNode(NODE)
    if not NODE then return false end

    mqutils.safe_call(function() NODE.Child('OW_BtnQuestTemplate').LeftMouseUp() end)

    return mqutils.delay(1000, function()
        local a = mqutils.safe_call(function() return NODE.Child('OW_BtnQuestTemplate').Text() end)
        local b = mqutils.safe_call(function() return mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_TitleLabel').Text() end)
        if a and b then return a == b end
        return false
    end)
end

-- Click an active quest node and wait until the quest name reflects the active quest
function M.SelectActiveQuestNode(NODE)
    if not NODE then return false end

    mqutils.safe_call(function() NODE.Child('OW_BtnQuestTemplate').LeftMouseUp() end)

    return mqutils.delay(1000, function()
        local a = mqutils.safe_call(function() return NODE.Child('OW_BtnQuestTemplate').Text() end)
        local b = mqutils.safe_call(function() return mq.TLO.Window(CurrentQuestName).Text() end)
        if a and b then return a == b end
        return false
    end)
end

function M.IsOverseerWindowOpen()
    local open = mqutils.safe_call(function() return mq.TLO.Window('OverseerWnd').Open() end)
    return open == true
end

function M.OpenOverseerWindowLight()
    if not M.IsOverseerWindowOpen() then mq.cmd('/overseer') end
end

function M.OpenOverseerWindow()
    if M.IsOverseerWindowOpen() then return end

    local loopCount = 1
    ::loop::
    mq.cmd('/overseer')
    mq.doevents()
    if not M.IsOverseerWindowOpen() then mq.delay(4000) end

    mq.doevents()

    local isOpen = mqutils.safe_call(function() return mq.TLO.Window('OverseerWnd').Open() end)
    if not isOpen then
        if loopCount > 10 then
            logger.error('[ERROR] Cannot open OverseerWnd.  Ending.')
            return
        end
        loopCount = loopCount + 1
        logger.warning('[WARNING] ...waiting for Overseer system to initialize.')
        goto loop
    end
end

function M.CloseOverseerWindowLight()
    if M.IsOverseerWindowOpen() then mq.cmd('/overseer') end
end

function M.CloseOverseerWindow()
    ::closeWindow::
    if M.IsOverseerWindowOpen() then mq.cmd('/overseer') end

    if M.IsOverseerWindowOpen() then
        mq.cmd('/overseer')
        mq.doevents()
        local closed = mqutils.delay(2000, function() return M.IsOverseerWindowOpen() == false end)
        if not closed then
            logger.warning("[WARNING] OverseerWnd did not close within 2s; continuing anyway")
        end
    end

    if M.IsOverseerWindowOpen() then goto closeWindow end
end

return M