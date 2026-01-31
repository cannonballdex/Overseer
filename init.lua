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

local sqlite3 = require('lsqlite3')
--- @type Mq
local db = require('overseer.database')
local settings = require 'overseer.overseer_settings'
local overseer = require 'overseer.overseer'
local ui = require 'overseer.overseerui'
local logger = require('overseer.utils.logger')
require 'overseer.overseer_settings_commands'
local lfs = require('lfs')
local io_utils = require('overseer.utils.io_utils') -- if present, otherwise build path manually
local mq = require('mq')

local data_dir = io_utils.get_lua_file_path('data') -- adjust if your utils differ
local shared = data_dir .. '/overseer.db'
local char = mq.TLO.Me.CleanName() or 'unknown'
local dest = string.format("%s/overseer_%s.db", data_dir, char)
logger.info("package.loaded['database'] = %s, package.loaded['overseer.database'] = %s",
    tostring(package.loaded['database'] ~= nil), tostring(package.loaded['overseer.database'] ~= nil))
-- Utility: copy file in chunks (portable)
local function copy_file(src, dst)
  local inFile = io.open(src, "rb")
  if not inFile then return false, "open src failed" end
  local outFile = io.open(dst, "wb")
  if not outFile then inFile:close(); return false, "open dst failed" end
  while true do
    local block = inFile:read(8192)
    if not block then break end
    outFile:write(block)
  end
  inFile:close(); outFile:close()
  return true
end

-- Utility: get number of quest rows in a DB file (returns count or nil and an error string)
local function get_quest_count(dbpath)
  local ok, sdb = pcall(function() return sqlite3.open(dbpath) end)
  if not ok or not sdb then
    return nil, "open_failed"
  end

  local count = nil
  local ok2, err = pcall(function()
    for row in sdb:nrows("SELECT count(*) AS cnt FROM OverseerQuests;") do
      count = tonumber(row.cnt) or 0
      break
    end
  end)
  sdb:close()
  if not ok2 then
    return nil, "query_failed"
  end
  return count, nil
end

-- Decide whether to copy shared -> per-character DB
local function ensure_perchar_db()
  -- Ensure data directory exists
  local attr = lfs.attributes(data_dir)
  if not attr then
    logger.info("Data directory missing; creating: %s", tostring(data_dir))
    local ok, err = lfs.mkdir(data_dir)
    if not ok then
      logger.error("Failed to create data directory %s: %s", tostring(data_dir), tostring(err))
      return false
    end
  elseif attr.mode ~= 'directory' then
    logger.error("Data path exists but is not a directory: %s", tostring(data_dir))
    return false
  end

  -- If destination doesn't exist -> copy if shared present
  local dest_attr = lfs.attributes(dest)
  if not dest_attr then
    local shared_attr = lfs.attributes(shared)
    if not shared_attr then
      logger.info("Shared DB not found (%s). Will not copy; per-character DB will be created by database module.", tostring(shared))
      return true
    end

    local ok, err = copy_file(shared, dest)
    if ok then
      logger.info("Copied shared DB to: %s", tostring(dest))
      return true
    else
      logger.error("Copy failed from %s to %s: %s", tostring(shared), tostring(dest), tostring(err))
      return false
    end
  end

  -- dest exists: attempt to read counts for both files
  local dest_count, dest_err = get_quest_count(dest)
  local shared_count, shared_err = get_quest_count(shared)

  if dest_count == nil then
    logger.info("Could not determine contents of per-character DB (%s): %s. Leaving file intact.", tostring(dest), tostring(dest_err))
    return true
  end

  if shared_count == nil then
    logger.info("Shared DB not available or unreadable (%s): %s. Will not overwrite per-character DB.", tostring(shared), tostring(shared_err))
    return true
  end

  -- If per-character DB has greater-than OR EQUAL rows compared to shared DB, do not overwrite
  if dest_count >= shared_count then
    logger.info("Database is up to date (%s) has (%d) and main DB (%d) rows.", tostring(dest), dest_count, shared_count)
    logger.debug("Per-character DB (%s) has (%d) and shared DB (%d) rows. Skipping copy to avoid data loss.", tostring(dest), dest_count, shared_count)
    return true
  end

  -- At this point dest_count < shared_count -> overwrite by copying shared
  local ok, err = copy_file(shared, dest)
  if ok then
    logger.info("Copied shared DB to per-character DB (overwrote): %s", tostring(dest))
    return true
  else
    logger.error("Failed to copy shared DB into per-character DB: %s", tostring(err))
    return false
  end
end

-- Only attempt the copy/ensure once at startup
local ok_ensure = ensure_perchar_db()
if not ok_ensure then
  logger.error("Failed to ensure per-character DB. Aborting startup.")
  return
end

-- Basic level check
if (mq.TLO.Me.Level() < 85) then
    logger.error('Overseer requires level 85+ to initiate. Ending script.')
    return
end

local args = {...}
local no_run = args[1] == 'no_run'

-- Initialize database and then the rest of the system
local initialized = db.Initialize()
if not initialized then
  logger.error("Database initialization failed. Aborting startup.")
  return
end

settings.InitializeOverseerSettings(no_run)

ui.InitializeUi(Settings.General and Settings.General.showUi)
overseer.Main()

while Open do
    mq.delay(500)
    mq.doevents()
end
