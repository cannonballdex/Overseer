local mq = require('mq')
local sqlite3 = require('lsqlite3')
local logger = require('utils.logger')
local io = require('utils.io_utils')
-- add near the top of the file with other module-level locals
local db -- explicit module-level DB handle
local db_path -- store the filesystem path opened by Initialize()




local actions = {}
--local db = {}   -- <- This has to be commented out or it don't konw the correct type.

local function initialize()
    -- initialize expects db to be set by Initialize()
    if not db then
        logger.error("DB initialize called but DB handle is nil")
        return
    end
    db:exec("PRAGMA journal_mode=WAL;")
end

local function create_tables()
    if not db then
        logger.error("create_tables called but DB handle is nil")
        return
    end

    db:exec [=[
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
end

local function to_quest_model(item)
    item.runOrder = 0
    item.experience = tonumber(item.experience)
    return item
end

local function start_transaction()
    if not db then
        logger.warning("start_transaction: DB handle is nil; skipping transaction")
        return
    end

    logger.trace('\ag Starting Transaction')
    local res = 0

    local waiting_counter = 0
    local waiting_max = 5000
    local waiting_amount = 250

    repeat
        res = db:exec("BEGIN IMMEDIATE TRANSACTION;")
        if res == sqlite3.BUSY then
            if (waiting_counter == 0) then
                logger.trace("\ayWaiting for DB Lock...")
            elseif (waiting_counter % waiting_max == 0) then
                logger.info("\ay Still waiting for DB lock...")
            end

            waiting_counter = waiting_counter + waiting_amount
            mq.delay(waiting_amount)
        end
    until res ~= sqlite3.BUSY

    logger.trace('\at * Acquired Transaction')
end

local function commit_transaction()
    if not db then
        logger.warning("commit_transaction: DB handle is nil; nothing to commit")
        return
    end
    -- Ensure commit comes after acquire
    mq.delay(1)
    db:exec("COMMIT TRANSACTION;")
    logger.trace("\agCommitted DB Transaction")
end

local function rollback_transaction()
    if not db then
        logger.warning("rollback_transaction: DB handle is nil; nothing to rollback")
        return
    end
    db:exec("ROLLBACK TRANSACTION;")
    logger.trace("\agDB Transaction Rolled Back")
end


local overseerquests_upsert =
'INSERT INTO OverseerQuests VALUES("%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", CURRENT_TIMESTAMP)  ON CONFLICT(name) DO UPDATE SET level=excluded.level, rarity=excluded.rarity, type=excluded.type, duration=excluded.duration, successRate=excluded.successRate, experience=excluded.experience, mercenaryAas=excluded.mercenaryAas, tetradrachms=excluded.tetradrachms, DateModified=excluded.DateModified;'

function actions.GetQuestDetails(questName)
    if not db then
        logger.error('DB: GetQuestDetails called but DB is not initialized; quest=%s', tostring(questName))
        return nil
    end

    local sql = string.format('select * from OverseerQuests where name="%s";', questName)

    logger.trace('DB: GetQuestDetails: '.. sql)
    for x in db:nrows(sql) do
        return to_quest_model(x)
    end

    return nil
end

function actions.UpdateQuestDetails(questName, quest)
    if not db then
        logger.error('DB: UpdateQuestDetails called but DB is not initialized; aborting update for %s', tostring(questName))
        return
    end

    start_transaction()

    local sql = string.format(overseerquests_upsert, questName, quest.level, quest.rarity, quest.type, quest.duration, quest.successRate, quest.experience, quest.mercenaryAas, quest.tetradrachms)
    logger.trace('DB: UpdateQuestDetails: '.. sql)
    if (db:exec(sql) ~= 0) then
        rollback_transaction()
        logger.error('Unable to save database record')
        logger.trace('DB: UpdateQuestDetails: '.. sql)
    else
        commit_transaction()
        logger.info('DB: Added %s', questName)
    end
end

function actions.Initialize()
    local data_dir = io.get_lua_file_path('data')
    io.ensure_dir(data_dir)

    -- determine paths
    local shared_path = data_dir .. '/overseer.db'

    -- get character clean name safely
    local char = 'unknown'
    if mq and mq.TLO and mq.TLO.Me and mq.TLO.Me.CleanName then
        local ok, cn = pcall(mq.TLO.Me.CleanName)
        if ok and cn and cn ~= '' then char = cn end
    end
    local perchar_path = string.format('%s/overseer_%s.db', data_dir, char)

    -- prefer per-character DB if it exists (falls back to shared)
    local chosen_path = shared_path
    if io.file_exists and io.file_exists(perchar_path) then
        chosen_path = perchar_path
        logger.info('Using per-character database: %s', tostring(perchar_path))
    else
        logger.info('Using shared database: %s', tostring(shared_path))
    end

    -- save path for external inspection and log it
    db_path = chosen_path
    logger.info('DB path chosen: %s', tostring(db_path))
    logger.info(string.format('DB: %s', tostring(db_path))) -- optional, prints to MQ console

    logger.trace('Opening database: %s', tostring(chosen_path))
    local ok, handle_or_err = pcall(function() return sqlite3.open(chosen_path) end)
    if not ok or not handle_or_err then
        logger.error('Failed to open database %s: %s', tostring(chosen_path), tostring(handle_or_err))
        return nil
    end

    db = handle_or_err

    -- PRAGMA and table setup; wrapped in pcall to avoid crashes bubbling up
    local ok_init, init_err = pcall(function()
        initialize()
        create_tables()
    end)
    if not ok_init then
        logger.error('Error during database initialization: %s', tostring(init_err))
    end

    logger.info('Database initialized: %s', tostring(chosen_path))
    logger.debug('Database handle: %s', tostring(db))

    return db
end
-- near the end of the file, before `return actions`, add:
function actions.GetDbPath()
    return db_path
end
return actions
