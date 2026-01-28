local mq = require('mq')
local sqlite3 = require('lsqlite3')
local logger = require('utils.logger')
local io = require('utils.io_utils')

local actions = {}

---@type any
local db = nil

local function initialize()
    if not db then
        logger.error('Database not initialized')
        return false
    end
    
    local result = db:exec("PRAGMA journal_mode=WAL;")
    if result ~= sqlite3.OK then
        logger.error('Failed to enable WAL mode')
        return false
    end
    
    return true
end

local function create_tables()
    if not db then
        logger.error('Database not initialized')
        return false
    end
    
    local result = db:exec [=[
        CREATE TABLE IF NOT EXISTS "OverseerQuests" (
            "name"	TEXT NOT NULL UNIQUE,
            "level"	TEXT NOT NULL,
            "rarity"	TEXT NOT NULL,
            "type"	TEXT NOT NULL,
            "duration"	TEXT NOT NULL,
            "successRate"	TEXT,
            "experience"	TEXT,
            "mercenaryAas"	TEXT,
            "tetradrachms"	TEXT,
            "DateModified"	DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY("name")
        );
    ]=]
    
    if result ~= sqlite3.OK then
        logger.error('Failed to create tables: %s', db:errmsg())
        return false
    end
    
    return true
end

local function to_quest_model(item)
    item.runOrder = 0
    item.available = true
    item.experience = tonumber(item.experience) or 0
    item.mercenaryAas = tonumber(item.mercenaryAas) or 0
    item.tetradrachms = tonumber(item.tetradrachms) or 0
    item.level = tonumber(item.level) or 0
    return item
end

local function start_transaction()
    if not db then 
        logger.error('Database not initialized, cannot start transaction')
        return false
    end

    logger.trace('Starting Transaction')
    local res = 0
    
    local waiting_counter = 0
    local waiting_max = 15000  -- 15 seconds
    local waiting_amount = 250

    repeat
        res = db:exec("BEGIN IMMEDIATE TRANSACTION;")
        if res == sqlite3.BUSY then
            if waiting_counter == 0 then
                logger.trace("Waiting for DB Lock...")
            elseif waiting_counter % 2500 == 0 then
                logger.info("Still waiting for DB lock... (%d seconds)", waiting_counter / 1000)
            end

            waiting_counter = waiting_counter + waiting_amount
            
            if waiting_counter >= waiting_max then
                logger.error("Database lock timeout after %d seconds!", waiting_max / 1000)
                return false
            end
            
            mq.delay(waiting_amount)
        end
    until res ~= sqlite3.BUSY

    logger.trace('Acquired Transaction')
    return true
end

local function commit_transaction()
    if not db then return end
    mq.delay(1)
    local result = db:exec("COMMIT TRANSACTION;")
    if result == sqlite3.OK then
        logger.trace("Committed DB Transaction")
    else
        logger.error("Failed to commit transaction: %s", db:errmsg())
    end
end

local function rollback_transaction()
    if not db then return end
    local result = db:exec("ROLLBACK TRANSACTION;")
    if result == sqlite3.OK then
        logger.trace("DB Transaction Rolled Back")
    else
        logger.error("Failed to rollback transaction: %s", db:errmsg())
    end
end

local overseerquests_upsert =
'INSERT INTO OverseerQuests VALUES("%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", CURRENT_TIMESTAMP) ' ..
'ON CONFLICT(name) DO UPDATE SET ' ..
'level=excluded.level, ' ..
'rarity=excluded.rarity, ' ..
'type=excluded.type, ' ..
'duration=excluded.duration, ' ..
'successRate=excluded.successRate, ' ..
'experience=excluded.experience, ' ..
'mercenaryAas=excluded.mercenaryAas, ' ..
'tetradrachms=excluded.tetradrachms, ' ..
'DateModified=excluded.DateModified;'

function actions.GetQuestDetails(questName)
    if not db then
        logger.error('Database not initialized')
        return nil
    end

    local safeName = questName:gsub("'", "''"):gsub('"', '""')
    local sql = string.format('SELECT * FROM OverseerQuests WHERE name="%s";', safeName)

    logger.trace('DB: GetQuestDetails: %s', sql)
    
    for x in db:nrows(sql) do
        return to_quest_model(x)
    end

    return nil
end

function actions.UpdateQuestDetails(questName, quest)
    if not db then
        logger.error('Database not initialized')
        return
    end

    if not start_transaction() then
        logger.error('Failed to start transaction for %s', questName)
        return
    end

    local safeName = (questName or ''):gsub("'", "''"):gsub('"', '""')
    local safeLevel = tostring(quest.level or '')
    local safeRarity = tostring(quest.rarity or '')
    local safeType = tostring(quest.type or '')
    local safeDuration = tostring(quest.duration or '')
    local safeSuccessRate = tostring(quest.successRate or '0%')
    local safeExperience = tostring(quest.experience or 0)
    local safeMercenaryAas = tostring(quest.mercenaryAas or 0)
    local safeTetradrachms = tostring(quest.tetradrachms or 0)

    local sql = string.format(overseerquests_upsert, 
        safeName, 
        safeLevel, 
        safeRarity, 
        safeType, 
        safeDuration, 
        safeSuccessRate, 
        safeExperience, 
        safeMercenaryAas, 
        safeTetradrachms
    )
    
    logger.trace('DB: UpdateQuestDetails: %s', sql)
    
    local result = db:exec(sql)
    if result ~= sqlite3.OK then
        rollback_transaction()
        logger.error('Unable to save database record for %s (error: %d)', questName, result)
        logger.error('SQL: %s', sql)
        logger.error('DB Error: %s', db:errmsg())
    else
        commit_transaction()
        logger.debug('DB: Added/Updated %s', questName)
    end
end

function actions.Initialize()
    local data_dir = io.get_lua_file_path('data')
    
    -- ✅ Ensure directory exists (but don't fail if ensure_dir has issues)
    local lfs = require('lfs')
    local attr = lfs.attributes(data_dir)
    
    if not attr then
        -- Directory doesn't exist, try to create it
        logger.debug('Data directory does not exist, creating: %s', data_dir)
        local success, err = lfs.mkdir(data_dir)
        if not success then
            logger.error('Failed to create data directory: %s (error: %s)', data_dir, err or 'unknown')
            return nil
        end
        logger.debug('Data directory created successfully')
    elseif attr.mode ~= 'directory' then
        logger.error('Data path exists but is not a directory: %s', data_dir)
        return nil
    end
    
    local char_name = mq.TLO.Me.CleanName()
    if not char_name or char_name == '' then
        logger.error('Unable to get character name')
        return nil
    end
    
    -- ✅ Per-character database (no locking issues with multiple characters)
    local path = data_dir .. '/overseer_' .. char_name .. '.db'
    
    logger.trace('Opening database: %s', path)
    
    db = sqlite3.open(path)
    
    if not db then
        logger.error('Failed to open database at %s', path)
        return nil
    end

    if not initialize() then
        db:close()
        db = nil
        return nil
    end
    
    if not create_tables() then
        db:close()
        db = nil
        return nil
    end

    logger.info('Database initialized for %s', char_name)
    return db
end

function actions.Cleanup()
    if db then
        local result = db:close()
        if result == sqlite3.OK then
            logger.info('Database closed successfully')
        else
            logger.warning('Database close returned code: %d', result)
        end
        db = nil
    end
end

return actions
