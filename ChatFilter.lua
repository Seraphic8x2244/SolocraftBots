-- SoloCraft Bots - narrow presentation-only filter for SoloCraft bot spam.
-- The underlying CHAT_MSG_SYSTEM events still fire; only selected lines
-- are suppressed when a chat frame attempts to display them.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

-- These strings describe SoloCraft server output, not SCB display text.
-- Keep them here rather than in Locale: translating them would break matching.
local SCB_MOVEMENT_ROLE_PREFIXES = {
    "Tanks ",
    "Melee DPS ",
    "Range DPS ",
    "Ranged DPS ",
    "Healers ",
}

local SCB_MISSING_ROLE_NAMES = {
    "tanks",
    "melee dps",
    "range dps",
    "ranged dps",
    "healers",
    -- Observed SoloCraft typo. Match the server exactly as emitted.
    "range dos bits",
}

local function SCB_StartsWith(text, prefix)
    return string.sub(text or "", 1, string.len(prefix)) == prefix
end

local function SCB_IsMovementActorLine(text)
    local i
    if SCB_StartsWith(text, "All party bots ") or SCB_StartsWith(text, "All bots ") then
        return true
    end
    if string.find(text, "^[^%s]+%* ") then
        return true
    end
    for i = 1, table.getn(SCB_MOVEMENT_ROLE_PREFIXES) do
        if SCB_StartsWith(text, SCB_MOVEMENT_ROLE_PREFIXES[i]) then
            return true
        end
    end
    return false
end

local function SCB_IsMovementFailure(text)
    local lower = string.lower(text or "")
    local i, prefix

    for i = 1, table.getn(SCB_MISSING_ROLE_NAMES) do
        prefix = "there are no " .. SCB_MISSING_ROLE_NAMES[i] .. " in the group"
        if lower == prefix .. "." then return true end
        if lower == prefix .. " or they cannot move." then return true end
        if lower == prefix .. " or they cannot stay." then return true end
        if lower == prefix .. " or they cannot come." then return true end
    end

    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot move%.$") then return true end
    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot stay%.$") then return true end
    if string.find(lower, "^[^%s]+%* is not a party bot or it cannot come%.$") then return true end

    return false
end

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
        if SCB_IsMovementFailure(text) then return true end
        if SCB_IsMovementActorLine(text) then
            if string.find(text, "are coming to your position%.$") or string.find(text, "is coming to your position%.$") then return true end
            if string.find(text, "are now moving%.$") or string.find(text, "are moving%.$") then return true end
            if string.find(text, "is now moving%.$") or string.find(text, "is moving%.$") then return true end
            if string.find(text, "are now staying%.$") or string.find(text, "are staying%.$") then return true end
            if string.find(text, "is now staying%.$") or string.find(text, "is staying%.$") then return true end
        end
    end

    if options.hideBotPauseMessages then
        local botLine = SCB_StartsWith(text, "All party bots ")
            or SCB_StartsWith(text, "All bots ")
            or string.find(text, "^[^%s]+%* ")
        if botLine then
            if string.find(text, "paused for 30 seconds%.$") then return true end
            if string.find(text, "unpaused%.$") then return true end
        end
    end

    if options.hideBotAttackMessages then
        -- Attack responses include the target name, so match the fixed server
        -- prefix rather than incorrectly requiring the sentence to end there.
        if SCB_StartsWith(text, "All party bots are now attacking ") then return true end
        if SCB_StartsWith(text, "All party bots have stopped attacking ") then return true end
        if SCB_StartsWith(text, "All party bots are casting AoE spells at") then return true end

        -- Retain the shorter wording seen on some SoloCraft responses/builds.
        if SCB_StartsWith(text, "All bots are attacking ") or text == "All bots are attacking." then return true end
        if SCB_StartsWith(text, "All bots have stopped attacking ") or text == "All bots have stopped attacking." then return true end
        if SCB_StartsWith(text, "All bots are casting AoE spells at") then return true end
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
