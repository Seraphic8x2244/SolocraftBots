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

-- -------------------------------------------------------------------------
-- Safe bot removal
-- -------------------------------------------------------------------------

SCB.raidZoneLocaleKeys = {
    "GROUP_ZG", "GROUP_AQ20", "GROUP_MC", "GROUP_ONYXIA",
    "GROUP_BWL", "GROUP_AQ40", "GROUP_NAXX",
}

function SCB_IsKnownRaidZone(zoneName)
    local i, key
    if not zoneName or zoneName == "" then return false end
    for i = 1, table.getn(SCB.raidZoneLocaleKeys) do
        key = SCB.raidZoneLocaleKeys[i]
        if zoneName == SCB_L(key) then return true end
    end
    return false
end

function SCB_GetSavedRaidDecision()
    local zoneName, count, i, savedName, savedID, reset, sawNamedMatch
    zoneName = (GetRealZoneText and GetRealZoneText()) or ""

    if not GetRealZoneText or not GetNumSavedInstances or not GetSavedInstanceInfo then
        return false, "api", zoneName, nil, nil, 0
    end
    if not SCB_IsKnownRaidZone(zoneName) then
        return false, "notraid", zoneName, nil, nil, 0
    end

    count = GetNumSavedInstances() or 0
    for i = 1, count do
        savedName, savedID, reset = GetSavedInstanceInfo(i)
        if savedName == zoneName then
            sawNamedMatch = true
            if savedID and savedID ~= 0 and reset and reset > 0 then
                return true, "matched", zoneName, savedID, reset, count
            end
        end
    end

    if sawNamedMatch then
        return false, "invalid", zoneName, nil, nil, count
    end
    return false, "nomatch", zoneName, nil, nil, count
end

function SCB_CurrentRaidHasSavedID()
    local matched = SCB_GetSavedRaidDecision()
    return matched
end

function SCB_SurvivorSafetyRequired()
    local matched, reason, zoneName, savedID, reset, count = SCB_GetSavedRaidDecision()
    local zoneText = (zoneName and zoneName ~= "") and zoneName or "?"

    -- Keep the debug laboratory explicit about why survivor safety was or was
    -- not applied. This is diagnostic only; the policy itself remains
    -- conservative for dungeons, unknown zones, and failed/invalid ID reads.
    if SCB_DebugLog then
        if matched then
            SCB_DebugLog("RAID ID", string.format(SCB_L("DEBUG_RAID_ID_MATCH"), zoneText, tostring(savedID), tostring(reset)))
        elseif reason == "api" then
            SCB_DebugLog("RAID ID", string.format(SCB_L("DEBUG_RAID_ID_API"), zoneText))
        elseif reason == "notraid" then
            SCB_DebugLog("RAID ID", string.format(SCB_L("DEBUG_RAID_ID_NOT_RAID"), zoneText))
        elseif reason == "invalid" then
            SCB_DebugLog("RAID ID", string.format(SCB_L("DEBUG_RAID_ID_INVALID"), zoneText, count or 0))
        else
            SCB_DebugLog("RAID ID", string.format(SCB_L("DEBUG_RAID_ID_NO_MATCH"), zoneText, count or 0))
        end
    end

    return not matched
end

function SCB_FindGroupOneSurvivor(members)
    local i, fallback
    for i = 1, table.getn(members or {}) do
        if members[i].isBot then
            if not fallback then fallback = members[i].name end
            if members[i].subgroup == 1 then
                return members[i].name
            end
        end
    end
    return fallback
end

function SCB_SafetyMessageOnUpdate()
    local frame = this
    frame.scbElapsed = (frame.scbElapsed or 0) + arg1
    if frame.scbElapsed >= 2.4 then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        return
    end
    local pulse = 0.82 + (0.18 * math.abs(math.sin(frame.scbElapsed * math.pi * 2)))
    local fade = 1
    if frame.scbElapsed > 1.8 then
        fade = 1 - ((frame.scbElapsed - 1.8) / 0.6)
    end
    frame:SetAlpha(pulse * fade)
end

function SCB_ShowSafetyMessage()
    SCB_EnsureOptionsDB()
    if not SoloCraftBotsDB.options.showSafetyMessages then return end
    if not SCB.safetyMessageFrame then return end
    SCB.safetyMessageFrame.scbElapsed = 0
    SCB.safetyMessageFrame:SetAlpha(1)
    SCB.safetyMessageFrame:Show()
    SCB.safetyMessageFrame:SetScript("OnUpdate", SCB_SafetyMessageOnUpdate)
end

function SCB_KickBots(deadOnly)
    local members = SCB_CollectGroupMembers()
    local bots, candidates = {}, {}
    local otherHumans = 0
    local i, member, survivorName, removed, safetyApplied

    if not UninviteByName then
        SCB_Print("Native group removal is unavailable on this client.")
        return
    end

    for i = 1, table.getn(members) do
        member = members[i]
        if member.isBot then
            table.insert(bots, member)
            if not deadOnly or member.dead then
                table.insert(candidates, member)
            end
        elseif not member.isSelf then
            otherHumans = otherHumans + 1
        end
    end

    if table.getn(bots) == 0 then
        SCB_Print("No bots to kick.")
        return
    end
    if deadOnly and table.getn(candidates) == 0 then
        SCB_Print("No dead bots to kick.")
        return
    end

    -- When survivor safety is required, deliberately preserve a Group 1 bot.
    -- In a party every bot is Group 1; in a raid this prevents a random bot in
    -- a later subgroup from becoming the survivor.
    if otherHumans == 0 and SCB_SurvivorSafetyRequired() then
        survivorName = SCB_FindGroupOneSurvivor(members)
    end

    removed = 0
    safetyApplied = false
    for i = 1, table.getn(candidates) do
        if survivorName and candidates[i].name == survivorName then
            safetyApplied = true
        else
            UninviteByName(candidates[i].name)
            removed = removed + 1
        end
    end

    if not deadOnly then
        if safetyApplied and survivorName then
            SCB_SetKickAllAnchor(survivorName)
        else
            SCB_ClearKickAllAnchor()
        end
    end

    if safetyApplied then
        SCB_Print(SCB_L("SURVIVOR_CHAT"))
        SCB_ShowSafetyMessage()
    elseif removed > 0 then
        if deadOnly then
            SCB_Print("Kicked " .. removed .. " dead bot" .. (removed == 1 and "." or "s."))
        else
            SCB_Print("Kicked " .. removed .. " bot" .. (removed == 1 and "." or "s."))
        end
    end
end

function SCB_KickDeadOnClick()
    SCB_KickBots(true)
end

function SCB_KickAllOnClick()
    SCB_KickBots(false)
end
