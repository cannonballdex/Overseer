local overseer = require('overseer')

local actions = {}

TextStyle = {
    Error = "Error",
    ItemValue = "ItemValue",
    SubSectionTitle = "SubSectionTitle",
    SubSectionTitleCallout = "SubSectionTitleCallout",
    ProcessName = "ProcessName",
    ItemValueDetail = "ItemValueDetail",
    ItemLabelHint = "ItemLabelHint",
    TableColHeader = "TableColHeader",
    ImportantLabel = "ImportantLabel",
    Green = "Green",
    Yellow = "Yellow",
}

function actions.text_colored(style, text)
    if (style == TextStyle.ItemValue) then
        ImGui.TextColored(0, 0.5, 1, 1, text)
    elseif (style == TextStyle.ImportantLabel) then
        ImGui.TextColored(0.88, 0.223, 0.259, 1, text)
    elseif (style == TextStyle.TableColHeader) then
        ImGui.TextColored(0.690, 0.553, 0.259, 1, text)
    elseif (style == TextStyle.SubSectionTitle) then
        ImGui.TextColored(0, 0.5, 1, 1, text)
    elseif (style == TextStyle.SubSectionTitleCallout) then
        ImGui.TextColored(1, 0.5, 1, 1, text)
    elseif (style == TextStyle.ProcessName) then
        ImGui.TextColored(0.100, 0.775, 0.100, 1,text)
    elseif (style == TextStyle.ItemValueDetail) then
        ImGui.TextColored(1, .65, 0, 1,text)
    elseif (style == TextStyle.ItemLabelHint) then
        ImGui.TextColored(0.54, 0.63, 0.68, 1,text)
    elseif (style == TextStyle.Error) then
        ImGui.TextColored(0.999, 0.10, 0.10, 1,text)
    elseif (style == TextStyle.Green) then
        ImGui.TextColored(0.000, 1.00, 0.00, 1,text)
    elseif (style == TextStyle.Yellow) then
        ImGui.TextColored(1.000, 1.00, 0.00, 1,text)
    else
        ImGui.Text(text)
    end
end

function actions.add_button(verbiage, action, tooltip)
    if ImGui.Button(verbiage) then action() end
    if (tooltip ~= nil) then
        actions.add_tooltip(tooltip)
    end
end

function actions.add_action_button(verbiage, actionName, tooltip, actionParameter)
    if ImGui.Button(verbiage) then overseer.SetAction(actionName, actionParameter)
    end
    if (tooltip ~= nil) then
        actions.add_tooltip(tooltip)
    end
end

function actions.add_icon_action_button(icon, verbiage, actionName, tooltip, actionParameter)
    local display = string.format('%s %s', icon, verbiage)
    if ImGui.Button(display) then overseer.SetAction(actionName, actionParameter)
    end
    if (tooltip ~= nil) then
        actions.add_tooltip(tooltip)
    end
end

function actions.add_tooltip(verbiage)
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(verbiage)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

function actions.add_setting_checkbox(verbiage, initialValue, tooltip)
    local response, changed = ImGui.Checkbox(verbiage, initialValue)
    if (tooltip ~= nil) then
        actions.add_tooltip(tooltip)
    end
    return response, changed
end

actions.draw_combo_box = function(label, initialVal, options, bykey)
    local selectedVal
    if ImGui.BeginCombo(label, initialVal) then
        for i,j in pairs(options) do
            if bykey then
                if ImGui.Selectable(i, i == initialVal) then
                    selectedVal = i
                end
            else
                if ImGui.Selectable(j, j == initialVal) then
                    selectedVal = j
                end
            end
        end
        ImGui.EndCombo()
    end
    return selectedVal
end



return actions