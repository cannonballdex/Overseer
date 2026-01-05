--- @type Mq
local mq = require('mq')
local mqFacade = require('overseer.mq_facade')
local overseer = require('overseer.overseer')
local uiutils = require('overseer.overseer_ui_utils')
local ui_settings_rewards = require('overseer.overseerui_settings_rewards')
local settings = require('overseer.overseer_settings')
local logger = require('overseer.utils.logger')
local tests = require('overseer.tests.string_utils_tests')
local string_utils = require('overseer/utils/string_utils')
local utils = require('utils.utils')
local icons = require('mq.Icons')

local actions = {}

--- @type boolean
Open, ShowUI = true, true
--- @type boolean
MyShowUi = true

local TEXT_BASE_HEIGHT = ImGui.GetTextLineHeightWithSpacing();

function actions.InitializeUi(showUi)
    mq.imgui.init('Overseer LUA UI', DrawMainWindow)
    MyShowUi = showUi
end

function HideUi() SetWindowVisibleState(false) end

function SetWindowVisibleState(show)
    MyShowUi = show
    if (Settings.General.showUi ~= MyShowUi) then
        if (MyShowUi) then
            logger.info('\aoShowing Overseer UI\ar')
        else
            logger.info('\aoHiding Overseer UI\ar')
        end

        Settings.General.showUi = MyShowUi
        settings.SaveSettings()
    end
end

function DrawMainWindow()
    if MyShowUi == false then return end

    local changed
    MyShowUi, ShowUI = ImGui.Begin('Overseer', Open)
    if ShowUI then
        if (overseer.HasAutoFillButton() == false) then
            uiutils.text_colored(TextStyle.Error, "Cannot Run Quests. Current UI Skin Has No [Auto Fill] Button.")
            uiutils.add_tooltip("Load the default skin or add the button to current one.")
        end
        if (overseer.HasMaxQuestLabel() == false) then
            uiutils.text_colored(TextStyle.Error, "Cannot Run Quests. Current UI Skin Has No [Max Quest] Label.")
            uiutils.add_tooltip("Load the default skin or update the skin appropriately.")
        end

        if (CampingToDesktop) then
            uiutils.text_colored(TextStyle.Error, "Character is camping to desktop")
            ImGui.SameLine()
            uiutils.add_button("Cancel Camping Out", overseer.AbandonCampingOut, 'Abandon current camping out')
            ImGui.Separator()
        elseif (Settings.General.campAfterFullCycle) then
            uiutils.text_colored(TextStyle.Yellow, "Character will automatically camp out after full cycle is completed")
            Settings.General.campAfterFullCycle, changed = uiutils.add_setting_checkbox("Camp Character After Full Run",
                Settings.General.campAfterFullCycle, 'Camps character to desktop after full run.\n\nCommand: campAfterFullCycle')
            if (changed) then settings.SaveSettings() end
            ImGui.Separator()
        end

        ImGui.Text('State: ')
        ImGui.SameLine()
        if (CurrentProcessName == "Idle") then
            uiutils.text_colored(TextStyle.ItemValue, "Idle")
        elseif (overseer.Aborting) then
            uiutils.text_colored(TextStyle.ItemValue, "Canceling")
        else
            uiutils.text_colored(TextStyle.ProcessName, CurrentProcessName)
        end

        RenderTabBar()
    end

    ImGui.End()
end

function RenderTabBar()
    ImGui.BeginTabBar("OverseerTabBar", ImGuiTabBarFlags.Reorderable)

    RenderGeneralTab()
    RenderSettingsTab()
    RenderActionsTab()
    RenderStatsTab()
    if (settings.InTestMode == true) then
        RenderTestTab()
    end

    ImGui.EndTabBar()
end

local game_states = { "CHARSELECT", "INGAME", "PRECHARSELECT", "UNKNOWN" }
local subscription_levels = { "GOLD", "SILVER", "FREE", "UNKNOWN" }

local function add_claim_table_row(name, value)
    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    uiutils.text_colored(TextStyle.ItemValueDetail, name)
    ImGui.TableNextColumn()
    if value > 0 then
        ImGui.TextColored(0, 1, 0, 1, value)
    else
        ImGui.Text(string.format("%s", value))
    end
end

function RenderGeneralTab()
    local changed

    if ImGui.BeginTabItem("General") then
        ImGui.Text("Configuration: ")
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValue, settings.ConfigurationType)
        uiutils.add_tooltip(settings.ConfigurationSource)

        if (HasInitialized == false) then
            ImGui.Text("Next Quest Completion: ")
            ImGui.SameLine()
            uiutils.text_colored(TextStyle.ItemValue, "Initializing...")

            ImGui.Text("Next Rotation: ")
            ImGui.SameLine()
            uiutils.text_colored(TextStyle.ItemValue, "Initializing...")
        elseif (overseer.TutorialIsRequired == true) then
        else
            if (InProcess == false and MinutesUntilNextQuest == -1) then
                ImGui.Text("Next Quest Completion: ")
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.690, 0.100, 0.100, 1)
                ImGui.Text("No quests currently active.")
                ImGui.PopStyleColor(1)
            elseif (MinutesUntilNextQuest ~= nil and MinutesUntilNextQuest == 0) then
                ImGui.Text("Next Quest Completion: ")
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.100, 0.775, 0.100, 1)
                ImGui.Text("Quests are pending collection")
                ImGui.PopStyleColor(1)
            elseif (NextQuestTimeStampText ~= nil) then
                ImGui.Text("Next Quest Completion: ")
                ImGui.SameLine()
                uiutils.text_colored(TextStyle.ItemValue, NextQuestTimeStampText)
            end

            if (NextRotationTimeStampText ~= nil) then
                ImGui.Text("Next Rotation: ")
                ImGui.SameLine()
                uiutils.text_colored(TextStyle.ItemValue, NextRotationTimeStampText)
            end
        end

        if (overseer.TutorialIsRequired == true) then
            ImGui.Text("")
            uiutils.text_colored(TextStyle.ImportantLabel, "Tutorial Not Completed")
            uiutils.add_icon_action_button(icons.MD_PLAY_CIRCLE_FILLED, 'Run Tutorial', 'RunTutorial',
                'Runs the tutorial')
            ImGui.Text("")
        else
            Settings.General.autoRestartEachCycle, changed = uiutils.add_setting_checkbox("Automatically Restart",
                Settings.General.autoRestartEachCycle,
                'Automatically run full cycle when next quest has completed or on quest rotation\n\nCommand: autoRestart')
            if (changed) then settings.SaveSettings() end

            if (CurrentProcessName ~= "Initialze") then
                if (InProcess) then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.999, 0.999, 0.999, 1)
                    ImGui.PushStyleColor(ImGuiCol.Button, 0.690, 0.100, 0.100, 1)
                    uiutils.add_button(icons.MD_PAN_TOOL, overseer.AbortCurrentProcess, 'Cancel Full Cycle')

                    ImGui.PopStyleColor(2)
                else
                    uiutils.add_action_button(icons.MD_PLAY_CIRCLE_FILLED, 'FullCycle',
                        'Runs the full/classic Overseer cycle')
                end

                ImGui.SameLine()
            end
        end

        if IsOverseerWindowOpen() then
            uiutils.add_button(icons.MD_TAB, CloseOverseerWindowLight)
        else
            uiutils.add_button(icons.MD_TAB_UNSELECTED, OpenOverseerWindowLight)
        end
        uiutils.add_tooltip('Opens or Closes Overseer Window')
        ImGui.SameLine()
        uiutils.add_button(icons.FA_WINDOW_CLOSE, HideUi)
        uiutils.add_tooltip('Hides this window.  To redisplay, use the "/mqoverseer show" command.')
        ImGui.SameLine()
        local SnoozTimer = MinutesUntilNextQuest*600
        if ImGui.Button(icons.MD_ADD_ALARM) then
            mq.cmdf('/timed %s /lua run overseer', SnoozTimer)
            mq.cmd('/lua stop overseer')
        end
        uiutils.add_tooltip('Snooze Overseer.lua Until The Next Quest Is Complete.')
        ImGui.SameLine()
        if ImGui.Button(icons.MD_POWER_SETTINGS_NEW) then mq.cmd('/lua stop overseer') end
        uiutils.add_tooltip('Stops this script')

        local fragments = mq.TLO.FindItemCount('=Overseer Collection Item Dispenser Fragment')()
        local ornamentation = mq.TLO.FindItemCount('=Overseer Ornamentation Dispenser')()
        local collectionDispenser = mq.TLO.FindItemCount('=Overseer Collection Item Dispenser')()
        local agent = mq.TLO.FindItemCount('=Overseer Agent Pack')()
        local coffer = mq.TLO.FindItemCount('=Sealed Tetradrachm Coffer')()
        local agentElite = mq.TLO.FindItemCount('=Elite Agent Echo')()
        local agentUncommon = mq.TLO.FindItemCount('=Overseer Bonus Uncommon Agent')()
        local tetradrachms = mq.TLO.Me.AltCurrency('Overseer Tetradrachms')()

        ImGui.Separator()
        if ImGui.CollapsingHeader('Overseer Claims (Inventory)') then
            local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)
            if ImGui.BeginTable('##tableClaims', 3, flags, 0, TEXT_BASE_HEIGHT, 0.0) then
                ImGui.TableSetupColumn('Name', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 0)
                ImGui.TableSetupColumn('Value', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 1)
                ImGui.TableSetupColumn('Padding', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 1)

                add_claim_table_row('Overseer Tetradrachms', tetradrachms)
                add_claim_table_row('Dispenser Fragments', fragments)
                add_claim_table_row('Ornamentation Dispensers', ornamentation)
                add_claim_table_row('Collection Item Dispensers', collectionDispenser)
                add_claim_table_row('Agent Packs', agent)
                add_claim_table_row('Sealed Tetradrachm Coffer', coffer)
                add_claim_table_row('Uncommon Agent Packs', agentUncommon)
                add_claim_table_row('Elite Agent Echos', agentElite)

                ImGui.EndTable()
            end
        end

        ImGui.EndTabItem()
    end
end

function RenderSettingsTab()
    if ImGui.BeginTabItem("Settings") then
        if (Settings == nil or Settings.General == nil or Settings.Initialized == false) then
            ImGui.EndTabItem()
            return
        end

        ImGui.BeginTabBar("OverseerSettingsTabBar", ImGuiTabBarFlags.Reorderable)
        RenderSettingsGeneralTab()
        RenderSettingsQuestsSection()
        RenderSettingsRewardsTab()
        RenderSettingsSpecificQuestSection()
        ImGui.EndTabBar()

        ImGui.EndTabItem()
    end
end

local log_levels = { "Off", "Error", "Warning", "Normal", "Debug", "Trace" }

function RenderSettingsGeneralTab()
    if ImGui.BeginTabItem("General") then
        local changed
        -- local useCharacterConfigurations
        -- useCharacterConfigurations, changed = ImGui.Checkbox('Use Character Configurations', overseer.UsingCharacterConfiguration)
        -- if (changed) then
        --     UpdateGlobalCharConfigurationSetting(useCharacterConfigurations)
        -- end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, 'General Settings')
        ImGui.Separator()

        Settings.General.runFullCycleOnStartup, changed = uiutils.add_setting_checkbox("Run Full Cycle on Startup",
            Settings.General.runFullCycleOnStartup,
            'Runs the full Overseer cycle when script begins\n\nCommand: runOnStartup')
        if (changed) then settings.SaveSettings() end

        Settings.General.autoRestartEachCycle, changed = uiutils.add_setting_checkbox("Automatically Restart",
            Settings.General.autoRestartEachCycle,
            'Automatically run full cycle when next quest has completed or on quest rotation\n\nCommand: autoRestart')
        if (changed) then settings.SaveSettings() end

        Settings.General.pauseOnCharacterChange, changed = uiutils.add_setting_checkbox("Pause On Char Change",
            Settings.General.pauseOnCharacterChange, 'Pauses cycles until character that started the script logs in')
        if (changed) then settings.SaveSettings() end

        Settings.General.campAfterFullCycle, changed = uiutils.add_setting_checkbox("Camp Character After Full Run",
            Settings.General.campAfterFullCycle, 'Camps character to desktop after full run.\n\nCommand: campAfterFullCycle')
        if (changed) then settings.SaveSettings() end
        if (Settings.General.campAfterFullCycle) then
            ImGui.Indent(20)
            Settings.General.campAfterFullCycleFastCamp, changed = uiutils.add_setting_checkbox("Fast Camp",
                Settings.General.campAfterFullCycleFastCamp, 'Fast Camps to desktop ("/yes") when in a fast camp zone.\n\nCommand: campAfterFullCycleFastCamp')
            ImGui.Unindent(20)
            if (changed) then settings.SaveSettings() end
        end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, "Claim Settings")
        ImGui.Separator()
        RenderSettingsRewardsGeneralSection()

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, "Ignore Specific Quests")
        ImGui.Separator()

        Settings.General.ignoreRecruitmentQuests, changed = uiutils.add_setting_checkbox('Ignore Recruitment Quests',
            Settings.General.ignoreRecruitmentQuests,
            'If selected, will not run Recruitment quests\n\nCommand: ignoreRecruit')
        if (changed) then settings.SaveSettings() end

        Settings.General.ignoreConversionQuests, changed = uiutils.add_setting_checkbox('Ignore Conversion Quests',
            Settings.General.ignoreConversionQuests,
            'If selected, will not run Conversion quests\n\nCommand: ignoreConversion')
        if (changed) then settings.SaveSettings() end

        Settings.General.ignoreRecoveryQuests, changed = uiutils.add_setting_checkbox('Ignore Recovery Quests',
            Settings.General.ignoreRecoveryQuests,
            'If selected, will not run Recovery quests\n\nCommand: ignoreRecovery')
        if (changed) then settings.SaveSettings() end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, "Agents Required Before Conversion")
        ImGui.Separator()

        -- TODO: Elite Retire
        Settings.General.convertEliteAgents, changed = uiutils.add_setting_checkbox('Convert Elite Agents',
            Settings.General.convertEliteAgents,
            'Specifies number of elite agents to maintain\n\nCommand: convertEliteAgents')
        if (changed) then settings.SaveSettings() end
        if (Settings.General.convertEliteAgents) then
            ImGui.Indent(20)
        end

        if Settings.General.agentCountForConversionCommon ~= nil then
            ImGui.PushItemWidth(100)
            Settings.General.agentCountForConversionCommon, changed = ImGui.InputInt("Common",
                Settings.General.agentCountForConversionCommon, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
            uiutils.add_tooltip('Specifies number of common agents to maintain\n\nCommand: conversionCountCommon #')

            if Settings.General.agentCountForConversionCommon < 2 then Settings.General.agentCountForConversionCommon = 1 end
            if (changed) then settings.SaveSettings() end
            ImGui.SameLine()
            if ImGui.Button'Mass Convert Common' then
                mq.cmdf('/overseermassconvert common %s', Settings.General.agentCountForConversionCommon)
            end

            ImGui.PushItemWidth(100)
            Settings.General.agentCountForConversionUncommon, changed = ImGui.InputInt("Uncommon",
                Settings.General.agentCountForConversionUncommon, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
            uiutils.add_tooltip('Specifies number of uncommon agents to maintain\n\nCommand: conversionCountUncommon #')
            if Settings.General.agentCountForConversionUncommon < 2 then Settings.General.agentCountForConversionUncommon = 1 end
            if (changed) then settings.SaveSettings() end
            ImGui.SameLine()
            local uncommon = Settings.General.agentCountForConversionUncommon
            if ImGui.Button'Mass Convert Uncommon' then
                mq.cmdf('/overseermassconvert uncommon %s', uncommon)
            end

            ImGui.PushItemWidth(100)
            Settings.General.agentCountForConversionRare, changed = ImGui.InputInt("Rare",
                Settings.General.agentCountForConversionRare, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
            uiutils.add_tooltip('Specifies number of rare agents to maintain\n\nCommand: conversionCountRare #')
            if Settings.General.agentCountForConversionRare < 2 then Settings.General.agentCountForConversionRare = 1 end
            if (changed) then settings.SaveSettings() end
            ImGui.SameLine()
            if ImGui.Button'Mass Convert Rare' then
                mq.cmdf('/overseermassconvert rare %s', Settings.General.agentCountForConversionRare)
            end

            if (Settings.General.convertEliteAgents) then
                ImGui.PushItemWidth(100)
                Settings.General.agentCountForConversionElite, changed = ImGui.InputInt("Elite",
                    Settings.General.agentCountForConversionElite, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
                uiutils.add_tooltip('Specifies number of elite agents to maintain\n\nCommand: conversionCountElite #')
                if Settings.General.agentCountForConversionElite < 2 then Settings.General.agentCountForConversionElite = 1 end
                if (changed) then settings.SaveSettings() end
                ImGui.SameLine()
            if ImGui.Button'Mass Convert Elite' then
                mq.cmdf('/overseermassconvert elite %s', Settings.General.agentCountForConversionElite)
            end
                ImGui.Unindent(20)
            end
        end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, "Quest Mode")
        ImGui.Separator()
        ImGui.Indent(20)
        ImGui.Text(" Not Implemented ")
        ImGui.Unindent(20)
        ImGui.Separator()

        -- Settings.General.rewards.maximizeStoredExpRewards, changed = uiutils.add_setting_checkbox('Save Highest Exp Quests/Rewards',
        -- Settings.General.rewards.maximizeStoredExpRewards,
        -- 'If selected, highest exp quests will be run, and highest exp rewards will be saved\n\nCommand: saveMaxExpRewards')
        -- if (changed) then settings.SaveSettings() end

        -- ImGui.Indent(20)
        -- ImGui.PushItemWidth(100)
        -- Settings.General.rewards.storedExpRewardsCount, changed = ImGui.InputInt("Number of rewards to bank", Settings.General.rewards.storedExpRewardsCount, 1, 10, ImGuiInputTextFlags.EnterReturnsTrue)
        -- if Settings.General.rewards.storedExpRewardsCount < 1 then Settings.General.rewards.storedExpRewardsCount = 1 end
        -- if Settings.General.rewards.storedExpRewardsCount > 10 then Settings.General.rewards.storedExpRewardsCount = 10 end
        -- uiutils.add_tooltip('If MaximizeStoredExpRewards option selected, specifies number of rewards to maintain in the reward window before claiming.')
        -- if (changed) then settings.SaveSettings() end
        -- ImGui.PopItemWidth()
        -- ImGui.Unindent(20)
        uiutils.text_colored(TextStyle.ItemValue, "Reward Claim")
        ImGui.Separator()

        if Settings.General.maxLevelForClaimingExpReward ~= nil then
            Settings.General.maxLevelUseCurrentCap, changed = uiutils.add_setting_checkbox('Use Current Character Level Cap: '..mq.TLO.Me.MaxLevel(), Settings.General.maxLevelUseCurrentCap,
            'Always claim exp up to current character level cap.')
            if (changed) then settings.SaveSettings() end

            if (Settings.General.maxLevelUseCurrentCap) then
                ImGui.Indent(20)
                ImGui.Text(" Claiming Exp. ")
                ImGui.SameLine()
                uiutils.text_colored(TextStyle.Green, Settings.General.maxLevelPctForClaimingExpReward)
                ImGui.SameLine()
                uiutils.text_colored(TextStyle.Green,"%")
                ImGui.SameLine()
                ImGui.Text(" into level ")
                ImGui.SameLine()
                uiutils.text_colored(TextStyle.Green, Settings.General.maxLevelForClaimingExpReward)
            end

            if (not Settings.General.maxLevelUseCurrentCap) then
                ImGui.PushItemWidth(100)
                Settings.General.maxLevelForClaimingExpReward, changed = ImGui.InputInt("Custom Max Level Claim Exp.",
                    Settings.General.maxLevelForClaimingExpReward, 1, mq.TLO.Me.MaxLevel(), ImGuiInputTextFlags.EnterReturnsTrue)
                if Settings.General.maxLevelForClaimingExpReward < 1 then Settings.General.maxLevelForClaimingExpReward = 1 end
                if Settings.General.maxLevelForClaimingExpReward > mq.TLO.Me.MaxLevel() then Settings.General.maxLevelForClaimingExpReward = 130 end
                uiutils.add_tooltip('Max Level To Claim Experience Rewards')
                if (changed) then settings.SaveSettings() end
            end
            ImGui.PushItemWidth(100)
            Settings.General.maxLevelPctForClaimingExpReward, changed = ImGui.InputInt("Max Exp Level Claim Exp.",
                Settings.General.maxLevelPctForClaimingExpReward, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
            if Settings.General.maxLevelPctForClaimingExpReward < 1 then Settings.General.maxLevelPctForClaimingExpReward = 1 end
            if Settings.General.maxLevelPctForClaimingExpReward > 100 then Settings.General.maxLevelPctForClaimingExpReward = 100 end
            uiutils.add_tooltip('Max Experience at Level To Claim Experience Rewards')
            if (changed) then settings.SaveSettings() end
            ImGui.PushItemWidth(100)
            Settings.General.minimumSuccessPercent, changed = ImGui.InputInt("Mininum Success %",
                Settings.General.minimumSuccessPercent, 1, 100, ImGuiInputTextFlags.EnterReturnsTrue)
            if Settings.General.minimumSuccessPercent < 1 then Settings.General.minimumSuccessPercent = 0 end
            if Settings.General.minimumSuccessPercent > 100 then Settings.General.minimumSuccessPercent = 100 end
            uiutils.add_tooltip('Minimum Success % to Select Quest')
            if (Settings.General.maxLevelUseCurrentCap) then
                ImGui.Unindent(20)
            end
            if (changed) then settings.SaveSettings() end
        end

        if Settings.General.uiActions.useUiActionDelay ~= nil then
            ImGui.Separator()
            uiutils.text_colored(TextStyle.ItemValue, 'UI Actions')
            ImGui.Separator()
            Settings.General.uiActions.useUiActionDelay, changed = uiutils.add_setting_checkbox('Use UI Action Delay',
                Settings.General.uiActions.useUiActionDelay,
                'If selected, most UI actions impose a random delay between the two times specified below.\n\nCommand: useUiDelay')
            if (changed) then settings.SetUiDelays() end
        end

        if Settings.General.uiActions.useUiActionDelay then
            ImGui.Indent(20)
            Settings.General.uiActions.delayMinMs, changed = ImGui.InputInt("Minimum random delay (ms)",
                Settings.General.uiActions.delayMinMs, 1, 10000, ImGuiInputTextFlags.EnterReturnsTrue)
            uiutils.add_tooltip('Minimum random delay (ms) for most UI actions\n\nCommand: uiDelayMin')
            if (changed) then settings.SetUiDelays() end
            Settings.General.uiActions.delayMaxMs, changed = ImGui.InputInt("Maximum random delay (ms)",
                Settings.General.uiActions.delayMaxMs, 1, 10000, ImGuiInputTextFlags.EnterReturnsTrue)
            uiutils.add_tooltip('Maximum random delay (ms) for most UI actions\n\nCommand: uiDelayMax')
            if (changed) then settings.SetUiDelays() end
            ImGui.Unindent(20)
        end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, 'Logging')
        ImGui.Separator()

        local logLevel, changed = ImGui.Combo("Log Level", Settings.General.logLevel, log_levels, #log_levels)
        ImGui.PushItemWidth(100)
        ImGui.SameLine()
        ImGui.Text("'%s'", log_levels[Settings.General.logLevel])
        if (changed) then settings.SetLogLevel(logLevel) end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, 'Display')
        ImGui.Separator()
        Settings.Display.showDetailed, changed = uiutils.add_setting_checkbox('Show Additional UI Details',
            Settings.Display.showDetailed, 'Displays additional details in the UI.')

        ImGui.Separator()

        settings.InTestMode, changed = uiutils.add_setting_checkbox('Enter Test Mode', settings.InTestMode,
            'Adds "Test" tab and enables test mode.')

        ImGui.EndTabItem()
    end
end

-- TODO: Move this to overseer.lua
local all_rewards = {
    "Character Experience",
    "Overseer Tetradrachm",
    "Mercenary Experience",
    "Ornamentation Dispenser",
    "Collection Item Dispenser",
    "Seeds of Destruction",
    "Veil of Alaris",
    "The Darkened Sea",
    "Ring of Scale",
    "Underfoot",
    "Rain of Fear",
    "The Burning Lands",
    "House of Thule",
    "Call of the Forsaken",
    "Torment of Velious",
    "Claws of Veeshan",
    "Terror of Luclin",
    "Night of Shadows",
    "Laurion's Song"
}

local active_item_current_idx = 0
local available_item_current_idx = 0

local all_eliteecho_rewards = {
    "None",
    "Overseer Plunder XP",
    "Overseer Stealth XP",
    "Overseer Military XP",
    "Overseer Crafting XP",
    "Overseer Harvesting XP",
    "Overseer Research XP",
    "Overseer Diplomacy XP",
    "Overseer Trade XP",
    "Overseer Exploration XP",
    "Overseer Recruitment XP",
    "Overseer Recovery XP",
    "Overseer Rare Agents x2"
}

local function render_settings_rewards_eliteecho_section()
    -- TODO: Elite Retire
    local changed
    Settings.General.claimEliteAgentEchos, changed = uiutils.add_setting_checkbox('Claim Elite Agent Echos',
        Settings.General.claimEliteAgentEchos,
        'Claim any Elite Agent Echos automatically, after each full cycle.\n\nCommand: claimEliteAgentEchos')
    if (changed) then settings.SaveSettings() end

    if (Settings.General.claimEliteAgentEchos == nil or Settings.General.claimEliteAgentEchos == false) then return end
    ImGui.Text('  ')
    ImGui.SameLine()
    ImGui.PushItemWidth(185)

    if ImGui.BeginCombo("##EliteEchoRewards", Settings.Rewards.eliteAgentEchoReward) then -- Remove the ## if you'd like for the title to display above combo box
        for i, option in ipairs(all_eliteecho_rewards) do
            if ImGui.Selectable(option, (option == Settings.Rewards.eliteAgentEchoReward)) then
                Settings.Rewards.eliteAgentEchoReward = option
                settings.SaveSettings()
                -- ImGui.SetItemDefaultFocus()
            end
        end

        ImGui.EndCombo()
    end
end

function RenderSettingsRewardsGeneralSection()
    local changed
    Settings.General.rewards.claimRewards, changed = uiutils.add_setting_checkbox('Claim Rewards',
        Settings.General.rewards.claimRewards,
        'If selected, will claim quest rewards based on INI-specified priorities.\n\nCommand: claimRewards')
    if (changed) then settings.SaveSettings() end

    Settings.General.claimCollectionFragments, changed = uiutils.add_setting_checkbox('Claim Collection Fragments',
        Settings.General.claimCollectionFragments,
        'Claim Overseer Collection Item Dispenser Fragments automatically, after each full cycle.\n\nCommand: claimCollectionFragments')
    if (changed) then settings.SaveSettings() end

    Settings.General.claimAgentPacks, changed = uiutils.add_setting_checkbox('Claim Agent Packs',
        Settings.General.claimAgentPacks,
        'Claim any agent packs automatically, after each full cycle.\n\nCommand: claimAgentPacks')
    if (changed) then settings.SaveSettings() end

    Settings.General.claimTetradrachmPacks, changed = uiutils.add_setting_checkbox('Claim Tetradrachm Coffer',
        Settings.General.claimTetradrachmPacks,
        'Claim any Tetradrachm packs automatically, after each full cycle.\n\nCommand: claimTetradrachm')
    if (changed) then settings.SaveSettings() end

    -- TODO: Elite Retire
    render_settings_rewards_eliteecho_section()
end

local QuestConfigType = {
    Simple = 1,
    Custom = 2,
}

local questConfigType
local function RenderSettingsQuestsPriorityGroupSection(priorityName, config)
    if (ImGui.BeginTabItem(priorityName)) then
        local changed
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.6, 0.6, 1)
        config.general.selectHighestExp, changed = uiutils.add_setting_checkbox('Select highest exp rewards', config.general.selectHighestExp)
        ImGui.PopStyleColor(1)
        uiutils.add_tooltip('If selected, prioritizes quests purely on raw amount of exp earned.')
        if (changed) then settings.SaveGroupPrioritySettings("general", priorityName) end

        ImGui.Separator()

        if (config.general.selectHighestExp == false) then
            ImGui.Separator()
            questConfigType = ImGui.RadioButton("Simple##questConfigType", questConfigType or QuestConfigType.Simple,
                QuestConfigType.Simple)
            ImGui.SameLine()
            questConfigType = ImGui.RadioButton("Advanced##questConfigType", questConfigType or QuestConfigType.Custom,
                QuestConfigType.Custom)

            ImGui.Separator()

            if (questConfigType == QuestConfigType.Simple) then
                RenderSettingsQuestsSimpleSection(priorityName, config)
            elseif (questConfigType == QuestConfigType.Custom) then
                RenderSettingsQuestsCustomSection()
            end
        end

        ImGui.EndTabItem()
    end
end

function RenderSettingsQuestsSection()
    if (ImGui.BeginTabItem("Quests")) then
        ImGui.BeginTabBar("OverseerSettingsQuestsTabBar", ImGuiTabBarFlags.Reorderable)

        -- TODO: One tab per Priority Group, each tab has "Add Another" and "Delete This" (except Default)
        RenderSettingsQuestsPriorityGroupSection("Default", SettingsTemp.QuestPriorities.Default)
        if (SettingsTemp.QuestPriorities.Unsubscribed ~= nil) then
            RenderSettingsQuestsPriorityGroupSection("Unsubscribed", SettingsTemp.QuestPriorities.Unsubscribed)
        end

        if (Settings.General.useQuestPriorityGroups ~= nil) then
            local index = 0
            local ourSplit = string_utils.split(Settings.General.useQuestPriorityGroups, '|')

            repeat
                index = index + 1
                local questPriorityGroup = ourSplit[index]
                if (questPriorityGroup) then
                    RenderSettingsQuestsPriorityGroupSection(questPriorityGroup,
                        SettingsTemp.QuestPriorities[questPriorityGroup])
                end
            until not questPriorityGroup
        end

        ImGui.EndTabBar()
        ImGui.EndTabItem()
    end
end

function RenderSettingsQuestsCustomSection()
    ui_settings_rewards.RenderSettingsRewardsCustomSection()
end

local function ShowDetailedUI()
    return Settings.Display ~= nil and Settings.Display.showDetailed == true
end

function RenderSettingsQuestsSimpleSection(priorityName, config)
    local changed
    uiutils.text_colored(TextStyle.ItemValue, 'Durations')
    if (ShowDetailedUI()) then
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Durations)
    end
    config.durations.h36, changed = uiutils.add_setting_checkbox('36h', config.durations.h36)
    if (changed) then settings.SaveGroupPrioritySettings("durations", priorityName) end
    ImGui.SameLine()
    config.durations.h24, changed = uiutils.add_setting_checkbox('24h', config.durations.h24)
    if (changed) then settings.SaveGroupPrioritySettings("durations", priorityName) end
    ImGui.SameLine()
    config.durations.h12, changed = uiutils.add_setting_checkbox('12h', config.durations.h12)
    if (changed) then settings.SaveGroupPrioritySettings("durations", priorityName) end
    ImGui.SameLine()
    config.durations.h6, changed = uiutils.add_setting_checkbox('6h', config.durations.h6)
    if (changed) then settings.SaveGroupPrioritySettings("durations", priorityName) end
    ImGui.SameLine()
    config.durations.h3, changed = uiutils.add_setting_checkbox('3h', config.durations.h3)
    if (changed) then settings.SaveGroupPrioritySettings("durations", priorityName) end

    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Levels')
    if (ShowDetailedUI()) then
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Levels)
    end
    config.levels.level5, changed = uiutils.add_setting_checkbox('5', config.levels.level5)
    if (changed) then settings.SaveGroupPrioritySettings("levels", priorityName) end
    ImGui.SameLine()
    config.levels.level4, changed = uiutils.add_setting_checkbox('4', config.levels.level4)
    if (changed) then settings.SaveGroupPrioritySettings("levels", priorityName) end
    ImGui.SameLine()
    config.levels.level3, changed = uiutils.add_setting_checkbox('3', config.levels.level3)
    if (changed) then settings.SaveGroupPrioritySettings("levels", priorityName) end
    ImGui.SameLine()
    config.levels.level2, changed = uiutils.add_setting_checkbox('2', config.levels.level2)
    if (changed) then settings.SaveGroupPrioritySettings("levels", priorityName) end
    ImGui.SameLine()
    config.levels.level1, changed = uiutils.add_setting_checkbox('1', config.levels.level1)
    if (changed) then settings.SaveGroupPrioritySettings("levels", priorityName) end

    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Rarities')
    if (ShowDetailedUI()) then
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Rarities)
    end
    config.rarities.elite, changed = uiutils.add_setting_checkbox('Elite', config.rarities.elite)
    if (changed) then settings.SaveGroupPrioritySettings("rarities", priorityName) end
    ImGui.SameLine()
    config.rarities.rare, changed = uiutils.add_setting_checkbox('Rare', config.rarities.rare)
    if (changed) then settings.SaveGroupPrioritySettings("rarities", priorityName) end
    ImGui.SameLine()
    config.rarities.uncommon, changed = uiutils.add_setting_checkbox('Uncommon', config.rarities.uncommon)
    if (changed) then settings.SaveGroupPrioritySettings("rarities", priorityName) end
    config.rarities.common, changed = uiutils.add_setting_checkbox('Common', config.rarities.common)
    if (changed) then settings.SaveGroupPrioritySettings("rarities", priorityName) end
    ImGui.SameLine()
    config.rarities.easy, changed = uiutils.add_setting_checkbox('Easy', config.rarities.easy)
    if (changed) then settings.SaveGroupPrioritySettings("rarities", priorityName) end

    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Types')
    if (ShowDetailedUI()) then
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Types)
    end
    config.types.exploration, changed = uiutils.add_setting_checkbox('Exploration', config.types.exploration)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.diplomacy, changed = uiutils.add_setting_checkbox('Diplomacy', config.types.diplomacy)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.trade, changed = uiutils.add_setting_checkbox('Trade', config.types.trade)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end

    config.types.plunder, changed = uiutils.add_setting_checkbox('Plunder', config.types.plunder)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.military, changed = uiutils.add_setting_checkbox('Military', config.types.military)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.stealth, changed = uiutils.add_setting_checkbox('Stealth', config.types.stealth)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end

    config.types.research, changed = uiutils.add_setting_checkbox('Research', config.types.research)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.crafting, changed = uiutils.add_setting_checkbox('Crafting', config.types.crafting)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end
    ImGui.SameLine()
    config.types.harvesting, changed = uiutils.add_setting_checkbox('Harvesting', config.types.harvesting)
    if (changed) then settings.SaveGroupPrioritySettings("types", priorityName) end

    ImGui.Text('')
    local setConfig = nil
    if ImGui.Button(icons.MD_FILTER_9) then
        Settings.QuestPriority.Types = settings.AllQuestTypes
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Any Type')
    ImGui.SameLine()
    if ImGui.Button(icons.FA_ARCHIVE) then setConfig = "collection" end
    uiutils.add_tooltip('Collections')
    ImGui.SameLine()
    if ImGui.Button(icons.MD_EXPLORE) then setConfig = "ornamentation" end
    uiutils.add_tooltip('Ornamentations')
    ImGui.SameLine()
    if ImGui.Button(icons.FA_DIAMOND) then setConfig = "tradeskill" end
    uiutils.add_tooltip('Tradeskills')

    if (setConfig ~= nil) then
        config.types.exploration = setConfig == "collection"
        config.types.diplomacy = setConfig == "collection"
        config.types.trade = setConfig == "collection"
        config.types.plunder = setConfig == "ornamentation"
        config.types.military = setConfig == "ornamentation"
        config.types.stealth = setConfig == "ornamentation"
        config.types.research = setConfig == "tradeskill"
        config.types.crafting = setConfig == "tradeskill"
        config.types.harvesting = setConfig == "tradeskill"
        settings.SaveGroupPrioritySettings("types", priorityName)
    end

    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Priorities')
    if (ShowDetailedUI()) then
        ImGui.SameLine()
        uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Priorities)
    end
    config.priorities.rarities, changed = uiutils.add_setting_checkbox('Rarities', config.priorities.rarities)
    if (changed) then settings.SaveGroupPrioritySettings("priorities", priorityName) end
    ImGui.SameLine()
    config.priorities.types, changed = uiutils.add_setting_checkbox('Types', config.priorities.types)
    if (changed) then settings.SaveGroupPrioritySettings("priorities", priorityName) end
    ImGui.SameLine()
    config.priorities.levels, changed = uiutils.add_setting_checkbox('Levels', config.priorities.levels)
    if (changed) then settings.SaveGroupPrioritySettings("priorities", priorityName) end
    config.priorities.durations, changed = uiutils.add_setting_checkbox('Durations', config.priorities.durations)
    if (changed) then settings.SaveGroupPrioritySettings("priorities", priorityName) end

    ImGui.SameLine()
end

local function render_settings_rewards_active_section()
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Select Reward Priorities')
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValueDetail, 'Active Rewards')
    ImGui.PushItemWidth(200)
    if ImGui.BeginListBox(' ') then
        for n, item in ipairs(Settings.Rewards) do
            local is_selected = n == active_item_current_idx
            local _, clicked = ImGui.Selectable(item, is_selected)
            if clicked then
                active_item_current_idx = n
            end

            if is_selected then
                ImGui.SetItemDefaultFocus()
            end
        end
        ImGui.EndListBox()
        uiutils.add_tooltip(
            'Indicates priority of rewards to select.  Higher on the list will be selected first, if available.')
    end
    if ImGui.Button(icons.FA_PLUS_CIRCLE) then
        settings.AddActiveReward(all_rewards[available_item_current_idx])
    end
    uiutils.add_tooltip('Moves currently selected available reward into active reward list.')
    ImGui.SameLine()
    if ImGui.Button(icons.FA_MINUS_CIRCLE) then
        settings.RemoveActiveReward(active_item_current_idx)
    end
    uiutils.add_tooltip('Moves currently selected active reward out of active reward list.')
    ImGui.SameLine()
    if ImGui.Button(icons.FA_HAND_O_UP) then
        active_item_current_idx = settings.ReorderRewardUp(active_item_current_idx)
    end
    uiutils.add_tooltip('Moves currently selected reward up in priority.')
    ImGui.SameLine()
    if ImGui.Button(icons.FA_HAND_O_DOWN) then
        active_item_current_idx = settings.ReorderRewardDown(active_item_current_idx)
    end
    uiutils.add_tooltip('Moves currently selected reward down in priority.')
    uiutils.text_colored(TextStyle.ItemLabelHint, 'Available Rewards')
    ImGui.PushItemWidth(200)
    if ImGui.BeginListBox('') then
        for n, item in ipairs(all_rewards) do
            local is_selected = n == available_item_current_idx
            local _, clicked = ImGui.Selectable(item, is_selected)
            if clicked then
                available_item_current_idx = n
            end

            if is_selected then
                ImGui.SetItemDefaultFocus()
            end
        end
        ImGui.EndListBox()
        uiutils.add_tooltip(
            'Lists available rewards. May be selected and moved up to active rewards. A reward may only be listed once.')
    end
end

local function GetAchievementQuestStatusDetails(actual_achievement)
    local status = settings.get_achievement_status(actual_achievement)
    if (status == 'done') then
        return 'Done', TextStyle.Green
    end

    if (status == 'partial') then
        return 'Partial', TextStyle.Error --ItemLabelHint
    end

    return 'Not Started', TextStyle.SubSectionTitle
end

local typedSpecifiedQuestName = ""
function RenderSettingsSpecificQuestSection()
    local changed
    if ImGui.BeginTabItem("Specific") then
        ImGui.Separator()
        Settings.General.ForceCompletedAchievementQuests, changed = uiutils.add_setting_checkbox(
        "Run Completed Achievements##ach_forcerun", Settings.General.ForceCompletedAchievementQuests,
            'Always run achievement quests, even if already completed.')
        if (changed) then
            settings.ForceRunCompletedAchievements_Changed()
            settings.SaveSettings()
        end
        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, 'Run Achievement Quests')
        ImGui.Separator()

        
        uiutils.text_colored(TextStyle.ItemValueDetail, 'Active Achievement Quests')

        local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)
if ImGui.BeginTable('##achievementQuests', 3, flags, 0, TEXT_BASE_HEIGHT, 0.0) then
    ImGui.TableSetupColumn('Run', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 0)
    ImGui.TableSetupColumn('Name', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 1)
    ImGui.TableSetupColumn('Status', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 1)

    for name, achievement_quest in pairs(Settings.AchievementQuests) do
        ImGui.TableNextRow()
        ImGui.TableNextColumn()

        achievement_quest.run, changed = uiutils.add_setting_checkbox("##ach_run" .. achievement_quest.id,
            achievement_quest.run, 'Run quests associated with this achievement.')
        if (changed) then settings.SaveSettings() end

        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.ItemValue, name)

        ImGui.TableNextColumn()
        local actual_achievement = mq.TLO.Achievement.Achievement(achievement_quest.id)
        local status, format = GetAchievementQuestStatusDetails(actual_achievement)
        uiutils.text_colored(format, status)
    end

    ImGui.EndTable()
end


        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValue, 'Run Specific Quest By Name')
        ImGui.Separator()
        uiutils.text_colored(TextStyle.ItemValueDetail, 'Active Specified Quests')
        ImGui.PushItemWidth(200)
        if ImGui.BeginListBox('  ') then
            if (Settings.SpecificQuests ~= nil) then
                for n, item in ipairs(Settings.SpecificQuests) do
                    local is_selected = n == active_item_current_idx
                    local _, clicked = ImGui.Selectable(item, is_selected)
                    if clicked then
                        active_item_current_idx = n
                    end

                    if is_selected then
                        ImGui.SetItemDefaultFocus()
                    end
                end
            end
            ImGui.EndListBox()
            uiutils.add_tooltip(
                'Indicates priority of specific quests to select.  Higher on the list will be selected first, if available.')
        end

        if ImGui.Button(icons.FA_PLUS_CIRCLE) then
            printf('A: %s', typedSpecifiedQuestName)
            settings.AddSpecifiedQuest(typedSpecifiedQuestName)
        end
        uiutils.add_tooltip('Moves currently specified name into active list list.')
        ImGui.SameLine()
        if ImGui.Button(icons.FA_MINUS_CIRCLE) then
            settings.RemoveSpecifiedQuest(active_item_current_idx)
        end
        uiutils.add_tooltip('Removes currently selected specific quest.')
        ImGui.SameLine()
        if ImGui.Button(icons.FA_HAND_O_UP) then
            active_item_current_idx = settings.ReorderSpecifiedQuestsUp(active_item_current_idx)
        end
        uiutils.add_tooltip('Moves currently selected item up in priority.')
        ImGui.SameLine()
        if ImGui.Button(icons.FA_HAND_O_DOWN) then
            active_item_current_idx = settings.ReorderSpecifiedQuestsDown(active_item_current_idx)
        end
        uiutils.add_tooltip('Moves currently selected item down in priority.')

        uiutils.text_colored(TextStyle.ItemLabelHint, 'E.g. Dark Deeds')

        ImGui.PushItemWidth(200)
        if (typedSpecifiedQuestName == nil) then typedSpecifiedQuestName = "" end
        local name, _ = ImGui.InputText('  ', typedSpecifiedQuestName)
        typedSpecifiedQuestName = name

        ImGui.EndTabItem()
    end
end

function RenderSettingsRewardsTab()
    if ImGui.BeginTabItem("Rewards") then
        render_settings_rewards_active_section()

        ImGui.EndTabItem()
    end
end

function RenderActionsTab()
    if ImGui.BeginTabItem("Actions") then
        uiutils.add_icon_action_button(icons.MD_BEENHERE, 'Claim Completed Missions', 'ClaimCompletedMissions',
            'Claims any completed missions')
        uiutils.add_icon_action_button(icons.MD_BEENHERE, 'Select Best Agents', 'SelectBestAgents',
            'Selects best agents for selected mission')
        uiutils.add_icon_action_button(icons.FA_USERS, 'Run Conversion Quests', 'RunConversions',
            'Runs all available conversion quests')
        uiutils.add_icon_action_button(icons.MD_ANDROID, 'Run Recruit Quests', 'RunRecruitQuests',
            'Runs any available recruit quests')
        uiutils.add_icon_action_button(icons.MD_BEENHERE, 'Claim Inventory Items', 'ClaimInventoryItems',
            'Initiates claiming of collection fragments, agent packs, tetra packs, and agent echos.')
        uiutils.add_icon_action_button(icons.MD_DIRECTIONS_RUN, 'Run General Quest Cycle', 'RunGeneralQuests',
            'Initiates a full general quest cycle')
        uiutils.add_icon_action_button(icons.MD_CACHED, 'Collect All Rewards', 'CollectAllRewards',
            'Collects all Overseer-related rewards')
        uiutils.add_icon_action_button(icons.FA_VIDEO_CAMERA, 'Preview General Quest Cycle', 'PreviewGeneralQuestList',
            'Calculates actual quests which would be run at this time. **No actual quests will be invoked.')

        if (CurrentProcessName ~= "Initialze") then
            if (InProcess and CurrentProcessName == ('Claiming completed missions' or 'Running conversion quests' or 'Running recruit quests' or 'Running general quests' or 'Generating quest preview list')) then
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.999, 0.999, 0.999, 1)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.690, 0.100, 0.100, 1)
                uiutils.add_button(icons.MD_PAN_TOOL, overseer.AbortCurrentProcess)
                ImGui.PopStyleColor(2)
            end
        end

        uiutils.add_icon_action_button(icons.MD_TRANSFER_WITHIN_A_STATION, 'Retire Elite Agents##retireElite2', 'RetireEliteAgents',
        'Retire Elite Agents')

        uiutils.add_icon_action_button(icons.MD_TRANSFER_WITHIN_A_STATION, 'Output Quest Details', 'DumpQuestDetails',
            'Dump quest details')

        ImGui.EndTabItem()
    end
end

local agent_show_type = 1

local function render_stats_agents_rarity(row)
    if (AgentStatisticCounts[row] == nil) then return end
    local rarityDisplay = AgentStatisticCounts[row][2]
    local rarity = string.lower(rarityDisplay)

    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.Text(string.format('%s', rarityDisplay))
    ImGui.TableNextColumn()
    if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
        local itemValue = AgentStatisticSpecificCounts[rarity].count
        ImGui.Text(itemValue)
    end
    ImGui.TableNextColumn()
    if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
        local itemValue = AgentStatisticSpecificCounts[rarity].countHave
        if (itemValue ~= nil) then
            ImGui.Text(itemValue)
        end
    end
    ImGui.TableNextColumn()
    if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
        local itemValue = AgentStatisticSpecificCounts[rarity].countDuplicates
        if (itemValue ~= nil) then
            ImGui.Text(itemValue)
        end
    end
end

local filterComboVisible = false

function RenderStatsTab()
    if ImGui.BeginTabItem("Stats") then
        if (CurrentProcessName ~= "Initialze") then
            if (InProcess) then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.999, 0.999, 0.999, 1)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.690, 0.100, 0.100, 1)
                uiutils.add_button('Cancel Agent Count', overseer.AbortCurrentProcess)
                ImGui.PopStyleColor(2)
            else
                uiutils.add_action_button('Collect Statistics', 'CountAgents', 'Build Stats on Agents Possessed')
                if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts['elite'] ~= nil) then
                    -- TODO: Elite Retire
                    ImGui.SameLine()
                    uiutils.add_action_button('Retire Elite Agents##retireElite2', 'RetireEliteAgents',
                        'Retire Elite Agents')
                end
            end
        end

        local column_types = {
            type = 0,
            available = 1,
            have = 2,
            duplicates = 3
        }

        local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)
        if ImGui.BeginTable('##table2', 4, flags, 0, TEXT_BASE_HEIGHT * 5, 0.0) then
            ImGui.TableSetupColumn('Type', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, column_types.type)
            ImGui.TableSetupColumn('Available', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, column_types.available)
            ImGui.TableSetupColumn('Have', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, column_types.have)
            ImGui.TableSetupColumn('Duplicates', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, column_types.duplicates)

            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Type')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Available')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Have')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Duplicates')

            for row = 4, 1, -1 do
                if (AgentStatisticCounts[row] ~= nil) then
                    ImGui.TableNextRow()
                    for col = 2, 5 do
                        ImGui.TableNextColumn()
                        local rarity = string.lower(AgentStatisticCounts[row][2])
                        if (col == 3) then
                            if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
                                local itemValue = AgentStatisticSpecificCounts[rarity].count
                                ImGui.Text(itemValue)
                            end
                        elseif (col == 4) then
                            if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
                                local itemValue = AgentStatisticSpecificCounts[rarity].countHave
                                if (itemValue ~= nil) then
                                    ImGui.Text(itemValue)
                                end
                            end
                        elseif (col == 5) then
                            if (AgentStatisticSpecificCounts ~= nil and AgentStatisticSpecificCounts[rarity] ~= nil) then
                                local itemValue = AgentStatisticSpecificCounts[rarity].countDuplicates
                                if (itemValue ~= nil) then
                                    ImGui.Text(itemValue)
                                end
                            end
                        else
                            ImGui.Text(string.format('%s', AgentStatisticCounts[row][col]))
                        end
                    end
                end
            end
            ImGui.EndTable()
        end

        ImGui.Text('')

        filterComboVisible = false

        RenderSpecificAgentCountSection('Elite', agent_show_type)
        RenderSpecificAgentCountSection('Rare', agent_show_type)
        RenderSpecificAgentCountSection('Uncommon', agent_show_type)
        RenderSpecificAgentCountSection('Common', agent_show_type)

        ImGui.EndTabItem()
    end
end

local function is_elite(rarity) return rarity == 'elite' end

function RenderSpecificAgentCountSection(name, showType)
    local rarity = string.lower(name)
    if (AgentStatisticSpecificCounts == nil or AgentStatisticSpecificCounts[rarity] == nil) then
        return
    end

    if (filterComboVisible == false) then
        ImGui.PushItemWidth(100)
        agent_show_type, _ = ImGui.Combo('Filter', agent_show_type, 'All\0Have\0Missing\0')
        filterComboVisible = true
    end

    local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)

    if ImGui.CollapsingHeader(string.format('%s Agents', name)) then
        if ImGui.BeginTable('##tableEliteAgentCounts', 5, flags, 0, TEXT_BASE_HEIGHT * 5, 0.0) then
            -- Declare columns
            ImGui.TableSetupColumn('Agent', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 0)
            ImGui.TableSetupColumn('Count', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 1)
            ImGui.TableSetupColumn('Source', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 3)
            ImGui.TableSetupColumn('Retire', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 2)
            ImGui.TableSetupColumn('Padding', bit32.bor(ImGuiTableColumnFlags.NoSort), -1.0, 4)

            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Agent')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Count')
            ImGui.TableNextColumn()

            -- TODO: Elite Retire
            if (is_elite(rarity)) then
                uiutils.text_colored(TextStyle.TableColHeader, 'Retire')
            else
                ImGui.Text('                 ')
            end

            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Source')
            ImGui.TableNextColumn()

            for item, value in pairs(AgentStatisticSpecificCounts[rarity].agents) do
                if (showType == nil or showType == 1 or (showType == 2 and value.count > 0) or (showType == 3 and value.count <= 0)) then
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text(item)
                    ImGui.TableNextColumn()

                    if (is_elite(rarity) and Settings.General.agentCountForConversionElite ~= nil and value.count > Settings.General.agentCountForConversionElite) then
                        ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.8, 0.2, 1)
                        ImGui.Text(value.count)
                        ImGui.PopStyleColor(1)
                    else
                        ImGui.Text(value.count)
                    end

                    ImGui.TableNextColumn()

                    -- TODO: Elite Retire
                    if (is_elite(rarity) and value.count > 1) then
                        uiutils.add_action_button(string.format('Retire##retire%s', item), 'RetireEliteAgent',
                            'Retire Elite Agent', item)
                    else
                        ImGui.Text('                 ')
                    end

                    ImGui.TableNextColumn()
                    if (value.source ~= nil) then
                        ImGui.Text(value.source)
                    end
                    ImGui.TableNextColumn()
                end
            end
            ImGui.EndTable()
        end
    end
end



function RenderTestTab()
    if not ImGui.BeginTabItem("Test") then return end

    -- Timing controls
    local function HandleInputInt(label, current, min, max, callback)
        local value, changed = ImGui.InputInt(label, current, min, max, ImGuiInputTextFlags.EnterReturnsTrue)
        if changed then
            print(label..": "..value)
            callback(value)
        end
    end

    HandleInputInt("Min Til Next Quest", MinutesUntilNextQuest, 1, 120, function(v)
        MinutesUntilNextQuest = v
        overseer.PostProcessNextRunTimes()
    end)

    HandleInputInt("Sec Til Next Rotation", SecondsUntilNextRotation, 1, 120, overseer.SetQuestRotationTimeSeconds)

    -- Character controls
    HandleInputInt("Char Level", mqFacade.GetCharLevel(), 1, 120, mqFacade.SetCharLevel)

    local name, changed = ImGui.InputText("Char Name", mqFacade.GetCharNameAndClass(), ImGuiInputTextFlags.EnterReturnsTrue)
    if changed then
        print("Name: "..name)
        mqFacade.SetCharName(name)
    end

    -- State selection dropdowns
    local function RenderCombo(label, current, items, setter)
        if not ImGui.BeginCombo(label, current) then return end
        for k, v in pairs(items) do
            if ImGui.Selectable(v, v == current) then
                setter(v)
            end
        end
        ImGui.EndCombo()
    end

    RenderCombo("Game State", mqFacade.GetGameState(), game_states, mqFacade.SetGameState)
    RenderCombo("Subscription Level", mqFacade.GetSubscriptionLevel(), subscription_levels, mqFacade.SetSubscriptionLevel)

    -- Buttons section
    ImGui.Separator()
    if ImGui.Button('Run Unit Tests') then tests.RunTests() end
    if ImGui.Button('Sample Log Output') then logger.output_test_logs() end

    -- Database settings
    ImGui.Separator()
    uiutils.text_colored(TextStyle.SubSectionTitleCallout, "Database")

    local function HandleSettingCheckbox(label, value, tooltip)
        local changed
        value, changed = uiutils.add_setting_checkbox(label, value, tooltip)
        if changed then settings.SaveSettings() end
        return value
    end

    Settings.General.useQuestDatabase = HandleSettingCheckbox(
        'Load known quests from database.',
        Settings.General.useQuestDatabase,
        'If selected, quests will be loaded from database rather than parsing from the overseer UI.\n\nCommand: useDatabase'
    )

    Settings.Debug.processFullQuestRewardData = HandleSettingCheckbox(
        "Add Quests to Database",
        Settings.Debug.processFullQuestRewardData,
        'Adds new quests to the local database.\n\nCommand: addToDatabase'
    )

    Settings.Debug.validateQuestRewardData = HandleSettingCheckbox(
        "Validate Quest Reward Data",
        Settings.Debug.validateQuestRewardData,
        'Validates current quest exp matches stored exp.\n\nCommand: addToDatabase\n\nNOTE: Full System Walk (Takes a while)\nErrors are only logged to output window.'
    )

    ImGui.EndTabItem()
end

return actions