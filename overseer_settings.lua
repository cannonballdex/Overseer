-- Minimized & hardened version of overseer settings
--- @type Mq
local mq = require('mq')
local utils = require('utils.string_utils')
local io = require('utils.io_utils')
local logger = require('utils.logger')
local legacyConfig = require('overseer_settings_legacy')
local json_file = require('utils.json_file')
local mqutils = require('utils.mq_utils')
require('utils.persistence')

local actions = {}

local Version = '3.78'
local MyIni = 'Overseer.lua'

actions.InTestMode = false
--- @type boolean
actions.Initialized = false
--- @type string
actions.AllQuestTypes = legacyConfig.AllQuestTypes

-- Identifies character script was run against.
--- @type string
TrackingCharacter = ''

--- @type string
actions.ConfigurationType = ''

--- @type string
actions.ConfigurationSource = ''

SettingsTemp = {}

-- Helper: safe persistence save (guards MyIniPath / persistence availability)
function actions.SaveSettings()
	if not MyIniPath or type(persistence) ~= 'table' or type(persistence.store) ~= 'function' then return end
	persistence.store(MyIniPath, Settings)
end

-- Collection helpers (robust against nil / missing index)
local function ensure_collection_index(collection)
	if not collection then return nil end
	collection.index = collection.index or 0
	return collection
end

local function ReorderCollectionUp(collection, index)
	if not collection or not collection.index or index <= 1 or index > collection.index then return index end
	collection[index], collection[index - 1] = collection[index - 1], collection[index]
	actions.SaveSettings()
	return index - 1
end

local function ReorderCollectionDown(collection, index)
	if not collection or not collection.index or index < 1 or index >= collection.index then return index end
	collection[index], collection[index + 1] = collection[index + 1], collection[index]
	actions.SaveSettings()
	return index + 1
end

local function AddCollectionItem(collection, name)
	if not collection then return end
	collection.index = (collection.index or 0) + 1
	collection[collection.index] = name
	actions.SaveSettings()
end

local function RemoveCollectionItem(collection, index)
	if not collection or not collection.index or index < 1 or index > collection.index then return end
	for i = index, collection.index - 1 do
		collection[i] = collection[i + 1]
	end
	collection[collection.index] = nil
	collection.index = collection.index - 1
	actions.SaveSettings()
end

-- Exposed wrappers (preserve API)
function actions.ReorderRewardUp(index) return ReorderCollectionUp(Settings.Rewards, index) end
function actions.ReorderRewardDown(index) return ReorderCollectionDown(Settings.Rewards, index) end
function actions.AddActiveReward(name) AddCollectionItem(Settings.Rewards, name) end
function actions.RemoveActiveReward(index) RemoveCollectionItem(Settings.Rewards, index) end
function actions.ReorderSpecifiedQuestsUp(index) return ReorderCollectionUp(Settings.SpecificQuests, index) end
function actions.ReorderSpecifiedQuestsDown(index) return ReorderCollectionDown(Settings.SpecificQuests, index) end

local function GetSpecificCollectionIndexByValue(collection, name)
	if not collection or not collection.index then return -1 end
	for i = 1, collection.index do
		if collection[i] == name then return i end
	end
	return -1
end

local function HasSpecificQuest(collection, name)
	return GetSpecificCollectionIndexByValue(collection, name) > -1
end

function actions.AddSpecifiedQuest(name)
	if not Settings.SpecificQuests then
		Settings.SpecificQuests = { index = 0 }
	end
	if HasSpecificQuest(Settings.SpecificQuests, name) then return end
	AddCollectionItem(Settings.SpecificQuests, name)
end

function actions.RemoveSpecifiedQuest(index)
	RemoveCollectionItem(Settings.SpecificQuests, index)
end

-- EnsureExists returns true if already existed, false if created
local function EnsureExists(section, key, default)
	Settings[section] = Settings[section] or {}
	if Settings[section][key] == nil then
		Settings[section][key] = default
		return false
	end
	return true
end

-- has_item: used for splitting legacy pipe lists
local function has_item(array, itemName)
	if not array then return false end
	for _, v in ipairs(array) do
		if v == itemName then return true end
	end
	return false
end

-- concatenate helper: build legacy pipe-delimited strings
local function concatenate(value, source, expected, isFirst)
	if (not value or not expected or value ~= true) then return source, isFirst end
	if (not source or isFirst == true) then return expected, false end
	return source .. '|' .. expected, false
end

local function get_questpriority_sections(priorityName)
	local legacySectionName = "QuestPriority"
	if (priorityName ~= "Default") then
		legacySectionName = "QuestPriority_" .. priorityName
	end
	local old = Settings[legacySectionName]
	if (old == nil) then
		logger.error('** Legacy QuestPriority Group (%s) Not Found **', legacySectionName)
		return nil, nil
	end

	if (SettingsTemp.QuestPriorities == nil) then
		logger.error('** Temp Settings Not Set**')
		return nil, nil
	end
	local new = SettingsTemp.QuestPriorities[priorityName]
	if (not new) then
		logger.error('** QuestPriority Group Not Found **')
		return nil, nil
	end

	return old, new
end

local function save_quest_priority_types(old, new)
	if (not old or not new) then return end
	local isFirst = true
	old.Types = ""
	old.Types, isFirst = concatenate(new.types.exploration, old.Types, "Exploration", isFirst)
	old.Types, isFirst = concatenate(new.types.diplomacy, old.Types, "Diplomacy", isFirst)
	old.Types, isFirst = concatenate(new.types.trade, old.Types, "Trade", isFirst)
	old.Types, isFirst = concatenate(new.types.plunder, old.Types, "Plunder", isFirst)
	old.Types, isFirst = concatenate(new.types.military, old.Types, "Military", isFirst)
	old.Types, isFirst = concatenate(new.types.stealth, old.Types, "Stealth", isFirst)
	old.Types, isFirst = concatenate(new.types.research, old.Types, "Research", isFirst)
	old.Types, isFirst = concatenate(new.types.crafting, old.Types, "Crafting", isFirst)
	old.Types, _ = concatenate(new.types.harvesting, old.Types, "Harvesting", isFirst)
end

local function save_quest_priority_rarities(old, new)
	if (not old or not new) then return end
	local isFirst = true
	old.Rarities = ""
	old.Rarities, isFirst = concatenate(new.rarities.elite, old.Rarities, "Elite", isFirst)
	old.Rarities, isFirst = concatenate(new.rarities.rare, old.Rarities, "Rare", isFirst)
	old.Rarities, isFirst = concatenate(new.rarities.uncommon, old.Rarities, "Uncommon", isFirst)
	old.Rarities, isFirst = concatenate(new.rarities.common, old.Rarities, "Common", isFirst)
	old.Rarities, _ = concatenate(new.rarities.easy, old.Rarities, "Easy", isFirst)
end

local function save_quest_priority_durations(old, new)
	if (not old or not new) then return end
	local isFirst = true
	old.Durations = ""
	old.Durations, isFirst = concatenate(new.durations.h3, old.Durations, "3h", isFirst)
	old.Durations, isFirst = concatenate(new.durations.h6, old.Durations, "6h", isFirst)
	old.Durations, isFirst = concatenate(new.durations.h12, old.Durations, "12h", isFirst)
	old.Durations, isFirst = concatenate(new.durations.h24, old.Durations, "24h", isFirst)
	old.Durations, _ = concatenate(new.durations.h36, old.Durations, "36h", isFirst)
end

local function save_quest_priority_levels(old, new)
	if (not old or not new) then return end
	local isFirst = true
	old.Levels = ""
	old.Levels, isFirst = concatenate(new.levels.level5, old.Levels, "5", isFirst)
	old.Levels, isFirst = concatenate(new.levels.level4, old.Levels, "4", isFirst)
	old.Levels, isFirst = concatenate(new.levels.level3, old.Levels, "3", isFirst)
	old.Levels, isFirst = concatenate(new.levels.level2, old.Levels, "2", isFirst)
	old.Levels, _ = concatenate(new.levels.level1, old.Levels, "1", isFirst)
end

local function save_quest_priority_priorities(old, new)
	if (not old or not new) then return end
	local isFirst = true
	old.Priorities = ""
	old.Priorities, isFirst = concatenate(new.priorities.levels, old.Priorities, "Levels", isFirst)
	old.Priorities, isFirst = concatenate(new.priorities.durations, old.Priorities, "Durations", isFirst)
	old.Priorities, isFirst = concatenate(new.priorities.rarities, old.Priorities, "Rarities", isFirst)
	old.Priorities, _ = concatenate(new.priorities.types, old.Priorities, "Types", isFirst)
end

local function save_quest_general(old, new)
	if (not old or not new) then return end
	old.general = new.general
end

local function load_settings_temp_questpriorities_item(legacySectionName, priorityName)
	if (legacySectionName == nil) then
		legacySectionName = "QuestPriority"
	else
		legacySectionName = "QuestPriority_" .. legacySectionName
	end

	local old = Settings[legacySectionName]
	if (old == nil) then return end

	SettingsTemp.QuestPriorities = SettingsTemp.QuestPriorities or {}
	SettingsTemp.QuestPriorities[priorityName] = {}
	local new = SettingsTemp.QuestPriorities[priorityName]

	new.general = old.general

	local split = nil
	if (old.Types ~= nil) then
		split = utils.split(old.Types, '|')
	end
	new.types = {
		exploration = has_item(split, "Exploration") or has_item(split, "Any"),
		diplomacy = has_item(split, "Diplomacy") or has_item(split, "Any"),
		trade = has_item(split, "Trade") or has_item(split, "Any"),
		plunder = has_item(split, "Plunder") or has_item(split, "Any"),
		military = has_item(split, "Military") or has_item(split, "Any"),
		stealth = has_item(split, "Stealth") or has_item(split, "Any"),
		research = has_item(split, "Research") or has_item(split, "Any"),
		crafting = has_item(split, "Crafting") or has_item(split, "Any"),
		harvesting = has_item(split, "Harvesting") or has_item(split, "Any"),
	}

	if (not old.Rarities) then split = nil else split = utils.split(old.Rarities, '|') end
	new.rarities = {
		elite = has_item(split, "Elite") or has_item(split, "Any"),
		rare = has_item(split, "Rare") or has_item(split, "Any"),
		uncommon = has_item(split, "Uncommon") or has_item(split, "Any"),
		common = has_item(split, "Common") or has_item(split, "Any"),
		easy = has_item(split, "Easy") or has_item(split, "Any"),
	}

	if (not old.Durations) then split = nil else split = utils.split(old.Durations, '|') end
	new.durations = {
		h3 = has_item(split, "3h") or has_item(split, "Any"),
		h6 = has_item(split, "6h") or has_item(split, "Any"),
		h12 = has_item(split, "12h") or has_item(split, "Any"),
		h24 = has_item(split, "24h") or has_item(split, "Any"),
		h36 = has_item(split, "36h") or has_item(split, "Any"),
	}

	if (not old.Levels) then split = nil else split = utils.split(old.Levels, '|') end
	new.levels = {
		level1 = has_item(split, "1") or has_item(split, "Any"),
		level2 = has_item(split, "2") or has_item(split, "Any"),
		level3 = has_item(split, "3") or has_item(split, "Any"),
		level4 = has_item(split, "4") or has_item(split, "Any"),
		level5 = has_item(split, "5") or has_item(split, "Any"),
	}

	if (not old.Priorities) then split = nil else split = utils.split(old.Priorities, '|') end
	new.priorities = {
		levels = has_item(split, "Levels") or has_item(split, "Any"),
		durations = has_item(split, "Durations") or has_item(split, "Any"),
		rarities = has_item(split, "Rarities") or has_item(split, "Any"),
		types = has_item(split, "Types") or has_item(split, "Any"),
	}
end

local function load_settings_temp_questpriorities()
	load_settings_temp_questpriorities_item(nil, "Default")
	load_settings_temp_questpriorities_item("Unsubscribed", "Unsubscribed")

	if (Settings.General.useQuestPriorityGroups ~= nil) then
		local index = 0
		local ourSplit = utils.split(Settings.General.useQuestPriorityGroups, '|')
		repeat
			index = index + 1
			local questPriorityGroup = ourSplit[index]
			if (not questPriorityGroup) then return end
			load_settings_temp_questpriorities_item(questPriorityGroup, questPriorityGroup)
		until false
	end
end

function actions.save_custom_quest_settings()
	actions.SaveSettings()
	load_settings_temp_questpriorities()
end

function actions.SaveGroupPrioritySettings(property, priorityName)
	local old, new = get_questpriority_sections(priorityName)
	if (not old or not new) then return end

	if (property == "types") then save_quest_priority_types(old, new)
	elseif (property == "rarities") then save_quest_priority_rarities(old, new)
	elseif (property == "durations") then save_quest_priority_durations(old, new)
	elseif (property == "levels") then save_quest_priority_levels(old, new)
	elseif (property == "priorities") then save_quest_priority_priorities(old, new)
	elseif (property == "general") then save_quest_general(old, new)
	end

	actions.SaveSettings()
end

function actions.get_achievement_status(actual_achievement)
	if not actual_achievement then return 'notdone' end
	if actual_achievement.Completed() == true then return 'done' end

	local count = actual_achievement.ObjectiveCount() or 0
	for i = count, 1, -1 do
		local actual_objective = actual_achievement.ObjectiveByIndex(i)
		if actual_objective and actual_objective.Completed() == false then
			return 'partial'
		end
	end

	return 'notdone'
end

function actions.ForceRunCompletedAchievements_Changed()
	if not Settings or not Settings.AchievementQuests then return end
	for _, achievement_quest in pairs(Settings.AchievementQuests) do
		if (Settings.General.ForceCompletedAchievementQuests) then
			achievement_quest.run = true
		else
			local ok, actual_achievement = pcall(function() return mq.TLO.Achievement.Achievement(achievement_quest.id) end)
			if ok and actual_achievement then
				local status = actions.get_achievement_status(actual_achievement)
				if (status == 'done') then
					achievement_quest.run = false
				else
					achievement_quest.run = true
				end
			end
		end
	end
end

local function load_achievement_quests()
	local file = json_file.loadTable('data/achievement_quests.json')
	if (file == nil) then
		logger.error("AchievementQuests configuration file not found.")
		return
	end
	if (file.achievements == nil) then
		logger.error("Achievement quests do not exist in configuration file.")
		return
	end

	Settings.AchievementQuests = Settings.AchievementQuests or {}
	local added = false

	for _, achievement_item in pairs(file.achievements) do
		local existing_ach = Settings.AchievementQuests[achievement_item.name]
		if (existing_ach == nil) then
			logger.warning('ADDING new achievement: \ag%s\aw', achievement_item.name)
			Settings.AchievementQuests[achievement_item.name] = {
				run = true,
				id = achievement_item.id,
				name = achievement_item.name
			}
			added = true
		end
	end

	if added then actions.SaveSettings() end
end

local function load_settings_temp()
	load_settings_temp_questpriorities()
	actions.SaveSettings()
end

local function safe_tlo(fn, fallback)
	local ok, res = pcall(fn)
	if ok then return res end
	return fallback
end

local function ensure_ini_defaults()
	io.ensure_config_dir()

	MyIniPath = io.get_config_file_path(MyIni)
	if io.file_exists(MyIniPath) then
		local retryLeft = 20
		repeat
			Settings = persistence.load(MyIniPath)
			if Settings ~= nil then
				retryLeft = 0
			else
				logger.info("Did not load global file.  Retrying.")
				retryLeft = retryLeft - 1
				mq.doevents()
				mq.delay(500)
			end
		until retryLeft == 0

		if Settings == nil then
			logger.error("Unable to load global file. Continuing with character settings.")
		end
	else
		Settings = legacyConfig.load_legacy_global_configurations(MyIniPath)
	end

	-- Ensure at least minimal structure and persistence
	if not Settings or not Settings.General or Settings.General.useCharacterConfigurations == nil then
		Settings = {
			General = {
				useCharacterConfigurations = true
			}
		}
		persistence.store(MyIniPath, Settings)
	end

	actions.ConfigurationType = "Global"
	actions.ConfigurationSource = "Overseer.lua"

	local globalConfigIsEmpty = false
	if Settings.General.useCharacterConfigurations then
		MyIni = string.format('Overseer_%s_%s.lua', safe_tlo(function() return mq.TLO.Me.CleanName() end, 'Unknown'), safe_tlo(function() return mq.TLO.Me.Class.ShortName() end, 'Unknown'))
		MyIniPath = io.get_config_file_path(MyIni)

		if not io.file_exists(MyIniPath) then
			local test_pre_persona_ini = string.format('Overseer_%s.lua', safe_tlo(function() return mq.TLO.Me.CleanName() end, 'Unknown'))
			local test_pre_persona_ini_path = io.get_config_file_path(test_pre_persona_ini)
			if io.file_exists(test_pre_persona_ini_path) then
				io.rename(test_pre_persona_ini_path, MyIniPath)
				logger.info('Migrating pre-AltPersona INI (\aw%s\ao) to post (\ag%s\ao)', test_pre_persona_ini, MyIni)
			end
		end

		actions.ConfigurationType = "Character"
		actions.ConfigurationSource = string.format("%s", MyIni)

		if io.file_exists(MyIniPath) then
			Settings = persistence.load(MyIniPath)
		else
			io.ensure_config_dir()
			Settings = legacyConfig.load_legacy_configurations(MyIniPath)
		end

		actions.UsingCharacterConfiguration = true
	else
		if Settings.General.runFullCycleOnStartup == nil then
			globalConfigIsEmpty = true
		end
	end

	if not Settings or not Settings.General or globalConfigIsEmpty then
		Settings = {
			General = {
				version = legacyConfig.SettingsVersion,
				rewards = {
					maximizeStoredExpRewards = false,
					storedExpRewardsCount = 8,
					claimRewards = false,
				},
				useRandomizedUiInteractionDelays = false,
				useQuestDatabase = true,
				minimumSuccessPercent = 0,
				logLevel = 1,
				ignoreConversionQuests = false,
				ignoreRecruitmentQuests = false,
				ignoreRecoveryQuests = true,
				countAgentsBetweenCycles = false,
				maxLevelUseCurrentCap = true,
				maxLevelForClaimingExpReward = safe_tlo(function() return mq.TLO.Me.MaxLevel() end, 255),
				maxLevelPctForClaimingExpReward = 97,
				claimCollectionFragments = false,
				claimAgentPacks = false,
				claimTetradrachmPacks = false,
				claimEliteEchos = false,
				agentCountForConversionCommon = 2,
				agentCountForConversionUncommon = 2,
				agentCountForConversionRare = 2,
				showUi = true,
				autoRestartEachCycle = false,
				runFullCycleOnStartup = false,
				campAfterFullCycle = false,
				campAfterFullCycleFastCamp = false,
				pauseOnCharacterChange = false,
				convertEliteAgents = false,
				ForceCompletedAchievementQuests = false,
				uiActions = {
					useUiActionDelay = true,
					useDelay = true,
					delayMinMs = 1000,
					delayMaxMs = 2000,
				}
			},
			Display = {
				showDetailed = true,
			},
			QuestPriority = {
				Priorities = 'Levels|Durations|Rarities|Types',
				Durations = '3h|6h|12h',
				Rarities = 'Elite|Rare|Uncommon|Common|Easy',
				Types = actions.AllQuestTypes,
				Levels = '5|4|3|2|1',
				general = {
					selectHighestExp = false,
				}
			},
			Rewards = {
				[1] = "Character Experience",
				[2] = "Overseer Tetradrachm",
				index = 2,
				eliteAgentEchoReward = nil,
			},
			Debug = {
				doNotRunQuests = false,
				doNotFindAgents = false,
				allowTestMode = false,
			}
		}

		if globalConfigIsEmpty then
			Settings.General.useCharacterConfigurations = false
		end

		persistence.store(MyIniPath, Settings)

		SettingsTemp.QuestPriorities = SettingsTemp.QuestPriorities or {
			Default = {
				general = {
					selectHighestExp = false,
				},
				rarities = {
					elite = true,
					rare = true,
					uncommon = true,
					common = true,
					easy = true,
				},
				durations = {
					h36 = true,
					h24 = true,
					h12 = true,
					h6 = true,
					h3 = true,
				},
				levels = {
					level1 = true,
					level2 = true,
					level3 = true,
					level4 = true,
					level5 = true,
				},
				types = {
					exploration = true,
					diplomacy = true,
					trade = true,
					plunder = true,
					military = true,
					stealth = true,
					research = true,
					crafting = true,
					harvesting = true,
				},
			},
		}
	end

	-- Ensure global Settings reference for other modules
	_G.Settings = Settings

	-- restore behavior: set log level and ensure some debug flags exist
	logger.set_log_level(Settings.General.logLevel)

	EnsureExists('Debug', 'doNotRunQuests', false)
	EnsureExists('Debug', 'doNotFindAgents', false)
end

function actions.SetLogLevel(level)
	logger.set_log_level(level)
	Settings.General.logLevel = level
	actions.SaveSettings()
end

function actions.SetUiDelays()
	mqutils.set_delays(Settings.General.uiActions.useUiActionDelay, Settings.General.uiActions.delayMinMs, Settings.General.uiActions.delayMaxMs)
	actions.SaveSettings()
end

local function initialize(turn_off_autorun_settings)
	TrackingCharacter = string.format("%s (%s)", safe_tlo(function() return mq.TLO.Me.Name() end, 'Unknown'), safe_tlo(function() return mq.TLO.Me.Class.ShortName() end, 'Unknown'))

	MaxAllowedQuests = 5
	AvailableQuestList = "OverseerWnd/OW_OQP_QuestList"
	CollectRewardButton = 'OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CollectRewardButton'
	CompleteQuestButton = 'OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CompleteQuestButton'
	AvailableQuestCompletionTime = 'OverseerWnd/OW_OverseerQuestsPage/OW_ALL_DurationValue'
	CurrentQuestCompletionTime = 'OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_DurationValue'
	CurrentQuestName = 'OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_TitleLabel'
	ActiveQuestList = 'OverseerWnd/OW_AQP_QuestList'
	AvailableQuestDifficulty = 'OverseerWnd/OW_OverseerQuestsPage/OW_ALL_DifficultyLabel'
	AvailableQuestMinions = 'OverseerWnd/OW_OverseerQuestsPage/OW_ALL_QuestTemplate/OW_ALL_MinionInfoArea'
	MinionSelectionScreen = 'OverseerWnd/OW_OverseerQuestsPage/OW_OQP_MinionSelectionScreen/OW_OQP_MinionPictureArea'
	MinionSelectionScreenFirstMinion = 'OverseerWnd/OW_OverseerQuestsPage/OW_OQP_MinionSelectionScreen/OW_OQP_MinionPictureArea'
	TooManyPendingRewards = false
	IsInTutorial = false
	ActiveQuestListDirty = true
	NoPendingRewards = false

	NextQuestCompletion = 0
	MinutesUntilNextQuest = 0

	AllActiveQuests = {}
	for i = 1, 10 do
		AllActiveQuests[i] = {
			name = '',
			timeRemainingString = '',
			completionMinutes = ''
		}
	end
	AllActiveQuestCount = 0

	AllAvailableQuests = {}
	for i = 1, 40 do
		AllAvailableQuests[i] = {
			available = true,
			name = '',
			duration = '',
			difficulty = 0,
			runOrder = 0,
			successRate = 0,
			experience = 0,
			mercenaryAas = 0,
			tetradrachms = 0,
			level = 0,
			rarity = 0,
			type = 0
		}
	end
	AvailableQuestCount = 0
	AvailableQuestListLoaded = false

	-- InitializeAgentCounts must exist elsewhere; keep call for behavior
	InitializeAgentCounts()

	QuestOrder = {}
	for i = 1, 4 do
		QuestOrder[i] = {
			name = '',
			allItems = 0,
			currentIndex = 0,
			currentItem = 0
		}
	end

	FailedQuest_InStartQuestBadAgentErrorMode = false
	FailedQuest_CurrentPendingMinionCacheCount = 0
	FailedQuest_CurrentPendingMinions = {}

	ensure_ini_defaults()
	logger.warning('v. \at%s\ax   Configuration: \at%s\ax', Version, MyIni)

	EnsureIniDefaults_VersionUpdates()

	StopOnMaxMercAA = Settings.General.stopOnMaxMercAA
	CountAgentsBetweenCycles = Settings.General.countAgentsBetweenCycles

	DebugNoRunQuestMode = Settings.Debug.doNotRunQuests
	DebugNoSelectAgents = Settings.Debug.doNotFindAgents
	mqutils.set_delays(Settings.General.uiActions.useUiActionDelay, Settings.General.uiActions.delayMinMs, Settings.General.uiActions.delayMaxMs)

	load_achievement_quests()
	load_settings_temp()

	if (turn_off_autorun_settings) then
		local is_dirty = false
		if (Settings.General.runFullCycleOnStartup) then
			logger.warning('RunFullCycleOnStartup set to false per command-line parameter')
			Settings.General.runFullCycleOnStartup = false
			is_dirty = true
		end
		if (Settings.General.autoRestartEachCycle) then
			logger.warning('AutoRestartEachCycle set to false per command-line parameter')
			Settings.General.autoRestartEachCycle = false
			is_dirty = true
		end
		if (is_dirty) then actions.SaveSettings() end
	end

	actions.Initialized = true
end

function actions.InitializeOverseerSettings(turn_off_autorun_settings)
	initialize(turn_off_autorun_settings)
end

function UpdateGlobalCharConfigurationSetting(value)
	if Settings.General.useCharacterConfigurations == value then
		logger.info('Already Same Value')
		return
	end

	if value then
		logger.info('Already Using Global, so updating Global')
		Settings.General.useCharacterConfigurations = value
		persistence.store(MyIniPath, Settings)
		return
	end

	logger.info('Using char so updating Global.')

	-- attempt to update a global INI if present (kept as placeholder)
	local config_dir = mq.configDir:gsub('\\', '/') .. '/'
	local globalIniFileFullPath = config_dir .. 'OverseerLua.ini'
	if io.file_exists(globalIniFileFullPath) then
		-- legacy placeholder; preserved behavior
	end
end

function UpdateSetting(section, property, value)
	Settings[section][property] = value
	persistence.store(MyIniPath, Settings)
end

function actions.ApplySettingsTemp()
	-- placeholder retained for compatibility
end

return actions
