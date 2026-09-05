-- SoloCraft Bots - Direct commands and raid marks
-- Loaded after SoloCraftBots.lua; intentionally behavior-preserving.

local SCB = SoloCraftBots

-- -------------------------------------------------------------------------
-- Direct command matrix
-- -------------------------------------------------------------------------

SCB.recipients = {
    { key = "all", label = "All", icon = "all.tga", highlightIcon = "all_h.tga" },
    { key = "target", label = "Target", icon = "one.tga", highlightIcon = "one_h.tga" },
    { key = "tank", label = "Tanks", icon = "tank.tga", highlightIcon = "tank_h.tga" },
    { key = "melee", label = "Melee", icon = "melee.tga", highlightIcon = "melee_h.tga" },
    { key = "ranged", label = "Ranged", icon = "ranged.tga", highlightIcon = "ranged_h.tga" },
    { key = "healer", label = "Healers", icon = "healer.tga", highlightIcon = "healer_h.tga" },
}

SCB.commandOrder = {
    "play", "move", "stay", "pause",
    "pull", "spread", "hug", "object", "aoe", "attackstart", "attackstop",
}

SCB.commands = {
    play = {
        label = "Play",
        icon = "unpause.tga",
        highlightIcon = "unpause_h.tga",
        routes = {
            all = { "unpause all" },
            target = { "unpause" },
        },
    },
    move = {
        label = "Move",
        icon = "move.tga",
        highlightIcon = "move_h.tga",
        routes = {
            all = { "moveall" },
            target = { "move" },
            tank = { "movetank" },
            healer = { "moveheal" },
            melee = { "movemelee" },
            ranged = { "moverange" },
            tankmelee = { "movetank", "movemelee" },
            meleeranged = { "movemelee", "moverange" },
            rangedhealer = { "moverange", "moveheal" },
        },
    },
    come = {
        label = "Come",
        icon = "come.tga",
        highlightIcon = "come_h.tga",
        routes = {
            all = { "cometome" },
            target = { "come" },
            tank = { "cometank" },
            healer = { "comeheal" },
            melee = { "comemelee" },
            ranged = { "comerange" },
            tankmelee = { "cometank", "comemelee" },
            meleeranged = { "comemelee", "comerange" },
            rangedhealer = { "comerange", "comeheal" },
        },
    },
    stay = {
        label = "Stay",
        icon = "stay.tga",
        highlightIcon = "stay_h.tga",
        routes = {
            all = { "stayall" },
            target = { "stay" },
            tank = { "staytank" },
            healer = { "stayheal" },
            melee = { "staymelee" },
            ranged = { "stayrange" },
        },
    },
    pause = {
        label = "Pause",
        icon = "pause.tga",
        highlightIcon = "pause_h.tga",
        routes = {
            all = { "pause all" },
            target = { "pause" },
        },
    },
    pull = {
        label = "Pull",
        icon = "pull.tga",
        highlightIcon = "pull_h.tga",
        routes = { tank = { "pull" } },
    },
    spread = {
        label = "Spread",
        icon = "spread.tga",
        highlightIcon = "spread_h.tga",
        routes = { ranged = { "spread" } },
    },
    hug = {
        label = "Hug",
        icon = "unspread.tga",
        highlightIcon = "unspread_h.tga",
        routes = { ranged = { "spreadoff" } },
    },
    spreadtoggle = {
        label = "Spread",
        icon = "spread.tga",
        highlightIcon = "spread_h.tga",
        routes = { ranged = { "spread" } },
    },
    object = {
        label = "Object",
        icon = "object.tga",
        highlightIcon = "object_h.tga",
        routes = { all = { "usegobject" } },
    },
    aoe = {
        label = "AoE",
        icon = "aoe.tga",
        highlightIcon = "aoe_h.tga",
        routes = { all = { "aoe" } },
    },
    attackstart = {
        label = "Attack Start",
        icon = "attackstart.tga",
        highlightIcon = "attackstart_h.tga",
        routes = { all = { "attackstart" } },
    },
    attackstop = {
        label = "Attack Stop",
        icon = "attackstop.tga",
        highlightIcon = "attackstop_h.tga",
        routes = { all = { "attackstop" } },
    },
}

function SCB_IsFriendlyBotTarget()
    local name
    if not UnitExists or not UnitExists("target") then
        return false
    end
    if UnitIsFriend and UnitIsFriend("player", "target") ~= 1 then
        return false
    end
    name = UnitName and UnitName("target")
    if not name or string.sub(name, -1) ~= "*" then
        return false
    end
    return true
end

function SCB_InvalidTargetFlashOnUpdate()
    this.scbInvalidElapsed = (this.scbInvalidElapsed or 0) + arg1
    if this.scbInvalidElapsed >= 0.28 then
        this:SetScript("OnUpdate", nil)
        this.scbInvalidElapsed = nil
        if this.icon then this.icon:SetVertexColor(1, 1, 1) end
        return
    end
    if this.icon then
        local fade = this.scbInvalidElapsed / 0.28
        this.icon:SetVertexColor(1, 0.20 + (0.80 * fade), 0.20 + (0.80 * fade))
    end
end

function SCB_FlashInvalidTarget(button)
    if not button or not button.icon then return end
    button.scbInvalidElapsed = 0
    button.icon:SetVertexColor(1, 0.20, 0.20)
    button:SetScript("OnUpdate", SCB_InvalidTargetFlashOnUpdate)
end

function SCB_RefreshSpreadToggle(button)
    if not button then return end
    if SCB.rangedSpreadOn then
        SCB_SetArtButtonTexture(button, SCB.assetRoot .. "unspread.tga", SCB.assetRoot .. "unspread_h.tga")
        button.scbTooltip = "Ranged - Spread Off"
    else
        SCB_SetArtButtonTexture(button, SCB.assetRoot .. "spread.tga", SCB.assetRoot .. "spread_h.tga")
        button.scbTooltip = "Ranged - Spread"
    end
    SCB_RefreshVisibleTooltip(button)
end

function SCB_SpreadToggleOnClick()
    if SCB.rangedSpreadOn then
        SCB_SendCommand("spreadoff")
        SCB.rangedSpreadOn = false
    else
        SCB_SendCommand("spread")
        SCB.rangedSpreadOn = true
    end
    SCB_RefreshSpreadToggle(this)
end

function SCB_DirectCommandOnClick()
    local commandInfo = SCB.commands[this.scbCommandKey]
    local route
    local moveRoute
    local i

    if not commandInfo then
        return
    end

    -- SoloCraft target commands fall back to ALL when no valid bot target exists.
    -- Protect the ONE row from accidentally commanding the entire bot group.
    if this.scbRecipientKey == "target" and not SCB_IsFriendlyBotTarget() then
        SCB_FlashInvalidTarget(this)
        return
    end

    route = commandInfo.routes[this.scbRecipientKey]
    if not route then
        SCB_Print(commandInfo.label .. " is not available for " .. this.scbRecipientLabel .. ".")
        return
    end

    -- Ctrl-click Come replaces the old ForceMove button: issue Move first to
    -- clear Stay, then immediately issue the matching Come command.
    if this.scbCommandKey == "come" and IsControlKeyDown and IsControlKeyDown() then
        moveRoute = SCB.commands.move.routes[this.scbRecipientKey]
        if moveRoute then
            for i = 1, table.getn(moveRoute) do
                SCB_SendCommand(moveRoute[i])
            end
        end
    end

    for i = 1, table.getn(route) do
        SCB_SendCommand(route[i])
    end
end

-- -------------------------------------------------------------------------
-- Raidmarks
-- -------------------------------------------------------------------------

SCB.raidMarks = {
    { key = "skull", name = "Skull" },
    { key = "cross", name = "Cross" },
    { key = "square", name = "Square" },
    { key = "moon", name = "Moon" },
    { key = "triangle", name = "Triangle" },
    { key = "diamond", name = "Diamond" },
    { key = "circle", name = "Circle" },
    { key = "star", name = "Star" },
}

function SCB_RefreshRaidmarkModeButton()
    if not SCB.assignmentModeButton then
        return
    end
    if SCB.raidMarkMode == "cc" then
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "cc_h.tga", nil)
        SCB.assignmentModeButton.scbTooltip = "CC assignments\nClick to switch to Focus assignments"
    else
        SCB.raidMarkMode = "focus"
        SCB_SetArtButtonTexture(SCB.assignmentModeButton, SCB.assetRoot .. "focus_h.tga", nil)
        SCB.assignmentModeButton.scbTooltip = "Focus assignments\nClick to switch to CC assignments"
    end
    SCB_RefreshVisibleTooltip(SCB.assignmentModeButton)
end

function SCB_RaidmarkModeOnClick()
    if SCB.raidMarkMode == "focus" then
        SCB.raidMarkMode = "cc"
    else
        SCB.raidMarkMode = "focus"
    end
    SCB_RefreshRaidmarkModeButton()
end

function SCB_RaidMarkOnClick()
    if not this.scbMark or not SCB.raidMarkMode then
        return
    end
    SCB_SendCommand(SCB.raidMarkMode .. "mark " .. this.scbMark)
end
