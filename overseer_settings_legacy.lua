--- @type Mq
local mq = require('mq')
local LIP = require('overseer.lib.LIP')
local utils = require('overseer.utils.string_utils')
local io = require('overseer.utils.io_utils')
require('overseer.utils.persistence')

local actions = {}

actions.SettingsVersion = 12

--- @type string
actions.AllQuestTypes = 'Exploration|Diplomacy|Trade|Plunder|Military|Stealth|Research|Crafting|Harvesting'

Settings = nil

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

local function EnsureExistsSubsection(section, subsection, key, default)
	if (Settings[section] == nil) then
		Settings[section] = {}
	end

	if (Settings[section][subsection] == nil) then
		Settings[section][subsection] = {}
	end

	if (Settings[section][subsection][key] == nil) then
		Settings[section][subsection][key] = default
		return false
	end

	return true
end

local function ConfigToNewBool(value, default)
	if (value == 0) then return false end
	if (value == 1) then return true end

	return default
end

function actions.load_legacy_configurations(final_file_path)
	io.ensure_config_dir()
	local legacyCharacterIni = string.format('Overseer_%s.ini', mq.TLO.Me.CleanName)
	-- First check if we have a version 3 INI file
	local legacyIniFile = io.get_config_file_path(legacyCharacterIni)
	if (io.file_exists(legacyIniFile)) then
		printf('Migrating Legacy v3 Character INI File: %s to %s', legacyIniFile, MyIniPath)
		Settings = LIP.load(legacyIniFile)
		EnsureIniDefaults_VersionUpdates()
		persistence.store(final_file_path, Settings)
		return Settings
	end

	-- Now check if we have a version < 3
	legacyIniFile = io.get_root_config_file_path(legacyIniFile)
	if (io.file_exists(legacyIniFile)) then
		printf('Migrating Legacy v<3 Character INI File: %s to %s', legacyIniFile, MyIniPath)
		Settings = LIP.load(legacyIniFile)
		EnsureIniDefaults_VersionUpdates()
		persistence.store(final_file_path, Settings)
		return Settings
	end
end

function actions.load_legacy_global_configurations(final_file_path)
	io.ensure_config_dir()
	local fileName = "Overseer.ini"
	-- First check if we have a version 3 INI file
	local legacyIniFile = io.get_config_file_path(fileName)
	if (io.file_exists(legacyIniFile)) then
		printf('Migrating Legacy v3 Global INI File: %s to %s', legacyIniFile, MyIniPath)
		Settings = LIP.load(legacyIniFile)
		EnsureIniDefaults_VersionUpdates()
		persistence.store(final_file_path, Settings)
		return Settings
	end

	-- Now check if we have a version < 3
	legacyIniFile = io.get_root_config_file_path(legacyIniFile)
	if (io.file_exists(legacyIniFile)) then
		printf('Migrating Legacy v<3 Global INI File: %s to %s', legacyIniFile, MyIniPath)
		Settings = LIP.load(legacyIniFile)
		Settings.General.useCharacterConfigurations = ConfigToNewBool(Settings.General.useCharacterConfigurations)
		EnsureIniDefaults_VersionUpdates()
		persistence.store(final_file_path, Settings)
		return Settings
	end
end

function EnsureIniDefaults_VersionUpdates_AgentConversionCounts()
	local tempAgentCountForConversion = Settings.General.agentCountForConversion
	if (tempAgentCountForConversion == nil) then tempAgentCountForConversion = 2 end
	local split = utils.split(tempAgentCountForConversion, '|')
	local lastValue = tempAgentCountForConversion

	local agentCountsForConversion = {} -- [3]

	for index = 1, 3 do
		local nextValue = split[index]
		if (nextValue == nil) then
			agentCountsForConversion[index] = lastValue
		else
			agentCountsForConversion[index] = nextValue
			lastValue = nextValue
		end
	end

	Settings.General.agentCountForConversionCommon = tonumber(agentCountsForConversion[1])
	Settings.General.agentCountForConversionUncommon = tonumber(agentCountsForConversion[2])
	Settings.General.agentCountForConversionRare = tonumber(agentCountsForConversion[3])

	Settings.General.agentCountForConversion = nil
end

function CleanupPriorityGroups()
	if (Settings.QuestPriority == nil or Settings.QuestPriority_Unsubscribed == nil) then return end

	if (Settings.QuestPriority.Durations ~= Settings.QuestPriority_Unsubscribed.Durations
		or Settings.QuestPriority.Levels ~= Settings.QuestPriority_Unsubscribed.Levels
		or Settings.QuestPriority.Priorities ~= Settings.QuestPriority_Unsubscribed.Priorities
		or Settings.QuestPriority.Rarities ~= Settings.QuestPriority_Unsubscribed.Rarities
		or Settings.QuestPriority.Types ~= Settings.QuestPriority_Unsubscribed.Types) then
		return
	end

	Settings.QuestPriority_Unsubscribed = nil
end

local function is_string(object)
    return type(object) == "string"
end

local function ensure_string(object, defaultValue)
    if (is_string(object)) then return object end
	
	return defaultValue
end

function AddCollectionItem(collection, name)
	if (collection == nil) then return end

	collection.index = collection.index + 1
	collection[collection.index] = name
end

function EnsureIniDefaults_VersionUpdates()
	-- Version-agnostic upgrade logic

	-- These were ending up nil in config, unintentionally
	EnsureExists('General', 'autoRestartEachCycle', false)
	EnsureExists('General', 'runFullCycleOnStartup', false)
	EnsureExists('General', 'pauseOnCharacterChange', false)
	EnsureExists('General', 'convertEliteAgents', false)
	EnsureExists('General', 'ForceCompletedAchievementQuests', false)

	EnsureExists('General', 'claimEliteAgentEchos', false)
	EnsureExists('General', 'rewards', {})

	EnsureExists('Rewards', 'eliteAgentEchoReward', '')
	EnsureExists('Display', 'showDetailed', false)
	Settings.QuestPriorities = nil
	Settings.General.useLegacyAgentSelection = nil
	Settings.Rewards.eliteAgentEchoReward = ensure_string(Settings.Rewards.eliteAgentEchoReward, 'None')
	EnsureExists('General', 'agentCountForConversionElite', 99)
	Settings.General.countAgentsBetweenCycles = nil
	Settings.General.minimumQuestExperience = nil

	if (Settings.SpecificQuests == nil) then
		Settings.SpecificQuests = {index=0}
	elseif (Settings.SpecificQuests.index == nil) then
		Settings.SpecificQuests.index = 0
	end

	if (Settings.General.uiActions == nil) then Settings.General.uiActions = {useUiActionDelay = false, delayMinMs = 1000, delayMaxMs = 2000} end
	if (Settings.Rewards == nil) then
		Settings.Rewards = {index=0}
	elseif (Settings.Rewards.index == nil) then
		Settings.Rewards.index = 0
	end

	if (Settings.QuestPriority.Types == 'Any' or Settings.QuestPriority.Types == 'ANY') then
		Settings.QuestPriority.Types = actions.AllQuestTypes
	end

	EnsureExistsSubsection('QuestPriority', 'general', 'selectHighestExp', false)
	EnsureExistsSubsection('QuestPriority', 'general', 'storedExpRewardsCount', 8)

	-- If a legacy "Unsubscribed"... fix it up a bit
	if (Settings['QuestPriority_Unsubscribed'] ~= nil) then
		EnsureExistsSubsection('QuestPriority_Unsubscribed', 'general', 'selectHighestExp', false)
		EnsureExistsSubsection('QuestPriority_Unsubscribed', 'general', 'storedExpRewardsCount', 8)
	end

	EnsureExists('General', 'maxLevelUseCurrentCap', Settings.General.maxLevelForClaimingExpReward == mq.TLO.Me.MaxLevel())

	EnsureExists('General', 'campAfterFullCycle', false)
	EnsureExists('General', 'campAfterFullCycleFastCamp', false)
	

	-- These shouldn't be persisted, and shouldn't be used by "normies" But were not normies.
	--Settings.Debug.processFullQuestRewardData = false
	--Settings.Debug.validateQuestRewardData = false
	--if (Settings.General.useQuestDatabase ~= true) then Settings.General.useQuestDatabase = true end

	if (Settings.General.version == nil or Settings.General.version >= actions.SettingsVersion) then
		return
	end

	-- Version-specific upgrades
	if (Settings.General.version <= 12) then
		Settings.General.rewards.claimRewards = Settings.General.claimRewards
		Settings.General.claimRewards = nil
		Settings.General.rewards.maximizeStoredExpRewards = false
		Settings.General.useQuestDatabase = true
	end

	if (Settings.General.version <= 11 and Settings.General.logLevel ~= nil) then
		Settings.General.logLevel = Settings.General.logLevel + 2
	end

	if (Settings.General.version <= 10) then
		Settings.General.maxLevelForClaimingExpReward = 130
	end

	if (Settings.General.version <= 9) then
		-- Changes for Achievement Tracking
		Settings.SpecificQuests = { index = 0 }
		Settings.AchievementQuests = {}
		Settings.General.ForceCompletedAchievementQuests = true

		-- Changes for honoring max-level cap per char/expansion
		-- if (Settings.General.maxLevelForClaimingExpReward == mq.TLO.Me.MaxLevel()) then
		-- 	Settings.General.useMaxLevelForClaimingExpReward = true
		-- else
		-- 	Settings.General.useMaxLevelForClaimingExpReward = false
		-- end
	end

	if (Settings.General.version <= 6) then
		if (Settings.QuestPriority.Types == 'Any') then
			Settings.QuestPriority.Types = actions.AllQuestTypes
		end

		if (Settings.General.ignoreRecoveryQuests == nil) then
			Settings.General.ignoreRecoveryQuests = true

			Settings.General.version = actions.SettingsVersion
			persistence.store(MyIniPath, Settings)
		end
	end

	if (Settings.General.version == 4) then
		-- Upgrade from 4.0 -> 5.0
		EnsureExists('General', 'claimFragments', false)
		CleanupPriorityGroups()

		Settings.General.version = actions.SettingsVersion
		persistence.store(MyIniPath, Settings)
	elseif (Settings.General.version == 3) then
		-- Upgrade from 3.0 -> 4.0
		EnsureExists('General', 'agentCountForConversionCommon', 2)
		EnsureExists('General', 'agentCountForConversionUncommon', 2)
		EnsureExists('General', 'agentCountForConversionRare', 2)
		EnsureExists('General', 'claimFragments', false)
		CleanupPriorityGroups()

		if (Settings.Rewards == nil or Settings.Rewards.index == 0) then
			Settings.Rewards = {}
			Settings.Rewards.index = 2
			if (Settings.Rewards[1] == nil) then
				Settings.Rewards[1] = "Character Experience"
			end
			if (Settings.Rewards[2] == nil) then
				Settings.Rewards[2] = "Overseer Tetradrachm"
			end
		end

		Settings.General.version = actions.SettingsVersion
		persistence.store(MyIniPath, Settings)
	elseif (Settings.General.version == nil or Settings.General.version <=2) then
		-- Upgrade from 1&2 to 4.0

		-- New properties
		Settings.General.showUi = true
		Settings.General.runFullCycleOnStartup = true
		Settings.General.onCharacterChange = 2 -- 'Pause' (Until I get it working with a string instead of int)
		Settings.General.claimFragments = false
		if (Settings.Debug == nil) then Settings.Debug = {} end
		Settings.Debug.allowTestMode = false

		-- Migrated properties
		if (Settings.General.repeatTimeMinutes ~= 0) then
			Settings.General.autoRestartEachCycle = true
		else
			Settings.General.autoRestartEachCycle = false
		end

		EnsureIniDefaults_VersionUpdates_AgentConversionCounts()

		-- Obsoleted properties
		Settings.General.storeQuestExperienceHistory = nil
		Settings.General.useFastAgentSelection = nil
		Settings.General.stopOnMaxMercAA = nil
		Settings.General.trackQuestExperience = nil
		Settings.General.repeatTimeMinutes = nil
		Settings.General.monitorQuestRotation = nil
		Settings.General.questSelectionType = nil
		Settings.General.useQuestPriorities = nil

		-- From Mac->Lua, use bool instead of 0/1
		Settings.General.claimRewards = ConfigToNewBool(Settings.General.claimRewards, false)
		Settings.General.ignoreConversionQuests = ConfigToNewBool(Settings.General.ignoreConversionQuests, false)
		Settings.General.ignoreRecruitmentQuests = ConfigToNewBool(Settings.General.ignoreRecruitmentQuests, false)
		Settings.General.countAgentsBetweenCycles = ConfigToNewBool(Settings.General.countAgentsBetweenCycles, false)
		Settings.General.claimAgentPacks = ConfigToNewBool(Settings.General.claimAgentPacks, false)
		Settings.General.claimTetradrachmPacks = ConfigToNewBool(Settings.General.claimTetradrachmPacks, false)
		if (Settings.Debug ~= nil) then
			Settings.Debug.doNotRunQuests = ConfigToNewBool(Settings.Debug.doNotRunQuests, false)
			Settings.Debug.doNotFindAgents = ConfigToNewBool(Settings.Debug.doNotFindAgents, false)
		end

		CleanupPriorityGroups()
	end

	Settings.General.version = actions.SettingsVersion
end

return actions
