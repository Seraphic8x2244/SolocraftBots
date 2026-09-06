-- SoloCraft Bots - narrow presentation-only filter for SoloCraft bot spam.
-- The underlying CHAT_MSG_SYSTEM events still fire; only selected lines
-- are suppressed when a chat frame attempts to display them.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local function SCB_ShouldHideBotChatMessage(text)
    local options
    if not text or text == "" then return false end
    SCB_EnsureOptionsDB()
    options = SoloCraftBotsDB.options

    if options.hideBotSummonMessage and text == "New party bot added." then
        return true
    end

    if options.hideBotGroupMessages then
        -- SoloCraft bot names are suffixed with '*'. Anchor the whole
        -- rendered line so ordinary player chat containing these words
        -- is not mistaken for a system membership message.
        if string.find(text, "^[^%s]+%* joins the party%.$") then return true end
        if string.find(text, "^[^%s]+%* leaves the party%.$") then return true end

        -- Vanilla raid membership wording. These remain bot-only by
        -- requiring the SoloCraft '*' suffix and the complete line.
        if string.find(text, "^[^%s]+%* has joined the raid group%.?$") then return true end
        if string.find(text, "^[^%s]+%* has left the raid group%.?$") then return true end
    end

    if options.hideBotMovementMessages then
        -- SoloCraft uses "All bots" for plural command responses and
        -- Botname* for a single targeted bot.
        local botLine = string.find(text, "^All bots ") or string.find(text, "^[^%s]+%* ")
        if botLine then
            if string.find(text, "are coming to your position%.$") or string.find(text, "is coming to your position%.$") then return true end
            if string.find(text, "are moving%.$") or string.find(text, "is moving%.$") then return true end
            if string.find(text, "are now staying%.$") or string.find(text, "is now staying%.$") then return true end
        end
    end

    if options.hideBotPauseMessages then
        -- Keep the same plural/singular identity rule as movement responses.
        local botLine = string.find(text, "^All bots ") or string.find(text, "^[^%s]+%* ")
        if botLine then
            if string.find(text, "paused for 30 seconds%.$") then return true end
            if string.find(text, "unpaused%.$") then return true end
        end
    end

    if options.hideBotAttackMessages then
        if string.find(text, "^All bots are not attacking%.?$") then return true end
        if string.find(text, "^All bots have stopped attacking%.?$") then return true end
        if string.find(text, "^All bots are casting AoE spells at") then return true end
    end

    return false
end

local function SCB_FilteredChatFrameAddMessage(frame, text, r, g, b, id)
    if SCB_ShouldHideBotChatMessage(text) then return end
    if frame and frame.scbBotChatOriginalAddMessage then
        return frame.scbBotChatOriginalAddMessage(frame, text, r, g, b, id)
    end
end

function SCB_InstallBotChatFilter()
    local i, count, frame
    if SCB.botChatFilterInstalled then return end
    count = NUM_CHAT_WINDOWS or 7
    for i = 1, count do
        frame = getglobal and getglobal("ChatFrame" .. i) or nil
        if frame and frame.AddMessage and not frame.scbBotChatOriginalAddMessage then
            frame.scbBotChatOriginalAddMessage = frame.AddMessage
            frame.AddMessage = SCB_FilteredChatFrameAddMessage
        end
    end
    SCB.botChatFilterInstalled = true
end
