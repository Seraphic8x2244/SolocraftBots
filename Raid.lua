-- SoloCraft Bots - Raid subsystem
-- Consolidated observed roster, Active Roster, role identity and pfUI integration.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

-- -------------------------------------------------------------------------
-- Observed roster / bot identity
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

    for i = 1, 8 do roster.groups[i] = {} end
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
            if member.intendedGroup then member.groupMatchesIntent = member.currentGroup == member.intendedGroup end
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
        if not roster.groups[member.currentGroup] then roster.groups[member.currentGroup] = {} end
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
    if refresh or not SCB.liveRoster then return SCB_RefreshLiveRoster() end
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

-- -------------------------------------------------------------------------
-- Persistent Active Roster
-- -------------------------------------------------------------------------

function SCB_EnsureActiveRosterDB()
    SoloCraftBotsCharDB = SoloCraftBotsCharDB or {}
    if type(SoloCraftBotsCharDB.activeRoster) ~= "table" or SoloCraftBotsCharDB.activeRoster.version ~= 1 then
        SoloCraftBotsCharDB.activeRoster = { version = 1, active = false, suppressed = false, expectedCap = 0, slots = {} }
    end
    local roster = SoloCraftBotsCharDB.activeRoster
    roster.slots = roster.slots or {}
    if roster.active == nil then roster.active = false end
    if roster.suppressed == nil then roster.suppressed = false end
    roster.expectedCap = tonumber(roster.expectedCap) or 0
    return roster
end

function SCB_GetActiveRoster() return SCB_EnsureActiveRosterDB() end

function SCB_CountActiveBotSlots(roster)
    local count = 0
    local _, slot
    roster = roster or SCB_EnsureActiveRosterDB()
    for _, slot in pairs(roster.slots or {}) do if slot and slot.expected then count = count + 1 end end
    return count
end

function SCB_GetActiveSlot(slotID)
    local roster = SCB_EnsureActiveRosterDB()
    return slotID and roster.slots and roster.slots[slotID] or nil
end

function SCB_GetActiveSlotByName(name)
    local roster = SCB_EnsureActiveRosterDB()
    local id, slot
    if not name then return nil, nil end
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected and slot.currentName == name then return slot, id end
    end
    return nil, nil
end

function SCB_UpdateActiveRosterLocation(roster, explicitSize, observedCount)
    local context = SCB_GetLocationContext and SCB_GetLocationContext() or nil
    local signature = SCB_GetLocationSignature and SCB_GetLocationSignature(context) or "?"
    local previousCap
    roster = roster or SCB_EnsureActiveRosterDB()
    observedCount = tonumber(observedCount) or table.getn(SCB_CollectGroupMembers())
    if roster.locationSignature == signature then previousCap = roster.expectedCap end
    if SCB_ResolveLocationExpectedCap then
        roster.expectedCap = SCB_ResolveLocationExpectedCap(context, observedCount, previousCap, explicitSize)
    elseif explicitSize then
        roster.expectedCap = explicitSize
    elseif observedCount > (roster.expectedCap or 0) then
        roster.expectedCap = observedCount
    end
    roster.locationSignature = signature
    roster.locationGroupID = context and context.groupID or nil
    roster.locationZone = context and context.resolvedZone or nil
    roster.locationMax = SCB_GetLocationMaxCapacity and SCB_GetLocationMaxCapacity(context) or roster.expectedCap
    roster.updatedAt = GetTime and GetTime() or 0
    return roster.expectedCap
end

function SCB_ClearActiveRoster(reason, suppress)
    local roster = SCB_EnsureActiveRosterDB()
    roster.active = false
    roster.suppressed = suppress and true or false
    roster.expectedCap = 0
    roster.slots = {}
    roster.clearedReason = reason
    roster.updatedAt = GetTime and GetTime() or 0
    if reason ~= "preset-transition" then SCB.activeRosterTransition = nil end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
end

function SCB_BeginActiveRosterPresetTransition(size)
    local roster
    SCB_ClearActiveRoster("preset-transition", true)
    roster = SCB_EnsureActiveRosterDB()
    roster.expectedCap = tonumber(size) or 0
    SCB_UpdateActiveRosterLocation(roster, tonumber(size), table.getn(SCB_CollectGroupMembers()))
    SCB.activeRosterTransition = { kind = "preset", expectedCap = tonumber(size) or 0, startedAt = GetTime and GetTime() or 0 }
end

function SCB_CancelActiveRosterPresetTransition()
    SCB.activeRosterTransition = nil
    local roster = SCB_EnsureActiveRosterDB()
    if not roster.active then roster.suppressed = false end
end

function SCB_AllowActiveRosterAdoption()
    local roster = SCB_EnsureActiveRosterDB()
    roster.suppressed = false
end

local function SCB_ActiveObservedClass(member)
    if member and member.classFile then return string.lower(member.classFile) end
    return nil
end

function SCB_EstablishActiveRosterFromTracker(tracker)
    local roster, observed, i, assignment, member, slot
    if not tracker or not tracker.ready or not tracker.assignments then return false end
    roster = SCB_EnsureActiveRosterDB()
    observed = SCB_GetLiveRoster(true)
    roster.active = true
    roster.suppressed = false
    roster.slots = {}
    SCB_UpdateActiveRosterLocation(roster, tracker.size, observed and observed.count or 0)
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.botName then
            member = observed and observed.byName and observed.byName[assignment.botName] or nil
            slot = {
                id = assignment.slotIndex, expected = true, currentName = assignment.botName,
                class = SCB_ActiveObservedClass(member) or assignment.class,
                role = assignment.role, extra = assignment.extra,
                currentGroup = member and member.currentGroup or assignment.group or 1,
                intendedGroup = assignment.group, source = "preset", trackerSlotIndex = assignment.slotIndex,
                state = member and member.dead and "dead" or "alive", lastSeenAt = GetTime and GetTime() or 0,
            }
            roster.slots[assignment.slotIndex] = slot
        end
    end
    roster.updatedAt = GetTime and GetTime() or 0
    SCB.activeRosterTransition = nil
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

local function SCB_FindFreeActiveSlotID(roster)
    local i
    local limit = tonumber(roster.expectedCap) or 0
    for i = 1, limit do if not roster.slots[i] then return i end end
    i = limit + 1
    while roster.slots[i] do i = i + 1 end
    return i
end

local function SCB_FindMissingActiveSlot(roster, preferredGroup)
    local id, slot, fallbackID, fallback
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected and slot.state == "missing" then
            if not fallback then fallback, fallbackID = slot, id end
            if preferredGroup and slot.currentGroup == preferredGroup then return slot, id end
        end
    end
    return fallback, fallbackID
end

function SCB_AdoptObservedBotIntoActiveRoster(member, roster)
    local slot, slotID, now
    if not member or not member.isBot then return nil end
    roster = roster or SCB_EnsureActiveRosterDB()
    now = GetTime and GetTime() or 0
    slot, slotID = SCB_FindMissingActiveSlot(roster, member.currentGroup)
    if not slot then
        slotID = SCB_FindFreeActiveSlotID(roster)
        slot = { id = slotID, expected = true }
        roster.slots[slotID] = slot
    end
    slot.expected = true
    slot.currentName = member.name
    slot.class = SCB_ActiveObservedClass(member)
    slot.role = member.confirmedRole
    if member.confirmedExtraKnown then slot.extra = member.confirmedExtra else slot.extra = nil end
    slot.currentGroup = member.currentGroup or 1
    slot.intendedGroup = nil
    slot.source = "manual"
    slot.trackerSlotIndex = nil
    slot.state = member.dead and "dead" or "alive"
    slot.missingSince = nil
    slot.lastSeenAt = now
    return slot
end

function SCB_InitializeActiveRosterFromObserved(observed)
    local roster, i, member
    observed = observed or SCB_GetLiveRoster(true)
    if not observed or (observed.botCount or 0) <= 0 then return false end
    roster = SCB_EnsureActiveRosterDB()
    if roster.suppressed or SCB.activeRosterTransition then return false end
    roster.active = true
    roster.slots = {}
    SCB_UpdateActiveRosterLocation(roster, nil, observed.count or 0)
    for i = 1, table.getn(observed.members or {}) do
        member = observed.members[i]
        if member and member.isBot then SCB_AdoptObservedBotIntoActiveRoster(member, roster) end
    end
    roster.updatedAt = GetTime and GetTime() or 0
    return true
end

function SCB_SyncActiveRosterFromObserved()
    local roster, observed, now, id, slot, member, bound, i
    if SCB.activeRosterReconcilePending or SCB.activeRosterTransition then return end
    roster = SCB_EnsureActiveRosterDB()
    observed = SCB_GetLiveRoster(true)
    if not roster.active then
        if not roster.suppressed then SCB_InitializeActiveRosterFromObserved(observed) end
        return
    end
    now = GetTime and GetTime() or 0
    SCB_UpdateActiveRosterLocation(roster, nil, observed and observed.count or 0)
    bound = {}
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected then
            member = nil
            if slot.state ~= "missing" and slot.currentName and observed and observed.byName then member = observed.byName[slot.currentName] end
            if member and member.isBot then
                slot.class = SCB_ActiveObservedClass(member) or slot.class
                slot.currentGroup = member.currentGroup or slot.currentGroup or 1
                slot.state = member.dead and "dead" or "alive"
                slot.missingSince = nil
                slot.lastSeenAt = now
                bound[member.name] = true
            else
                if slot.state ~= "missing" then slot.missingSince = now end
                slot.state = "missing"
            end
        end
    end
    if not (SCB.refillState and SCB.refillState.active) and not (SCB.replaceDeadState and SCB.replaceDeadState.active) then
        for i = 1, table.getn(observed and observed.members or {}) do
            member = observed.members[i]
            if member and member.isBot and not bound[member.name] then
                SCB_AdoptObservedBotIntoActiveRoster(member, roster)
                bound[member.name] = true
            end
        end
    end
    roster.updatedAt = now
end

function SCB_UpdateActiveBotDetection(name, role, extra, extraKnown)
    local slot = SCB_GetActiveSlotByName(name)
    if not slot then return false end
    if role then slot.role = role end
    if extraKnown then slot.extra = extra end
    slot.detected = true
    slot.updatedAt = GetTime and GetTime() or 0
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

function SCB_BuildActiveReplacementRecord(slot)
    if not slot or not slot.expected then return nil end
    if not slot.class or not slot.role or not SCB_IsValidSpawnAssignment(slot.class, slot.role, slot.extra) then return nil end
    return {
        source = "active", sourceName = slot.currentName, activeSlotID = slot.id, slotIndex = slot.id,
        group = slot.currentGroup or 1, class = slot.class, role = slot.role, extra = slot.extra,
        command = SCB_BuildSpawnCommand(slot.class, slot.role, slot.extra), missingSince = slot.missingSince,
    }
end

function SCB_BindReplacementToActiveSlot(slotID, newName, group)
    local roster = SCB_EnsureActiveRosterDB()
    local slot = roster.slots and roster.slots[slotID]
    local tracker, i, assignment
    if not slot or not newName then return false end
    slot.currentName = newName
    slot.currentGroup = group or slot.currentGroup or 1
    slot.state = "alive"
    slot.missingSince = nil
    slot.lastSeenAt = GetTime and GetTime() or 0
    roster.active = true
    roster.suppressed = false
    roster.updatedAt = slot.lastSeenAt
    if slot.trackerSlotIndex and SoloCraftBotsCharDB then
        tracker = SoloCraftBotsCharDB.raidRoleTracker
        if tracker and tracker.assignments then
            for i = 1, table.getn(tracker.assignments) do
                assignment = tracker.assignments[i]
                if assignment and assignment.slotIndex == slot.trackerSlotIndex then assignment.botName = newName; break end
            end
        end
    end
    return true
end

function SCB_GetActiveMaintenanceRecords()
    local roster = SCB_EnsureActiveRosterDB()
    local observed, missing, dead, unavailableMissing, unavailableDead = nil, {}, {}, {}, {}
    local id, slot, member, replacement
    if not roster.active or SCB.activeRosterTransition then return missing, dead, unavailableMissing, unavailableDead end
    SCB_SyncActiveRosterFromObserved()
    observed = SCB_GetLiveRoster(false)
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected then
            replacement = SCB_BuildActiveReplacementRecord(slot)
            if slot.state == "missing" then
                if replacement then table.insert(missing, slot) else table.insert(unavailableMissing, slot) end
            else
                member = slot.currentName and observed and observed.byName and observed.byName[slot.currentName] or nil
                if member and member.isBot and member.dead then
                    if replacement then table.insert(dead, slot) else table.insert(unavailableDead, slot) end
                end
            end
        end
    end
    return missing, dead, unavailableMissing, unavailableDead
end

function SCB_ReconcileSavedActiveRoster()
    local roster = SCB_EnsureActiveRosterDB()
    local observed = SCB_GetLiveRoster(true)
    local expectedCount, presentCount = 0, 0
    local id, slot, member, now
    now = GetTime and GetTime() or 0
    if SCB.activeRosterTransition then SCB.activeRosterReconcilePending = false; return end
    if not roster.active then
        SCB.activeRosterReconcilePending = false
        if not roster.suppressed then SCB_InitializeActiveRosterFromObserved(observed) end
        if SCB_ValidateSavedSession then SCB_ValidateSavedSession() end
        if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
        return
    end
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected and slot.currentName then
            expectedCount = expectedCount + 1
            member = observed and observed.byName and observed.byName[slot.currentName] or nil
            if member and member.isBot then presentCount = presentCount + 1 end
        end
    end
    if expectedCount > 0 and presentCount == 0 then
        SCB.activeRosterReconcilePending = false
        SCB_ClearActiveRoster("session-ended", false)
        if SCB_ValidateSavedSession then SCB_ValidateSavedSession() end
        return
    end
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected then
            member = slot.currentName and observed and observed.byName and observed.byName[slot.currentName] or nil
            if member and member.isBot then
                slot.class = SCB_ActiveObservedClass(member) or slot.class
                slot.currentGroup = member.currentGroup or slot.currentGroup or 1
                slot.state = member.dead and "dead" or "alive"
                slot.missingSince = nil
                slot.lastSeenAt = now
            else
                slot.state = "missing"
                if not slot.missingSince then slot.missingSince = now end
            end
        end
    end
    SCB_UpdateActiveRosterLocation(roster, nil, observed and observed.count or 0)
    SCB.activeRosterReconcilePending = false
    SCB_SyncActiveRosterFromObserved()
    if SCB_ValidateSavedSession then SCB_ValidateSavedSession() end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
end

function SCB_QueueActiveRosterWorldReconcile(delay)
    local frame = SCB.activeRosterReconcileFrame
    SCB.activeRosterReconcilePending = true
    if not frame then
        frame = CreateFrame("Frame", "SoloCraftBotsActiveRosterReconcileFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0.75) then return end
            this.scbElapsed = 0
            this:Hide()
            SCB_ReconcileSavedActiveRoster()
        end)
        SCB.activeRosterReconcileFrame = frame
    end
    frame.scbDelay = delay or 0.75
    frame.scbElapsed = 0
    frame:Show()
end

function SCB_GroupHasBots()
    local members = SCB_CollectGroupMembers()
    local i
    for i = 1, table.getn(members) do if members[i].isBot then return true end end
    return false
end

function SCB_FindFirstGroupBotName()
    local members = SCB_CollectGroupMembers()
    local i
    for i = 1, table.getn(members) do if members[i].isBot then return members[i].name end end
    return nil
end

function SCB_CountGroupBots()
    local members = SCB_CollectGroupMembers()
    local count, i = 0, nil
    for i = 1, table.getn(members) do if members[i].isBot then count = count + 1 end end
    return count
end

function SCB_CountOtherHumans()
    local members = SCB_CollectGroupMembers()
    local count, i = 0, nil
    for i = 1, table.getn(members) do if not members[i].isBot and not members[i].isSelf then count = count + 1 end end
    return count
end

function SCB_GroupHasName(name)
    local members = SCB_CollectGroupMembers()
    local i
    if not name then return false end
    for i = 1, table.getn(members) do if members[i].name == name then return true end end
    return false
end

function SCB_GetPresetStartBotState()
    local botCount = SCB_CountGroupBots()
    local otherHumans = SCB_CountOtherHumans()
    if botCount == 0 then return "empty", nil end
    if botCount == 1 and otherHumans == 0 then return "survivor", SCB_FindFirstGroupBotName() end
    return "blocked", nil
end

function SCB_EnsureSessionDB()
    SoloCraftBotsDB.session = SoloCraftBotsDB.session or {}
    SoloCraftBotsDB.session.knownBots = SoloCraftBotsDB.session.knownBots or {}
    SoloCraftBotsDB.session.state = SoloCraftBotsDB.session.state or {}
    if not SoloCraftBotsDB.session.state.distance then SoloCraftBotsDB.session.state.distance = "near" end
end

function SCB_SetKickAllAnchor(name) SCB_EnsureSessionDB(); SoloCraftBotsDB.session.state.kickAllAnchorName = name end
function SCB_ClearKickAllAnchor(name)
    SCB_EnsureSessionDB()
    if not name or SoloCraftBotsDB.session.state.kickAllAnchorName == name then SoloCraftBotsDB.session.state.kickAllAnchorName = nil end
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
    if SCB_CountGroupBots() == 1 and SCB_CountOtherHumans() == 0 then return name end
    return nil
end

function SCB_ResetSessionState()
    SCB_EnsureSessionDB()
    SoloCraftBotsDB.session.knownBots = {}
    SoloCraftBotsDB.session.state = { distance = "near" }
end

function SCB_RefreshDistanceButtons()
    if not SCB.distanceButton then return end
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
    for name in pairs(known) do if roster[name] then retained[name] = true; hasKnown = true end end
    if hasKnown then SoloCraftBotsDB.session.knownBots = retained else SCB_ResetSessionState() end
    SCB.lastRoster = roster
    SCB.pendingBotAdds = 0
    SCB.pendingBotAddsExpires = 0
    SCB_RefreshDistanceButtons()
    SCB_RefreshLiveRoster()
end

function SCB_RegisterSpawnIntent()
    SCB.pendingBotAdds = SCB.pendingBotAdds + 1
    if GetTime then SCB.pendingBotAddsExpires = GetTime() + 5 end
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
    for i = 1, table.getn(SCB.AUTO_LOOT_METHODS) do if SCB.AUTO_LOOT_METHODS[i].key == method then return SCB.AUTO_LOOT_METHODS[i] end end
    return SCB.AUTO_LOOT_METHODS[1]
end

function SCB_ApplyAutoLootMethod()
    local method, current, partyCount, raidCount
    SCB_EnsureOptionsDB()
    method = SoloCraftBotsDB.options.autoLootMethod or "off"
    if method == "off" or not SetLootMethod then return true end
    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if partyCount <= 0 and raidCount <= 0 then return false end
    if IsPartyLeader and not IsPartyLeader() then return false end
    if GetLootMethod then current = GetLootMethod(); if current == method and method ~= "master" then return true end end
    if method == "master" then
        if UnitName and UnitName("player") then SetLootMethod("master", UnitName("player")) else return false end
    else
        SetLootMethod(method)
    end
    if GetLootMethod then current = GetLootMethod(); return current == method end
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
            if SCB_ApplyAutoLootMethod() or this.scbAttempts >= 4 then this:Hide() end
        end)
        SCB.autoLootApplyFrame = frame
    end
    frame = SCB.autoLootApplyFrame
    frame.scbElapsed = 0
    frame.scbAttempts = 0
    frame:Show()
end

function SCB_ApplyAutoPromotePlayers()
    local count, i, name, rank, playerName
    if not SoloCraftBotsDB or not SoloCraftBotsDB.options or not SoloCraftBotsDB.options.autoPromotePlayers then return end
    if not GetNumRaidMembers or not GetRaidRosterInfo or not PromoteToAssistant then return end
    count = GetNumRaidMembers()
    if count == 0 then return end
    playerName = UnitName("player")
    if not playerName then return end
    local isLeader = false
    for i = 1, count do name, rank = GetRaidRosterInfo(i); if name == playerName and rank == 2 then isLeader = true; break end end
    if not isLeader then return end
    for i = 1, count do
        name, rank = GetRaidRosterInfo(i)
        if name and name ~= playerName and rank == 0 and not SCB_IsBotName(name) then PromoteToAssistant(name) end
    end
end

function SCB_HandleRosterChange()
    local current = SCB_GetRosterNames()
    local name, scbBotAdded
    SCB_EnsureSessionDB()
    if SCB.pendingBotAdds > 0 and GetTime and SCB.pendingBotAddsExpires > 0 and GetTime() > SCB.pendingBotAddsExpires then
        SCB.pendingBotAdds = 0; SCB.pendingBotAddsExpires = 0
    end
    if SCB.lastRoster and SCB.pendingBotAdds > 0 then
        for name in pairs(current) do
            if SCB.pendingBotAdds <= 0 then break end
            if not SCB.lastRoster[name] and name ~= UnitName("player") then
                SoloCraftBotsDB.session.knownBots[name] = true
                SCB.pendingBotAdds = SCB.pendingBotAdds - 1
                scbBotAdded = true
            end
        end
    end
    SCB_ApplyAutoPromotePlayers()
    SCB.lastRoster = current
    if scbBotAdded then SCB_ApplyAutoLootMethod(); SCB_QueueAutoLootApply() end
    SCB_RefreshLiveRoster()
    if SCB_SyncActiveRosterFromObserved then SCB_SyncActiveRosterFromObserved() end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
end

-- -------------------------------------------------------------------------
-- Role identity / pfUI integration (former RoleTracking.lua)
-- -------------------------------------------------------------------------

SCB.pendingAssumedSpawns = SCB.pendingAssumedSpawns or {}
SCB.assumedRolesByName = SCB.assumedRolesByName or {}
SCB.PRESET_WAIT_REAL_RAID_START = "__SCB_WAIT_REAL_RAID_START__"

local SCB_T3_RAID_GROUPS = { zg = true, aq20 = true, mc = true, onyxia = true, bwl = true, aq40 = true, naxx = true }
function SCB_IsT3RaidLocation()
    local context = SCB_GetLocationContext and SCB_GetLocationContext() or nil
    return context and context.inInstance and SCB_T3_RAID_GROUPS[context.groupID] == true
end
function SCB_ClearPendingAssumedSpawns() SCB.pendingAssumedSpawns = {} end
function SCB_GetResolvedLiveRole(member) if not member then return nil end; return member.confirmedRole or member.assumedRole end

local function SCB_BindAssumedSpawnName(name, intent)
    if not name or not intent then return false end
    intent.name = name
    intent.boundAt = GetTime and GetTime() or 0
    SCB.assumedRolesByName[name] = intent
    return true
end
function SCB_BindNextAssumedSpawnName(name)
    local intent
    if not name or SCB.assumedRolesByName[name] then return false end
    if table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return false end
    intent = table.remove(SCB.pendingAssumedSpawns, 1)
    return SCB_BindAssumedSpawnName(name, intent)
end
local function SCB_PruneAssumedRolesToCurrentRoster()
    local current = SCB_GetRosterNames and SCB_GetRosterNames() or {}
    local name
    for name in pairs(SCB.assumedRolesByName or {}) do if not current[name] then SCB.assumedRolesByName[name] = nil end end
end
function SCB_HandleAssumedRoleSystemMessage(text)
    local _, _, name
    if not text or text == "" then return false end
    _, _, name = string.find(text, "^([^%s]+%*) joins the party%.$")
    if not name then _, _, name = string.find(text, "^([^%s]+%*) has joined the raid group%.?$") end
    if not name then return false end
    if SCB.assumedRolesByName[name] then return false end
    return SCB_BindNextAssumedSpawnName(name)
end
local function SCB_BindAssumptionsFromRosterDelta(previousNames)
    local newMembers, used, consumed = {}, {}, {}
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local qi, mi, intent, member, _, classFile, wantedClass, chosen
    if not previousNames or table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return end
    for mi = 1, table.getn(members) do
        member = members[mi]
        if member and member.isBot and member.name and not previousNames[member.name] and not SCB.assumedRolesByName[member.name] then
            _, classFile = UnitClass and UnitClass(member.unit)
            table.insert(newMembers, { name = member.name, class = classFile and string.lower(classFile) or nil })
        end
    end
    if table.getn(newMembers) == 0 then return end
    for qi = 1, table.getn(SCB.pendingAssumedSpawns) do
        if table.getn(consumed) >= table.getn(newMembers) then break end
        intent = SCB.pendingAssumedSpawns[qi]
        wantedClass = intent.class and string.lower(intent.class) or nil
        chosen = nil
        if wantedClass then for mi = 1, table.getn(newMembers) do if not used[mi] and newMembers[mi].class == wantedClass then chosen = mi; break end end end
        if not chosen then for mi = 1, table.getn(newMembers) do if not used[mi] then chosen = mi; break end end end
        if chosen then used[chosen] = true; SCB_BindAssumedSpawnName(newMembers[chosen].name, intent); table.insert(consumed, qi) end
    end
    for qi = table.getn(consumed), 1, -1 do table.remove(SCB.pendingAssumedSpawns, consumed[qi]) end
end

local SCB_OriginalBuildLiveRoster = SCB_BuildLiveRoster
if SCB_OriginalBuildLiveRoster then
    function SCB_BuildLiveRoster()
        local roster = SCB_OriginalBuildLiveRoster()
        local i, member, assumption, slot
        for i = 1, table.getn(roster and roster.members or {}) do
            member = roster.members[i]
            assumption = member and SCB.assumedRolesByName[member.name] or nil
            if assumption then
                member.assumedRole = assumption.role; member.assumedExtra = assumption.extra; member.assumedClass = assumption.class or member.assumedClass
                member.assumedRoleSource = "spawn"; member.spawnKind = assumption.spawnKind
            elseif member and member.isBot and SCB_GetActiveSlotByName then
                slot = SCB_GetActiveSlotByName(member.name)
                if slot and slot.role then member.assumedRole = slot.role; member.assumedExtra = slot.extra; member.assumedRoleSource = "active" end
            elseif member and member.assumedRole then member.assumedRoleSource = member.assumedRoleSource or "preset" end
            if member then member.resolvedRole = SCB_GetResolvedLiveRole(member) end
        end
        return roster
    end
end

function SCB_ApplyLivePfUITankRoles()
    local roles, roster, i, member, name, frame
    if not pfUI or not pfUI.uf or not pfUI.uf.raid or type(pfUI.uf.raid.tankrole) ~= "table" then return end
    roles = pfUI.uf.raid.tankrole
    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    SCB.pfuiAutoTanks = SCB.pfuiAutoTanks or {}
    for name in pairs(SCB.pfuiAutoTanks) do roles[name] = nil end
    SCB.pfuiAutoTanks = {}
    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if member and member.name and member.spawnKind ~= "bootstrap" and SCB_GetResolvedLiveRole(member) == "tank" then
            roles[member.name] = true; SCB.pfuiAutoTanks[member.name] = true
        end
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 and pfUI.uf.raid.Show then pfUI.uf.raid:Show() end
    if pfUI.uf.RefreshUnit and pfUI.uf.frames then
        for i = 1, table.getn(pfUI.uf.frames) do
            frame = pfUI.uf.frames[i]
            if frame and frame.label and (frame.label == "party" or frame.label == "raid") then pfUI.uf:RefreshUnit(frame, "all") end
        end
    end
end
function SCB_ApplyTrackedPfUITankRoles(tracker) SCB_ApplyLivePfUITankRoles() end

function SCB_ReconcileTrackerFromAssumedRoles(tracker)
    local roster, used, replacements = nil, {}, {}
    local i, j, assignment, member, assumption, wantedGroup, matchedName
    if not tracker or not tracker.ready or tracker.scbRoleIdentityReconciled then return tracker and tracker.scbRoleIdentityReconciled or false end
    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
    if not roster then return false end
    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive then
            wantedGroup = assignment.group or 1; matchedName = nil
            for j = 1, table.getn(roster.members or {}) do
                member = roster.members[j]; assumption = member and SCB.assumedRolesByName[member.name] or nil
                if member and member.isBot and member.name and not used[member.name] and (member.currentGroup or 1) == wantedGroup
                    and assumption and assumption.spawnKind ~= "bootstrap" and assumption.command == assignment.command then matchedName = member.name; break end
            end
            if not matchedName then return false end
            replacements[i] = matchedName; used[matchedName] = true
        end
    end
    for i = 1, table.getn(tracker.assignments or {}) do if replacements[i] then tracker.assignments[i].botName = replacements[i] end end
    tracker.scbRoleIdentityReconciled = true
    return true
end

local SCB_OriginalTryFinalizeRaidRoleTracking = SCB_TryFinalizeRaidRoleTracking
if SCB_OriginalTryFinalizeRaidRoleTracking then
    function SCB_TryFinalizeRaidRoleTracking()
        local ready = SCB_OriginalTryFinalizeRaidRoleTracking()
        local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
        if ready and tracker and SCB_ReconcileTrackerFromAssumedRoles(tracker) then
            if SCB_EstablishActiveRosterFromTracker then SCB_EstablishActiveRosterFromTracker(tracker) end
            if SCB_RefreshLiveRoster then SCB_RefreshLiveRoster() end
        end
        if ready then SCB_ApplyLivePfUITankRoles() end
        return ready
    end
end

local SCB_OriginalAdoptObservedBotIntoActiveRoster = SCB_AdoptObservedBotIntoActiveRoster
if SCB_OriginalAdoptObservedBotIntoActiveRoster then
    function SCB_AdoptObservedBotIntoActiveRoster(member, roster)
        local assumption = member and member.name and SCB.assumedRolesByName[member.name] or nil
        if assumption and assumption.spawnKind == "bootstrap" then return nil end
        return SCB_OriginalAdoptObservedBotIntoActiveRoster(member, roster)
    end
end

local SCB_OriginalHandleRosterChange = SCB_HandleRosterChange
if SCB_OriginalHandleRosterChange then
    function SCB_HandleRosterChange()
        local previousNames = SCB.lastRoster
        SCB_BindAssumptionsFromRosterDelta(previousNames)
        SCB_OriginalHandleRosterChange()
        SCB_PruneAssumedRolesToCurrentRoster()
        SCB_ApplyLivePfUITankRoles()
    end
end

SCB.REPLACE_REMOVAL_SETTLE_DELAY = 3.0
local SCB_OriginalMaintenanceReplaceOnUpdate = SCB_MaintenanceReplaceOnUpdate
if SCB_OriginalMaintenanceReplaceOnUpdate then
    function SCB_MaintenanceReplaceOnUpdate()
        local state = SCB.replaceDeadState
        local now = GetTime and GetTime() or 0
        local waitForDeparture = state and state.active and (state.phase == "waitremoved" or state.phase == "waitsurvivorremoved")
            and state.removedNames and next(state.removedNames) ~= nil
        if waitForDeparture then
            if state.scbRemovalDelayPhase ~= state.phase then state.scbRemovalDelayPhase = state.phase; state.scbRemovalGoneAt = nil end
            if not SCB_ReplaceDeadNamesGone or not SCB_ReplaceDeadNamesGone(state.removedNames) then state.scbRemovalGoneAt = nil; return end
            if not state.scbRemovalGoneAt then state.scbRemovalGoneAt = now; return end
            if (now - state.scbRemovalGoneAt) < SCB.REPLACE_REMOVAL_SETTLE_DELAY then return end
            if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return end
        end
        return SCB_OriginalMaintenanceReplaceOnUpdate()
    end
end

local SCB_OriginalCreateRaidRoleTracker = SCB_CreateRaidRoleTracker
if SCB_OriginalCreateRaidRoleTracker then
    function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        SCB_ClearPendingAssumedSpawns()
        return SCB_OriginalCreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    end
end
local SCB_OriginalStartRefillAssignments = SCB_StartRefillAssignments
if SCB_OriginalStartRefillAssignments then function SCB_StartRefillAssignments(assignments) SCB_ClearPendingAssumedSpawns(); return SCB_OriginalStartRefillAssignments(assignments) end end
local SCB_OriginalAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_OriginalAbortBotSpawnOperations then function SCB_AbortBotSpawnOperations() SCB_ClearPendingAssumedSpawns(); return SCB_OriginalAbortBotSpawnOperations() end end
local SCB_OriginalResetSessionState = SCB_ResetSessionState
if SCB_OriginalResetSessionState then function SCB_ResetSessionState() SCB_ClearPendingAssumedSpawns(); SCB.assumedRolesByName = {}; return SCB_OriginalResetSessionState() end end

local roleEventFrame = CreateFrame("Frame", "SoloCraftBotsRoleTrackingEventFrame", UIParent)
roleEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
roleEventFrame:SetScript("OnEvent", function() if event == "CHAT_MSG_SYSTEM" then SCB_HandleAssumedRoleSystemMessage(arg1) end end)
