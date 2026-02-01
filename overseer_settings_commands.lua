--- @type Mq
local mq = require('mq')
local settings = require ('overseer_settings')
local overseer = require ('overseer.overseer')

local actions = {}

local overseer_msg = '\ao[\agOverseer Lua\ao]\ag::\aw'
local function help()
    printf('%s \agOverseerLua available options:', overseer_msg)
    printf('%s \ao\"/mqoverseer help\" \ar: Displays this message', overseer_msg)
    printf('%s \ao\"/mqoverseer\" \ar: Toggles display of the UI (or use show/hide)', overseer_msg)
    printf('%s \ao\"/mqoverseer show|hide\" \ar: Show or hide the UI', overseer_msg)
    printf('%s \ao\"/mqoverseer run\" \ar: Initiates a full automation cycle', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agSettings (boolean params accept on/true/yes or off/false/no; omitting toggles):', overseer_msg)
    printf('%s \aorunOnStartup [on|off] \ar: Toggle Run full cycle on startup (Settings.General.runFullCycleOnStartup)', overseer_msg)
    printf('%s \aoautoRestart [on|off] \ar: Toggle auto restart each cycle (Settings.General.autoRestartEachCycle)', overseer_msg)
    printf('%s \aoignoreRecruit [on|off] \ar: Toggle ignoring Recruitment quests', overseer_msg)
    printf('%s \aoignoreConversion [on|off] \ar: Toggle ignoring Conversion quests', overseer_msg)
    printf('%s \aoignoreRecovery [on|off] \ar: Toggle ignoring Recovery quests', overseer_msg)
    printf('%s \aocountEachCycle [on|off] \ar: Toggle counting agents between cycles', overseer_msg)
    printf('%s \aoconversionCountCommon <number> \ar: Set agentCountForConversionCommon', overseer_msg)
    printf('%s \aoconversionCountUncommon <number> \ar: Set agentCountForConversionUncommon', overseer_msg)
    printf('%s \aoconversionCountRare <number> \ar: Set agentCountForConversionRare', overseer_msg)
    printf('%s \aoconversionCountElite <number> \ar: Set agentCountForConversionElite', overseer_msg)
    printf('%s \aouseDatabase [on|off] \ar: Toggle loading quests from local DB (Settings.General.useQuestDatabase)', overseer_msg)
    printf('%s \aocampAfterFullCycle [on|off] \ar: Toggle camping after full cycle', overseer_msg)
    printf('%s \aocampAfterFullCycleFastCamp [on|off] \ar: Toggle fast camp behavior', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agUI timing and delays:', overseer_msg)
    printf('%s \aouseUiDelay [on|off] \ar: Toggle UI action delays (Settings.General.uiActions.useUiActionDelay)', overseer_msg)
    printf('%s \aouiDelayMin <ms> \ar: Set UI delay minimum in ms', overseer_msg)
    printf('%s \aouiDelayMax <ms> \ar: Set UI delay maximum in ms', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agRewards settings:', overseer_msg)
    printf('%s \aoclaimRewards [on|off] \ar: Toggle auto-claiming rewards', overseer_msg)
    printf('%s \aoclaimAgentPacks [on|off] \ar: Toggle claiming agent packs', overseer_msg)
    printf('%s \aoclaimTetradrachm [on|off] \ar: Toggle claiming tetradrachm packs', overseer_msg)
    printf('%s \aoclaimEliteAgentEchos [on|off] \ar: Toggle claiming elite agent echos', overseer_msg)
    printf('%s \aorunCompletedAchievementQuests [on|off] \ar: Force completed achievement quests run', overseer_msg)
    printf('%s \aosaveMaxExpRewards [on|off] \ar: Toggle maximize stored exp rewards', overseer_msg)
    printf('%s \aosavedRewardCount <number> \ar: Set stored exp rewards count', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agQuest priority:', overseer_msg)
    printf('%s \aoselectHighestExp [on|off] \ar: Toggle selecting highest exp in quest priority', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agActions (runtime flows):', overseer_msg)
    printf('%s \aorunFullCycle \ar: Start a full cycle (alias: run)', overseer_msg)
    printf('%s \aooutputQuestDetails \ar: Dump current quest details', overseer_msg)
    printf('%s \aoaddSpecificQuest \"<name>\" \ar: Add a specific quest by name', overseer_msg)
    printf('%s \aoremoveSpecificQuest \"<name>\" \ar: Remove a specific quest by name', overseer_msg)
    printf('%s \aoaddAllSpecificQuests \ar: Add all quests from the specific-quests list', overseer_msg)
    printf('%s \aoremoveAllSpecificQuests \ar: Remove all specific-quests entries', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agDebug / Test (opt-in, non-persistent by design):', overseer_msg)
    printf('%s \aoaddToDatabase [on|off] \ar: Toggle adding discovered quests into local DB (Settings.Debug.processFullQuestRewardData)', overseer_msg)
    printf('%s \aovalidateQuestRewardData [on|off] \ar: Toggle validation (compare UI reward XP to DB) (Settings.Debug.validateQuestRewardData)', overseer_msg)
    printf('%s', overseer_msg)

    printf('%s \agNotes:', overseer_msg)
    printf('%s - Boolean params: omit to toggle; or pass on/true/yes or off/false/no', overseer_msg)
    printf('%s - Numeric params expect plain numbers (no units).', overseer_msg)
    printf('%s - When a command modifies settings, the new value is saved automatically.', overseer_msg)
    printf('%s - If you pass an unknown command the brief help will be shown.', overseer_msg)
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
