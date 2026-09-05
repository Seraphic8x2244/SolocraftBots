-- SoloCraft Bots - Roster
-- Shared roster, bot identity, session state, distance, and Auto Loot helpers.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

-- -------------------------------------------------------------------------
-- Roster / bot identity
-- -------------------------------------------------------------------------

function SCB_GetRosterNames()
    local names = {}
    local i, name

    name = UnitName("player")
    if name then
        names[name] = true
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            name = UnitName("raid" .. i)
            if name then
                names[name] = true
            end
        end
    elseif GetNumPartyMembers then
        for i = 1, GetNumPartyMembers() do
            name = UnitName("party" .. i)
            if name then
                names[name] = true
            end
        end
    end
    return names
end

function SCB_IsBotName(name)
    return name and string.sub(name, -1) == "*"
end

function SCB_CollectGroupMembers()
    local members = {}
    local playerName = UnitName and UnitName("player") or nil
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local i, unit, name

    if raidCount > 0 then
        for i = 1, raidCount do
            unit = "raid" .. i
            name = UnitName(unit)
            if name then
                local _, _, subgroup = GetRaidRosterInfo(i)
                table.insert(members, {
                    unit = unit,
                    name = name,
                    subgroup = subgroup,
                    isSelf = playerName and name == playerName or false,
                    isBot = SCB_IsBotName(name),
                    dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false,
                })
            end
        end
    else
        if playerName then
            table.insert(members, {
                unit = "player",
                name = playerName,
                subgroup = 1,
                isSelf = true,
                isBot = false,
                dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true or false,
            })
        end
        for i = 1, partyCount do
            unit = "party" .. i
            name = UnitName(unit)
            if name then
                table.insert(members, {
                    unit = unit,
                    name = name,
                    subgroup = 1,
                    isSelf = false,
                    isBot = SCB_IsBotName(name),
                    dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false,
                })
            end
        end
    end
    return members
end

function SCB_GroupHasBots()
    local members = SCB_CollectGroupMembers()
    local i
    for i = 1, table.getn(members) do
        if members[i].isBot then return true end
    end
    return false
end

function SCB_FindFirstGroupBotName()
    local members = SCB_CollectGroupMembers()
    local i
    for i = 1, table.getn(members) do
        if members[i].isBot then return members[i].name end
    end
    return nil
end

function SCB_CountGroupBots()
    local members = SCB_CollectGroupMembers()
    local count = 0
    local i
    for i = 1, table.getn(members) do
        if members[i].isBot then count = count + 1 end
    end
    return count
end

function SCB_CountOtherHumans()
    local members = SCB_CollectGroupMembers()
    local count = 0
    local i
    for i = 1, table.getn(members) do
        if not members[i].isBot and not members[i].isSelf then
            count = count + 1
        end
    end
    return count
end

function SCB_GroupHasName(name)
    local members = SCB_CollectGroupMembers()
    local i
    if not name then return false end
    for i = 1, table.getn(members) do
        if members[i].name == name then return true end
    end
    return false
end

-- Preset spawning accepts either a genuinely bot-clean group, or the one
-- deliberate survivor state created by safe bot removal: player + one bot,
-- with no other humans. Anything else stays behind the empty gate.
function SCB_GetPresetStartBotState()
    local botCount = SCB_CountGroupBots()
    local otherHumans = SCB_CountOtherHumans()
    if botCount == 0 then
        return "empty", nil
    end
    if botCount == 1 and otherHumans == 0 then
        return "survivor", SCB_FindFirstGroupBotName()
    end
    return "blocked", nil
end

function SCB_EnsureSessionDB()
    SoloCraftBotsDB.session = SoloCraftBotsDB.session or {}
    SoloCraftBotsDB.session.knownBots = SoloCraftBotsDB.session.knownBots or {}
    SoloCraftBotsDB.session.state = SoloCraftBotsDB.session.state or {}
    if not SoloCraftBotsDB.session.state.distance then
        SoloCraftBotsDB.session.state.distance = "near"
    end
end

-- Kick All can deliberately leave one Group 1 bot alive as an instance-safety
-- anchor.  Record that exact bot explicitly: a random lone surviving preset bot
-- must never be mistaken for the anchor later.
function SCB_SetKickAllAnchor(name)
    SCB_EnsureSessionDB()
    SoloCraftBotsDB.session.state.kickAllAnchorName = name
end

function SCB_ClearKickAllAnchor(name)
    SCB_EnsureSessionDB()
    if not name or SoloCraftBotsDB.session.state.kickAllAnchorName == name then
        SoloCraftBotsDB.session.state.kickAllAnchorName = nil
    end
end

function SCB_GetKickAllAnchorName()
    local name
    SCB_EnsureSessionDB()
    name = SoloCraftBotsDB.session.state.kickAllAnchorName
    if not name then return nil end
    if SCB_GroupHasName(name) then return name end
    SCB_ClearKickAllAnchor(name)
    return nil
end

function SCB_GetKickAllAnchorForFreshBuild()
    local name = SCB_GetKickAllAnchorName()
    if not name then return nil end
    -- Kick All roster removals arrive asynchronously. Do not erase the marker
    -- while the other kicked bots are still disappearing; simply enable the
    -- fresh-build handoff once the intended player + one-anchor shape is real.
    if SCB_CountGroupBots() == 1 and SCB_CountOtherHumans() == 0 then return name end
    return nil
end

function SCB_ResetSessionState()
    SCB_EnsureSessionDB()
    SoloCraftBotsDB.session.knownBots = {}
    SoloCraftBotsDB.session.state = { distance = "near" }
end

function SCB_RefreshDistanceButtons()
    if not SCB.distanceButton then
        return
    end
    SCB_EnsureSessionDB()
    local state = SoloCraftBotsDB.session.state.distance
    if state == "far" then
        SCB_SetArtButtonTexture(SCB.distanceButton, SCB.assetRoot .. "distance.tga", nil)
        SCB.distanceButton.scbTooltip = "Spawn Far\n.partybot distance on\nClick to switch to Spawn Near"
    else
        SCB_SetArtButtonTexture(SCB.distanceButton, SCB.assetRoot .. "distance_off.tga", nil)
        SCB.distanceButton.scbTooltip = "Spawn Near\n.partybot distance off\nClick to switch to Spawn Far"
    end
    SCB_RefreshVisibleTooltip(SCB.distanceButton)
end

function SCB_ValidateSavedSession()
    SCB_EnsureSessionDB()
    local roster = SCB_GetRosterNames()
    local known = SoloCraftBotsDB.session.knownBots
    local retained = {}
    local hasKnown = false
    local name

    for name in pairs(known) do
        if roster[name] then
            retained[name] = true
            hasKnown = true
        end
    end

    if hasKnown then
        SoloCraftBotsDB.session.knownBots = retained
    else
        SCB_ResetSessionState()
    end

    SCB.lastRoster = roster
    SCB.pendingBotAdds = 0
    SCB.pendingBotAddsExpires = 0
    SCB_RefreshDistanceButtons()
end

function SCB_RegisterSpawnIntent()
    SCB.pendingBotAdds = SCB.pendingBotAdds + 1
    if GetTime then
        SCB.pendingBotAddsExpires = GetTime() + 5
    end
end

SCB.AUTO_LOOT_METHODS = {
    { key = "off", label = "Off" },
    { key = "group", label = "Group Loot" },
    { key = "needbeforegreed", label = "Need Before Greed" },
    { key = "roundrobin", label = "Round Robin" },
    { key = "freeforall", label = "Free For All" },
    { key = "master", label = "Master Looter" },
}

function SCB_GetAutoLootInfo(method)
    local i
    for i = 1, table.getn(SCB.AUTO_LOOT_METHODS) do
        if SCB.AUTO_LOOT_METHODS[i].key == method then
            return SCB.AUTO_LOOT_METHODS[i]
        end
    end
    return SCB.AUTO_LOOT_METHODS[1]
end

function SCB_ApplyAutoLootMethod()
    local method, current, partyCount, raidCount
    SCB_EnsureOptionsDB()
    method = SoloCraftBotsDB.options.autoLootMethod or "off"
    if method == "off" or not SetLootMethod then return true end

    -- Loot method changes only make sense once the player is actually in a
    -- group, and only the group/raid leader can make them. The first bot join
    -- can fire a roster event before those states have fully settled, so the
    -- caller may retry briefly if this returns false.
    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if partyCount <= 0 and raidCount <= 0 then return false end
    if IsPartyLeader and not IsPartyLeader() then return false end

    if GetLootMethod then
        current = GetLootMethod()
        if current == method and method ~= "master" then return true end
    end

    if method == "master" then
        if UnitName and UnitName("player") then
            SetLootMethod("master", UnitName("player"))
        else
            return false
        end
    else
        SetLootMethod(method)
    end

    if GetLootMethod then
        current = GetLootMethod()
        return current == method
    end
    return true
end

function SCB_QueueAutoLootApply()
    local frame
    if not SCB.autoLootApplyFrame then
        frame = CreateFrame("Frame", "SoloCraftBotsAutoLootApplyFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + arg1
            if this.scbElapsed < 0.25 then return end
            this.scbElapsed = 0
            this.scbAttempts = (this.scbAttempts or 0) + 1
            if SCB_ApplyAutoLootMethod() or this.scbAttempts >= 4 then
                this:Hide()
            end
        end)
        SCB.autoLootApplyFrame = frame
    end

    frame = SCB.autoLootApplyFrame
    frame.scbElapsed = 0
    frame.scbAttempts = 0
    frame:Show()
end

function SCB_HandleRosterChange()
    local current = SCB_GetRosterNames()
    local name, scbBotAdded

    SCB_EnsureSessionDB()

    if SCB.pendingBotAdds > 0 and GetTime and SCB.pendingBotAddsExpires > 0 and GetTime() > SCB.pendingBotAddsExpires then
        SCB.pendingBotAdds = 0
        SCB.pendingBotAddsExpires = 0
    end

    if SCB.lastRoster and SCB.pendingBotAdds > 0 then
        for name in pairs(current) do
            if SCB.pendingBotAdds <= 0 then
                break
            end
            if not SCB.lastRoster[name] and name ~= UnitName("player") then
                SoloCraftBotsDB.session.knownBots[name] = true
                SCB.pendingBotAdds = SCB.pendingBotAdds - 1
                scbBotAdded = true
            end
        end
    end

    SCB.lastRoster = current
    if scbBotAdded then
        -- Try immediately, then verify/retry for up to one second. Vanilla can
        -- report the first solo->party roster change before leader/loot state
        -- is fully ready for SetLootMethod().
        SCB_ApplyAutoLootMethod()
        SCB_QueueAutoLootApply()
    end
end

