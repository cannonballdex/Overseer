-- ****************************************************************
-- * Overseer.lua.  Version 5.0 Heavly refractored by Cannonballdex
-- ****************************************************************

local mq = require('mq')
local mqfacade = require('overseer.mq_facade')
local string_utils = require('overseer.utils.string_utils')
local mqutils = require('overseer.utils/mq_utils')
local logger = require('overseer.utils.logger')
local json_file = require('utils.json_file')
local db = require('overseer.database')
local utils = require('overseer.utils.utils')
local _db_path_logged = false
local actions = {}

--- @type boolean
CycleIsRunning = false

--- @type boolean
actions.UsingCharacterConfiguration = false


Settings = {}

local nextAction = nil
local nextActionParameter = nil

---@type boolean
actions.TutorialIsRequired = true
---@type boolean
InProcess = false
---@type boolean
Aborting = false
---@type string
CurrentProcessName = 'Idle'
---@type number
NextQuestTimeStamp = 0
---@type boolean
CampingToDesktop = false

local hasInitializedQuestTimes = false
HasInitialized = false
NextRotationTimeStamp = 0
SecondsUntilNextRotation = 0
NextRotationTimeStampText = ''

CountAgentsBetweenCycles = false

---Perform any actions on first-time startup.
local function initialize()
	if (actions.HasMaxQuestLabel() == false and Settings.General.autoRestartEachCycle == true) then
		logger.warning('Disabling AutoRestart Due to Missing Key UI Fields')
		Settings.General.autoRestartEachCycle = false
	end
end

function actions.Main()
	initialize()

	local run_initial_full_cycle = Settings.General.runFullCycleOnStartup
	nextAction = 'Initialize'

	while true do
		ValidateCharacter()

		if (nextAction ~= nil) then
			if (nextAction == 'FullCycle') then SetCurrentProcess('Running complete cycle') RunCompleteCycle()
			elseif (nextAction == 'Initialize') then SetCurrentProcess('Initialze') ReadInitialData()
			elseif (nextAction == 'CountAgents') then SetCurrentProcess('Collecting Statistics') CollectAgentStatistics()
			elseif (nextAction == 'ClaimCompletedMissions') then SetCurrentProcess('Claiming completed missions') ClaimCompletedMissions()
			elseif (nextAction == 'CollectAllRewards') then SetCurrentProcess('Collecting Rewards') CollectAllRewards()
			elseif (nextAction == 'RunTutorial') then SetCurrentProcess('Running tutorial') RunTutorial()
			elseif (nextAction == 'RunConversions') then SetCurrentProcess('Running conversion quests') RunConversions()
			elseif (nextAction == 'RunRecoveryQuests') then SetCurrentProcess('Running recovery quests') RunRecoveryQuests()
			elseif (nextAction == 'RunRecruitQuests') then SetCurrentProcess('Running recruit quests') RunRecruitQuests()
			elseif (nextAction == 'RunGeneralQuests') then SetCurrentProcess('Running general quests') RunGeneralQuests()
			elseif (nextAction == 'SelectBestAgents') then SetCurrentProcess('Selecting best agents') SelectBestAgents()
			elseif (nextAction == 'PreviewGeneralQuestList') then SetCurrentProcess('Generating quest preview list') PreviewGeneralQuestList()
			elseif (nextAction == 'RetireEliteAgent') then SetCurrentProcess('Retiring Elite Agent') RetireEliteAgent(nextActionParameter)
			elseif (nextAction == 'RetireEliteAgents') then SetCurrentProcess('Retiring Elite Agents') RetireEliteAgents()
			elseif (nextAction == 'DumpQuestDetails') then SetCurrentProcess('Outputting Quest Details') DumpQuestDetails()
			elseif (nextAction == 'ClaimInventoryItems') then SetCurrentProcess('Claiming Inventory Items') ClaimAllAdditionalItems()
			end

			if (hasInitializedQuestTimes == false) then
				SetCurrentProcess('Initialize')
				ReadInitialData()
			end

			if (HasInitialized == false) then
				InitializeTimers()
				HasInitialized = true
			end

			EndCurrentProcess()
			nextAction = nil
		end

		if (run_initial_full_cycle == true) then
			nextAction = 'FullCycle'
			run_initial_full_cycle = false
		end

		UpdateTimers()
		mq.delay(1000)
		end
end

-- simple agent stats summary print (call from OutputAgentCounts before EndCurrentProcess)
local function print_agent_stats_summary()
  logger.info('\atAgent summary:\ao')
  for i = 1, 4 do
    local rarity = AgentStatisticCounts[i] and AgentStatisticCounts[i][2] or ('rarity' .. tostring(i))
    local unique = tonumber(AgentStatisticCounts[i] and AgentStatisticCounts[i][4]) or 0
    local duplicates = tonumber(AgentStatisticCounts[i] and AgentStatisticCounts[i][5]) or 0
    local total = unique + duplicates
    logger.info('  %s: total=%d (unique=%d, duplicates=%d)', tostring(rarity), total, unique, duplicates)
	end
end

-- 1==Idle, 2==Not INGAME, 3==Char Pause
local inCharacterPauseState = false
local previousGameState = nil
function ValidateCharacter()
	local justChangedGameState = false
	local gameState = mqfacade.GetGameState()
	if (previousGameState ~= gameState) then
		previousGameState = gameState
		if (gameState ~= 'INGAME') then
			CurrentProcessName = 'Paused. Waiting for In Game'
			nextAction = nil
			return
		end

		CurrentProcessName = 'Idle'
		justChangedGameState = true
	end

	if (mqfacade.GetCharNameAndClass() == TrackingCharacter) then
		return
	end

	if (inCharacterPauseState and justChangedGameState == false) then
		return
	end

	if (mqfacade.GetCharLevel() < 85) then
		inCharacterPauseState = true
		CurrentProcessName = 'Paused.  Character must be level 85 to utilize overseer.'
	elseif (Settings.General.pauseOnCharacterChange == true) then
		-- We've been asked to pause on character change
		inCharacterPauseState = true
		CurrentProcessName = string.format('Paused.  Waiting for %s', TrackingCharacter)

		return
	end
end

function SetCurrentProcess(processName)
	InProcess = true
	CurrentProcessName = processName
end

function EndCurrentProcess()
	Aborting = false
	InProcess = false
	CurrentProcessName = 'Idle'
end

function actions.AbortCurrentProcess()
	if (Aborting == true) then return end
	if (InProcess == false) then logger.info("No process to abort") end

	logger.info("REQUEST: Abort Current Process")
	Aborting = true
end

function actions.SetAction(actionName, actionParameter)
	nextAction = actionName
	nextActionParameter = actionParameter
end

function InitializeTimers()
	if (TutorialRequired()) then return end

	ParseQuestRotationTime()
	UpdateTimers()
end

local updateTimerPendingNextRun = false

-- NextRotationTimeStamp: When the next rotation occurs
-- TimeUntilNextRotation: Seconds until NextRotationTimeStamp
-- NextRotationTimeStampText: Time Until NextRotationTimeStamp formatted (i.e. '12h:10m:5s')
function UpdateTimers()
	if (TutorialRequired()) then return end

	SecondsUntilNextRotation, NextRotationTimeStampText = string_utils.seconds_until_with_display(NextRotationTimeStamp)
	if (MinutesUntilNextQuest > 0 and NextQuestTimeStamp ~= nil) then
		SecondsUntilNextQuest, NextQuestTimeStampText = string_utils.seconds_until_with_display(NextQuestTimeStamp)
	else
		SecondsUntilNextQuest = 0
		NextQuestTimeStampText = ''
	end

	if (NextQuestTimeStamp ~= nil and SecondsUntilNextQuest <= 0) then
		if (Settings.General.autoRestartEachCycle) then
			logger.warning("Next Quest Available For Claiming.  Initiating Full Cycle.")
			logger.debug("%s, %s, %s", NextQuestTimeStamp, MinutesUntilNextQuest, NextQuestTimeStamp)
			actions.SetAction('FullCycle')
			return
		end

		if (updateTimerPendingNextRun == false) then
			updateTimerPendingNextRun = true
			if (MinutesUntilNextQuest > 0) then MinutesUntilNextQuest = 0 end
			NextQuestTimeStamp = 0
			logger.warning("Next Quest Available For Claiming.")
		end
	end

	if (SecondsUntilNextRotation <= 0) then
		if (Settings.General.autoRestartEachCycle) then
			logger.warning("Quest Rotation Cycle Available.  Initiating Full Cycle.")
			logger.debug("UpdateTimers Rotation: %s, %s, %s", NextRotationTimeStamp, SecondsUntilNextRotation, NextRotationTimeStampText)
			actions.SetAction('FullCycle')
		else
			logger.warning("Quest Rotation Cycle Available.")
			ParseQuestRotationTime()
		end
	end
end

local tabs = { 'OW_OverseerQuestsPage', 'OW_OverseerMinionsPage', 'OW_OverseerActiveQuestsPage', 'OW_OverseerStatsPage' }
local function ChangeTab(tabIndex)
	if (mq.TLO.Window('OverseerWnd/OW_Subwindows').Child(tabs[tabIndex]).Open() == true) then
		return
	end

	mqutils.cmdf('/notify OverseerWnd OW_Subwindows tabselect %s', tabIndex)
	mq.doevents()
	mq.delay(1000, mq.TLO.Window('OverseerWnd/OW_Subwindows').Child(tabs[tabIndex]).Open)
end

local function AvailableQuestsMoreThan(count)
	return mq.TLO.Window(AvailableQuestList).Items() > count
end

function TutorialRequired()
	if (actions.TutorialIsRequired == false) then return false end

	-- Added for performance but other one should be valid enough
	-- if (AvailableQuestListLoaded == true) then
	-- 	actions.TutorialIsRequired = AvailableQuestListLoaded == true and AvailableQuestCount < 6
	-- 	return actions.TutorialIsRequired
	-- end

	actions.TutorialIsRequired = AvailableQuestsMoreThan(6) == false

	-- This method doesn't work as server won't always send the info
	-- local text = mq.TLO.Window('OverseerWnd/OW_QSP_StatsQuestsCompleteValue').Text()
	-- local textNum = tonumber(text)
	-- actions.TutorialIsRequired = (textNum == nil or textNum < 4)

	return actions.TutorialIsRequired
end

function ReadInitialData()
	local wasOverseerOpen = IsOverseerWindowOpen()
	OpenOverseerWindow()

	if (TutorialRequired() == false) then
		DetermineNextQuestTimes()
		DetermineNextRunTime()
		InitializeTimers()

		HasInitialized = true
	end

	if (wasOverseerOpen == false) then CloseOverseerWindow() end
end

function actions.AbandonCampingOut()
	mq.cmd('/camp')
	CampingToDesktop = false
end

function CampCharacterToDesktop()
	if (not Settings.General.campAfterFullCycle) then
		return
	end

	CampingToDesktop = true
	mq.cmd('/camp desktop')

	if (Settings.General.campAfterFullCycleFastCamp) then
		mqutils.WaitForWindow('ConfirmationDialogBox')
		mq.cmd('/yes')
	end
end

function RunCompleteCycle()
	-- Reset these in case they were modified by a debug run
	DebugNoRunQuestMode = Settings.Debug.doNotRunQuests
	DebugNoSelectAgents = Settings.Debug.doNotFindAgents

	if (TutorialRequired()) then return end

	UpdateTimers()
	if (DebugNoRunQuestMode == true) then
		logger.warning('DEBUG: Not Actually Running Quests due to Debug|doNotRunQuests configuration flag')
	end

	CycleIsRunning = true

	if (mqfacade.GetCharLevel() < 85) then
		if (Settings.General.autoRestartEachCycle) then
			logger.error('Character must be level 85+ to utilize Overseer. Exiting.')
			os.exit()
		end

		logger.error('Character must be level 85+ to utilize Overseer.')
		return
	end

	-- Reset any variables we're keying off of
	TooManyPendingRewards = false
	AvailableQuestListLoaded = false
	ActiveQuestListDirty = true

	logger.info('Starting Cycle ' .. os.date('(%H:%M:%S)', os.time()))

	ClaimAllAdditionalItems()	if Aborting then return end
	OpenOverseerWindow()		if Aborting then return end
	CollectAllRewards()			if Aborting then return end
	ClaimCompletedMissions()	if Aborting then return end
	CollectAllRewards()			if Aborting then return end
	RunConversions()			if Aborting then return end
	RunRecoveryQuests()			if Aborting then return end
	RunRecruitQuests()			if Aborting then return end
	RunGeneralQuests()			if Aborting then return end
	DetermineNextQuestTimes()	if Aborting then return end
	DetermineNextRunTime()		if Aborting then return end
	CloseOverseerWindow()		if Aborting then return end
	ClaimAllAdditionalItems()	if Aborting then return end
	UpdateTimers()				if Aborting then return end
	ParseQuestRotationTime()	if Aborting then return end

	local nextCheck = math.min(MinutesUntilNextQuest, math.floor(SecondsUntilNextRotation / 60))
	if nextCheck >= 0 then
		logger.warning('*** ' .. nextCheck .. ' minutes until next overseer check.  ' .. os.date('(%H:%M:%S)', os.time()))
	else
		logger.warning('Calculated on second run.' .. os.date('(%H:%M:%S)', os.time()))
	end
	if (Settings.General.campAfterFullCycle) then
		CampCharacterToDesktop()
	end
	-- Schedule collect statistics after each completed cycle
	CollectAgentStatistics()
end

function PreviewGeneralQuestList()
	DebugNoRunQuestMode = true
	DebugNoSelectAgents = true
	ReloadAvailableQuests(false)
	OpenOverseerWindow()
	RunConversions()
	RunRecoveryQuests()
	RunRecruitQuests()
	RunGeneralQuests()
	OutputAvailableQuestList()
end

function CursorCheck()
	if mq.TLO.Cursor.ID() then mq.cmd('/autoinv') end
end

function actions.GetActiveQuestCounts()
	local activeQuestsText = mq.TLO.Window('OverseerWnd/OW_AQP_CountLabel').Text()
	if (activeQuestsText == nil) then
		return nil, nil
	end

	local activeQuests = string.sub(activeQuestsText, 20, 20)
	local maxActiveQuests = string.sub(activeQuestsText, 24, 24)
	return activeQuests, maxActiveQuests
end

-- Determine if we are at max cap for available quests
function AreAtMaxQuests()
	if (DebugNoRunQuestMode == true) then
		return false
	end

	local activeQuests, maxActiveQuests = actions.GetActiveQuestCounts()

	if (activeQuests >= maxActiveQuests) then
		return true
	end
	return false
end

-- Ensures MQ2Rewards plug-in is loaded, returning true if we had to load, false if not
local function load_mq2rewards()
	if (mq.TLO.Plugin("MQ2Rewards").IsLoaded()) then return true end

	logger.warning('MQ2Rewards required for collecting rewards. Loading.')
	mq.cmd("/plugin mq2rewards load")
	if (mq.TLO.Plugin("MQ2Rewards").IsLoaded() == false) then
		logger.error("MQ2Rewards could not be loaded. Rewards will not be collected.")
		return false
	end

	return true
end

-- NOTE: Disabled due to change in MQ2 core that doesn't allow unloading of a plugin loaded by the same script (i.e this one)
local function unload_mq2rewards()
	-- if (mq.TLO.Plugin("MQ2Rewards").IsLoaded()) then
	-- 	mq.cmd("/plugin mq2rewards unload")
	-- end
end

---Finds a given reward by name and returns the index and RewardItem TLO
---@return RewardItem?,number? RewardItem TLO and index integrer or nil to both if not found.
local function find_specific_reward_by_name(rewardName)
	local rewardIndex = mq.TLO.Rewards.Count()
	if (rewardIndex == 0) then return nil,nil end

	for index = rewardIndex, 1, -1 do
		local rewardItem = mq.TLO.Rewards.Reward(rewardIndex)
		if (rewardItem.Text() == rewardName) then
			return rewardItem, rewardIndex
		end
	end

	return nil, nil
end

local ClaimReward_Successful = 1
local ClaimReward_Skipped = 0
local ClaimReward_Error = -1

---Finds reward with specified name and collects, if configurations facilitate.
---@param rewardName string Defines name of reward to look up
---@param wait_for_reward_delay_ms number? If defined, wait this long for reward to appear in the window
---@return integer 1 if able to complete reward, 0 if not one for us to complete, -1 if error attempting to complete
local function collect_specific_reward(rewardName, wait_for_reward_delay_ms)
	if (Settings.General.rewards.claimRewards == false) then
		return ClaimReward_Skipped
	end

	load_mq2rewards()
	if (mq.TLO.Plugin("MQ2Rewards").IsLoaded() == false) then
		logger.warning('Not claiming rewards. MQ2Rewards unable to be loaded.')
		return ClaimReward_Skipped
	end

	::try_again::
	local rewardItem, rewardIndex = find_specific_reward_by_name(rewardName)
	if (rewardItem == nil or rewardIndex == nil) then
		if (wait_for_reward_delay_ms == nil or wait_for_reward_delay_ms <= 0) then
			printf('\at REWARD NOT FOUND: %s', rewardName)
			-- os.exit()
			return ClaimReward_Skipped
		end

		mq.delay(wait_for_reward_delay_ms, function() return mq.TLO.Rewards.Reward(rewardName).Text() ~= nil end)

		wait_for_reward_delay_ms = nil
		goto try_again
	end

	-- TODO: Handle Gather EXP Details for this mechanism
	return CollectSpecificReward(rewardItem, rewardIndex, false, nil)
end

local function claim_missions_and_rewards()
	OpenOverseerWindow()
	logger.warning('Claiming Completed Missions and Rewards As Appropriate')
	ChangeTab(3)

	::process_next::
	local claim_quest_result = EnumerateActiveQuests(true)
	if (claim_quest_result ~= nil) then
		collect_specific_reward(claim_quest_result, 3000)
		goto process_next
	end

	ActiveQuestListDirty = false
end

function ClaimCompletedMissionsAndClaimRewards()
	OpenOverseerWindow()
	logger.warning('Claiming Completed Missions')
	ChangeTab(3)
end

-- Walk all active quests and see if any are [Success] or [Failed].  Click if so.
function ClaimCompletedMissions()
	if (true) then
		claim_missions_and_rewards()
		return
	end

	if (Settings.General.rewards.maximizeStoredExpRewards == true) then
		ClaimCompletedMissionsAndClaimRewards()
		return
	end

	OpenOverseerWindow()
	logger.warning('Claiming Completed Missions')
	ChangeTab(3)
	EnumerateActiveQuests(false)
	ActiveQuestListDirty = false
end

function DetermineNextQuestTimesStart()
	MinutesUntilNextQuest = -1
	AllActiveQuestCount = 0
end

-- This method structured this way to allow unit testing
function AddNextQuestTime()
	AddNextQuestTimeInternal(mq.TLO.Window(CurrentQuestName).Text(), mq.TLO.Window(CurrentQuestCompletionTime).Text())
end

function AddNextQuestTimeInternal(questName, completionTime)
	local result = ParseDuration(completionTime)
	AllActiveQuestCount = AllActiveQuestCount + 1
	AllActiveQuests[AllActiveQuestCount].name = questName
	AllActiveQuests[AllActiveQuestCount].timeRemainingString = completionTime
	AllActiveQuests[AllActiveQuestCount].completionMinutes = result
end

function actions.PostProcessNextRunTimes()
	if (MinutesUntilNextQuest == 0) then
		logger.warning('No pending quests.')

		-- If at 10/10, we can't claim more 'til rotation...
		local runningQuestCount = mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_AQP_CompletedLabel').Text()
		if (string.find(runningQuestCount, "10 / 10")) then
			logger.info('Max quests claimed for this cycle. Must wait until next rotation.')
			NextQuestTimeStamp = NextRotationTimeStamp
			MinutesUntilNextQuest = SecondsUntilNextRotation / 60
		end

	else
		logger.warning('Next Quest Completes In \ay%s\ao.', NextQuestCompletion)

		if (MinutesUntilNextQuest > 0) then
			NextQuestTimeStamp = os.time() + (MinutesUntilNextQuest*60)
		end
	end
end

function DetermineNextRunTime()
	local NextQuestWindow = 10

	hasInitializedQuestTimes = true

	MinutesUntilNextQuest = -1

	if (AllActiveQuestCount < 1) then
		return
	end

	-- Quick sort the list to order by Minutes Until Next
	local order = {}
	for index = 1, AllActiveQuestCount do
		order[index] = index
	end

	for index = 1, AllActiveQuestCount do
		if (index == AllActiveQuestCount) then
			break
		end

		local innerStart = index + 1
		for inner = innerStart, AllActiveQuestCount do
			-- If inner < index --- swap
			if (AllActiveQuests[inner].completionMinutes < AllActiveQuests[order[index]].completionMinutes) then
				local temp = order[index]
				order[index] = order[inner]
				order[inner] = temp
			end
		end
	end

	if (MinutesUntilNextQuest == -1) then
		NextQuestCompletion = AllActiveQuests[order[1]].timeRemainingString
		MinutesUntilNextQuest = AllActiveQuests[order[1]].completionMinutes
	else
		local windowEnd
		for index = 1, AllActiveQuestCount do
			local checkMinutes = AllActiveQuests[order[index]].completionMinutes
			if (checkMinutes < windowEnd) then
				MinutesUntilNextQuest = AllActiveQuests[order[index]].completionMinutes
				windowEnd = MinutesUntilNextQuest + NextQuestWindow
			end
		end
	end

	actions.PostProcessNextRunTimes()
end

local function SelectAvailableQuestNode(NODE)
	mqutils.action(NODE.Child('OW_BtnQuestTemplate').LeftMouseUp)
	mq.delay(1000, function() return NODE.Child('OW_BtnQuestTemplate').Text() == mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_TitleLabel').Text() end)
end

---Selects the active quest (by node) supplied and waits for it to register before returning
local function SelectActiveQuestNode(NODE)
	mqutils.action(NODE.Child('OW_BtnQuestTemplate').LeftMouseUp)
	mq.delay(1000, function() return NODE.Child('OW_BtnQuestTemplate').Text() == mq.TLO.Window(CurrentQuestName).Text() end)
end

function DetermineNextQuestTimes()
	-- If we've already calculated and nothing changed...
	if (not ActiveQuestListDirty) then
		return
	end

	DetermineNextQuestTimesStart()
	if (mq.TLO.Window(ActiveQuestList).Children() == false) then
		return
	end

	local NODE = mq.TLO.Window(ActiveQuestList).FirstChild

	ChangeTab(3)
	::nextNode::
	SelectActiveQuestNode(NODE)

	AddNextQuestTime()

	if (NODE.Siblings()) then
		NODE = NODE.Next
		goto nextNode
	end
end

function IsOverseerWindowOpen()
	return mq.TLO.Window('OverseerWnd').Open()
end

function OpenOverseerWindowLight()
	if (IsOverseerWindowOpen() == false) then
		mq.cmd('/overseer')
	end
end

function OpenOverseerWindow()
	if (IsOverseerWindowOpen()) then
		return
	end

	local loopCount = 1
	::loop::
	mq.cmd('/overseer')
	mq.doevents()
	if (IsOverseerWindowOpen() == false) then mq.delay(4000) end

	mq.doevents()

	if (mq.TLO.Window('OverseerWnd').Open() == false) then
		if (loopCount > 10) then
			logger.error('Cannot open OverseerWnd.  Ending.')
			--maybe?
			return
		end
		loopCount = loopCount + 1
		logger.warning('...waiting for Overseer system to initialize.')
		goto loop
	end
end

function CloseOverseerWindowLight()
	if (IsOverseerWindowOpen()) then
		mq.cmd('/overseer')
	end
end

function CloseOverseerWindow()
		::closeWindow::
	if (IsOverseerWindowOpen()) then
		mq.cmd('/overseer')
	end

	-- send the close command if the window is open, then wait up to 2s for it to close
	if IsOverseerWindowOpen() then
	mq.cmd('/overseer')
	mq.doevents()
	local closed = mq.delay(2000, function() return IsOverseerWindowOpen() == false end)
	if not closed then
		logger.warning("OverseerWnd did not close within 2s; continuing anyway")
	end
	end

	if (IsOverseerWindowOpen()) then
		goto closeWindow
	end
end

local function is_quest_completed(success_text)
	return string_utils.contains(success_text, 'Success') or string_utils.contains(success_text, 'Failure')
end

---Given an Active Quest Node, will complete it if appropriate and able
---@return boolean,string? True + Name of completed quest, if able, otherwise False,Nil
local function process_active_quest(NODE)
	SelectActiveQuestNode(NODE)

	-- If at 10/10, only claim Conversions...
	local runningQuestCount = mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_AQP_CompletedLabel').Text()
	if (string.find(runningQuestCount, "10 / 10")) then
		local difficulty = mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_DifficultyLabel').Text()
		if (string.find(difficulty, "Conversion") == nil) then
			return false, nil
		end
	end

	if (NODE == nil or tostring(NODE) == "NULL" or tostring(NODE) == nil) then
		logger.error("ProcessActiveQuest: Error on final.  Skipping away...")
		return false, nil
	end
	if NODE.Child == nil or NODE.Child('OW_BtnQuestTemplate')() == nil then
		return false, nil
	end

	SelectActiveQuestNode(NODE)

	if NODE.Child == nil or NODE.Child('OW_BtnQuestTemplate').Text() == nil then
		return false, nil
	end

	local questName = NODE.Child('OW_BtnQuestTemplate').Text()

	local wait_for_loading = function()
		-- Need to wait for the quest to fully load. Only way to determine is the Success field updates to a result.
		local successText = mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_SuccessValue').Text()
		while(is_quest_completed(successText) == false) do
			mq.delay(1000)
			mq.doevents()
			successText = mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_SuccessValue').Text()
		end
	end

	-- Represents "Collect Reward!" button for a successfully completed quest.
	if (mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CollectRewardButton').Enabled()) then
		logger.info('\ay%s\ao has succeeded.  Claiming.', questName)
		wait_for_loading()
		mqutils.leftmouseup('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CollectRewardButton')
	elseif (mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CompleteQuestButton').Enabled()) then
		logger.info('\ay%s\ao has failed.  Completing.', questName)
		wait_for_loading()
		mqutils.leftmouseup('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CompleteQuestButton')
	else
		local duration = mq.TLO.Window(CurrentQuestCompletionTime).Text()
		logger.debug('Not claiming \ay%s\ao, Duration: \ay%s', questName, duration)
		return false, nil
	end

	-- TODO: Logic good UNLESS we have two quests IN A ROW with the same name to be claimed. Not sure even possible, but we should address
	-- wait up to 4s for either the quest to be removed OR the reward selection window to open
	mq.delay(4000, function()
		return NODE == nil
			or mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_TitleLabel').Text() ~= questName
			or mq.TLO.Window('RewardSelectionWnd').Open()
	end)
	mq.delay(10)
	mq.doevents()
	-- If rewards UI opened, hand off to reward collector (this is expected for option-based rewards)
if mq.TLO.Window('RewardSelectionWnd').Open() then
    logger.trace("RewardSelectionWnd opened for '%s' — delegating claim to reward collector", questName)
    return true, questName
end

-- If still present and no reward UI, treat as failure
	if (NODE ~= nil and mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_TitleLabel').Text() == questName) then
		logger.warning("Claiming completed mission does not appear to have succeeded: %s", questName)

		-- For now use this return.  Needs more testing.
		return false, nil
	end

	return true, questName
end

---Walks all active quests and completes any that are availble
---@param onlyProcessFirst boolean If true, only claims the first available and returns the name of it; else does all and returns nil
---@return string? Name of completed quest, if param is true, else nil
function EnumerateActiveQuests(onlyProcessFirst)
	local currentNode = nil
	local nextNode = nil
	local nextNodeCheck = ''

	ActiveQuestListDirty = false

	DetermineNextQuestTimesStart()

	if mq.TLO.Window(ActiveQuestList).Children() == false then
		logger.info('No active quests')
		return nil
	end

	::nextNodeX::
	if (TooManyPendingRewards) then
		return nil
	end

	if (mq.TLO.Window(ActiveQuestList).Children() == false) then
		-- We've claimed all active quests
		return nil
	end

	if (currentNode == nil) then
		nextNode = mq.TLO.Window(ActiveQuestList).FirstChild
	else
		if (not currentNode.Siblings()) then
			return nil
		end

		nextNode = currentNode.Next

		-- Sanity check to help avoid infinite loop
		if (mq.TLO.Window(nextNode).Child('OW_BtnQuestTemplate').Text() == nextNodeCheck) then
			-- We THINK the next quest should have been removed and we have new, but we don't.
			logger.warning('INFINITE LOOP SAVE. ' .. nextNodeCheck)
			currentNode = nextNode
			goto nextNodeX
		end
	end

	-- Store name we're testing to save from catastrophic loop if things are buggy/laggy
	nextNodeCheck = nextNode.Child('OW_BtnQuestTemplate').Text()

	local result, name = process_active_quest(nextNode)
	if (result == false) then
		currentNode = nextNode
		AddNextQuestTime()
	elseif (onlyProcessFirst) then
		return name
	end

	goto nextNodeX
end

function SkipRewardOption(rewardOptionName)
	if (rewardOptionName ~= "Character Experience") then return false end

	local maxLevel = Settings.General.maxLevelForClaimingExpReward
	if (Settings.General.maxLevelUseCurrentCap) then
		maxLevel = mq.TLO.Me.MaxLevel()
	end
	local maxPct = Settings.General.maxLevelPctForClaimingExpReward
	if (maxLevel == nil) then return false end
	if (maxPct == nil) then maxPct = 95 end


	if (maxLevel < mqfacade.GetCharLevel()) then return true end
	if (maxLevel > mqfacade.GetCharLevel()) then return false end

	if (maxPct < mq.TLO.Me.PctExp()) then return true end
	return false
end

local function collect_reward_option(option, rewardItem, rewardOptionName, rewardIndex)
	local retry_attempts = 1

	::retryOptionClaim::
	option.Select()

	logger.info('Claiming \ay%s\ao (\ag%s\ao)', option.Text(), rewardItem.Text())
	mq.delay(2000, function() return option.Selected() == true and option.Text() == rewardOptionName end)

	--- TEMP logic to detect not-select option
	if (option.Selected() == false or option.Text() ~= rewardOptionName) then
		if (retry_attempts <= 0) then
			logger.warning('Unable to select option. Starting reward collection from the top.')
			return false
		end

		retry_attempts = retry_attempts - 1
		logger.info('Option selection issue.  Attempting again.')
		mqutils.action(mq.TLO.Rewards.Reward(rewardIndex).Option(rewardOptionName).Select)
		goto retryOptionClaim
	elseif (option.Text() ~= rewardOptionName) then
		-- Verify the selected option is the one we want
		logger.info('Incorrect option selected (\ay%s\ao). Skipping.', option.Text())
		return false
	end

	rewardItem.Claim()
	mq.delay(100)
	if mq.TLO.Cursor.ID() then mqutils.autoinventory() end
	return true
end

local function IsClaimableReward(rewardItem)
	if (string_utils.starts_with(rewardItem.Text(), "Recruit") or string_utils.starts_with(rewardItem.Text(), "Discredited") or string_utils.starts_with(rewardItem.Text(), "The First Recruitment")) then
		return true
	end

	if (rewardItem.Options() == 0 and rewardItem.Items() >= 3) then
		if (rewardItem.Item(2).Text() == "Recruitment Overseer Experience" or rewardItem.Item(2).Text() == "Recovery Overseer Experience") then
			return true
		end
	end

	return false
end

function RewardItemToListItem(index, rewardItem)
	local listItem = {
		index = index,
		name = rewardItem.Text(),
		experience = ParseRewardExpFromReward(index, rewardItem)
	}

	return listItem
end

---Collects the specified reward item, if it exists and we're configured to do so
---@return integer 1 if able to complete reward, 0 if not one for us to complete, -1 if error attempting to complete
function CollectSpecificReward(rewardItem, rewardIndex, gather_exp_list_only, reward_exp_list)
	if (rewardItem.Text() == nil) then return ClaimReward_Skipped end

	mqutils.action(rewardItem.Select)

	if (IsClaimableReward(rewardItem)) then
		logger.info('Claiming ' .. rewardItem.Text())
		rewardItem.Claim()
		if mq.TLO.Cursor.ID() then mqutils.autoinventory() end

		return ClaimReward_Successful
	end

	if (rewardItem.Options() == 0) then
		logger.info('Skipping ' .. rewardItem.Text() .. ' as no options exist.')
		return ClaimReward_Skipped
	end

	if (string_utils.starts_with(rewardItem.Text(), "Elite Agent Echo")) then
		if (Settings.General.claimEliteAgentEchos == false or Settings.Rewards.eliteAgentEchoReward == nil or Settings.Rewards.eliteAgentEchoReward == 'None') then
			logger.info('Skipping Elite Agent Echo due to configuration settings.')
			return ClaimReward_Skipped
		end

		local option = rewardItem.Option(Settings.Rewards.eliteAgentEchoReward)
		if (tostring(option) == "NULL") then
			logger.error('Skipping Elite Agent Echo as configured reward is missing (assumed invalid): %s', Settings.Rewards.eliteAgentEchoReward)
			return ClaimReward_Skipped
		end

		collect_reward_option(option, rewardItem, Settings.Rewards.eliteAgentEchoReward, rewardIndex)
		return ClaimReward_Successful
	end

	local rewardOptionCount = Settings.Rewards.index
	for optionIndex = 1, rewardOptionCount do
		if Aborting then return ClaimReward_Skipped end
		local rewardOptionName = Settings.Rewards[optionIndex]
		if (SkipRewardOption(rewardOptionName)) then goto nextRewardOption end

		local option = rewardItem.Option(rewardOptionName)
		if (option.Text() ~= nil) then
			mq.delay(250)

			if (gather_exp_list_only) then
				logger.trace('Exp Save ' .. rewardItem.Text())
				table.insert(reward_exp_list, RewardItemToListItem(rewardIndex, rewardItem))
			else
				if (collect_reward_option(option, rewardItem, rewardOptionName, rewardIndex) == false) then
					return ClaimReward_Error
				end
			end

			-- Put to inventory in case the user selected something that pops on the cursor
			if mq.TLO.Cursor.ID() then mqutils.autoinventory() end

			if (option.Text() == "Overseer Tetradrachm") then
				logger.info("    You now have %s Overseer Tetradrachm", mq.TLO.Me.OverseerTetradrachm())
			end
			break
		end

		::nextRewardOption::
	end

	return ClaimReward_Successful
end

---Walks all outstanding rewards, collecting any our current configuration requests
---@param gather_exp_list_only boolean If true, does not claim rewards, but builds list of exp rewards
---@return boolean, table? If true, reward selection conmpleted successfully; else if false - claiming failed for error reasons.
function CollectAllRewards_Internal(gather_exp_list_only)
	if (Settings.General.rewards.claimRewards == false) then
		logger.info('Nothing to claim.')
		logger.warning('Not claiming rewards per configuration')
		return true
	end

	-- if (Settings.General.rewards.maximizeStoredExpRewards == true) then
	-- 	logger.info('Not claiming rewards per configuration (maximize exp)')
	-- 	return
	-- end

	local weLoadedMq2Rewards = load_mq2rewards()
	if (mq.TLO.Plugin("MQ2Rewards").IsLoaded() == false) then
		logger.warning('Not claiming rewards. MQ2Rewards unable to be loaded.')
		return true
	end

	logger.warning('Collecting any pending rewards')

	::restart_process::
	local rewardIndex = mq.TLO.Rewards.Count()
	if (rewardIndex == 0 or OpenRewardWindow() == false) then
		logger.info('No rewards to claim')
		return true
	end

	local reward_exp_list = {}

	-- Go backwards as list changes when we claim. Simpler than messing with the index
	while (true) do
		if Aborting then return true end

		mq.doevents()

		local rewardItem = mq.TLO.Rewards.Reward(rewardIndex)
		if (CollectSpecificReward(rewardItem, rewardIndex, gather_exp_list_only, reward_exp_list) == false) then
			return false
		end

		mq.doevents()
		if (ErrorGrantingReward) then
			ErrorGrantingReward = false
			logger.warning("Error granting rewards detected. Starting process over.")
			goto restart_process
		end

		rewardIndex = rewardIndex - 1
		if (rewardIndex == 0) then break; end
	end

	if (gather_exp_list_only) then return true, reward_exp_list end

	mq.doevents()
	if (ErrorGrantingReward) then
		ErrorGrantingReward = false
		logger.warning("Error granting rewards detected. Starting process over.")
		goto restart_process
	end

	if mq.TLO.Window('RewardSelectionWnd').Open() then
		CloseRewardWindow()
	end

	-- If we had to load MQ2Rewards, then unload. Play nicely with other scripts
	if (weLoadedMq2Rewards) then
		unload_mq2rewards()
	end

	return true
end

local function sort_exp_rewards(t,a,b)
	if (t[b].experience == nil) then return true end
	if (t[a].experience == nil) then return false end
	return t[b].experience > t[a].experience
end

function CollectAllRewards()
	local retry_count = 1
	::retry_reward_collection::

	ErrorGrantingReward = false

	if (Settings.General.rewards.maximizeStoredExpRewards) then
		local result, reward_list = CollectAllRewards_Internal(true)
		if (result == true) then
			if (#reward_list <= Settings.General.rewards.storedExpRewardsCount) then
				logger.trace('Exp Reward count under specified for saving.  Claiming none.')
				return
			end

			local delta = #reward_list - Settings.General.rewards.storedExpRewardsCount
			logger.trace('%s extra rewards to claim.', delta)
			if (reward_list ~= nil) then
				for _,reward in utils.spairs(reward_list, sort_exp_rewards) do
					logger.info('\aw Claiming next lowest exp reward: \at%s  \ag%s', reward.name, reward.experience)
				end
			end

			return
		end
	else
		local result, _ = CollectAllRewards_Internal(false)

		if (result == true) then
			return
		end
	end

	if (retry_count <= 0) then
		logger.warning('Error claiming rewards. Leaving for this cycle.')
		return
	end

	retry_count = retry_count - 1
	goto retry_reward_collection
end

function RunConversions()
	if (Settings.General.ignoreConversionQuests == true) then
		logger.warning('Skipping conversion quests (per configuration).')
		return
	end

	OpenOverseerWindow()

	logger.warning('Checking all conversion quests')

	ChangeTab(1)

	LoadAvailableQuests()	if Aborting then return end

	ProcessConversion(1, 'Common Conversion')	if Aborting then return end
	ProcessConversion(2, 'Uncommon Conversion')	if Aborting then return end
	ProcessConversion(3, 'Rare Conversion')		if Aborting then return end
end

function RunCategoryQuests(category)
	if (AreAtMaxQuests()) then
		logger.warning('\ayMax Overseer Quests Already Running')
		return
	end

	OpenOverseerWindow()

	ChangeTab(1)

	LoadAvailableQuests()

	EnumerateAvailableQuests(IsQuestByCategory, ProcessGeneralQuest, category)
end

function RunRecruitQuests()
	if (Settings.General.ignoreRecruitmentQuests == true) then
		logger.warning('Skipping recruitment quests (per configuration).')
		return
	end

	RunCategoryQuests('Recruitment')
end

function RunRecoveryQuests()
	if (Settings.General.ignoreRecoveryQuests == true) then
		logger.warning('Skipping recovery quests (per configuration).')
		return
	end

	RunCategoryQuests('Recovery')
end

function ReloadAvailableQuests(loadExtraData)
	AvailableQuestListLoaded = false
	ChangeTab(1)
	LoadAvailableQuests(loadExtraData)
end

-- Option are the items in the left pane (i.e. "Character Experience")
local function reward_select_option(reward_index, option_index)
	mqutils.cmdf('/notify RewardSelectionWnd RewardSelectionOptionList listselect %s', option_index)
	mq.delay(1000, function() return mq.TLO.Rewards.Reward(reward_index).Option(option_index).Selected() ~= nil end)
end

-- Items are the sub-informationals on the right (i.e. "All of the options for this reward include:....")
local function reward_select_item(reward_index, option_index, item_index)
	mqutils.cmdf('/notify RewardSelectionWnd RewardSelectionItemList listselect %s', item_index)
	mq.delay(1000, function() return mq.TLO.Window('RewardSelectionWnd/RewardSelectionItemList').GetCurSel() == item_index end)
end

function ParseRewardExpFromReward(index, rewardItem)
	if (index ~= nil) then return index end

	local questName = rewardItem.Text()
	local listIndex = 6
	local exp_string_compare = 'Experience (No AA Exp)'
	if (mq.TLO.Rewards.Reward(questName).Item(listIndex).Text() ~= exp_string_compare) then
		listIndex = 5
		if (mq.TLO.Rewards.Reward(questName).Item(listIndex).Text() ~= exp_string_compare) then
			logger.trace('No exp details for quest: %s', questName)
			return 0
		end
	end

	reward_select_item(questName, 1, listIndex)

	local rewardDescription = mq.TLO.Window('RewardSelectionWnd/RewardPageTabWindow').Tab(questName).Child('RewardSelectionDescriptionArea').Text()

	-- Parse out the exp %.  Format of valid string is:
	-- "1.23% of the experience rewquired to go from level X to Y and 23.45% of a mercenary AA point."
	local bits = string_utils.split(rewardDescription, '%%')
	return tonumber(bits[1])
end

function LoadAvailableQuestsExperience(quest_name)
	mqutils.leftmouseup('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_PreviewRewardButton')
	mq.delay(1000, function() return mq.TLO.Rewards.Reward(1).Text() == quest_name end)

	local reward = mq.TLO.Rewards.Reward(1)
	AllAvailableQuests[AvailableQuestCount].experience = ParseRewardExpFromReward(nil, reward)
end

function LoadAvailableQuestsExtraData(quest_name)
	mqutils.leftmouseup('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_PreviewRewardButton')
	mq.delay(1000, function() return mq.TLO.Rewards.Reward(1).Text() == quest_name end)

	local reward = mq.TLO.Rewards.Reward(1)
	local questName = reward.Text()

	reward_select_item(1, 1, 5)

	local rewardDescription = mq.TLO.Window('RewardSelectionWnd/RewardPageTabWindow').Tab(questName).Child('RewardSelectionDescriptionArea').Text()
	local experience, mercenaryAas = rewardDescription:match("([^%%]*)%%[a-zA-Z0-9 ]* and ([0-9.]*)")

	-- Two possible descriptions of Merc AA's.  One for < 1%, other >= 1%.
	if (string_utils.ends_with(rewardDescription, "t.") == true) then
		local exp = tonumber(mercenaryAas);
		exp = exp / 100
		mercenaryAas = exp
	end

	AllAvailableQuests[AvailableQuestCount].experience = tonumber(experience)
	AllAvailableQuests[AvailableQuestCount].mercenaryAas = mercenaryAas

	reward_select_option(1, 2)
	local tetraOption = reward.Item(5)
	local bits = string_utils.split(tetraOption.Text(), ' ')
	AllAvailableQuests[AvailableQuestCount].tetradrachms = bits[1]
end

function LoadAvailableQuests(loadExtraData)
	if (AvailableQuestListLoaded == true) then
		return
	end

	local questName
	local fullQuestDetailString
	local current_quest
	local NODE = mq.TLO.Window(AvailableQuestList).FirstChild
	local database_exp_amount = nil

	AvailableQuestCount = 0
	QuestRunOrder = 0

	if (Settings.Debug.validateQuestRewardData) then
		logger.warning('\ay In Quest Validation Mode. Rewards will be checked for each against database.')
	end

	::nextNodeX::
	database_exp_amount = nil

	if Aborting then return end
	if (NODE == nil or tostring(NODE) == "NULL" or tostring(NODE) == nil or AvailableQuestList == nil) then
		logger.error("LoadAvailableQuests: Error on final.  Skipping away...")
		return false
	end

	if NODE.Child == nil or NODE.Child('OW_BtnQuestTemplate')() == nil then
		return
	end

	if NODE.Child == nil or NODE.Child('OW_BtnQuestTemplate').Text() == nil then
		return
	end

	if NODE.Child('OW_BtnQuestTemplate').Text() ~= nil then
		questName = NODE.Child('OW_BtnQuestTemplate').Text()
	end

	if (string.find(questName, 'Conversion') and actions.TutorialIsRequired == false and DebugNoRunQuestMode == false) then
		goto doneWithThisNode
	end

	AvailableQuestCount = AvailableQuestCount + 1

	 if (Settings.General.useQuestDatabase == true) then
    -- LOAD FROM DB.  i.e. "Do we already know about this one"
    logger.trace("\aoDB: \ayQuerying for quest details: %s", tostring(questName))

	-- Log DB path once, on first actual DB use
	if not _db_path_logged and db and type(db.GetDbPath) == 'function' then
		local p = db.GetDbPath()
		if p and p ~= '' then
			logger.info("Using DB file for queries: %s", tostring(p))
		end
		_db_path_logged = true
	end

	current_quest = db.GetQuestDetails(questName)
		if (current_quest ~= nil) then
			logger.trace("\agDB: \ayFound quest in DB: %s (exp=%s, type=%s)", tostring(current_quest.name), tostring(current_quest.experience), tostring(current_quest.type))
			AllAvailableQuests[AvailableQuestCount] = current_quest
			current_quest.available = true
			database_exp_amount = current_quest.experience

			if (not Settings.Debug.validateQuestRewardData) then
				goto doneWithThisNode
			end
		else
			logger.trace("\arDB: No record for quest\at '%s'", tostring(questName))
		end
	end

	SelectAvailableQuestNode(NODE)

	current_quest = AllAvailableQuests[AvailableQuestCount]
	current_quest.available = true
	current_quest.name = questName
	current_quest.duration = mq.TLO.Window(AvailableQuestCompletionTime).Text()

	fullQuestDetailString = mq.TLO.Window(AvailableQuestDifficulty).Text()

	-- Have to do this as the official text has a leading space (' Conversion')
	if (string.find(fullQuestDetailString, 'Conversion')) then
		current_quest.type = 'Conversion'
	else
		local questLevel, questRarity, questType = fullQuestDetailString:match("Level (%d+) (%a+) (%a+)")
		current_quest.level = questLevel
		current_quest.rarity = questRarity
		current_quest.type = questType
	end

	current_quest.experience = 0.0
	current_quest.mercenaryAas = 0.0
	current_quest.tetradrachms = 0

	if (current_quest.type ~= 'Recruitment' and current_quest.type ~= 'Conversion' and current_quest.type ~= 'Recovery') then
		if (Settings.Debug.processFullQuestRewardData == true or loadExtraData == true) then
			LoadAvailableQuestsExtraData(current_quest.name)
		elseif (Settings.General.rewards.maximizeStoredExpRewards == true) then
			LoadAvailableQuestsExperience(current_quest.name)
		end
	end

	-- If we're in validation mode, log it (to screen) but do not save.
	if (Settings.Debug.validateQuestRewardData and database_exp_amount ~= nil and database_exp_amount ~= current_quest.experience) then
		logger.error('\ar EXP VIOLATION: \aw Quest \ag%s\aw in database as \ay%s\aw but current \ay%s', current_quest.name, database_exp_amount, current_quest.experience)
		logger.error('    \at Not updating database at all for this quest.')
	elseif (database_exp_amount == nil and Settings.Debug.processFullQuestRewardData == true) then
		db.UpdateQuestDetails(questName, current_quest)
	end

	::doneWithThisNode::
	if (NODE.Siblings()) then
		NODE = NODE.Next
		goto nextNodeX
	end

	if mq.TLO.Window('RewardSelectionWnd').Open() then
		CloseRewardWindow()
	end
	AvailableQuestListLoaded = true
end

function RunGeneralQuests()
	if (AreAtMaxQuests()) then
		logger.warning('\ayMax Overseer General Quests Running')
		return
	end

	OpenOverseerWindow()
	ChangeTab(1)
	RunSpecificQuests()
	RunAchievementQuests()

	RunGeneralQuestPriorityGroups()
end

function QuestPriorityResetItems(questPrioritySectionName)
	QuestPriorityResetItem(1, questPrioritySectionName)
	QuestPriorityResetItem(2, questPrioritySectionName)
	QuestPriorityResetItem(3, questPrioritySectionName)
	QuestPriorityResetItem(4, questPrioritySectionName)
end

function QuestPriorityResetItem(index, questPrioritySectionName)
	local ourSplit = string_utils.split(Settings[questPrioritySectionName]['Priorities'], '|')
	local specificSplit = ourSplit[index]
	QuestOrder[index].name = specificSplit

	-- If we have less than 4 filters, skip the ones user didn't specify
	if (QuestOrder[index].name == 'NULL' or QuestOrder[index].name == nil) then
		return
	end

	QuestOrder[index].allItems = Settings[questPrioritySectionName][QuestOrder[index].name]
	QuestOrder[index].currentIndex = 1

	local ourSplit2 = string_utils.split(QuestOrder[index].allItems, '|')
	local ourSpecificSplit2 = ourSplit2[QuestOrder[index].currentIndex]
	QuestOrder[index].currentItem = ourSpecificSplit2

	if (QuestOrder[index].currentItem == "NULL" or QuestOrder[index].currentItem == nil) then
		logger.error('General>%s>%s One of the functions is missing or invalid.', questPrioritySectionName, QuestOrder[index].name)
		os.exit()
	end
end

function QuestPriorityRollItem(index)
	if (QuestOrder[index].currentItem == nil) then
		return false
	end

	QuestOrder[index].currentIndex = QuestOrder[index].currentIndex + 1

	local ourSplit = string_utils.split(QuestOrder[index].allItems, '|')

	local specificSplit = ourSplit[QuestOrder[index].currentIndex]
	QuestOrder[index].currentItem = specificSplit
	if (QuestOrder[index].currentItem ~= nil) then
		return true
	end

	QuestOrder[index].currentIndex = 1
	QuestOrder[index].currentItem = ourSplit[1]
	return false
end

function QuestPriorityFindIndex(itemType)
	for index = 1, 4 do
		if (QuestOrder[index].name == itemType) then
			return index
		end
	end

	return 0
end

function IsGeneralQuestType(quest)
	return quest.type ~= "Recruitment" and quest.type ~= "Recovery" and quest.type ~= "Conversion"
end

function RunMaxExperienceQuests()
	for index,quest in utils.spairs(AllAvailableQuests, function(t,a,b) return t[b].experience < t[a].experience end) do
		if (index > AvailableQuestCount) then goto done_with_process end

		if (AreAtMaxQuests() == true) then return false end
		if Aborting then return false end

		if (IsGeneralQuestType(quest) == true and quest.available == true) then
			ProcessGeneralQuest(index, quest.rarity)
		end
	end

	::done_with_process::
	return true
end

function RunGeneralQuestPriorityGroups()
	ChangeTab(1)
	ReloadAvailableQuests(true)
	-- LoadAvailableQuests()

	local questPriorityGroups = Settings.General.useQuestPriorityGroups
	if (not questPriorityGroups) then
		RunGeneralQuestsPriority()
		return
	end

	local index = 0
	local ourSplit = string_utils.split(questPriorityGroups, '|')

	repeat
		index = index + 1
		local questPriorityGroup = ourSplit[index]
		if (not questPriorityGroup) then
			return
		end

		RunGeneralQuestsPriority(questPriorityGroup)
	until false
end

function GetQuestPrioritySectionName(questPriorityGroupName)
	local questPrioritySection = "QuestPriority"
	if (questPriorityGroupName ~= nil and questPriorityGroupName:len() > 0) then
		questPrioritySection = 'QuestPriority_' .. questPriorityGroupName
	elseif (mqfacade.GetSubscriptionLevel() ~= 'GOLD' and Settings['QuestPriority_Unsubscribed'] ~= nil) then
		questPrioritySection = 'QuestPriority_Unsubscribed'
	end

	return questPrioritySection
end

function RunGeneralQuestsPriority(priorityGroupName)
	local questPrioritySection = GetQuestPrioritySectionName(priorityGroupName)
	if (Settings[questPrioritySection].general ~= nil and Settings[questPrioritySection].general.selectHighestExp == true) then
		RunMaxExperienceQuests()
		return
	end

	QuestPriorityResetItems(questPrioritySection)

	local durationIndex = QuestPriorityFindIndex("Durations")
	local rarityIndex   = QuestPriorityFindIndex("Rarities")
	local typeIndex     = QuestPriorityFindIndex("Types")
	local levelIndex    = QuestPriorityFindIndex("Levels")

	local duration
	local rarity
	local typeIndicator
	local levelIndicator
	local message

	local maxSearchProperty = 0
	::next::
	maxSearchProperty = 0
	if (durationIndex == 0) then duration = nil else
		duration = QuestOrder[durationIndex].currentItem
		maxSearchProperty = maxSearchProperty + 1
	end
	if (rarityIndex == 0) then rarity = nil else
		rarity = QuestOrder[rarityIndex].currentItem
		maxSearchProperty = maxSearchProperty + 1
	end
	if (typeIndex == 0) then typeIndicator = nil else
		typeIndicator = QuestOrder[typeIndex].currentItem
		maxSearchProperty = maxSearchProperty + 1
	end
	if (levelIndex == 0) then levelIndicator = nil else
		levelIndicator = QuestOrder[levelIndex].currentItem
		maxSearchProperty = maxSearchProperty + 1
	end

	if (maxSearchProperty == 0) then
		message = 'Finding Quests For: Any'
	else
		message = 'Finding Quests For: ' .. QuestOrder[1].currentItem
		if (maxSearchProperty >= 2 and QuestOrder[2].currentItem ~= nil) then message = string.format(message .. ' > ' .. QuestOrder[2].currentItem) end
		if (maxSearchProperty >= 3 and QuestOrder[3].currentItem ~= nil) then message = string.format(message .. ' > ' .. QuestOrder[3].currentItem) end
		if (maxSearchProperty >= 4 and QuestOrder[4].currentItem ~= nil) then message = string.format(message .. ' > ' .. QuestOrder[4].currentItem) end
	end

	logger.debug(message)

	local result = EnumerateAvailableQuests(IsRarityDurationQuest, ProcessGeneralQuest, rarity, duration, typeIndicator, levelIndicator)
	if (result == false) then
		return
	end

	if (maxSearchProperty == 0) then return end

	for i=4,1,-1 do
		if (maxSearchProperty >= i) then
			result = QuestPriorityRollItem(i)
			if (result) then
				goto next
			end
		end
	end
end

function RunFirstQuest()
	if Aborting then return end

	ChangeTab(1)

	LoadAvailableQuests()

	if Aborting then return end

	local questName = AllAvailableQuests[1].name
	ProcessGeneralQuest(1, questName, 'Common')
end

function RunDefinedQuestPriorities()
	if Aborting then return end

	if (Settings.RunDefinedQuestPriorities ~= true) then logger.warning('Not running defined quests') return end
logger.info('Running defined quests')
	local file = json_file.loadTable('data/quest_ordering.json')
	if (file == nil) then logger.error("RunDefinedQuestPriorities set to true but no quest ordering found.") return end


end

function RunAchievementQuests()
	if Aborting then return end

	if (Settings.AchievementQuests == nil) then return end

	for _, achievement_item in pairs(Settings.AchievementQuests) do

		if achievement_item.run == false then goto next_achievement end
		local actual_achievement = mq.TLO.Achievement.Achievement(achievement_item.id)
		if (Settings.General.ForceCompletedAchievementQuests == false and actual_achievement.Completed()) then goto next_achievement end
		if actual_achievement.ObjectiveCount() == nil then goto next_achievement end

		for objIndex = actual_achievement.ObjectiveCount(), 1, -1  do
			local actual_objective = actual_achievement.ObjectiveByIndex(objIndex)

--			if (actual_objective.Completed() == false) then
				for index = 1, AvailableQuestCount do
					if Aborting then return end

					local questName = AllAvailableQuests[index].name
					if (questName == actual_objective.Description()) then
						ProcessGeneralQuest(index, questName, 'Common')
					end

					if (AreAtMaxQuests()) then
						return
					end
				end
--			end
		end

		:: next_achievement ::
	end
end

function RunSpecificQuests()
	if Aborting then return end

	LoadAvailableQuests()

	if (Settings.SpecificQuests == nil) then return end

	local specialQuestCount = Settings.SpecificQuests.index
	if (specialQuestCount == nil) then return end

	for index = 1, AvailableQuestCount do
		if Aborting then return end

		local questName = AllAvailableQuests[index].name

		for optionIndex = 1, specialQuestCount do
			local rewardOptionName = Settings.SpecificQuests[optionIndex]
			if (questName == rewardOptionName) then
				ProcessGeneralQuest(index, questName, 'Common')
			end

			if (AreAtMaxQuests()) then
				return
			end
		end
	end
end

function MarkAvailableQuestAsRun(questName, success)
	-- 1==is available. 2==quest name. 3=Duration. 4==difficulty string. 5==quest run order. 6==Success Rate
	for index = 1, AvailableQuestCount do
		if (AllAvailableQuests[index].name) == questName then
			QuestRunOrder = QuestRunOrder + 1
			AllAvailableQuests[index].available = false
			AllAvailableQuests[index].runOrder = QuestRunOrder
			AllAvailableQuests[index].successRate = success
			return
		end
	end
	logger.error('Quest Not Found: ' .. questName)
end

-- Selects and attempts to populate/run the specified quest
-- Returns true if quest was able to run due to existing, having appropriate agents, and passing rules; else false
function ProcessGeneralQuest(index, rarity, duration, typeX, level)
	if Aborting then return end

	local questName = AllAvailableQuests[index].name

	local result = FindQuest(questName)
	if (result == false) then
		logger.error('ProcessGeneralQuest: Expected quest not found ' .. questName)
		return false
	end

	result = ProcessCurrentGeneralQuest(rarity, questName)
	if (result == false) then return false end

	-- Make sure to mark this quest as having been run
	QuestRunOrder = QuestRunOrder + 1
	AllAvailableQuests[index].available = false
	AllAvailableQuests[index].runOrder = QuestRunOrder
	AllAvailableQuests[index].successRate = mq.TLO.Window('OverseerWnd/OW_ALL_SuccessValue').Text()

	if (AreAtMaxQuests()) then return true end

	ChangeTab(1)

	return true
end

local function GetSuccessPercent()
	local successText = mq.TLO.Window('OverseerWnd/OW_ALL_SuccessValue').Text()
	local successPct = string.sub(successText, 1, -2)
	return successPct
end

function ProcessCurrentGeneralQuest(rarity, questName)
	logger.info('Attempting to run ' .. questName)
	FailedQuest_ResetMinionCache()

	local result
	::selectBestAgents::
	if Aborting then return end
	result = SelectBestAgents()

	-- If we didn't have proper agents to run, abort...
	if (result == false) then
		logger.info('Not enough appropriate agents to run quest.')
		return false
	end

	if (rarity ~= 'Recruit') then
		if (DebugNoSelectAgents == true) then
			logger.debug('Ignoring success rate of quests (due to Debug|doNotFindAgents)')
		else
			result = VerifySuccessRate(rarity, GetSuccessPercent())
			if (result == false) then
				logger.info('skipping quest \ay%s\ao. Success (\ay%s\ao) below accepted threshold for \ay%s\ao.', questName,
					mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_SuccessValue').Text(), rarity)
				return false
			end
		end
	else
		logger.debug('Ignoring success rate of Recruit Quests (All allowed)')
	end

	logger.warning('  .....Starting quest \ay%s\ao with \ay%s\ao success.', questName, mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_SuccessValue').Text())

	if Aborting then return end

	StartQuest()
	mq.doevents()
	mq.delay(500)

	if (FailedQuest_InStartQuestBadAgentErrorMode) then
		-- Start over fresh, just excluding others
		FailedQuest_InStartQuestBadAgentErrorMode = false
		FailedQuest_OutputFailedMinions()
		FailedQuest_ClearAllAssignedMinions()
		goto selectBestAgents
	end

	return true
end

function ProcessConversionQuest(priority)
	-- TODO: Qualify which this should be - i.e. OverseerWnd/OW_OverseerQuestsPage/OW_ALLTitleLabel
	local questName = mq.TLO.Window('OverseerWnd/OW_ALL_TitleLabel').Text()
	local NODE = mq.TLO.Window(AvailableQuestMinions).FirstChild.Next

	logger.debug('\aoProcessing Conversion \ay%s', questName)
	FailedQuest_ResetMinionCache()

	if (DebugNoRunQuestMode == true) then
		MarkAvailableQuestAsRun(questName, mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_SuccessValue').Text())
		return false
	end

	::nextAgent::
	if Aborting then return false end

	mqutils.action(NODE.Child('OW_ALL_MinionSelectBtn').LeftMouseUp)
	mq.doevents()
	mq.delay(1500)

	local result = SelectNextDuplicateAgent(priority)
	if (result == false) then
		logger.info('Not enough duplicate agents for \ay%s', questName)
		return false
	end

	if nil == NODE.Siblings() then
		goto nextAgent
	else
		if (NODE.Siblings()) then
			NODE = NODE.Next
			goto nextAgent
		end
	end

	-- Our success wasn't updating in time.  Not the most important but guarantees we're seeing what we should.
	mq.delay(1000)   -- TODO: Add condition
	logger.warning('  .....Starting quest \ay%s\ao with \ay%s\ao success.', questName, mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_SuccessValue').Text())

	if Aborting then return false end
	StartQuest()
	if (FailedQuest_InStartQuestBadAgentErrorMode) then
		-- Start over fresh, just excluding others
		FailedQuest_InStartQuestBadAgentErrorMode = false
		NODE = mq.TLO.Window(AvailableQuestMinions).FirstChild.Next
		FailedQuest_OutputFailedMinions()
		FailedQuest_ClearAllAssignedMinions()
		goto nextAgent
	end

	ClaimConversionQuest(questName)
	return true
end

function SelectNextDuplicateAgent(priority)
    -- Wait for UI to load
    mq.delay(500)

    local agentCountForConversion = 2
    if (priority == 1) then
        agentCountForConversion = Settings.General.agentCountForConversionCommon
    elseif (priority == 2) then
        agentCountForConversion = Settings.General.agentCountForConversionUncommon
    elseif (priority == 3) then
        agentCountForConversion = Settings.General.agentCountForConversionRare
    end

    -- preserve original early-exit behavior if there's no next node
    local ok_res, result = pcall(function() return mq.TLO.Window(MinionSelectionScreen).FirstChild.Next end)
    if not ok_res or result == nil then
        return false
    end

    local ok_node, firstNode = pcall(function() return mq.TLO.Window(MinionSelectionScreenFirstMinion).FirstChild end)
    if not ok_node or firstNode == nil then
        return false
    end

    -- If Siblings() explicitly returns false, bail (same as original)
    local ok_sib, sib_val = pcall(function()
        if firstNode and firstNode.Siblings then
            if type(firstNode.Siblings) == "function" then
                return firstNode:Siblings()
            else
                return firstNode.Siblings
            end
        end
        return nil
    end)
    if ok_sib and sib_val == false then
        return false
    end

    -- start from the first "Next" node
    local ok_next, tmpNext = pcall(function() return firstNode.Next end)
    if not ok_next or tmpNext == nil then
        return false
    end
    local NODE = tmpNext

    -- Iterate nodes (replaces goto-based loop)
    while NODE and tostring(NODE) ~= "NULL" do
        -- safe child lookup for the minion name button
        local ok_mb, minionButton = pcall(function()
            if NODE and NODE.Child then return NODE:Child('OW_OQP_MinionNameBtn') end
            return nil
        end)

        if ok_mb and minionButton and tostring(minionButton) ~= "NULL" then
            local ok_enabled, enabled = pcall(function()
                return (minionButton.Enabled and minionButton.Enabled()) or false
            end)

            if ok_enabled and enabled then
                -- safe count label access
                local ok_cl, countLabel = pcall(function()
                    if NODE and NODE.Child then return NODE:Child('OW_OQP_MinionCountLabel') end
                    return nil
                end)

                if ok_cl and countLabel and tostring(countLabel) ~= "NULL" then
                    local ok_text, countText = pcall(function()
                        if type(countLabel.Text) == "function" then return countLabel:Text() end
                        return countLabel.Text
                    end)

                    if ok_text and countText then
                        local amount = string.sub(tostring(countText), 2)

                        local ok_name, minionName = pcall(function()
                            if type(minionButton.Text) == "function" then return minionButton:Text() end
                            return minionButton.Text
                        end)

                        if ok_name and minionName and tonumber(amount) and tonumber(amount) > agentCountForConversion then
                            local ok_excl, result2 = pcall(function() return FailedQuest_IsExcludedAgent(minionName) end)
                            if ok_excl and result2 then
                                logger.info('...ignoring excluded agent \ay%s', minionName)
                            else
                                pcall(function() mqutils.leftmouseup(minionButton.LeftMouseUp) end)
                                pcall(function() FailedQuest_AddMinionToCurrentPendingCache(minionName) end)
                                return true
                            end
                        end
                    end
                end
            end
        end

        -- Advance to next node. Try to use Next regardless of Siblings presence to avoid errors.
        local ok_n, nxt = pcall(function() return NODE.Next end)
        if ok_n and nxt then
            NODE = nxt
        else
            break
        end
    end

    return false
end

function ProcessConversion(priority, name)
	::repeatEntireQuest::
	if Aborting then return end

	ChangeTab(1)
	if (FindQuest(name) == false) then
		logger.info('NOT Found \ay' .. name)
		return
	end

	local result = ProcessConversionQuest(priority)
	if Aborting then return end

	if (result == false) then
		return
	end

	goto repeatEntireQuest
end

function ClaimFirstConversionQuest()
	if mq.TLO.Window(ActiveQuestList).Children() == false then
		return
	end

	ChangeTab(3)

	local NODE = mq.TLO.Window('ActiveQuestList').FirstChild
	SelectActiveQuestNode(NODE)
	mq.doevents()
	mq.delay(1000)

	ClaimFastQuest()
end

function ClaimConversionQuest(name)
	if Aborting then return end
	ChangeTab(3)

	local result = SelectActiveQuest(name)
	if (result == nil) then
		logger.info('ERROR')
		os.exit()
	end

	if Aborting then return end
	ClaimFastQuest()
end

function ClaimFastQuest()
	local attempts = 0
	local waitSeconds = 1000
	local quest_name = mq.TLO.Window(CurrentQuestName).Text()

	::retryClaim::
	if Aborting then return end
	if (mq.TLO.Window('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CollectRewardButton').Enabled() == false) then
		if (attempts > 40) then
			logger.error('Quest not complete: \ay%s\ao.  Still waiting but maybe check things yourself also.', quest_name)
			attempts = 0
			goto retryClaim
		end

		attempts = attempts + 1
		if (attempts > 11) then
			logger.info('Waiting for quest to complete: \ay%s\ao...', quest_name)
		end

		if Aborting then return end
		mq.delay(waitSeconds)
		goto retryClaim
	end

	logger.info('\ay%s\ao has succeeded.  Claiming.', quest_name)
	mqutils.leftmouseup('OverseerWnd/OW_OverseerActiveQuestsPage/OW_ALL_CollectRewardButton')

	-- Wait until the quest has been removed from Active Quests tab, which can take a moment, else it's not back in Quests window
	mq.doevents()
	mq.delay(1000)  -- TODO: Add a "While Title ~= quest_name" kind of delay condition
end

function SelectActiveQuest(name)
	local NODE = mq.TLO.Window(ActiveQuestList).FirstChild

	::nextNode::
	if (NODE.Child('OW_BtnQuestTemplate').Text() == name) then
		SelectActiveQuestNode(NODE)
		mq.doevents()
		mq.delay(1000)
		return NODE
	end

	if (NODE.Siblings()) then
		NODE = NODE.Next
		goto nextNode
	end

	logger.info('\ay%s\ao not found.', name)
	return nil
end

-- Finds quest with complete name match and selects it
-- Returns true if found; false if not
function FindQuest(name)
	local NODE = mq.TLO.Window(AvailableQuestList).FirstChild

	::nextQuest::
	if (NODE.Child('OW_BtnQuestTemplate').Text() == name) then
		SelectAvailableQuestNode(NODE)
		mq.doevents()
		return true
	end

	if (not NODE.Siblings()) then
		return false
	end

	NODE = NODE.Next
	goto nextQuest
end

-- Enumerates each quest.
--     - Returns true if we can continue with more quests.  false if we are done.
function EnumerateAvailableQuests(determineMethod, runQuestMethod, rarity, duration, typeX, level)
	local currentIndex = 0
	::getNext::
	if (AreAtMaxQuests() == true) then return false end

	currentIndex = currentIndex + 1
	if (currentIndex > AvailableQuestCount) then
		return true
	end

	if Aborting then return false end

	-- Skip if already been run
	if (AllAvailableQuests[currentIndex].available == false) then
		goto getNext
	end

	local result = determineMethod(currentIndex, rarity, duration, typeX, level)
	if (result == false) then
		goto getNext
	end

	if Aborting then return false end
	result = runQuestMethod(currentIndex, rarity, duration, typeX, level)
	if (result == false) then
		goto getNext
	end

	if (AreAtMaxQuests() == true) then return false end

	goto getNext
	return true
end

function IsQuestByCategory(index, name)
	return AllAvailableQuests[index].type == name
end

function IsQuestByName(index, name)
	return string.sub(AllAvailableQuests[index].name, 1, name:len()) == name
end

function IsRarityDurationQuest(index, rarity, duration, typeX, level)
	if (rarity ~= nil and rarity ~= 0 and rarity ~= AllAvailableQuests[index].rarity) then
		return false
	end

	if (duration ~= nil) then
		local actualDuration = AllAvailableQuests[index].duration
		local durationFind = string.find(actualDuration, duration)
		if (durationFind == nil) then
			return false
		end
	end

	if (level ~= nil and level ~= 0 and level ~= AllAvailableQuests[index].level) then
		return false
	end

	if (IsGeneralQuestType(AllAvailableQuests[index]) == false) then
		return false
	end

	local isOurType = AllAvailableQuests[index].type == typeX
	if (typeX == nil or isOurType == true) then
		return true
	end

	return false
end

local function select_best_agents_autofill()
	mqutils.leftmouseup('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_AutoFillButton')
	logger.info('\atUsing AutoFill to select agents.')
	mq.delay(250)

	-- Now check if all slots were filled or not
	local NODE = mq.TLO.Window(AvailableQuestMinions).FirstChild.Next
	::nextAgent::

	-- See if this agent is populated (if Clear Button isn't enabled, then nobody selected)
	if (NODE.Child('OW_ALL_MinionsClearButton').Enabled() == false) then
		return false
	end

	if (not NODE.Siblings()) then
		return true
	end

	NODE = NODE.Next
	goto nextAgent

	return false
end

function SelectBestAgents()
	if (DebugNoSelectAgents == true) then
		logger.info('DEBUG: Skipping Agent Find assuming success.  (due to Debug|doNotFindAgents configuration flag)')
		return true
	end

	ChangeTab(1)

	return select_best_agents_autofill()
end

function actions.HasAutoFillButton()
	return mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_AutoFillButton')() == "TRUE"
end

function actions.HasMaxQuestLabel()
	local activeQuests, _ = actions.GetActiveQuestCounts()
	return (activeQuests ~= nil and string.len(activeQuests) > 0)
end

function FailedQuest_IsExcludedAgent(name)
	for index = 1, FailedQuest_CurrentPendingMinionCacheCount do
		if (name == FailedQuest_CurrentPendingMinions[index]) then
			return true
		end
	end
	return false
end

function FailedQuest_OutputFailedMinions()
	logger.info('Ignoring minions:')
	for index = 1, FailedQuest_CurrentPendingMinionCacheCount do
		logger.info('    * \ay%s\ao', FailedQuest_CurrentPendingMinions[index])
	end
end

function FailedQuest_ClearAllAssignedMinions()
	local NODE = mq.TLO.Window(AvailableQuestMinions).FirstChild.Next

	::nextAgent::
	if (NODE.Child('OW_ALL_MinionsClearButton').Enabled()) then
		mqutils.action(NODE.Child('OW_ALL_MinionsClearButton').LeftMouseUp)
		mq.delay(250)
	end

	if (not NODE.Siblings()) then
		return true
	end

	if (NODE.Siblings()) then
		NODE = NODE.Next
		goto nextAgent
	end
end

function FailedQuest_ResetMinionCache()
	FailedQuest_InStartQuestBadAgentErrorMode = false
	FailedQuest_CurrentPendingMinionCacheCount = 0
end

function FailedQuest_AddMinionToCurrentPendingCache(name)
	FailedQuest_CurrentPendingMinionCacheCount = FailedQuest_CurrentPendingMinionCacheCount + 1
	FailedQuest_CurrentPendingMinions[FailedQuest_CurrentPendingMinionCacheCount] = name
end

function CloseRewardWindow()
	mqutils.CloseAllWindowsOfType('RewardSelectionWnd')
end

function OpenRewardWindow()
	NoPendingRewards = false

	-- Do this to ensure we don't have the Preview
	mqutils.CloseAllWindowsOfType('RewardSelectionWnd')

	local rewardWindow = mq.TLO.Window('RewardSelectionWnd')
	rewardWindow.DoOpen()
	mq.delay(1000, function() return rewardWindow.Open() end)

	-- Ensure we can see the "You have no pending rewards"
	mq.doevents()

	if (rewardWindow.Open() == true) then return true end

	if (NoPendingRewards == false) then
		logger.error('No Pending Rewards. Unable to open RewardSelectionWnd.')
	end

	return false
end

function StartQuest()
	if Aborting then return end

	ActiveQuestListDirty = true
	FailedQuest_InStartQuestBadAgentErrorMode = false

	if (DebugNoRunQuestMode == true) then
		logger.info('DEBUG: Not Actually Running Quest.')
		return
	end

	if Aborting then return end

	-- Putting this declaration here to ensure nobody accidentally calls this without us knowing/centralizing
	mqutils.leftmouseup('OverseerWnd/OW_OverseerQuestsPage/OW_ALL_StartButton')

	mq.doevents()
	mq.delay(1000)  -- TODO: Put a condition on this delay.
end

-- Loop through claiming active quests, then running first quest in list.  Until we are done.
function RunTutorial()
	logger.warning("Running Tutorial")
	OpenOverseerWindow()
	-- First time on a new char/server this can take a bit to load everything
	mq.delay(2000)

	while(true) do
		if (TutorialRequired() == false) then
			InitializeTimers()
			HasInitialized = true
			return
		end

		ClaimFirstConversionQuest()
		CollectAllRewards()

		ReloadAvailableQuests()

		RunFirstQuest()
		ClaimFirstConversionQuest()
		mq.delay(2000)
		CollectAllRewards()
	end
end

function Event_NoActiveQuests()
	logger.warning('Out Of Sync:  No available quest spots.  Quitting.')
	os.exit()
end

function Event_TooManyRewards()
	logger.warning('Too many pending. Stopping further claim-attempts this run.')
	TooManyPendingRewards = true
end

function Event_FailedStart(line)
	FailedQuest_InStartQuestBadAgentErrorMode = true
	logger.error('FAILED START. Attempting quest again with different agents.')
end

function Event_ErrorGrantingRewards()
	logger.warning('Detected EQ event: Error granting reward.')
	ErrorGrantingReward = true
end

function Event_NoPendingRewards()
	NoPendingRewards = true
end

function SetRarityJobCombos(name)
	local comboIndex
	local word
	local firstPass = true

	::nextWord::
	name = string_utils.trim_left(name)

	local index, _ = string.find(name, " ")

	if (index > 1) then
		index = index - 1
		word = string.sub(name, 1, index)
		name = string.sub(name, index)
	else
		word = name
		name = nil
	end

	if (firstPass) then
		comboIndex = mq.TLO.Window('OverseerWnd/OW_OQP_RarityFilter').List(word, 1)()
		if (comboIndex ~= nil and comboIndex > 0) then
			mqutils.notifyf('OverseerWnd OW_OQP_RarityFilter listselect %d', comboIndex)
			goto nextWord
		end
		firstPass = false
	end

	comboIndex = mq.TLO.Window('OverseerWnd/OW_OQP_JobFilter').List(word, 1)()
	if (comboIndex <= 0) then
		logger.error("NOT FOUND  ****** ERROR.  '%s' %s", word, comboIndex)
		return
	end

	mqutils.notifyf('OverseerWnd OW_OQP_JobFilter listselect %s', comboIndex)
end

function ClaimAllAdditionalItems()
	mq.cmd('/keypress OPEN_INV_BAGS')
	if (Settings.General.claimAgentPacks == false and Settings.General.claimTetradrachmPacks == false and Settings.General.claimFrags == false) then
		return
	end

	if Settings.General.claimCollectionFragments then
		ClaimCollectionFragments()
		CursorCheck()
	end

	if Settings.General.claimAgentPacks then
		ClaimAdditionalItems('Overseer Agent Pack')
		ClaimAdditionalItems('Overseer Bonus Uncommon Agent')
		CursorCheck()
	end

	if Settings.General.claimEliteAgentEchos then
		-- TODO: Elite Retire
		ClaimAdditionalItems('Elite Agent Echo')
		CursorCheck()
	end

	if Settings.General.claimTetradrachmPacks then
		if (ClaimAdditionalItems('Sealed Tetradrachm Coffer')) then
			logger.info("    You now have \ay%s\ao Overseer Tetradrachm", mq.TLO.Me.OverseerTetradrachm())
			if mq.TLO.Window('ItemDisplayWindow').Open() then
				mq.cmd('/windowstate ItemDisplayWindow close')
			end
			CursorCheck()
		end
	end
	mq.cmd('/keypress CLOSE_INV_BAGS')
	mq.cmd('/keypress i')
	if mq.TLO.Window('ItemDisplayWindow').Open() then
		mq.cmd('/windowstate ItemDisplayWindow close')
	end
end

function ClaimCollectionFragments()
	local itemName = 'Overseer Collection Item Dispenser Fragment'
	if mq.TLO.FindItem(itemName).ID() == nil then
		return false
	end
	mq.cmd('/keypress OPEN_INV_BAGS')
	mq.delay(1000)
	mqutils.autoinventory()

	while mq.TLO.FindItemCount(itemName)() >= 4 do
		logger.info('Claiming \ay%s', itemName)
		mqutils.cmdf('/itemnotify "%s" rightmouseup', itemName)
		mq.delay(1000, function() return mq.TLO.Cursor.ID() == 105880 end)
		mqutils.autoinventory()
		CursorCheck()
	end
	return true
end

function ClaimAdditionalItems(itemName)
	if mq.TLO.FindItem(itemName).ID() == nil then
		return false
	end

	mqutils.InspectItem(itemName)

	while mq.TLO.FindItem(itemName).ID() do
		logger.info('Claiming \ay%s\ao.', itemName)

		-- TODO: Improve logic to properly re-initiate this. For now, if Item Window gets closed, walk away
		if (mq.TLO.Window('ItemDisplayWindow').Open() == false or Settings.General.claimEliteAgentEchos == false or Settings.Rewards.eliteAgentEchoReward == nil or Settings.Rewards.eliteAgentEchoReward == 'None') then
			logger.error('\arItemDisplayWindow\ao was closed.  Stopping claiming of \ay%s\ao for this run.', itemName)
			return false
		end
		
		mqutils.leftmouseup('ItemDisplayWindow/IDW_RewardButton')
		mqutils.autoinventory(true)

		if mq.TLO.FindItemCount('Elite Agent Echo')() > 0 then
			CollectAllRewards()
		end

		CursorCheck()
	end

	return true
end

function OutputAvailableQuestList()
	for runIndex = 1, QuestRunOrder do
		for index = 1, AvailableQuestCount do
			if (AllAvailableQuests[index].runOrder == runIndex) then
				local questDetail = AllAvailableQuests[index].type
				if (questDetail ~= 'Conversion') then
					questDetail = string.format('Level %s %s %s', AllAvailableQuests[index].level, AllAvailableQuests[index].rarity, AllAvailableQuests[index].type)
				end
				if (AllAvailableQuests[index].experience ~= nil) then
					questDetail = questDetail .. string.format(' Exp: \ay%s', AllAvailableQuests[index].experience)
				end

				logger.warning('\aw%s. %s\ax - \at%s\ax -  \ag%s\ax - \ao%s\ax', AllAvailableQuests[index].runOrder,
					AllAvailableQuests[index].name, AllAvailableQuests[index].successRate, AllAvailableQuests[index].duration, questDetail)
			end
		end
	end

	for index = 1, AvailableQuestCount do
		if (AllAvailableQuests[index].available == true) then
			local questDetail = AllAvailableQuests[index].type
			if (questDetail ~= 'Conversion') then
				questDetail = string.format('Level %s %s %s', AllAvailableQuests[index].level, AllAvailableQuests[index].rarity, AllAvailableQuests[index].type)
			end
			if (AllAvailableQuests[index].experience ~= nil) then
				questDetail = questDetail .. string.format(' Exp: \ay%s', AllAvailableQuests[index].experience)
			end
			logger.warning('\aw0. %s\ax - \arSkipped\ax - \ag%s - \as%s\ax', AllAvailableQuests[index].name,
				AllAvailableQuests[index].duration, questDetail)
		end
	end
end

function InitializeAgentCounts()
	-- 1==Type 2==name 3==available 4==count 5==duplicates
	for i = 1, 6 do
		AgentStatisticCounts[i] = {}
		for j = 1, 5 do
			AgentStatisticCounts[i][j] = 0
		end
	end

	AgentStatisticCounts[1][2] = 'Common'
	AgentStatisticCounts[1][3] = 108
	AgentStatisticCounts[1][4] = 0
	AgentStatisticCounts[1][5] = 0

	AgentStatisticCounts[2][2] = 'Uncommon'
	AgentStatisticCounts[2][3] = 72
	AgentStatisticCounts[2][4] = 0
	AgentStatisticCounts[2][5] = 0

	AgentStatisticCounts[3][2] = 'Rare'
	AgentStatisticCounts[3][3] = 36
	AgentStatisticCounts[3][4] = 0
	AgentStatisticCounts[3][5] = 0

	AgentStatisticCounts[4][2] = 'Elite'
	AgentStatisticCounts[4][3] = 18
	AgentStatisticCounts[4][4] = 0
	AgentStatisticCounts[4][5] = 0

	AgentStatisticCounts[5][2] = '????'
	AgentStatisticCounts[5][3] = 18
	AgentStatisticCounts[5][4] = 0
	AgentStatisticCounts[5][5] = 0
end

function CollectAgentStatistics()
	local wasWindowOpen = IsOverseerWindowOpen()
	OpenOverseerWindow()
	InitializeAgentCounts()
	ChangeTab(3)
	OutputAgentCounts()
	if (wasWindowOpen == false) then CloseOverseerWindow() end
end

-- Walks list of agents giving peeks and optionally returning one specific if asked
-- typeIndex: Index of agent type (1==common, 2==uncommon, 3==rare, 4==elite)
-- action: Callback method called on each agent.
-- 		signature: bool X(typeIndex, agentName, agentStatus, node)
--				return false to stop walking and return this node
-- startAction: Callback method called at start of operation
--		signature: void X(typeIndex)
-- doneAction:  Callback method called at end of operation
--		signature: void X(typeIndex)
local function walk_agents(typeIndex, action, startAction, doneAction)
	if (startAction ~= nil) then
		startAction(typeIndex)
	end

	mqutils.cmdf('/notify OverseerWnd OW_OM_RarityFilter listselect %s', typeIndex+1)
	mq.delay(250)

	local agentNode = mq.TLO.Window('OverseerWnd/OW_OM_MinionList').FirstChild

	local lastAgentName = nil

	::nextAgent::
	if Aborting then return end

	local agentText = agentNode.Child('OW_OM_MinionEntry').Text()
	local index = string.find(agentText, 'Status')
	local agentName = string.sub(agentText, 1, index - 2)
	local agentStatus = string.sub(agentText, index + 8)

	local isDuplicate = agentName == lastAgentName

	if (agentNode.Height() ~= nil) and (agentNode.Height() > 0) then
		if (action(typeIndex, agentName, agentStatus, agentNode, isDuplicate) == false) then
			return agentNode
		end
	end

	lastAgentName = agentName
	if (agentNode.Siblings() == nil) then
		goto nextAgent
	end

	if (agentNode.Siblings() ~= nil) and (agentNode.Siblings()) then
		agentNode = agentNode.Next
		goto nextAgent
	end

	if (doneAction ~= nil) then
		doneAction(typeIndex)
	end
end

local agent_select_temp_name, agent_select_temp_status
local function agent_select_callback(typeIndex, name, status)
	local result = ((agent_select_temp_name == nil or agent_select_temp_name == name)
	and (agent_select_temp_status == nil or agent_select_temp_status == status))
	return result == false
end

local function agent_select(typeIndex, name, status)
	agent_select_temp_name = name
	agent_select_temp_status = status
	return walk_agents(typeIndex, agent_select_callback)
end

local function load_all_overseer_agents()
	if (AgentStatisticSpecificCounts == nil) then
		AgentStatisticSpecificCounts = json_file.loadTable('data/overseer_agents.json')
	end
end

local function get_rarity_name(typeIndex)
	if(typeIndex == 1) then return 'common' end
	if(typeIndex == 2) then return 'uncommon' end
	if(typeIndex == 3) then return 'rare' end
	if(typeIndex == 4) then return 'elite' end
	return 'I DONT KNOW'
end
local function reset_overseer_agents_count(typeIndex)
	local rarityName = get_rarity_name(typeIndex)
	AgentStatisticSpecificCounts[rarityName].countHave = 0
	AgentStatisticSpecificCounts[rarityName].countDuplicates = 0
	for name, value in pairs(AgentStatisticSpecificCounts[rarityName].agents) do
			value.count = 0
	end
end

local previousAgentName = ''
AgentStatisticSpecificCounts = nil
local function count_specific_agents_start_callback(typeIndex)
	load_all_overseer_agents()

	reset_overseer_agents_count(typeIndex)
end

local function count_specific_agents_done_callback(typeIndex)
	-- if (AgentStatisticSpecificCounts[typeIndex] == nil or AgentStatisticSpecificCounts[typeIndex].agents == nil) then return end
	-- logger.info('Count Agent Index: %s', typeIndex)
	-- table.sort(AgentStatisticSpecificCounts[typeIndex].agents)
end

local function count_specific_agents_callback(typeIndex, name, _, _, isDuplicate)
	local rarityName = get_rarity_name(typeIndex)
	if (AgentStatisticSpecificCounts[rarityName] == nil) then AgentStatisticSpecificCounts[rarityName] = {} end
	if (AgentStatisticSpecificCounts[rarityName].agents[name] == nil) then
		 AgentStatisticSpecificCounts[rarityName].agents[name] = {}
		AgentStatisticSpecificCounts[rarityName].agents[name].count = 1
	else
		AgentStatisticSpecificCounts[rarityName].agents[name].count = AgentStatisticSpecificCounts[rarityName].agents[name].count + 1
	end

	if (AgentStatisticSpecificCounts[rarityName].countHave == nil) then
		AgentStatisticSpecificCounts[rarityName].countHave = 1
		AgentStatisticSpecificCounts[rarityName].countDuplicates = 0
	elseif (isDuplicate) then
		if (AgentStatisticSpecificCounts[rarityName].countDuplicates == nil) then AgentStatisticSpecificCounts[rarityName].countDuplicates = 1
		else AgentStatisticSpecificCounts[rarityName].countDuplicates = AgentStatisticSpecificCounts[rarityName].countDuplicates + 1
		end
	else
		AgentStatisticSpecificCounts[rarityName].countHave = AgentStatisticSpecificCounts[rarityName].countHave + 1
	end
end

function RetireEliteAgent(name)
	logger.debug('Retiring \ay%s\ao.', name)
	OpenOverseerWindow()
	ChangeTab(2)
	local agentNode = agent_select(4, name, 'Ready')
	if (agentNode == nil) then
		logger.info('Agent availble for retire, but none available at the moment. \ay%s', name)
		return
	end

	local buttonNode = agentNode.Child('OW_OM_MinionEntry')
	mqutils.action(buttonNode.LeftMouseUp)
	mq.delay(500)

	logger.warning('Agent Count Too High. Culling: \ay%s', name)
	mqutils.leftmouseup('OverseerWnd/OW_OverseerMinionsPage/OW_OM_RetireButton')

	mqutils.WaitForWindow('ConfirmationDialogBox')
	if (mq.TLO.Window('ConfirmationDialogBox').Open()) then
		mqutils.click_confirmation_yes()
	end

	if (AgentStatisticSpecificCounts['elite'].agents ~= nil and AgentStatisticSpecificCounts['elite'].agents[name] ~= nil) then
		AgentStatisticSpecificCounts['elite'].agents[name].count = AgentStatisticSpecificCounts['elite'].agents[name].count - 1
	end
	CloseOverseerWindow()
end

function RetireEliteAgents()
    if (Settings.General.convertEliteAgents ~= true or (tonumber(Settings.General.agentCountForConversionElite) or 0) < 1) then
        return
    end

    if not AgentStatisticSpecificCounts or not AgentStatisticSpecificCounts['elite'] or not AgentStatisticSpecificCounts['elite'].agents then
        logger.warning("RetireEliteAgents: no elite agent stats available; skipping")
        return
    end

    -- Open UI once
    if not pcall(OpenOverseerWindow) then
        logger.error("RetireEliteAgents: unable to open Overseer window; aborting")
        return
    end

    local ok, err = pcall(function()
        ChangeTab(2)

        -- Snapshot agent names + counts so we don't iterate a table that may be mutated
        local snapshot = {}
        for name, data in pairs(AgentStatisticSpecificCounts['elite'].agents) do
            table.insert(snapshot, { name = name, count = tonumber(data.count) or 0 })
        end

        local keep = tonumber(Settings.General.agentCountForConversionElite) or 0

        for _, entry in ipairs(snapshot) do
            local name = entry.name
            local have = entry.count
            if have <= keep then
                -- nothing to do
            else
                local toRetire = have - keep
                logger.info("RetireEliteAgents: retiring %d copies of elite agent '%s' (have=%d, keep=%d)",
                    toRetire, tostring(name), have, keep)

                -- Decide a sane per-agent attempt budget
                local max_attempts = math.max(3, toRetire)
                local attempts = 0
                local retired = 0

                while retired < toRetire and attempts < max_attempts do
                    attempts = attempts + 1

                    -- Call RetireEliteAgent in pcall to avoid hard errors
                    local ok_retire, retire_result = pcall(function() return RetireEliteAgent(name) end)
                    if not ok_retire then
                        logger.error("RetireEliteAgents: RetireEliteAgent(%s) threw an error on attempt %d: %s", tostring(name), attempts, tostring(retire_result))
                        mq.delay(500)
                        goto continue_attempts
                    end

                    -- If RetireEliteAgent returns boolean false -> treat as failed attempt
                    if retire_result == false then
                        logger.warning("RetireEliteAgents: RetireEliteAgent(%s) reported failure on attempt %d; retrying", tostring(name), attempts)
                        mq.delay(500)
                        goto continue_attempts
                    end

                    -- Assume success: refresh agent counts to verify
                    mq.delay(300) -- give UI/server a moment
                    walk_agents(4, count_specific_agents_callback, count_specific_agents_start_callback, count_specific_agents_done_callback)
                    mq.delay(300)

                    local refreshed = AgentStatisticSpecificCounts and AgentStatisticSpecificCounts['elite'] and AgentStatisticSpecificCounts['elite'].agents[name]
                    local refreshed_count = refreshed and tonumber(refreshed.count) or have - retired

                    if refreshed_count < (have - retired) then
                        -- we made progress
                        retired = retired + 1
                        logger.info("RetireEliteAgents: succeeded retiring '%s' (now have ~%d)", tostring(name), refreshed_count)
                    else
                        -- no progress detected
                        logger.warning("RetireEliteAgents: attempt %d to retire '%s' did not reduce count (still %d); will retry", attempts, tostring(name), refreshed_count)
                        mq.delay(500)
                    end

                    ::continue_attempts::
                end

                if retired < toRetire then
                    logger.warning("RetireEliteAgents: aborting further retire attempts for '%s' after %d attempts (retired %d of %d needed)",
                        tostring(name), attempts, retired, toRetire)
                else
                    logger.info("RetireEliteAgents: finished retiring %s copies of '%s'", tostring(retired), tostring(name))
                end
            end
        end
    end)

    if not ok then
        logger.error("RetireEliteAgents: unexpected error: %s", tostring(err))
    end

    pcall(CloseOverseerWindow)
end

local function count_agents_callback(typeIndex, name)
		local duplicateOrNotIndex = 5
	if (name ~= previousAgentName) then
		duplicateOrNotIndex = 4
		previousAgentName = name
	end

	if (typeIndex > -1) then AgentStatisticCounts[typeIndex][duplicateOrNotIndex] = AgentStatisticCounts[typeIndex][duplicateOrNotIndex] + 1 end
end

local function count_agents(typeIndex)
	previousAgentName = ''
	walk_agents(typeIndex, count_agents_callback, nil, nil)
end

function OutputAgentCounts()
	ChangeTab(2)

	if (mq.TLO.Window('OverseerWnd/OW_OM_MinionList').Children == nil) then
		logger.error('No agents')
		return
	end

	SetCurrentProcess('Counting Agents')
	logger.warning('Counting Agents')

	for index = 1, 4 do
		count_agents(index)
	end

	previousAgentName = ''
	walk_agents(4, count_specific_agents_callback, count_specific_agents_start_callback, count_specific_agents_done_callback)
	walk_agents(3, count_specific_agents_callback, count_specific_agents_start_callback, count_specific_agents_done_callback)
	walk_agents(2, count_specific_agents_callback, count_specific_agents_start_callback, count_specific_agents_done_callback)
	walk_agents(1, count_specific_agents_callback, count_specific_agents_start_callback, count_specific_agents_done_callback)

	EndCurrentProcess()
	print_agent_stats_summary()
end

function VerifySuccessRate(level, success)
	local percentKey = 'minimumSuccessPercent_' .. level
	local minimumAcceptedSuccess = Settings.General[percentKey]

	if (minimumAcceptedSuccess == nil) then
		minimumAcceptedSuccess = Settings.General.minimumSuccessPercent
	end

	if (minimumAcceptedSuccess == nil) then
		return true
	end

	if (tonumber(success) < minimumAcceptedSuccess) then
		return false
	end

	return true
end

function ParseQuestRotationTime()
	local questRotationTimeFullText = mq.TLO.Window('OverseerWnd/OW_OverseerQuestsPage/OW_OQP_RotateLabel').Text()
	local durationInSeconds = ParseDurationSeconds(questRotationTimeFullText)

	actions.SetQuestRotationTimeSeconds(durationInSeconds)

	local split = string.find(questRotationTimeFullText, ':')
	local duration = string.sub(questRotationTimeFullText, split + 2)
	logger.warning('Quest Rotation in \ay%s.', duration)

	local result = ParseDuration(duration)
	return result
end

-- Separated to allow Test UI a hook
function actions.SetQuestRotationTimeSeconds(seconds)
	NextRotationTimeStamp = os.time() + seconds
end

function ParseDurationSeconds(duration)
	local totalSeconds = 0

	for index = 1, 4 do
		local ourSplit = string_utils.split(duration, ':')
		local currentItem = ourSplit[index]
		if (currentItem ~= nil) then
			local len = currentItem:len()
			local currentUnit = string.sub(currentItem, len, len)
			local currentAmount = string.sub(currentItem, 1, -2)

			if (currentUnit == "h") then
				totalSeconds = totalSeconds + currentAmount * 3600
			elseif (currentUnit == "m") then
				totalSeconds = totalSeconds + currentAmount * 60
			elseif (currentUnit == "s") then
				totalSeconds = totalSeconds + currentAmount
			end
		end
	end

	return totalSeconds
end

function DumpQuestDetails()
	OpenOverseerWindow()
	local weLoadedMq2Rewards = load_mq2rewards();

	ReloadAvailableQuests(true)

	if (weLoadedMq2Rewards) then
		unload_mq2rewards()
	end

	math.randomseed(os.clock()*math.random(15020209090,95020209090))
    for i=1,6 do
        math.random(10000, 65000)
    end

	local filename = string.format('data/quests_%s_%s.json', mq.TLO.Me.CleanName(), math.random(100000, 999999))
	json_file.saveTable(AllAvailableQuests, filename)
	CloseOverseerWindow()
	logger.info('Dumped quest details to \ay%s\ao', filename)
end

function ParseDuration(duration)
	local totalMinutes = 0
	local currentItem
	local currentUnit
	local currentAmount

	for index = 1, 4 do
		local ourSplit = string_utils.split(duration, ':')
		currentItem = ourSplit[index]
		if (currentItem ~= nil) then
			local len = currentItem:len()
			currentUnit = string.sub(currentItem, len, len)
			currentAmount = string.sub(currentItem, 1, -2)

			if (currentUnit == "h") then
				totalMinutes = totalMinutes + currentAmount * 60
			elseif (currentUnit == "m") then
				totalMinutes = totalMinutes + currentAmount
			elseif (currentUnit == "s") then
				if (totalMinutes == 0) then
					return 1
				end
			end
		end
	end

	if (totalMinutes > 0) then
		totalMinutes = totalMinutes + 1
	end

	return totalMinutes
end

AgentStatisticCounts = {}

mq.event('NoActiveQuests', '#*#You currently have 5 active Overseer quests #*#', Event_NoActiveQuests)
mq.event('TooManyRewards', '#*#You have too many pending rewards to claim another!#*#', Event_TooManyRewards)
mq.event('FailedStart', '#*#has failed to start. Please verify your#*#', Event_FailedStart)
mq.event('NoPendingRewards', '#*#You currently do not have any pending rewards.#*#', Event_NoPendingRewards)
mq.event('ErrorGrantingReward', '#*#The system is currently unable to grant your reward for#*#', Event_ErrorGrantingRewards)

return actions
