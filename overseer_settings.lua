--- @type Mq
local mq = require('mq')
local utils = require('overseer.utils.string_utils')
local io = require('overseer.utils.io_utils')
local logger = require('overseer.utils.logger')
local legacyConfig = require('overseer.overseer_settings_legacy')
local json_file = require('overseer.utils.json_file')
local mqutils = require('overseer.utils.mq_utils')
require('overseer.utils.persistence')

local actions = {}

local Version = 'Beta 5.0'
local MyIni = 'Overseer.lua'

local __change_callbacks = {}

-- Settings change callbacks
local __change_callbacks = {}

function RegisterSettingsChangeCallback(fn)
    if type(fn) == 'function' then table.insert(__change_callbacks, fn) end
end

actions.InTestMode = false

--- @type boolean
actions.Initialized = false

--- @type string
actions.AllQuestTypes = legacyConfig.AllQuestTypes

-- Identifies character script was run against.
-- 'Settings.General.onCharacterChange' specifies whether we reload on each change
-- or pause and wait for that character to return
--- @type string
TrackingCharacter = ''

--- @type string
actions.ConfigurationType = ''

--- @type string
actions.ConfigurationSource = ''

SettingsTemp = {}

function actions.SaveSettings()
	persistence.store(MyIniPath, Settings)
	for _, cb in ipairs(__change_callbacks) do
		pcall(cb) -- protect callback errors from breaking SaveSettings
	end
end

function ReorderCollectionUp(collection, index)
	if (collection == nil or index < 2) then return index end

	local currentName = collection[index]
	collection[index] = collection[index - 1]
	collection[index - 1] = currentName

	actions.SaveSettings()

	return index - 1
end

function ReorderCollectionDown(collection, index)
	if (collection == nil or index > collection.index - 1) then return index end

	local currentName = collection[index]
	collection[index] = collection[index + 1]
	collection[index + 1] = currentName

	actions.SaveSettings()

	return index + 1
end

function AddCollectionItem(collection, name)
	if (collection == nil) then return end

	collection.index = collection.index + 1
	collection[collection.index] = name

	actions.SaveSettings()
end

function RemoveCollectionItem(collection, index)
	if (collection == nil or index < 1 or index > collection.index) then return end

	local last = collection.index - 1
	for optionIndex = index, last do
		collection[optionIndex] = collection[optionIndex + 1]
	end

	collection[last + 1] = nil
	collection.index = last

	actions.SaveSettings()
end

function actions.ReorderRewardUp(index)
	return ReorderCollectionUp(Settings.Rewards, index)
end

function actions.ReorderRewardDown(index)
	return ReorderCollectionDown(Settings.Rewards, index)
end

function actions.AddActiveReward(name)
	AddCollectionItem(Settings.Rewards, name)
end

function actions.RemoveActiveReward(index)
	RemoveCollectionItem(Settings.Rewards, index)
end

function actions.ReorderSpecifiedQuestsUp(index)
	return ReorderCollectionUp(Settings.SpecificQuests, index)
end

function actions.ReorderSpecifiedQuestsDown(index)
	return ReorderCollectionDown(Settings.SpecificQuests, index)
end

local function GetSpecificCollectionIndexByValue(collection, name)

	for optionIndex = 0, collection.index do
		if (name == collection[optionIndex]) then return optionIndex end
	end

	return -1
end

local function HasSpecificQuest(collection, name)
	return GetSpecificCollectionIndexByValue(collection, name) > -1
end

function actions.AddSpecifiedQuest(name)
	if (Settings.SpecificQuests == nil) then
		Settings.SpecificQuests = {}
		Settings.SpecificQuests.index = 0
	end

	if (HasSpecificQuest(Settings.SpecificQuests, name)) then return end

	AddCollectionItem(Settings.SpecificQuests, name)
end

function actions.RemoveSpecifiedQuest(index)
	RemoveCollectionItem(Settings.SpecificQuests, index)
end

-- Returns true if item exists, or false if didn't and default created
local function EnsureExists(section, key, default)
	if (Settings[section] == nil) then
		Settings[section] = {}
	end

	if (Settings[section][key] == nil) then
		Settings[section][key] = default
		return false
	end

	return true
end

local function has_item(array, itemName)
	if (not array) then return false end

	local index = 0
	repeat
		index = index + 1
		if (not array[index]) then
			return false
		end

		if (array[index] == itemName) then
			return true
		end
	until false
end

local function concatenate(value, source, expected, isFirst)
	if(not value or not expected or value ~= true) then return source, isFirst end

	if (not source or isFirst == true) then return expected, false end
	return source..'|'..expected, false
end

local function get_questpriority_sections(priorityName)
	local legacySectionName = "QuestPriority"
	if (priorityName ~= "Default") then
		legacySectionName = "QuestPriority_"..priorityName
	end
	local old = Settings[legacySectionName]
	if (old == nil) then logger.error('** Legacy QuestPriority Group (%s) Not Found **', legacySectionName) return nil, nil end

	if (SettingsTemp.QuestPriorities == nil) then logger.error('** Temp Settings Not Set**') return nil, nil end
	local new = SettingsTemp.QuestPriorities[priorityName]
	if (not new) then logger.error('** QuestPriority Group Not Found **') return nil, nil end

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
		legacySectionName = "QuestPriority_"..legacySectionName
	end

	local old = Settings[legacySectionName]
	if (old == nil) then return end

	-- TODO: SettingsTemp
	if (SettingsTemp.QuestPriorities == nil) then SettingsTemp.QuestPriorities = {} end
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

	if (not old.Rarities) then split = nil
	else split = utils.split(old.Rarities, '|')	end
	new.rarities = {
		elite = has_item(split, "Elite") or has_item(split, "Any"),
		rare = has_item(split, "Rare") or has_item(split, "Any"),
		uncommon = has_item(split, "Uncommon") or has_item(split, "Any"),
		common = has_item(split, "Common") or has_item(split, "Any"),
		easy = has_item(split, "Easy") or has_item(split, "Any"),
	}

	if (not old.Durations) then split = nil
	else split = utils.split(old.Durations, '|')	end
	new.durations = {
		h3 = has_item(split, "3h") or has_item(split, "Any"),
		h6 = has_item(split, "6h") or has_item(split, "Any"),
		h12 = has_item(split, "12h") or has_item(split, "Any"),
		h24 = has_item(split, "24h") or has_item(split, "Any"),
		h36 = has_item(split, "36h") or has_item(split, "Any"),
	}

	if (not old.Levels) then split = nil
	else split = utils.split(old.Levels, '|')	end
	new.levels = {
		level1 = has_item(split, "1") or has_item(split, "Any"),
		level2 = has_item(split, "2") or has_item(split, "Any"),
		level3 = has_item(split, "3") or has_item(split, "Any"),
		level4 = has_item(split, "4") or has_item(split, "Any"),
		level5 = has_item(split, "5") or has_item(split, "Any"),
	}

	if (not old.Priorities) then split = nil
	else split = utils.split(old.Priorities, '|')	end
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
			if (not questPriorityGroup) then
				return
			end

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
	if (actual_achievement.Completed() == true) then
		return 'done'
	end

	for objIndex = actual_achievement.ObjectiveCount(), 1, -1  do
		local actual_objective = actual_achievement.ObjectiveByIndex(objIndex)
		if (actual_objective.Completed() == false) then
			return 'partial'
		end

		return 'notdone'
	end
end

function actions.ForceRunCompletedAchievements_Changed()

	for _, achievement_quest in pairs(Settings.AchievementQuests) do
		if (Settings.General.ForceCompletedAchievementQuests) then
			achievement_quest.run = true
		else
			local actual_achievement = mq.TLO.Achievement.Achievement(achievement_quest.id)
			if (actual_achievement ~= nil) then
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
	if (file == nil) then logger.error("AchievementQuests configuration file not found.") return end

	if (file.achievements == nil) then logger.error("Achievement quests do not exist in configuration file.") return end

	if (Settings.AchievementQuests == nil) then Settings.AchievementQuests = {} end

	for _, achievement_item in pairs(file.achievements) do
		local existing_ach = Settings.AchievementQuests[achievement_item.name]
		if (existing_ach == nil) then
			logger.warning('ADDING new achievement: \ag%s\aw', achievement_item.name)

			local new_achievement = {
				run = true,
				id = achievement_item.id,
				name = achievement_item.name
			}
			Settings.AchievementQuests[achievement_item.name] = new_achievement
		end

		actions.SaveSettings()
	end
end

-- This is a temporary process until we're fully migrated to this new system and get rid of the "Types=One|Two|Three"
-- Will move to the legacy settings section after that happens
local function load_settings_temp()
	load_settings_temp_questpriorities()
	actions.SaveSettings()
end

local function ensure_ini_defaults()
	io.ensure_config_dir()

	MyIniPath = io.get_config_file_path(MyIni)
	if (io.file_exists(MyIniPath)) then

		local retryLeft = 20
		repeat
			Settings = persistence.load(MyIniPath)

			-- Too many characters loading at same time can cause issues. Retry
			if (Settings ~= nil) then
				retryLeft = 0
			else
				logger.info("Did not load global file.  Retrying.")
				retryLeft = retryLeft -1
				mq.doevents()
				mq.delay(500)
			end
		until(retryLeft == 0)

		if (Settings == nil) then
			logger.error("Unable to load global file. Continuing with character settings.")
		end

	else
		Settings = legacyConfig.load_legacy_global_configurations(MyIniPath)
	end

	if Settings == nil or Settings.General == nil or Settings.General.useCharacterConfigurations == nil then
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
		MyIni = string.format('Overseer_%s_%s.lua', mq.TLO.Me.CleanName(), mq.TLO.Me.Class.ShortName())
		MyIniPath = io.get_config_file_path(MyIni)

		-- THIS IS PORT LOGIC for Alternate Personaes
		-- TODO: Move this to a dif't method for better readability
		if (io.file_exists(MyIniPath) == false) then
			local test_pre_persona_ini = string.format('Overseer_%s.lua', mq.TLO.Me.CleanName())
			local test_pre_persona_ini_path = io.get_config_file_path(test_pre_persona_ini)
			if (io.file_exists(test_pre_persona_ini_path) == true) then
				-- If we're here, then we have to just rename old file to new
				io.rename(test_pre_persona_ini_path, MyIniPath)
				logger.info('Migrating pre-AltPersona INI (\aw%s\ao) to post (\ag%s\ao)', test_pre_persona_ini, MyIni)
			end
		end

		actions.ConfigurationType = "Character"
		actions.ConfigurationSource = string.format("%s", MyIni)

		if (io.file_exists(MyIniPath)) then
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

	if Settings == nil or Settings.General == nil or globalConfigIsEmpty then
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
				maxLevelForClaimingExpReward = mq.TLO.Me.MaxLevel(),
				maxLevelPctForClaimingExpReward = 95,
				claimCollectionFragments = false,
				claimAgentPacks = false,
				claimTetradrachmPacks = false,
				claimEliteEchos = false,
				agentCountForConversionCommon = 2,
				agentCountForConversionUncommon = 2,
				agentCountForConversionRare = 2,
				agentCountForRetireElite = 99,
				showUi = true,
				autoRestartEachCycle = false,
				runFullCycleOnStartup = false,
				campAfterFullCycle = false,
				campAfterFullCycleFastCamp = false,
				pauseOnCharacterChange = false,
				retireEliteAgents = false,
				ForceCompletedAchievementQuests = false,
				uiActions = {
					useDelay = false,
					delayMinMs = 1000,
					delayMaxMs = 2000,
				}
			},
			Display = {
				showDetailed = true,
			},
			QuestPriority = {
				Priorities = 'Levels|Durations|Rarities|Types',
				Durations = '6h|12h',
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

		if (SettingsTemp.QuestPriorities == nil) then
			SettingsTemp.QuestPriorities = {
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
	end

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
	TrackingCharacter = string.format("%s (%s)", mq.TLO.Me.Name(), mq.TLO.Me.Class.ShortName())

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

	-- 1==quest name, 2==quest completion string (i.e. 1h:10m), 3==quest completion minutes (i.e. 102)
	AllActiveQuests = {} -- [10,3]
	for i = 1, 10 do
		AllActiveQuests[i] = {
			name = '',				-- 1
			timeRemainingString = '',-- 2
			completionMinutes = ''	-- 3
		}
	end
	AllActiveQuestCount = 0

	-- 1==is available. 2==quest name. 3=Duration. 4==difficulty (Entire String, i.e. 'Level 1 Common Recruitment'). 5==quest run order. 
	-- 6==Success Rate. 7==Exp. 8==Tetra. 9==level. 10==Rarity (i.e. Common).11==type (i.e. Trade, Plunder, Recruitment)
	AllAvailableQuests = {}
	for i = 1, 40 do
		AllAvailableQuests[i] = {
			available = true,	-- 1
			name = '',			-- 2
			duration = '',
			difficulty = 0,		-- 4
			runOrder = 0,
			successRate = 0,	-- 6
			experience = 0,
			mercenaryAas = 0,
			tetradrachms = 0,	-- 8
			level = 0,			-- 9
			rarity = 0,			-- 10
			type = 0			-- 11
		}
	end
	AvailableQuestCount = 0
	AvailableQuestListLoaded = false

	InitializeAgentCounts()

	-- 1=Name (i.e. Durations)  2=allItems (i.e. '6h|12h')  3=curIndex 4=currentItem (i.e. '6h')
	QuestOrder = {} -- [4,6]
	for i = 1, 4 do
		QuestOrder[i] = {
			name = '',			-- 1
			allItems = 0,		-- 2
			currentIndex = 0,	-- 3
			currentItem = 0		-- 4
		}
	end

	-- Hopefully temporary while we sort out this silly bug
	FailedQuest_InStartQuestBadAgentErrorMode = false
	FailedQuest_CurrentPendingMinionCacheCount = 0
	FailedQuest_CurrentPendingMinions = {} -- [10]

	ensure_ini_defaults()
	logger.warning('v. \at%s\ax   Configuration: \at%s\ax', Version, MyIni)

	EnsureIniDefaults_VersionUpdates()
	-- sync persisted allowTestMode into runtime flag
	actions.InTestMode = (Settings.Debug and Settings.Debug.allowTestMode) and true or false

	StopOnMaxMercAA = Settings.General.stopOnMaxMercAA

	CountAgentsBetweenCycles = Settings.General.countAgentsBetweenCycles

	DebugNoRunQuestMode = Settings.Debug.doNotRunQuests
	DebugNoSelectAgents = Settings.Debug.doNotFindAgents
	mqutils.set_delays(Settings.General.uiActions.useUiActionDelay, Settings.General.uiActions.delayMinMs, Settings.General.uiActions.delayMaxMs)
	Settings.Debug = Settings.Debug or {}
	Settings.Debug.processFullQuestRewardData = Settings.Debug.processFullQuestRewardData or false
	Settings.Debug.validateQuestRewardData = Settings.Debug.validateQuestRewardData or false
	-- NEW: allow updates on validation mismatches when true (default: false)
	Settings.Debug.updateQuestDatabaseOnValidate = Settings.Debug.updateQuestDatabaseOnValidate or false
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
		if (is_dirty) then
			actions.SaveSettings()
		end
	end

	actions.Initialized = true
end

function actions.InitializeOverseerSettings(turn_off_autorun_settings)
	initialize(turn_off_autorun_settings)
end


function UpdateGlobalCharConfigurationSetting(value)
	if (Settings.General.useCharacterConfigurations == value) then
		logger.info('Already Same Value')
		return
	end

	if (value) then
		logger.info('Already Using Global, so updating Global')
		-- We're already using the global INI file.  Save it there
		Settings.General.useCharacterConfigurations = value
		persistence.store(MyIniPath, Settings)
		return
	end

	logger.info('Using char so updating Global.')

	-- In this case, we're using the character file and need to load the global
	local config_dir = mq.configDir:gsub('\\', '/') .. '/'
	local globalIniFileFullPath = config_dir .. 'OverseerLua.ini'
	if (io.file_exists(globalIniFileFullPath)) then
		-- local globalSettings = LIP.load(globalIniFileFullPath)
		-- globalSettings.General.useCharacterConfigurations = value
		-- LIP.save(globalIniFileFullPath, globalSettings)
	end
end

function UpdateSetting(section, property, value)
	Settings[section][property] = value
	persistence.store(MyIniPath, Settings)
end

function actions.ApplySettingsTemp()
end

return actions
