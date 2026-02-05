--- overseer_settings_commands.lua
--- CLI command handling for /mqoverseer
local mq = require('mq')
local settings = require ('overseer_settings')
local overseer = require ('overseer')
local logger = require('utils.logger')

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
    printf('%s \aoautoFitWindow [on|off] \arResize Window on Content Change is currently set to: \ao%s', overseer_msg, tostring(Settings.General.autoFitWindow))
    printf('%s \aorunOnStartup [on|off] \ar: Toggle Run full cycle on startup (Settings.General.runFullCycleOnStartup)', overseer_msg)
    printf('%s \aoautoRestart [on|off] \ar: Toggle auto restart each cycle (Settings.General.autoRestartEachCycle)', overseer_msg)
    printf('%s \aoignoreRecruit [on|off] \ar: Toggle ignoring Recruitment quests', overseer_msg)
    printf('%s \aoignoreConversion [on|off] \ar: Toggle ignoring Conversion quests', overseer_msg)
    printf('%s \aoignoreRecovery [on|off] \ar: Toggle ignoring Recovery quests', overseer_msg)
    printf('%s \aocountEachCycle [on|off] \ar: Toggle counting agents between cycles', overseer_msg)
    printf('%s \aoconversionCountCommon <number> \ar: Set agentCountForConversionCommon', overseer_msg)
    printf('%s \aoconversionCountUncommon <number> \ar: Set agentCountForConversionUncommon', overseer_msg)
    printf('%s \aoconversionCountRare <number> \ar: Set agentCountForConversionRare', overseer_msg)
    printf('%s \aoretireCountElite <number> \ar: Set agentCountForRetireElite', overseer_msg)
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

    -- Helper logger wrapper for info/warn messages
    local function log_info(name, value)
        if logger and logger.info then logger.info("%s = %s", name, tostring(value)) end
    end
    local function log_warn(msg, param)
        if logger and logger.warning then logger.warning("%s %s", tostring(msg), tostring(param or "")) end
    end

    if (arg=="runOnStartup") then
        Settings.General.runFullCycleOnStartup, success = apply_command_bool(Settings.General.runFullCycleOnStartup, c1)
        if success then log_info("Settings.General.runFullCycleOnStartup", Settings.General.runFullCycleOnStartup) else log_warn("Invalid parameter for runOnStartup:", c1) end
        -- Settings/General
    elseif (arg=="autoFitWindow") then
        Settings.General.autoFitWindow, success = apply_command_bool(Settings.General.autoFitWindow, c1)
        if success then log_info("Settings.General.autoFitWindow", Settings.General.autoFitWindow) else log_warn("Invalid parameter for autoFitWindow:", c1) end
    elseif (arg=="autoRestart") then
        Settings.General.autoRestartEachCycle, success = apply_command_bool(Settings.General.autoRestartEachCycle, c1)
        if success then log_info("Settings.General.autoRestartEachCycle", Settings.General.autoRestartEachCycle) else log_warn("Invalid parameter for autoRestart:", c1) end
    elseif (arg=="ignoreRecruit") then
        Settings.General.ignoreRecruitmentQuests, success = apply_command_bool(Settings.General.ignoreRecruitmentQuests, c1)
        if success then log_info("Settings.General.ignoreRecruitmentQuests", Settings.General.ignoreRecruitmentQuests) else log_warn("Invalid parameter for ignoreRecruit:", c1) end
    elseif (arg=="ignoreConversion") then
        Settings.General.ignoreConversionQuests, success = apply_command_bool(Settings.General.ignoreConversionQuests, c1)
        if success then log_info("Settings.General.ignoreConversionQuests", Settings.General.ignoreConversionQuests) else log_warn("Invalid parameter for ignoreConversion:", c1) end
    elseif (arg=="ignoreRecovery") then
        Settings.General.ignoreRecoveryQuests, success = apply_command_bool(Settings.General.ignoreRecoveryQuests, c1)
        if success then log_info("Settings.General.ignoreRecoveryQuests", Settings.General.ignoreRecoveryQuests) else log_warn("Invalid parameter for ignoreRecovery:", c1) end
    elseif (arg=="countEachCycle") then
        Settings.General.countAgentsBetweenCycles, success = apply_command_bool(Settings.General.countAgentsBetweenCycles, c1)
        if success then log_info("Settings.General.countAgentsBetweenCycles", Settings.General.countAgentsBetweenCycles) else log_warn("Invalid parameter for countEachCycle:", c1) end
    elseif (arg=="conversionCountCommon") then
        Settings.General.agentCountForConversionCommon, success = apply_command_number(Settings.General.agentCountForConversionCommon, c1)
        if success then log_info("Settings.General.agentCountForConversionCommon", Settings.General.agentCountForConversionCommon) else log_warn("Invalid parameter for conversionCountCommon:", c1) end
    elseif (arg=="conversionCountUncommon") then
        Settings.General.agentCountForConversionUncommon, success = apply_command_number(Settings.General.agentCountForConversionUncommon, c1)
        if success then log_info("Settings.General.agentCountForConversionUncommon", Settings.General.agentCountForConversionUncommon) else log_warn("Invalid parameter for conversionCountUncommon:", c1) end
    elseif (arg=="conversionCountRare") then
        Settings.General.agentCountForConversionRare, success = apply_command_number(Settings.General.agentCountForConversionRare, c1)
        if success then log_info("Settings.General.agentCountForConversionRare", Settings.General.agentCountForConversionRare) else log_warn("Invalid parameter for conversionCountRare:", c1) end
    elseif (arg=="conversionCountElite") then
        Settings.General.agentCountForRetireElite, success = apply_command_number(Settings.General.agentCountForRetireElite, c1)
        if success then log_info("Settings.General.agentCountForRetireElite", Settings.General.agentCountForRetireElite) else log_warn("Invalid parameter for conversionCountElite:", c1) end
    elseif (arg=="useDatabase") then
        Settings.General.useQuestDatabase, success = apply_command_bool(Settings.General.useQuestDatabase, c1)
        if success then log_info("Settings.General.useQuestDatabase", Settings.General.useQuestDatabase) else log_warn("Invalid parameter for useDatabase:", c1) end
    elseif (arg=="campAfterFullCycle") then
        Settings.General.campAfterFullCycle, success = apply_command_bool(Settings.General.campAfterFullCycle, c1)
        if success then log_info("Settings.General.campAfterFullCycle", Settings.General.campAfterFullCycle) else log_warn("Invalid parameter for campAfterFullCycle:", c1) end
    elseif (arg=="campAfterFullCycleFastCamp") then
        Settings.General.campAfterFullCycleFastCamp, success = apply_command_bool(Settings.General.campAfterFullCycleFastCamp, c1)
        if success then log_info("Settings.General.campAfterFullCycleFastCamp", Settings.General.campAfterFullCycleFastCamp) else log_warn("Invalid parameter for campAfterFullCycleFastCamp:", c1) end
        -- Settings/General/uiActions
    elseif (arg=="useUiDelay") then
        Settings.General.uiActions.useUiActionDelay, success = apply_command_bool(Settings.General.uiActions.useUiActionDelay, c1)
        if success then log_info("Settings.General.uiActions.useUiActionDelay", Settings.General.uiActions.useUiActionDelay) else log_warn("Invalid parameter for useUiDelay:", c1) end
    elseif (arg=="uiDelayMin") then
        Settings.General.uiActions.delayMinMs, success = apply_command_number(Settings.General.uiActions.delayMinMs, c1)
        if success then log_info("Settings.General.uiActions.delayMinMs", Settings.General.uiActions.delayMinMs) else log_warn("Invalid parameter for uiDelayMin:", c1) end
    elseif (arg=="uiDelayMax") then
        Settings.General.uiActions.delayMaxMs, success = apply_command_number(Settings.General.uiActions.delayMaxMs, c1)
        if success then log_info("Settings.General.uiActions.delayMaxMs", Settings.General.uiActions.delayMaxMs) else log_warn("Invalid parameter for uiDelayMax:", c1) end
        -- Settings/Rewards
    elseif (arg=="claimRewards") then
        Settings.General.rewards.claimRewards, success = apply_command_bool(Settings.General.rewards.claimRewards, c1)
        if success then log_info("Settings.General.rewards.claimRewards", Settings.General.rewards.claimRewards) else log_warn("Invalid parameter for claimRewards:", c1) end
    elseif (arg=="claimAgentPacks") then
        Settings.General.claimAgentPacks, success = apply_command_bool(Settings.General.claimAgentPacks, c1)
        if success then log_info("Settings.General.claimAgentPacks", Settings.General.claimAgentPacks) else log_warn("Invalid parameter for claimAgentPacks:", c1) end
    elseif (arg=="claimTetradrachm") then
        Settings.General.claimTetradrachmPacks, success = apply_command_bool(Settings.General.claimTetradrachmPacks, c1)
        if success then log_info("Settings.General.claimTetradrachmPacks", Settings.General.claimTetradrachmPacks) else log_warn("Invalid parameter for claimTetradrachm:", c1) end
    elseif (arg=="claimEliteAgentEchos") then
        Settings.General.claimEliteAgentEchos, success = apply_command_bool(Settings.General.claimEliteAgentEchos, c1)
        if success then log_info("Settings.General.claimEliteAgentEchos", Settings.General.claimEliteAgentEchos) else log_warn("Invalid parameter for claimEliteAgentEchos:", c1) end
    elseif (arg=="runCompletedAchievementQuests") then
        Settings.General.ForceCompletedAchievementQuests, success = apply_command_bool(Settings.General.ForceCompletedAchievementQuests, c1)
        if success then
            settings.ForceRunCompletedAchievements_Changed()
            log_info("Settings.General.ForceCompletedAchievementQuests", Settings.General.ForceCompletedAchievementQuests)
        else
            log_warn("Invalid parameter for runCompletedAchievementQuests:", c1)
        end
    elseif (arg=="saveMaxExpRewards") then
        Settings.General.rewards.maximizeStoredExpRewards, success = apply_command_bool(Settings.General.rewards.maximizeStoredExpRewards, c1)
        if success then log_info("Settings.General.rewards.maximizeStoredExpRewards", Settings.General.rewards.maximizeStoredExpRewards) else log_warn("Invalid parameter for saveMaxExpRewards:", c1) end
    elseif (arg=="savedRewardCount") then
        Settings.General.rewards.storedExpRewardsCount, success = apply_command_number(Settings.General.rewards.storedExpRewardsCount, c1)
        if success then log_info("Settings.General.rewards.storedExpRewardsCount", Settings.General.rewards.storedExpRewardsCount) else log_warn("Invalid parameter for savedRewardCount:", c1) end
        -- Settings/Quests
    elseif (arg=="selectHighestExp") then
        Settings.QuestPriority.general.selectHighestExp, success = apply_command_bool(Settings.QuestPriority.general.selectHighestExp, c1)
        if success then log_info("Settings.QuestPriority.general.selectHighestExp", Settings.QuestPriority.general.selectHighestExp) else log_warn("Invalid parameter for selectHighestExp:", c1) end
        -- Actions
    elseif (arg=="runFullCycle") then
        overseer.SetAction('FullCycle')
        success = true
        if success and logger and logger.info then logger.info("Action requested: FullCycle") end
    elseif (arg=="outputQuestDetails") then
        overseer.SetAction('DumpQuestDetails')
        success = true
        if success and logger and logger.info then logger.info("Action requested: DumpQuestDetails") end
    elseif (arg=="addSpecificQuest") then
        settings.AddSpecifiedQuests(c1)
        success = true
        if success then log_info("Settings.SpecificQuests.Add", c1) end
    elseif (arg=="removeSpecificQuest") then
        settings.RemoveSpecifiedQuests(c1)
        success = true
        if success then log_info("Settings.SpecificQuests.Remove", c1) end
    elseif (arg=="addAllSpecificQuests") then
        settings.AddAllSpecifiedQuests()
        success = true
        if success and logger and logger.info then logger.info("Action: AddAllSpecifiedQuests") end
    elseif (arg=="removeAllSpecificQuests") then
        settings.RemoveAllSpecifiedQuests()
        success = true
        if success and logger and logger.info then logger.info("Action: RemoveAllSpecifiedQuests") end
        -- Settings/Debug
    elseif (arg=="addToDatabase") then
        -- Ensure Debug table exists
        Settings.Debug = Settings.Debug or {}
        -- Toggle the flag via the shared helper
        Settings.Debug.processFullQuestRewardData, success = apply_command_bool(Settings.Debug.processFullQuestRewardData, c1)
        if success then
            -- Log the runtime change for visibility
            if Settings.Debug.processFullQuestRewardData then
                if logger and logger.info then logger.info("Enabled processFullQuestRewardData via CLI") end
            else
                if logger and logger.info then logger.info("Disabled processFullQuestRewardData via CLI") end
            end
        else
            if logger and logger.warning then logger.warning("Invalid parameter for addToDatabase: %s", tostring(c1)) end
        end
    elseif (arg=="validateQuestRewardData") then
        -- Ensure Debug table exists
        Settings.Debug = Settings.Debug or {}
        Settings.Debug.validateQuestRewardData, success = apply_command_bool(Settings.Debug.validateQuestRewardData, c1)
        if success then
            -- When disabling validation, automatically disable update-on-validate for safety
            if not Settings.Debug.validateQuestRewardData then
                Settings.Debug.updateQuestDatabaseOnValidate = false
                if settings.Debug then
                    settings.Debug.updateQuestDatabaseOnValidate = false
                end
            end
            if logger and logger.info then
                logger.info("Saved Settings.Debug.validateQuestRewardData = %s", tostring(Settings.Debug.validateQuestRewardData))
            end
        else
            if logger and logger.warning then logger.warning("Invalid parameter for validateQuestRewardData: %s", tostring(c1)) end
        end
    -- Allow toggling Test Mode via CLI: /mqoverseer allowTestMode true|false
    elseif (arg=="allowTestMode") then
        Settings.Debug = Settings.Debug or {}
        Settings.Debug.allowTestMode, success = apply_command_bool(Settings.Debug.allowTestMode, c1)
        if success then
            -- sync runtime flag used elsewhere
            settings.InTestMode = Settings.Debug.allowTestMode
            -- when disabling test mode, clear validation/update flags to match UI behavior
            if not Settings.Debug.allowTestMode then
                Settings.Debug.validateQuestRewardData = false
                Settings.Debug.updateQuestDatabaseOnValidate = false
                if settings.Debug then
                    settings.Debug.validateQuestRewardData = false
                    settings.Debug.updateQuestDatabaseOnValidate = false
                end
            end
            if logger and logger.info then
                logger.info("Saved Settings.Debug.allowTestMode = %s", tostring(Settings.Debug.allowTestMode))
            end
        else
            if logger and logger.warning then logger.warning("Invalid parameter for allowTestMode: %s", tostring(c1)) end
        end
    elseif (arg=="updateQuestDatabaseOnValidate") then
        -- Ensure Debug table exists
        Settings.Debug = Settings.Debug or {}
        -- Toggle the flag via the shared helper
        Settings.Debug.updateQuestDatabaseOnValidate, success = apply_command_bool(Settings.Debug.updateQuestDatabaseOnValidate, c1)
        if success then
            -- Warn if user enabled updates but validation is not enabled (likely a mistake)
            if Settings.Debug.updateQuestDatabaseOnValidate and not Settings.Debug.validateQuestRewardData then
                if logger and logger.warning then
                    logger.warning("updateQuestDatabaseOnValidate enabled but validateQuestRewardData is false — updates will only run when validation detects mismatches")
                end
            end
            if logger and logger.info then
                logger.info("Saved Settings.Debug.updateQuestDatabaseOnValidate = %s", tostring(Settings.Debug.updateQuestDatabaseOnValidate))
            end
        else
            if logger and logger.warning then logger.warning("Invalid parameter for updateQuestDatabaseOnValidate: %s", tostring(c1)) end
        end
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