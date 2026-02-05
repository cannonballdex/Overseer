require 'ImGui'
local settings = require('overseer_settings')
local uiutils = require('overseer_ui_utils')
local icons = require('mq.Icons')

local actions = {}

local SetTimePriority = ''
local SetLevelPriority = ''
local SetTypePriority = ''
local SetRarityPriority = ''
local SetQuestPriority = ''

local function ShowDetailedUI()
    return Settings.Display ~= nil and Settings.Display.showDetailed == true
end

function actions.RenderSettingsRewardsCustomSection()
    uiutils.text_colored(TextStyle.ItemValue, 'Durations')
    ImGui.SameLine()
    uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Durations)
    if (ShowDetailedUI()) then
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Opt. 12h|6h|36h|24h or 6h|12h')
    ImGui.SetCursorPosX(5)
    ImGui.PushItemWidth(100)
    end
    SetTimePriority, _ = ImGui.InputText('##SetTimePriority', SetTimePriority)
    ImGui.SameLine()
    if ImGui.Button(string.format('Durations  %s', icons.MD_INPUT)) then
        Settings.QuestPriority.Durations = SetTimePriority
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Set Current Durations')
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Levels')
    ImGui.SameLine()
    uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Levels)
    if (ShowDetailedUI()) then
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Opt. 3|2|1|4|5')
    ImGui.SetCursorPosX(5)
    ImGui.PushItemWidth(100)
    end
    SetLevelPriority,_ = ImGui.InputText('##SetLevelPriority', SetLevelPriority)
    ImGui.SameLine()
    if ImGui.Button(string.format('Levels  %s', icons.MD_INPUT)) then
        Settings.QuestPriority.Levels = SetLevelPriority
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Set Current Levels')
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Rarities')
    ImGui.SameLine()
    uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Rarities)
    if (ShowDetailedUI()) then
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Opt. Uncommon|Rare|Easy|Elite')
    ImGui.SetCursorPosX(5)
    ImGui.PushItemWidth(200)
    end
    SetRarityPriority,_ = ImGui.InputText('##SetRarityPriority', SetRarityPriority)
    ImGui.SameLine()
    if ImGui.Button(string.format('Rarities  %s', icons.MD_INPUT)) then
        Settings.QuestPriority.Rarities = SetRarityPriority
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Set Current Rarities')
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Types')
    ImGui.SameLine()
    -- Wrap at current cursor local X + 280 (window-local coordinate)
    local wrap_x = ImGui.GetCursorPosX() + 280
    ImGui.PushTextWrapPos(wrap_x)
    uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Types)
    ImGui.PopTextWrapPos()
    if (ShowDetailedUI()) then
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Opt. Exploration|Diplomacy|Trade|Plunder')
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Military|Stealth|Research|Crafting|Harvesting')
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'or Any')
    ImGui.SetCursorPosX(5)
    ImGui.PushItemWidth(200)
    end
    SetQuestPriority,_ = ImGui.InputText('##SetQuestPriority', SetQuestPriority)
    ImGui.SameLine()
    if ImGui.Button(string.format('Types  %s', icons.MD_INPUT)) then
        Settings.QuestPriority.Types = SetQuestPriority
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Set Current Types')
    ImGui.Separator()
    uiutils.text_colored(TextStyle.ItemValue, 'Priorities')
    ImGui.SameLine()
    uiutils.text_colored(TextStyle.ItemValueDetail, Settings.QuestPriority.Priorities)
    if (ShowDetailedUI()) then
    ImGui.TextColored(0.54, 0.63, 0.68, 1.00,'Opt. Rarities|Types|Levels|Durations')
    ImGui.SetCursorPosX(5)
    ImGui.PushItemWidth(200)
    end
    SetTypePriority,_ = ImGui.InputText('##SetTypePriority', SetTypePriority)
    ImGui.SameLine()
    if ImGui.Button(string.format('Priorities  %s', icons.MD_INPUT)) then
        Settings.QuestPriority.Priorities = SetTypePriority
        settings.save_custom_quest_settings()
    end
    uiutils.add_tooltip('Set Current Priorities')
end

return actions