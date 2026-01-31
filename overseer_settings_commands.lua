--- @type Mq
local mq = require('mq')
local settings = require ('overseer_settings')
local overseer = require ('overseer.overseer')

local actions = {}

local overseer_msg = '\ao[\agOverseer Lua\ao]\ag::\aw'
local function help()
    printf('%s \agOverseerLua available options include:', overseer_msg)
    printf('%s \ao\"/mqoverseer help\" \ar: Displays this message', overseer_msg)
    printf('%s \ao\"/mqoverseer\" \artoggles display of the UI', overseer_msg)
    printf('%s \ao\"/mqoverseer [show/hide]\" \ar Shows or hides the UI', overseer_msg)
    printf('%s \ao\"/mqoverseer run\" \ar Initiates full cycle run', overseer_msg)
    printf('%s \ao\"/mqoverseer hide\" \arto hide the UI', overseer_msg)
end

local function apply_command_bool(value, param)
    if (param == nil) then return not value, true end
    if (param == "on" or param == "true" or param == "yes") then return true, true
    elseif (param == "off" or param == "false" or param == "no") then return false, true
    else return value, false
    end
end

local function apply_command_number(value, param)
    if (param == nil) then return value, false end
    return tonumber(param), true
end

local function set_command(arg, c1)
    local success = false
    if (arg=="runOnStartup") then Settings.General.runFullCycleOnStartup, success = apply_command_bool(Settings.General.runFullCycleOnStartup, c1)
        -- Settings/General
    elseif (arg=="autoRestart") then Settings.General.autoRestartEachCycle, success = apply_command_bool(Settings.General.autoRestartEachCycle, c1)
    elseif (arg=="ignoreRecruit") then Settings.General.ignoreRecruitmentQuests, success = apply_command_bool(Settings.General.ignoreRecruitmentQuests, c1)
    elseif (arg=="ignoreConversion") then Settings.General.ignoreConversionQuests, success = apply_command_bool(Settings.General.ignoreConversionQuests, c1)
    elseif (arg=="ignoreRecovery") then Settings.General.ignoreRecoveryQuests, success = apply_command_bool(Settings.General.ignoreRecoveryQuests, c1)
    elseif (arg=="countEachCycle") then Settings.General.countAgentsBetweenCycles, success = apply_command_bool(Settings.General.countAgentsBetweenCycles, c1)
    elseif (arg=="conversionCountCommon") then Settings.General.agentCountForConversionCommon, success = apply_command_number(Settings.General.agentCountForConversionCommon, c1)
    elseif (arg=="conversionCountUncommon") then Settings.General.agentCountForConversionUncommon, success = apply_command_number(Settings.General.agentCountForConversionUncommon, c1)
    elseif (arg=="conversionCountRare") then Settings.General.agentCountForConversionRare, success = apply_command_number(Settings.General.agentCountForConversionRare, c1)
    elseif (arg=="conversionCountElite") then Settings.General.agentCountForConversionElite, success = apply_command_number(Settings.General.agentCountForConversionElite, c1)
    elseif (arg=="useDatabase") then Settings.General.useQuestDatabase, success = apply_command_bool(Settings.General.useQuestDatabase, c1)
    elseif (arg=="campAfterFullCycle") then Settings.General.campAfterFullCycle, success = apply_command_bool(Settings.General.campAfterFullCycle, c1)
    elseif (arg=="campAfterFullCycleFastCamp") then Settings.General.campAfterFullCycleFastCamp, success = apply_command_bool(Settings.General.campAfterFullCycleFastCamp, c1)
        -- Settings/General/uiActions
    elseif (arg=="useUiDelay") then Settings.General.uiActions.useUiActionDelay, success = apply_command_bool(Settings.General.uiActions.useUiActionDelay, c1)
    elseif (arg=="uiDelayMin") then Settings.General.uiActions.delayMinMs, success = apply_command_number(Settings.General.uiActions.delayMinMs, c1)
    elseif (arg=="uiDelayMax") then Settings.General.uiActions.delayMaxMs, success = apply_command_number(Settings.General.uiActions.delayMaxMs, c1)
        -- Settings/Rewards
    elseif (arg=="claimRewards") then Settings.General.rewards.claimRewards, success = apply_command_bool(Settings.General.rewards.claimRewards, c1)
    elseif (arg=="claimAgentPacks") then Settings.General.claimAgentPacks, success = apply_command_bool(Settings.General.claimAgentPacks, c1)
    elseif (arg=="claimTetradrachm") then Settings.General.claimTetradrachmPacks, success = apply_command_bool(Settings.General.claimTetradrachmPacks, c1)
    elseif (arg=="claimEliteAgentEchos") then Settings.General.claimEliteAgentEchos, success = apply_command_bool(Settings.General.claimEliteAgentEchos, c1)
    elseif (arg=="runCompletedAchievementQuests") then
        Settings.General.ForceCompletedAchievementQuests, success = apply_command_bool(Settings.General.ForceCompletedAchievementQuests, c1)
        settings.ForceRunCompletedAchievements_Changed()
    elseif (arg=="saveMaxExpRewards") then Settings.General.rewards.maximizeStoredExpRewards, success = apply_command_bool(Settings.General.rewards.maximizeStoredExpRewards, c1)
    elseif (arg=="savedRewardCount") then Settings.General.rewards.storedExpRewardsCount, success = apply_command_number(Settings.General.rewards.storedExpRewardsCount, c1)
        -- Settings/Quests
    elseif (arg=="selectHighestExp") then Settings.QuestPriority.general.selectHighestExp, success = apply_command_bool(Settings.QuestPriority.general.selectHighestExp, c1)
        -- Actions
    elseif (arg=="runFullCycle") then overseer.SetAction('FullCycle') success = true
    elseif (arg=="outputQuestDetails") then overseer.SetAction('DumpQuestDetails') success = true
    elseif (arg=="addSpecificQuest") then settings.AddSpecifiedQuests(c1) success = true
    elseif (arg=="removeSpecificQuest") then settings.RemoveSpecifiedQuests(c1) success = true
    elseif (arg=="addAllSpecificQuests") then settings.AddAllSpecifiedQuests() success = true
    elseif (arg=="removeAllSpecificQuests") then settings.RemoveAllSpecifiedQuests() success = true
        -- Settings/Debug
    elseif (arg=="addToDatabase") then Settings.Debug.processFullQuestRewardData, success = apply_command_bool(Settings.Debug.processFullQuestRewardData, c1)
    elseif (arg=="validateQuestRewardData") then Settings.Debug.validateQuestRewardData, success = apply_command_bool(Settings.Debug.validateQuestRewardData, c1)
    end
    return success
end

function actions.CommandUi(arg, c1)
    if arg == 'help' then
        help()
        return
    end

    local show = MyShowUi
    if (arg == nil) then show = show == false end

    -- Give everyone a shot at their own favorites
    if (arg == "show" or arg == "on" or arg == "true" or arg == "yes" or (arg == nil and show)) then
        show = true
    elseif (arg == "hide" or arg == "off" or arg == "false" or arg == "no" or (arg == nil and show == false)) then
        show = false
    elseif (arg == "run") then
        overseer.SetAction('FullCycle')
    else
        local success = set_command(arg, c1)
        if (success) then
            settings.SaveSettings()
        else
            help()
        end
        return
    end

    SetWindowVisibleState(show)
end

mq.bind('/mqoverseer', actions.CommandUi)

return actions
