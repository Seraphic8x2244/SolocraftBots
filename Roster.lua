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

-- -------------------------------------------------------------------------
-- Live roster
-- -------------------------------------------------------------------------

-- Preset intent and live WoW state are deliberately kept separate. The
-- tracker tells us what SCB intended when a preset was built; the roster tells
-- us where that member actually is now. Manual/unknown bots simply have no
-- preset association until another system (for example Detection.lua) learns
-- more about them.
function SCB_GetTrackedRosterAssociation(name, isBot)
    local tracker, list, i, entry
    if not name or not SoloCraftBotsCharDB then return nil end

    tracker = SoloCraftBotsCharDB.raidRoleTracker
    if not tracker then return nil end

    if isBot then
        list = tracker.assignments or {}
        for i = 1, table.getn(list) do
            entry = list[i]
            if entry and entry.botName == name then
                return {
                    source = "preset",
                    presetSlotIndex = entry.slotIndex,
                    intendedGroup = entry.group,
                    assumedClass = entry.class,
                    assumedRole = entry.role,
                    assumedExtra = entry.extra,
                    trackerEntry = entry,
                }
            end
        end
    else
        list = tracker.players or {}
        for i = 1, table.getn(list) do
            entry = list[i]
            if entry and entry.name == name then
                return {
                    source = "preset",
                    presetSlotIndex = entry.slotIndex,
                    intendedGroup = entry.group,
                    assumedRole = entry.role,
                    assumedExtra = entry.extra,
                }
            end
        end
    end

    return nil
end

function SCB_BuildLiveRoster()
    local rawMembers = SCB_CollectGroupMembers()
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local previousRevision = SCB.liveRoster and SCB.liveRoster.revision or 0
    local roster = {
        version = 1,
        revision = previousRevision + 1,
        mode = raidCount > 0 and "raid" or (partyCount > 0 and "party" or "solo"),
        updatedAt = GetTime and GetTime() or 0,
        members = {},
        byName = {},
        botsByName = {},
        humansByName = {},
        groups = {},
        count = 0,
        botCount = 0,
        humanCount = 0,
    }
    local i, member, className, classFile, association, knownBots

    for i = 1, 8 do
        roster.groups[i] = {}
    end

    if SoloCraftBotsDB and SoloCraftBotsDB.session then
        knownBots = SoloCraftBotsDB.session.knownBots
    end

    for i = 1, table.getn(rawMembers) do
        member = rawMembers[i]
        className, classFile = UnitClass and UnitClass(member.unit)
        association = SCB_GetTrackedRosterAssociation(member.name, member.isBot)

        member.class = className
        member.classFile = classFile
        member.currentGroup = member.subgroup or 1
        member.isHuman = not member.isBot
        member.isKnownSCBBot = member.isBot and knownBots and knownBots[member.name] and true or false
        member.isPresetMember = association and true or false

        if association then
            member.associationSource = association.source
            member.presetSlotIndex = association.presetSlotIndex
            member.intendedGroup = association.intendedGroup
            member.assumedClass = association.assumedClass
            member.assumedRole = association.assumedRole
            member.assumedExtra = association.assumedExtra
            member.trackerAssignment = association.trackerEntry
            if member.intendedGroup then
                member.groupMatchesIntent = member.currentGroup == member.intendedGroup
            end
        end

        if member.isPresetMember then
            member.origin = "preset"
        elseif member.isKnownSCBBot then
            member.origin = "scb"
        elseif member.isBot then
            member.origin = "unknown"
        else
            member.origin = "player"
        end

        table.insert(roster.members, member)
        roster.byName[member.name] = member
        roster.count = roster.count + 1

        if not roster.groups[member.currentGroup] then
            roster.groups[member.currentGroup] = {}
        end
        table.insert(roster.groups[member.currentGroup], member)

        if member.isBot then
            roster.botsByName[member.name] = member
            roster.botCount = roster.botCount + 1
        else
            roster.humansByName[member.name] = member
            roster.humanCount = roster.humanCount + 1
        end
    end

    return roster
end

function SCB_RefreshLiveRoster()
    SCB.liveRoster = SCB_BuildLiveRoster()
    return SCB.liveRoster
end

function SCB_GetLiveRoster(refresh)
    if refresh or not SCB.liveRoster then
        return SCB_RefreshLiveRoster()
    end
    return SCB.liveRoster
end

function SCB_GetLiveMember(name, refresh)
    local roster
    if not name then return nil end
    roster = SCB_GetLiveRoster(refresh)
    return roster and roster.byName[name] or nil
end

function SCB_GetLiveGroup(group, refresh)
    local roster = SCB_GetLiveRoster(refresh)
    if not roster then return nil end
    return roster.groups[group]
end

-- Snapshot the replacement facts from the bot that is actually in the live
-- roster now. The selected Preset UI is deliberately irrelevant here. Class
-- comes from UnitClass (observed live); role/extra use confirmed observation
-- when available and otherwise the assumption inherited when this bot joined.
-- currentGroup is the replacement destination, so manual raid-group tweaks are
-- preserved rather than snapping a replacement back to the original preset.
function SCB_BuildLiveReplacementRecord(member)
    local class, role, extra
    if not member or not member.isBot then return nil end

    class = member.classFile and string.lower(member.classFile) or member.assumedClass
    role = member.confirmedRole or member.assumedRole
    if member.confirmedExtraKnown then
        extra = member.confirmedExtra
    else
        extra = member.assumedExtra
    end

    if not class or not role or not SCB_IsValidSpawnAssignment(class, role, extra) then
        return nil
    end

    return {
        source = "live",
        sourceName = member.name,
        slotIndex = member.presetSlotIndex,
        group = member.currentGroup or 1,
        intendedGroup = member.intendedGroup,
        class = class,
        role = role,
        extra = extra,
        command = SCB_BuildSpawnCommand(class, role, extra),
        bindAssignment = member.trackerAssignment,
    }
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
        SCB.distanceButton.scbTooltip = SCB_L("TIP_SPAWN_FAR")
    else
        SCB_SetArtButtonTexture(SCB.distanceButton, SCB.assetRoot .. "distance_off.tga", nil)
        SCB.distanceButton.scbTooltip = SCB_L("TIP_SPAWN_NEAR")
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
    SCB_RefreshLiveRoster()
end

function SCB_RegisterSpawnIntent()
    SCB.pendingBotAdds = SCB.pendingBotAdds + 1
    if GetTime then
        SCB.pendingBotAddsExpires = GetTime() + 5
    end
end

SCB.AUTO_LOOT_METHODS = {
    { key = "off", label = SCB_L("LOOT_OFF") },
    { key = "group", label = SCB_L("LOOT_GROUP") },
    { key = "needbeforegreed", label = SCB_L("LOOT_NEED_BEFORE_GREED") },
    { key = "roundrobin", label = SCB_L("LOOT_ROUND_ROBIN") },
    { key = "freeforall", label = SCB_L("LOOT_FREE_FOR_ALL") },
    { key = "master", label = SCB_L("LOOT_MASTER") },
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

    SCB_RefreshLiveRoster()
end

