--- @type Mq
local mq = require('mq')
local settings = require ('overseer.overseer_settings')

local mqfacade = {}

local function GetEqNameAndClassCode()
    return string.format("%s (%s)", mq.TLO.Me.Name(), mq.TLO.Me.Class.ShortName())
end

GameState = mq.TLO.MacroQuest.GameState()
CharacterName = GetEqNameAndClassCode()
CharacterLevel = mq.TLO.Me.Level()
SubscriptionLevel = mq.TLO.Me.Subscription()

function mqfacade.GetGameState()
    if (settings.InTestMode) then return GameState end
    return mq.TLO.MacroQuest.GameState()
end

function mqfacade.SetGameState(name)
    printf('Setting Game State: %s', name)
    if (settings.InTestMode == false) then print('-- NOT in test mode') return end
    GameState = name
end

function mqfacade.GetCharNameAndClass()
    if (settings.InTestMode) then return CharacterName end
    return GetEqNameAndClassCode()
end

function mqfacade.SetCharName(name)
    if (settings.InTestMode == false) then print('-- NOT in test mode') return end
    printf('Setting Char Name: %s', name)
    CharacterName = name
end

function mqfacade.GetSubscriptionLevel()
    if (settings.InTestMode) then return SubscriptionLevel end
    return mq.TLO.Me.Subscription()
end

function mqfacade.SetSubscriptionLevel(level)
    if (settings.InTestMode == false) then print('-- NOT in test mode') return end
    SubscriptionLevel = level
end

function mqfacade.GetCharLevel()
    if (settings.InTestMode) then return CharacterLevel end
    return mq.TLO.Me.Level()
end

function mqfacade.SetCharLevel(level)
    if (settings.InTestMode == false) then print('-- NOT in test mode') return end
    CharacterLevel = level
end

return mqfacade