local mq = require('mq')
local sqlite3 = require('lsqlite3')
local logger = require('utils.logger')
local io = require('utils.io_utils')

local actions = {}
--local db = {}   -- <- This has to be commented out or it don't konw the correct type.

local function initialize()
    db:exec("PRAGMA journal_mode=WAL;")
end

local function create_tables()
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
    if not db then return end

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
    if not db then return end
    -- Ensure commit comes after acquire
    mq.delay(1)
    db:exec("COMMIT TRANSACTION;")
    logger.trace("\agCommitted DB Transaction")
end

local function rollback_transaction()
    if not db then return end
    db:exec("ROLLBACK TRANSACTION;")
    logger.trace("\agDB Transaction Rolled Back")
end


local overseerquests_upsert =
'INSERT INTO OverseerQuests VALUES("%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s", CURRENT_TIMESTAMP)  ON CONFLICT(name) DO UPDATE SET level=excluded.level, rarity=excluded.rarity, type=excluded.type, duration=excluded.duration, successRate=excluded.successRate, experience=excluded.experience, mercenaryAas=excluded.mercenaryAas, tetradrachms=excluded.tetradrachms, DateModified=excluded.DateModified;'

function actions.GetQuestDetails(questName)
    local sql = string.format('select * from OverseerQuests where name="%s";', questName)

    logger.trace('DB: GetQuestDetails: '.. sql)
    for x in db:nrows(sql) do
        return to_quest_model(x)
    end

    return nil
end

function actions.UpdateQuestDetails(questName, quest)
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
    local path = data_dir .. '/overseer.db'

    logger.trace('Opening database: \ao%s', path)
    db = sqlite3.open(path)

    initialize()
    create_tables()

    return db
end

return actions
