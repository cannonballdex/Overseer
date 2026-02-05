-- utils/claim_utils.lua
-- Helpers for claiming rewards and ensuring items placed on the cursor are moved to inventory.

local mq = require('mq')
local mqutils = require('utils.mq_utils')
local logger = require('utils.logger')

local claim_utils = {}

local function safe_cursor()
    local ok_id, id = pcall(function() return mq.TLO.Cursor.ID() end)
    local ok_name, name = pcall(function() return mq.TLO.Cursor.Name() end)
    return (ok_id and id) or nil, (ok_name and name) or nil
end

local function poll_for_cursor(timeout_s, interval_s)
    timeout_s = timeout_s or 3.0
    interval_s = interval_s or 0.08
    local start = os.clock()
    while (os.clock() - start) < timeout_s do
        local id, name = safe_cursor()
        if id and id ~= 0 then
            return id, name
        end
        if mq and type(mq.doevents) == 'function' then pcall(mq.doevents) end
        local t0 = os.clock()
        while os.clock() - t0 < interval_s do end
    end
    return nil, nil
end

local function clear_cursor_with_autoinv()
    -- Prefer the robust helper; it will wait for cursor item and attempt clear
    local ok = pcall(function() mqutils.autoinventory(true) end)
    if ok then
        local id = (pcall(function() return mq.TLO.Cursor.ID() end) and mq.TLO.Cursor.ID()) or nil
        if not id or id == 0 then return true end
    end

    -- Fallback single /autoinv
    pcall(function() mq.cmd('/autoinv') end)
    if mq and mq.delay then mq.delay(300) end
    local id2 = (pcall(function() return mq.TLO.Cursor.ID() end) and mq.TLO.Cursor.ID()) or nil
    if not id2 or id2 == 0 then return true end

    -- If ItemDisplayWindow might be blocking, close it and retry
    local ok_win, win_open = pcall(function() return mq.TLO.Window('ItemDisplayWindow').Open() end)
    if ok_win and win_open then
        pcall(function() mq.cmd('/windowstate ItemDisplayWindow close') end)
        if mq and mq.delay then mq.delay(200) end
        pcall(function() mq.cmd('/autoinv') end)
        if mq and mq.delay then mq.delay(300) end
    end

    local final_id = (pcall(function() return mq.TLO.Cursor.ID() end) and mq.TLO.Cursor.ID()) or nil
    return not (final_id and final_id ~= 0)
end

-- Collect (claim) a single reward option and ensure cursor item is handled
function claim_utils.collect_reward_option(option, rewardItem, rewardOptionName, rewardIndex, opts)
    opts = opts or {}
    local poll_timeout = opts.poll_timeout or 3.0

    -- selection/retry logic (preserves previous behavior)
    local retry_attempts = 1

    ::retryOptionClaim::
    pcall(function() option.Select() end)
    logger.info('[INFO] Claiming %s (%s)', tostring(option and option.Text and option:Text() or "<option>"),
                tostring(rewardItem and rewardItem.Text and rewardItem:Text() or "<reward>"))
    mq.delay(2000, function() return option.Selected() == true and option.Text() == rewardOptionName end)

    if (option.Selected() == false or option.Text() ~= rewardOptionName) then
        if (retry_attempts <= 0) then
            if logger and logger.warning then pcall(logger.warning, '[WARNING] Unable to select option: %s', tostring(rewardOptionName)) end
            return false
        end

        retry_attempts = retry_attempts - 1
        if logger and logger.info then pcall(logger.info, '[INFO] Option selection issue. Attempting again for %s', tostring(rewardOptionName)) end
        mqutils.action(mq.TLO.Rewards.Reward(rewardIndex).Option(rewardOptionName).Select)
        goto retryOptionClaim
    elseif (option.Text() ~= rewardOptionName) then
        if logger and logger.info then pcall(logger.info, '[INFO] Incorrect option selected (%s). Skipping.', tostring(option.Text())) end
        return false
    end

    -- Claim and give MQ a tick to process
    pcall(function() rewardItem.Claim() end)
    if mq and type(mq.doevents) == 'function' then pcall(mq.doevents) end

    -- Poll deterministically for cursor item
    local id, name = poll_for_cursor(poll_timeout)
    if not id then
        if logger and logger.debug then pcall(logger.debug, '[DEBUG] No item placed on cursor after claim; skipping autoinventory') end
        return true
    end

    if logger and logger.debug then pcall(logger.debug, '[DEBUG] Cursor after claim: ID=%s Name=%s', tostring(id), tostring(name)) end

    -- Attempt to clear cursor with helper + fallbacks
    local cleared = clear_cursor_with_autoinv()
    if not cleared then
        local fid, fname = safe_cursor()
        if logger and logger.warning then pcall(logger.warning, '[WARNING] collect_reward_option: cursor still holds item after fallbacks (Cursor.ID=%s, Name=%s)', tostring(fid), tostring(fname)) end
    end

    return true
end

return claim_utils