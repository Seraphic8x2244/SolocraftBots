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
    local memberRank, subgroup, groupRows

    if raidCount > 0 then
        groupRows = {}
        for i = 1, 8 do groupRows[i] = 0 end
        for i = 1, raidCount do
            unit = "raid" .. i
            name, memberRank, subgroup = GetRaidRosterInfo(i)
            if name then
                subgroup = subgroup or 1
                groupRows[subgroup] = (groupRows[subgroup] or 0) + 1
                table.insert(members, {
                    unit = unit,
                    name = name,
                    subgroup = subgroup,
                    rank = memberRank,
                    raidIndex = i,
                    groupRow = groupRows[subgroup],
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

function SCB_BuildLiveRoster(rawMembers)
    rawMembers = rawMembers or SCB_CollectGroupMembers()
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
    local assumption, slot, state, tracker, activeRoster, id, entry
    local trackerBotsByName, trackerHumansByName, activeSlotsByName = {}, {}, {}

    for i = 1, 8 do roster.groups[i] = {} end
    if SoloCraftBotsDB and SoloCraftBotsDB.session then
        knownBots = SoloCraftBotsDB.session.knownBots
    end

    tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    for i = 1, table.getn(tracker and tracker.assignments or {}) do
        entry = tracker.assignments[i]
        if entry and entry.botName then trackerBotsByName[entry.botName] = entry end
    end
    for i = 1, table.getn(tracker and tracker.players or {}) do
        entry = tracker.players[i]
        if entry and entry.name then trackerHumansByName[entry.name] = entry end
    end
    activeRoster = SCB_EnsureActiveRosterDB and SCB_EnsureActiveRosterDB()
        or (SoloCraftBotsCharDB and SoloCraftBotsCharDB.activeRoster or nil)
    for id, slot in pairs(activeRoster and activeRoster.slots or {}) do
        if slot and slot.expected and slot.currentName then activeSlotsByName[slot.currentName] = slot end
    end

    for i = 1, table.getn(rawMembers) do
        member = rawMembers[i]
        className, classFile = UnitClass and UnitClass(member.unit)
        if member.isBot then
            association = trackerBotsByName[member.name]
        else
            association = trackerHumansByName[member.name]
        end

        member.class = className
        member.classFile = classFile
        member.currentGroup = member.subgroup or 1
        member.isHuman = not member.isBot
        member.isKnownSCBBot = member.isBot and knownBots and knownBots[member.name] and true or false
        member.isPresetMember = association and true or false

        if association then
            member.associationSource = "preset"
            member.presetSlotIndex = association.slotIndex
            member.intendedGroup = association.group
            member.assumedRole = association.role
            member.assumedExtra = association.extra
            if member.isBot then
                member.assumedClass = association.class
                member.trackerAssignment = association
            end
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

        -- Former RoleTracking/Detection wrappers now enrich this one snapshot.
        assumption = member.name and SCB.assumedRolesByName and SCB.assumedRolesByName[member.name] or nil
        slot = nil
        if assumption then
            member.assumedRole = assumption.role
            member.assumedExtra = assumption.extra
            member.assumedClass = assumption.class or member.assumedClass
            member.assumedRoleSource = "spawn"
            member.spawnKind = assumption.spawnKind
        elseif member.isBot then
            slot = activeSlotsByName[member.name]
            if slot and slot.role then
                member.assumedRole = slot.role
                member.assumedExtra = slot.extra
                member.assumedRoleSource = "active"
            end
        elseif member.assumedRole then
            member.assumedRoleSource = member.assumedRoleSource or "preset"
        end

        if member.isBot and member.name then
            state = SCB.roleEvidenceByName and SCB.roleEvidenceByName[member.name] or nil
            slot = slot or activeSlotsByName[member.name]
            if state then
                member.roleEvidence = state.byRole
                member.confirmedRole = state.confirmedRole
                member.roleCandidate = state.candidateRole
            elseif slot then
                member.roleEvidence = slot.roleEvidence
                member.confirmedRole = slot.confirmedRole
            end
        end
        if SCB_GetResolvedLiveRole then
            member.resolvedRole = SCB_GetResolvedLiveRole(member)
        else
            member.resolvedRole = member.confirmedRole or member.assumedRole
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

function SCB_RefreshLiveRoster(rawMembers)
    SCB.liveRoster = SCB_BuildLiveRoster(rawMembers)
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

-- Membership/subgroup state is event-driven during active physical operations.
-- The bounded fallback protects forks/transitions that miss a roster event.
-- Combat checks are deliberately independent and are never gated by this.
function SCB_PollOperationRosterFallback(elapsed, interval)
    local revision = SCB.rosterEventRevision or 0
    interval = interval or 0.25

    if SCB.operationRosterSeenRevision ~= revision then
        SCB.operationRosterSeenRevision = revision
        SCB.operationRosterFallbackRemaining = interval
        return SCB.liveRoster
    end

    SCB.operationRosterFallbackRemaining = (SCB.operationRosterFallbackRemaining or interval) - (elapsed or 0)
    if SCB.operationRosterFallbackRemaining <= 0 then
        SCB.operationRosterFallbackRemaining = interval
        return SCB_RefreshLiveRoster()
    end
    return SCB.liveRoster
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
    SCB_UpdateActiveRosterLocation(roster, tonumber(size), SCB.liveRoster and SCB.liveRoster.count or nil)
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

function SCB_EstablishActiveRosterFromTracker(tracker, observed)
    local roster, i, assignment, member, slot
    if not tracker or not tracker.ready or not tracker.assignments then return false end
    roster = SCB_EnsureActiveRosterDB()
    observed = observed or SCB_GetLiveRoster(false) or SCB_GetLiveRoster(true)
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
                assumedRole = assignment.role, confirmedRole = nil, roleEvidence = nil, detected = nil,
                currentGroup = member and member.currentGroup or assignment.group or 1,
                intendedGroup = assignment.group, source = "preset", trackerSlotIndex = assignment.slotIndex,
                state = member and member.dead and "dead" or "alive", lastSeenAt = GetTime and GetTime() or 0,
            }
            roster.slots[assignment.slotIndex] = slot
        end
    end
    roster.updatedAt = GetTime and GetTime() or 0
    SCB.activeRosterTransition = nil
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton(observed, false) end
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
    local assumption
    if not member or not member.isBot then return nil end
    assumption = member.name and SCB.assumedRolesByName and SCB.assumedRolesByName[member.name] or nil
    if assumption and assumption.spawnKind == "bootstrap" then return nil end
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

function SCB_SyncActiveRosterFromObserved(observed)
    local roster, now, id, slot, member, bound, i
    if SCB.activeRosterReconcilePending or SCB.activeRosterTransition then return end
    roster = SCB_EnsureActiveRosterDB()
    observed = observed or SCB_GetLiveRoster(true)
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
    local tracker, i, assignment, assumption
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
    assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[newName] or nil
    if assumption and assumption.role then slot.assumedRole = assumption.role end
    slot.role = slot.assumedRole or slot.role
    slot.confirmedRole = nil
    slot.roleEvidence = nil
    slot.detected = nil
    return true
end

function SCB_GetActiveMaintenanceRecords(observed, syncFirst)
    local roster = SCB_EnsureActiveRosterDB()
    local missing, dead, unavailableMissing, unavailableDead = {}, {}, {}, {}
    local id, slot, member, replacement
    if not roster.active or SCB.activeRosterTransition then return missing, dead, unavailableMissing, unavailableDead end
    if syncFirst ~= false then SCB_SyncActiveRosterFromObserved(observed) end
    observed = observed or SCB_GetLiveRoster(false)
    for id, slot in pairs(roster.slots or {}) do
        if slot and slot.expected then
            if slot.state == "missing" then
                replacement = SCB_BuildActiveReplacementRecord(slot)
                if replacement then table.insert(missing, slot) else table.insert(unavailableMissing, slot) end
            else
                member = slot.currentName and observed and observed.byName and observed.byName[slot.currentName] or nil
                if member and member.isBot and member.dead then
                    replacement = SCB_BuildActiveReplacementRecord(slot)
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
        if SCB_ValidateSavedSession then SCB_ValidateSavedSession(observed) end
        if SCB_RefreshRefillButton then SCB_RefreshRefillButton(observed, false) end
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
        if SCB_ValidateSavedSession then SCB_ValidateSavedSession(observed) end
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
    SCB_SyncActiveRosterFromObserved(observed)
    if SCB_ValidateSavedSession then SCB_ValidateSavedSession(observed) end
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton(observed, false) end
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

local function SCB_GroupObservation(observed)
    observed = observed or SCB.liveRoster
    if observed then return observed end
    return SCB_BuildLiveRoster(SCB_CollectGroupMembers())
end

function SCB_GroupHasBots(observed)
    observed = SCB_GroupObservation(observed)
    return observed and (observed.botCount or 0) > 0 or false
end

function SCB_FindFirstGroupBotName(observed)
    local i, member
    observed = SCB_GroupObservation(observed)
    for i = 1, table.getn(observed and observed.members or {}) do
        member = observed.members[i]
        if member and member.isBot then return member.name end
    end
    return nil
end

function SCB_CountGroupBots(observed)
    observed = SCB_GroupObservation(observed)
    return observed and (observed.botCount or 0) or 0
end

function SCB_CountOtherHumans(observed)
    local count, name, member = 0, nil, nil
    observed = SCB_GroupObservation(observed)
    for name, member in pairs(observed and observed.humansByName or {}) do
        if member and not member.isSelf then count = count + 1 end
    end
    return count
end

function SCB_GroupHasName(name, observed)
    observed = SCB_GroupObservation(observed)
    return name and observed and observed.byName and observed.byName[name] ~= nil or false
end

function SCB_GetPresetStartBotState(observed)
    local botCount, otherHumans
    observed = SCB_GroupObservation(observed)
    botCount = observed and observed.botCount or 0
    otherHumans = SCB_CountOtherHumans(observed)
    if botCount == 0 then return "empty", nil end
    if botCount == 1 and otherHumans == 0 then return "survivor", SCB_FindFirstGroupBotName(observed) end
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
function SCB_GetKickAllAnchorName(observed)
    local name
    SCB_EnsureSessionDB()
    name = SoloCraftBotsDB.session.state.kickAllAnchorName
    if not name then return nil end
    if SCB_GroupHasName(name, observed) then return name end
    SCB_ClearKickAllAnchor(name)
    return nil
end
function SCB_GetKickAllAnchorForFreshBuild(observed)
    local name
    observed = SCB_GroupObservation(observed)
    name = SCB_GetKickAllAnchorName(observed)
    if not name then return nil end
    if SCB_CountGroupBots(observed) == 1 and SCB_CountOtherHumans(observed) == 0 then return name end
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

function SCB_ValidateSavedSession(observed)
    SCB_EnsureSessionDB()
    local roster = {}
    local known = SoloCraftBotsDB.session.knownBots
    local retained = {}
    local hasKnown = false
    local name
    if observed and observed.byName then
        for name in pairs(observed.byName) do roster[name] = true end
    else
        roster = SCB_GetRosterNames()
    end
    for name in pairs(known) do if roster[name] then retained[name] = true; hasKnown = true end end
    if hasKnown then SoloCraftBotsDB.session.knownBots = retained else SCB_ResetSessionState() end
    SCB.lastRoster = roster
    SCB.pendingBotAdds = 0
    SCB.pendingBotAddsExpires = 0
    SCB_RefreshDistanceButtons()
    if observed then
        SCB.liveRoster = observed
    else
        SCB_RefreshLiveRoster()
    end
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

function SCB_ApplyAutoPromotePlayers(observed)
    local count, i, name, rank, playerName, member
    if not SoloCraftBotsDB or not SoloCraftBotsDB.options or not SoloCraftBotsDB.options.autoPromotePlayers then return end
    if not PromoteToAssistant then return end

    if observed and observed.mode == "raid" then
        local isLeader = false
        for i = 1, table.getn(observed.members or {}) do
            member = observed.members[i]
            if member and member.isSelf and member.rank == 2 then isLeader = true; break end
        end
        if not isLeader then return end
        for i = 1, table.getn(observed.members or {}) do
            member = observed.members[i]
            if member and member.isHuman and not member.isSelf and member.rank == 0 then
                PromoteToAssistant(member.name)
            end
        end
        return
    end

    if not GetNumRaidMembers or not GetRaidRosterInfo then return end
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

local function SCB_BuildRosterDelta(previous, observed)
    local delta = { added = {}, removed = {}, botChanged = false, humanChanged = false, rankChanged = false }
    local name, member, old

    if not previous then
        for name, member in pairs(observed and observed.byName or {}) do
            delta.added[name] = true
            if member.isBot then delta.botChanged = true else delta.humanChanged = true end
        end
        return delta
    end

    for name, member in pairs(observed and observed.byName or {}) do
        old = previous.byName and previous.byName[name] or nil
        if not old then
            delta.added[name] = true
            if member.isBot then delta.botChanged = true else delta.humanChanged = true end
        elseif not member.isBot and old.rank ~= member.rank then
            delta.rankChanged = true
        end
    end
    for name, member in pairs(previous.byName or {}) do
        if not (observed and observed.byName and observed.byName[name]) then
            delta.removed[name] = true
            if member.isBot then delta.botChanged = true else delta.humanChanged = true end
        end
    end
    return delta
end

function SCB_HandleRosterChange()
    local previousObserved = SCB.lastHandledLiveRoster
    local previousNames = SCB.lastRoster
    local rawMembers = SCB_CollectGroupMembers()
    local observed, current, name, scbBotAdded

    if SCB_BindAssumptionsFromRosterDelta then
        SCB_BindAssumptionsFromRosterDelta(previousNames, rawMembers)
    end
    observed = SCB_RefreshLiveRoster(rawMembers)
    SCB.rosterEventRevision = (SCB.rosterEventRevision or 0) + 1
    observed.eventRevision = SCB.rosterEventRevision
    current = {}
    observed.delta = SCB_BuildRosterDelta(previousObserved, observed)
    for name in pairs(observed.byName or {}) do current[name] = true end

    SCB_EnsureSessionDB()
    if SCB.pendingBotAdds > 0 and GetTime and SCB.pendingBotAddsExpires > 0 and GetTime() > SCB.pendingBotAddsExpires then
        SCB.pendingBotAdds = 0
        SCB.pendingBotAddsExpires = 0
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
    if observed.delta.humanChanged or observed.delta.rankChanged then SCB_ApplyAutoPromotePlayers(observed) end

    SCB.lastRoster = current
    SCB.lastHandledLiveRoster = observed
    if scbBotAdded then SCB_ApplyAutoLootMethod(); SCB_QueueAutoLootApply() end
    if SCB_SyncActiveRosterFromObserved then SCB_SyncActiveRosterFromObserved(observed) end
    if SCB_QueueRefillButtonRefresh then
        SCB_QueueRefillButtonRefresh(0.15)
    elseif SCB_RefreshRefillButton then
        SCB_RefreshRefillButton(observed, false)
    end

    -- Former RoleTracking -> Detection -> lifecycle -> layout wrapper order.
    if SCB_PruneAssumedRolesToCurrentRoster then SCB_PruneAssumedRolesToCurrentRoster(observed) end
    if SCB_LinkAssumptionsToTrackerSlots then SCB_LinkAssumptionsToTrackerSlots() end
    for name in pairs(SCB.roleEvidenceByName or {}) do
        if not observed.byName[name] then SCB.roleEvidenceByName[name] = nil end
    end
    if SCB_QueuePresetRoleIndicatorsRefresh then
        SCB_QueuePresetRoleIndicatorsRefresh(0.15)
    elseif SCB_RefreshPresetRoleIndicators then
        SCB_RefreshPresetRoleIndicators()
    end
    if SCB_QueueRoleDetectionLifecycleRefresh then SCB_QueueRoleDetectionLifecycleRefresh(0.15) end
    if SCB_QueueTrackerLiveLayoutRefresh then SCB_QueueTrackerLiveLayoutRefresh(0.15) end
    return observed
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
    if intent.role == "tank" and intent.spawnKind ~= "bootstrap" and SCB_MarkPfUITank then
        SCB_MarkPfUITank(name)
    end
    return true
end
function SCB_BindNextAssumedSpawnName(name)
    local intent
    if not name or SCB.assumedRolesByName[name] then return false end
    if table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return false end
    intent = table.remove(SCB.pendingAssumedSpawns, 1)
    return SCB_BindAssumedSpawnName(name, intent)
end
function SCB_PruneAssumedRolesToCurrentRoster(observed)
    local current = observed and observed.byName or nil
    local name
    if not current then
        observed = SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil
        current = observed and observed.byName or {}
    end
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
function SCB_BindAssumptionsFromRosterDelta(previousNames, members)
    local newMembers, used, consumed = {}, {}, {}
    members = members or (SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {})
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

function SCB_MarkPfUITank(name)
    local roles
    if not name then return false end
    if not pfUI or not pfUI.uf or not pfUI.uf.raid or type(pfUI.uf.raid.tankrole) ~= "table" then return false end

    roles = pfUI.uf.raid.tankrole
    if roles[name] == true then return false end

    -- pfUI's own tank toggle is name-based. SCB only needs to set the tank once
    -- when that known tank identity appears; unrelated roster changes must not
    -- rebuild or refresh the whole raid.
    roles[name] = true
    SCB.pfuiAutoTanks = SCB.pfuiAutoTanks or {}
    SCB.pfuiAutoTanks[name] = true

    if GetNumRaidMembers and GetNumRaidMembers() > 0 and pfUI.uf.raid.Show then
        pfUI.uf.raid:Show()
    end
    return true
end

-- Compatibility entry point for older callers that already have an authoritative
-- tracker. It only marks previously-unmarked tanks; it never clears/rebuilds the
-- table and never forces RefreshUnit across raid frames.
function SCB_ApplyTrackedPfUITankRoles(tracker)
    local i, assignment, player
    if not tracker or not tracker.ready then return false end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.botName and assignment.role == "tank" then
            SCB_MarkPfUITank(assignment.botName)
        end
    end
    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        if player and player.name and player.role == "tank" then
            SCB_MarkPfUITank(player.name)
        end
    end
    return true
end

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

-- -------------------------------------------------------------------------
-- Combat role detection (absorbed from Detection.lua in 0.8.30).
-- Keep this scoped block to preserve the former file's local namespace.
-- -------------------------------------------------------------------------

do
-- SoloCraft Bots - combat role evidence and preset role-status indicators.
--
-- Vanilla 1.12 has no modern combat-log API. FillRaidBots demonstrates the
-- reliable old-client pattern: listen to CHAT_MSG_SPELL_* combat text, extract
-- the acting group member from arg1, and classify recognised spell names. SCB
-- keeps that proven transport but treats each observation as one evidence step.
-- Two observations are required before confirmedRole is set.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.roleEvidenceByName = SCB.roleEvidenceByName or {}
SCB.roleEvidenceRecent = SCB.roleEvidenceRecent or {}
SCB.ROLE_CONFIRM_THRESHOLD = 2

-- Vanilla-only subset of FRB's spell/role catalogue. Later-expansion entries
-- (for example Lava Lash, Crusader Strike, Steady Shot, Incinerate) are
-- deliberately excluded. These are evidence, not class locks: every role keeps
-- its own score and the strongest score wins once it reaches the threshold.
local SCB_ROLE_SPELLS = {
    warrior = {
        { "Defensive Stance", "tank" },
        { "Sunder Armor", "tank" },
        { "Taunt", "tank" },
        { "Revenge", "tank" },
        { "Shield Wall", "tank" },
        { "Last Stand", "tank" },
        { "Shield Block", "tank" },
        { "Mocking Blow", "tank" },
        { "Shield Slam", "tank" },
        { "Mortal Strike", "meleedps" },
        { "Bloodthirst", "meleedps" },
        { "Whirlwind", "meleedps" },
    },
    priest = {
        { "Greater Heal", "healer" },
        { "Prayer of Healing", "healer" },
        { "Flash Heal", "healer" },
        { "Power Word: Shield", "healer" },
        { "Holy Nova", "healer" },
        { "Heal", "healer" },
        { "Shadow Word: Pain", "rangedps" },
        { "Mind Blast", "rangedps" },
        { "Mind Flay", "rangedps" },
        { "Shadowform", "rangedps" },
        { "Vampiric Embrace", "rangedps" },
    },
    druid = {
        { "Dire Bear Form", "tank" },
        { "Bear Form", "tank" },
        { "Maul", "tank" },
        { "Growl", "tank" },
        { "Swipe", "tank" },
        { "Cat Form", "meleedps" },
        { "Rake", "meleedps" },
        { "Ferocious Bite", "meleedps" },
        { "Shred", "meleedps" },
        { "Healing Touch", "healer" },
        { "Regrowth", "healer" },
        { "Rejuvenation", "healer" },
        { "Tranquility", "healer" },
        { "Swiftmend", "healer" },
        { "Starfire", "rangedps" },
        { "Moonfire", "rangedps" },
        { "Hurricane", "rangedps" },
        { "Wrath", "rangedps" },
    },
    shaman = {
        { "Healing Wave", "healer" },
        { "Chain Heal", "healer" },
        { "Lesser Healing Wave", "healer" },
        { "Lightning Bolt", "rangedps" },
        { "Chain Lightning", "rangedps" },
        { "Earth Shock", "rangedps" },
        { "Flame Shock", "rangedps" },
        { "Stormstrike", "meleedps" },
        { "Windfury Weapon", "meleedps" },
    },
    paladin = {
        { "Holy Light", "healer" },
        { "Flash of Light", "healer" },
        { "Holy Shock", "healer" },
        { "Righteous Fury", "tank" },
        { "Holy Shield", "tank" },
        { "Seal of Command", "meleedps" },
        { "Judgement of Command", "meleedps" },
    },
    mage = {
        { "Arcane Missiles", "rangedps" },
        { "Arcane Power", "rangedps" },
        { "Arcane Explosion", "rangedps" },
        { "Fireball", "rangedps" },
        { "Frostbolt", "rangedps" },
        { "Ice Armor", "rangedps" },
        { "Blizzard", "rangedps" },
        { "Pyroblast", "rangedps" },
        { "Frost Nova", "rangedps" },
        { "Cone of Cold", "rangedps" },
        { "Scorch", "rangedps" },
        { "Flamestrike", "rangedps" },
        { "Fire Blast", "rangedps" },
        { "Ice Block", "rangedps" },
    },
    warlock = {
        { "Shadow Bolt", "rangedps" },
        { "Corruption", "rangedps" },
        { "Immolate", "rangedps" },
        { "Siphon Life", "rangedps" },
        { "Curse of Agony", "rangedps" },
        { "Curse of Doom", "rangedps" },
        { "Rain of Fire", "rangedps" },
        { "Life Tap", "rangedps" },
        { "Hellfire", "rangedps" },
        { "Shadowburn", "rangedps" },
        { "Death Coil", "rangedps" },
        { "Drain Soul", "rangedps" },
        { "Drain Life", "rangedps" },
    },
    rogue = {
        { "Stealth", "meleedps" },
        { "Backstab", "meleedps" },
        { "Sinister Strike", "meleedps" },
        { "Eviscerate", "meleedps" },
        { "Ambush", "meleedps" },
        { "Slice and Dice", "meleedps" },
        { "Gouge", "meleedps" },
        { "Hemorrhage", "meleedps" },
        { "Rupture", "meleedps" },
        { "Kidney Shot", "meleedps" },
        { "Expose Armor", "meleedps" },
        { "Sprint", "meleedps" },
        { "Vanish", "meleedps" },
        { "Distract", "meleedps" },
        { "Preparation", "meleedps" },
        { "Blind", "meleedps" },
    },
    hunter = {
        { "Aimed Shot", "rangedps" },
        { "Multi-Shot", "rangedps" },
        { "Arcane Shot", "rangedps" },
        { "Serpent Sting", "rangedps" },
        { "Scatter Shot", "rangedps" },
        { "Feign Death", "rangedps" },
        { "Rapid Fire", "rangedps" },
        { "Viper Sting", "rangedps" },
        { "Hunter's Mark", "rangedps" },
        { "Volley", "rangedps" },
    },
}

local SCB_COMBAT_SOURCE_PATTERNS = {
    "^(.-) begins to cast",
    "^(.-) casts",
    "^(.-)'s ",
    "^(.-) gains",
    "^(.-) deals",
    "^(.-) hits",
    "^(.-) heals",
    "^(.-) crits",
}

local function SCB_NormalizeCombatName(name)
    local result, i, char
    if type(name) ~= "string" then return nil end
    result = ""
    for i = 1, string.len(name) do
        char = string.sub(name, i, i)
        if (char >= "a" and char <= "z") or (char >= "A" and char <= "Z")
            or (char >= "0" and char <= "9") or char == "*" then
            result = result .. string.lower(char)
        end
    end
    if result == "" then return nil end
    return result
end

local function SCB_ExtractCombatSource(text)
    local i, _, _, name
    if type(text) ~= "string" then return nil end
    for i = 1, table.getn(SCB_COMBAT_SOURCE_PATTERNS) do
        _, _, name = string.find(text, SCB_COMBAT_SOURCE_PATTERNS[i])
        if name and name ~= "" then return name end
    end
    return nil
end

local function SCB_FindLiveBotForCombatSource(sourceName)
    local wanted = SCB_NormalizeCombatName(sourceName)
    local roster = SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil
    local members = roster and roster.members or {}
    local i, member, classFile
    if not wanted then return nil, nil end

    for i = 1, table.getn(members) do
        member = members[i]
        if member and member.isBot and member.name
            and SCB_NormalizeCombatName(member.name) == wanted then
            classFile = member.classFile
            if not classFile and UnitClass and member.unit then
                local unused
                unused, classFile = UnitClass(member.unit)
            end
            return member.name, classFile and string.lower(classFile) or nil
        end
    end
    return nil, nil
end

local function SCB_FindRoleSpell(classKey, text)
    local list = classKey and SCB_ROLE_SPELLS[classKey] or nil
    local i, entry
    if not list or type(text) ~= "string" then return nil, nil end
    for i = 1, table.getn(list) do
        entry = list[i]
        if string.find(text, entry[1], 1, true) then return entry[1], entry[2] end
    end
    return nil, nil
end

local function SCB_CopyRoleScores(scores)
    local copy, role = {}, nil
    for role, value in pairs(scores or {}) do copy[role] = value end
    return copy
end

local function SCB_GetAssumedRoleForName(name)
    local assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    local slot
    if assumption and assumption.spawnKind ~= "bootstrap" and assumption.role then
        return assumption.role
    end
    if SCB_GetActiveSlotByName then
        slot = SCB_GetActiveSlotByName(name)
        if slot then return slot.assumedRole or slot.role end
    end
    return nil
end

local function SCB_ResolveEvidenceCandidate(name, state)
    local assumedRole = SCB_GetAssumedRoleForName(name)
    local bestRole, bestScore, role, score = nil, -1, nil, 0

    for role, score in pairs(state.byRole or {}) do
        if score > bestScore then
            bestRole, bestScore = role, score
        elseif score == bestScore and role == assumedRole then
            bestRole = role
        end
    end

    state.candidateRole = bestRole
    state.candidateScore = bestScore > 0 and bestScore or 0
    if bestRole and bestScore >= SCB.ROLE_CONFIRM_THRESHOLD then
        state.confirmedRole = bestRole
    end
end

function SCB_GetBotRoleEvidence(name)
    return name and SCB.roleEvidenceByName[name] or nil
end

function SCB_GetBotRoleEvidenceStage(name, role)
    local state = SCB_GetBotRoleEvidence(name)
    local score
    if not state or not role then return 0 end
    if state.confirmedRole == role then return SCB.ROLE_CONFIRM_THRESHOLD end
    score = state.byRole and state.byRole[role] or 0
    if score > SCB.ROLE_CONFIRM_THRESHOLD then score = SCB.ROLE_CONFIRM_THRESHOLD end
    return score
end

local function SCB_SyncEvidenceToActiveSlot(name, state)
    local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
    if not slot then return end
    slot.roleEvidence = SCB_CopyRoleScores(state.byRole)
    slot.confirmedRole = state.confirmedRole
    if state.confirmedRole then slot.role = state.confirmedRole end
    slot.detected = state.confirmedRole and true or nil
    slot.updatedAt = GetTime and GetTime() or 0
end

local function SCB_IsDuplicateRoleObservation(name, spell)
    local now = GetTime and GetTime() or 0
    local key = tostring(name) .. "\031" .. tostring(spell)
    local previous, recentKey, seenAt
    previous = SCB.roleEvidenceRecent[key]
    SCB.roleEvidenceRecent[key] = now
    SCB.roleEvidenceRecentCount = (SCB.roleEvidenceRecentCount or 0) + 1
    if SCB.roleEvidenceRecentCount >= 100 then
        SCB.roleEvidenceRecentCount = 0
        for recentKey, seenAt in pairs(SCB.roleEvidenceRecent) do
            if (now - (seenAt or 0)) > 5 then SCB.roleEvidenceRecent[recentKey] = nil end
        end
    end
    return previous and (now - previous) < 0.30
end

function SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
    local state, oldConfirmed, score
    if not name or not classKey or not role or not spell then return false end
    if SCB_IsDuplicateRoleObservation(name, spell) then return false end

    state = SCB.roleEvidenceByName[name]
    if not state then
        state = { class = classKey, byRole = {}, observations = 0 }
        SCB.roleEvidenceByName[name] = state
    end
    if state.class and state.class ~= classKey then return false end

    oldConfirmed = state.confirmedRole
    state.class = classKey
    state.byRole[role] = (state.byRole[role] or 0) + 1
    state.observations = (state.observations or 0) + 1
    state.lastSpell = spell
    state.lastEvent = eventName
    state.updatedAt = GetTime and GetTime() or 0
    SCB_ResolveEvidenceCandidate(name, state)
    SCB_SyncEvidenceToActiveSlot(name, state)

    score = state.byRole[role] or 0
    if SCB.developerDebugEnabled and SCB_DebugLog then
        SCB_DebugLog("Detection", name .. " " .. classKey .. " " .. role
            .. " " .. spell .. " evidence=" .. tostring(score)
            .. " candidate=" .. tostring(state.candidateRole or "?")
            .. " confirmed=" .. tostring(state.confirmedRole or "?"))
    end

    local liveMember = SCB.liveRoster and SCB.liveRoster.byName and SCB.liveRoster.byName[name] or nil
    if liveMember then
        liveMember.roleEvidence = state.byRole
        liveMember.confirmedRole = state.confirmedRole
        liveMember.roleCandidate = state.candidateRole
        liveMember.resolvedRole = SCB_GetResolvedLiveRole and SCB_GetResolvedLiveRole(liveMember) or (state.confirmedRole or liveMember.assumedRole)
    end
    if SCB_QueuePresetRoleIndicatorsRefresh then
        SCB_QueuePresetRoleIndicatorsRefresh(0.05)
    elseif SCB_RefreshPresetRoleIndicators then
        SCB_RefreshPresetRoleIndicators()
    end

    return oldConfirmed ~= state.confirmedRole
end

function SCB_HandleRoleCombatText(text, eventName)
    local source, name, classKey, spell, role
    if type(text) ~= "string" or text == "" then return false end
    if string.find(text, "gains %d+ Mana") or string.find(text, "gains %d+ Rage")
        or string.find(text, "gains %d+ Energy") then
        return false
    end

    source = SCB_ExtractCombatSource(text)
    if not source then return false end
    name, classKey = SCB_FindLiveBotForCombatSource(source)
    if not name or not classKey then return false end

    spell, role = SCB_FindRoleSpell(classKey, text)
    if not spell or not role then return false end
    SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
    return true
end

-- -------------------------------------------------------------------------
-- Active Roster role semantics
-- -------------------------------------------------------------------------

function SCB_UpdateActiveBotDetection(name, role, extra, extraKnown)
    local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
    local assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    if not slot then return false end

    slot.assumedRole = slot.assumedRole or (assumption and assumption.role) or slot.role
    if role then
        slot.confirmedRole = role
        slot.role = role
    end
    if extraKnown then slot.extra = extra end
    slot.detected = role and true or slot.detected
    slot.updatedAt = GetTime and GetTime() or 0
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end


-- -------------------------------------------------------------------------
-- Associate name-linked spawn assumptions with preset rows for the first tick.
-- -------------------------------------------------------------------------

local function SCB_CurrentSlotMatchesTrackerAssignment(slotIndex, assignment)
    local slot = SCB.presetEditorSlots and SCB.presetEditorSlots[slotIndex] or nil
    local aExtra, sExtra
    if not slot or not assignment then return false end
    if slot.class ~= assignment.class or slot.role ~= assignment.role then return false end
    aExtra = assignment.extra or ""
    sExtra = slot.extra or ""
    return aExtra == sExtra
end

function SCB_LinkAssumptionsToTrackerSlots()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local used, i, assignment, name, intent, chosenName, chosenAt
    if not tracker or not tracker.assignments then return end
    used = {}

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        name = assignment and assignment.scbAssumedName or nil
        intent = name and SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
        if assignment and assignment.initialActive and intent
            and intent.spawnKind ~= "bootstrap" and intent.command == assignment.command then
            used[name] = true
        elseif assignment then
            assignment.scbAssumedName = nil
        end
    end

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and not assignment.scbAssumedName then
            chosenName, chosenAt = nil, nil
            for name, intent in pairs(SCB.assumedRolesByName or {}) do
                if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                    and intent.command == assignment.command then
                    if not chosenAt or (intent.boundAt or 0) < chosenAt then
                        chosenName = name
                        chosenAt = intent.boundAt or 0
                    end
                end
            end
            if chosenName then
                assignment.scbAssumedName = chosenName
                used[chosenName] = true
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- Preset role-icon overlays
-- -------------------------------------------------------------------------

local SCB_CONFIRM_COLORS = {
    [0] = { 1.00, 0.10, 0.10 },
    [1] = { 1.00, 0.90, 0.00 },
    [2] = { 0.20, 1.00, 0.20 },
}

local function SCB_UpdatePresetRoleIndicatorGeometry(row)
    local roleSize, tickSize, overlap, confirmedOffset
    if not row or not row.roleButton or not row.scbAssumedTick or not row.scbConfirmedTick then return end

    roleSize = SCB_GetLayoutValue and SCB_GetLayoutValue("preset", "roleSize") or 24
    if roleSize < 1 then roleSize = 1 end
    if row.scbRoleIndicatorRoleSize == roleSize then return end
    row.scbRoleIndicatorRoleSize = roleSize
    tickSize = math.floor((roleSize * 0.375) + 0.5)
    if tickSize < 4 then tickSize = 4 end
    overlap = math.floor((tickSize * 0.22) + 0.5)
    if overlap < 1 then overlap = 1 end
    confirmedOffset = tickSize - overlap

    row.scbAssumedTick:SetWidth(tickSize)
    row.scbAssumedTick:SetHeight(tickSize)
    row.scbAssumedTick:ClearAllPoints()
    row.scbAssumedTick:SetPoint("BOTTOMRIGHT", row.roleButton, "BOTTOMRIGHT", 0, 0)

    row.scbConfirmedTick:SetWidth(tickSize)
    row.scbConfirmedTick:SetHeight(tickSize)
    row.scbConfirmedTick:ClearAllPoints()
    row.scbConfirmedTick:SetPoint("BOTTOMRIGHT", row.roleButton, "BOTTOMRIGHT", -confirmedOffset, 0)
end

local function SCB_CreatePresetRoleIndicatorPair(row)
    local assumed, confirmed
    if not row or not row.roleButton then return end
    if row.scbAssumedTick and row.scbConfirmedTick then return end

    assumed = row.roleButton:CreateTexture(nil, "OVERLAY")
    assumed:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    assumed:SetVertexColor(0.20, 1.00, 0.20)
    assumed:Hide()
    row.scbAssumedTick = assumed

    confirmed = row.roleButton:CreateTexture(nil, "OVERLAY")
    confirmed:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    confirmed:Hide()
    row.scbConfirmedTick = confirmed

    SCB_UpdatePresetRoleIndicatorGeometry(row)
end

local function SCB_BuildTrackerAssignmentIndicatorIndex()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local bySlot, i, assignment
    if not tracker or not tracker.assignments then return nil, tracker end
    if tracker.size and SCB_CurrentPresetSize and tracker.size ~= SCB_CurrentPresetSize() then return nil, tracker end
    bySlot = {}
    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.slotIndex then bySlot[assignment.slotIndex] = assignment end
    end
    return bySlot, tracker
end

local function SCB_FindTrackerAssignmentForIndicator(slotIndex, bySlot)
    local assignment = bySlot and bySlot[slotIndex] or nil
    if assignment and assignment.initialActive
        and SCB_CurrentSlotMatchesTrackerAssignment(slotIndex, assignment) then
        return assignment
    end
    return nil
end

local function SCB_GetIndicatorBotName(assignment)
    local name, intent, member
    if not assignment then return nil end
    name = assignment.scbAssumedName or assignment.botName
    if not name then return nil end

    intent = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
    if intent and intent.spawnKind ~= "bootstrap" then return name end

    member = SCB_GetLiveMember and SCB_GetLiveMember(name, false) or nil
    if member and member.isBot and member.assumedRole then return name end
    return nil
end

function SCB_IsRoleDetectionEnabled()
    SoloCraftBotsDB = SoloCraftBotsDB or {}
    SoloCraftBotsDB.options = SoloCraftBotsDB.options or {}
    if SoloCraftBotsDB.options.confirmBotRolesFromCombat == nil then
        SoloCraftBotsDB.options.confirmBotRolesFromCombat = false
    end
    return SoloCraftBotsDB.options.confirmBotRolesFromCombat == true
end

function SCB_RefreshPresetRoleIndicators()
    local size = SCB_CurrentPresetSize and SCB_CurrentPresetSize() or 0
    local assignmentBySlot
    local detectionEnabled = SCB_IsRoleDetectionEnabled()
    local i, row, assignment, name, stage, color

    if not SCB.presetPanel or not SCB.presetPanel:IsShown() then
        SCB.presetRoleIndicatorsDirty = true
        return
    end
    SCB.presetRoleIndicatorsDirty = nil
    assignmentBySlot = SCB_BuildTrackerAssignmentIndicatorIndex()

    for i = 1, 40 do
        row = SCB.presetSlotRows and SCB.presetSlotRows[i] or nil
        if row then
            SCB_CreatePresetRoleIndicatorPair(row)
            SCB_UpdatePresetRoleIndicatorGeometry(row)
            if row.scbAssumedTick then row.scbAssumedTick:Hide() end
            if row.scbConfirmedTick then row.scbConfirmedTick:Hide() end

            if detectionEnabled and i <= size and not row.scbPresentPlayerKey then
                assignment = SCB_FindTrackerAssignmentForIndicator(i, assignmentBySlot)
                name = SCB_GetIndicatorBotName(assignment)
                if assignment and name then
                    row.scbAssumedTick:Show()
                    stage = SCB_GetBotRoleEvidenceStage(name, assignment.role)
                    if stage <= 0 then
                        local slot = SCB_GetActiveSlotByName and SCB_GetActiveSlotByName(name) or nil
                        local scores = slot and slot.roleEvidence or nil
                        stage = scores and scores[assignment.role] or 0
                        if slot and slot.confirmedRole == assignment.role then stage = SCB.ROLE_CONFIRM_THRESHOLD end
                    end
                    if stage < 0 then stage = 0 end
                    if stage > SCB.ROLE_CONFIRM_THRESHOLD then stage = SCB.ROLE_CONFIRM_THRESHOLD end
                    color = SCB_CONFIRM_COLORS[stage] or SCB_CONFIRM_COLORS[0]
                    row.scbConfirmedTick:SetVertexColor(color[1], color[2], color[3])
                    row.scbConfirmedTick:Show()
                end
            end
        end
    end
end

function SCB_QueuePresetRoleIndicatorsRefresh(delay)
    local frame
    SCB.presetRoleIndicatorsDirty = true
    if not SCB.presetPanel or not SCB.presetPanel:IsShown() then return end

    frame = SCB.presetRoleIndicatorRefreshFrame
    if not frame then
        frame = CreateFrame("Frame", "SoloCraftBotsPresetRoleIndicatorRefreshFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0.15) then return end
            this.scbElapsed = 0
            this:Hide()
            SCB_RefreshPresetRoleIndicators()
        end)
        SCB.presetRoleIndicatorRefreshFrame = frame
    end
    frame.scbDelay = delay or 0.15
    frame.scbElapsed = 0
    frame:Show()
end

local SCB_OriginalCreatePresetUI_Detection = SCB_CreatePresetUI
if SCB_OriginalCreatePresetUI_Detection then
    function SCB_CreatePresetUI(frame)
        local result = SCB_OriginalCreatePresetUI_Detection(frame)
        SCB_RefreshPresetRoleIndicators()
        return result
    end
end

local SCB_OriginalRefreshPresetSlots_Detection = SCB_RefreshPresetSlots
if SCB_OriginalRefreshPresetSlots_Detection then
    function SCB_RefreshPresetSlots()
        local result = SCB_OriginalRefreshPresetSlots_Detection()
        SCB_RefreshPresetRoleIndicators()
        return result
    end
end

-- -------------------------------------------------------------------------
-- Optional combat-role confirmation lifecycle
-- -------------------------------------------------------------------------

local detectionFrame = CreateFrame("Frame", "SoloCraftBotsRoleDetectionEventFrame", UIParent)
local SCB_DETECTION_EVENTS = {
    "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_PARTY_BUFF",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
    "CHAT_MSG_SPELL_CAST_START",
    "CHAT_MSG_SPELL_CAST_SUCCESS",
    "CHAT_MSG_SPELL_DAMAGE",
    "CHAT_MSG_SPELL_HEAL",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_COMBAT_PARTY_HITS",
}

local function SCB_EnsureRoleDetectionOption()
    return SCB_IsRoleDetectionEnabled()
end

local function SCB_LiveBotNeedsRoleConfirmation(member)
    local slot
    if not member or not member.isBot or member.spawnKind == "bootstrap" then return false end
    if member.confirmedRole then return false end
    if member.assumedRole then return true end

    if SCB_GetActiveSlotByName and member.name then
        slot = SCB_GetActiveSlotByName(member.name)
        if slot and (slot.assumedRole or slot.role) then
            return slot.confirmedRole == nil
        end
    end
    return false
end

local function SCB_RebuildRoleDetectionPendingNames(observed)
    local roster = observed or (SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil)
    local pending = {}
    local i, member, key

    for i = 1, table.getn(roster and roster.members or {}) do
        member = roster.members[i]
        if SCB_LiveBotNeedsRoleConfirmation(member) then
            key = SCB_NormalizeCombatName(member.name)
            if key then pending[key] = true end
        end
    end
    SCB.roleDetectionPendingNames = pending
    return next(pending) ~= nil
end

local function SCB_SetRoleDetectionEventsEnabled(enabled, reason)
    local i
    enabled = enabled == true
    if SCB.roleDetectionEventsEnabled == enabled then return end

    if enabled then
        for i = 1, table.getn(SCB_DETECTION_EVENTS) do
            detectionFrame:RegisterEvent(SCB_DETECTION_EVENTS[i])
        end
    else
        for i = 1, table.getn(SCB_DETECTION_EVENTS) do
            detectionFrame:UnregisterEvent(SCB_DETECTION_EVENTS[i])
        end
    end
    SCB.roleDetectionEventsEnabled = enabled

    if SCB.developerDebugEnabled and SCB_DebugLog then
        SCB_DebugLog("Detection", enabled and "Combat role scanning enabled" or (reason or "Combat role scanning sleeping"))
    end
end

function SCB_RefreshRoleDetectionLifecycle(observed)
    local enabled = SCB_EnsureRoleDetectionOption()
    local pending

    if not enabled then
        SCB.roleDetectionPendingNames = {}
        SCB_SetRoleDetectionEventsEnabled(false, "Combat role scanning disabled by option")
        return
    end

    pending = SCB_RebuildRoleDetectionPendingNames(observed)
    SCB_SetRoleDetectionEventsEnabled(pending, "Combat role scanning sleeping; all tracked bots confirmed")
end

function SCB_QueueRoleDetectionLifecycleRefresh(delay)
    local frame
    if not SCB_EnsureRoleDetectionOption() then return end
    frame = SCB.roleDetectionLifecycleRefreshFrame
    if not frame then
        frame = CreateFrame("Frame", "SoloCraftBotsRoleDetectionLifecycleRefreshFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0.15) then return end
            this.scbElapsed = 0
            this:Hide()
            SCB_RefreshRoleDetectionLifecycle(SCB.liveRoster)
        end)
        SCB.roleDetectionLifecycleRefreshFrame = frame
    end
    frame.scbDelay = delay or 0.15
    frame.scbElapsed = 0
    frame:Show()
end

local function SCB_CombatSourceNeedsRoleConfirmation(text)
    local source = SCB_ExtractCombatSource(text)
    local key = SCB_NormalizeCombatName(source)
    return key and SCB.roleDetectionPendingNames and SCB.roleDetectionPendingNames[key] == true
end

local SCB_PreviousHandleRoleCombatText_Lifecycle = SCB_HandleRoleCombatText
function SCB_HandleRoleCombatText(text, eventName)
    if not SCB_EnsureRoleDetectionOption() then return false end
    if not SCB_CombatSourceNeedsRoleConfirmation(text) then return false end
    return SCB_PreviousHandleRoleCombatText_Lifecycle(text, eventName)
end

local SCB_PreviousAddBotRoleEvidence_Lifecycle = SCB_AddBotRoleEvidence
function SCB_AddBotRoleEvidence(name, classKey, role, spell, eventName)
    local changed = SCB_PreviousAddBotRoleEvidence_Lifecycle(name, classKey, role, spell, eventName)
    if changed then SCB_RefreshRoleDetectionLifecycle(SCB.liveRoster) end
    return changed
end

detectionFrame:SetScript("OnEvent", function()
    if arg1 then SCB_HandleRoleCombatText(arg1, event) end
end)

SCB.roleDetectionEventsEnabled = false
SCB_EnsureRoleDetectionOption()
SCB_RefreshRoleDetectionLifecycle()
end


-- -------------------------------------------------------------------------
-- Preset player ownership (absorbed from RaidPlayers.lua in 0.8.31).
-- Keep this scoped block to preserve the former file local namespace.
-- -------------------------------------------------------------------------

do
-- SoloCraft Bots - exact logical human-slot ownership and execution snapshots.
--
-- A preset slot is composition intent. Blizzard's physical raid row is live
-- observation only and must never decide which bot a human suppresses.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}

local function SCB_CopyExactPlayerSlots(source, size)
    local copy = {}
    local key, slot
    size = tonumber(size) or 0
    for key, slot in pairs(source or {}) do
        if type(key) == "string" and type(slot) == "number"
            and slot >= 1 and slot <= size then
            copy[key] = slot
        end
    end
    return copy
end

local function SCB_PlayerSlotGroup(slotIndex)
    if not slotIndex then return nil end
    return math.floor((slotIndex - 1) / 5) + 1
end

-- -------------------------------------------------------------------------
-- Logical human layout
-- -------------------------------------------------------------------------

function SCB_GetPresetHumanLayout()
    local size = SCB_CurrentPresetSize()
    local roster = SCB_GetHumanRoster()
    local present, assignedPresent, playerRows = {}, {}, {}
    local used = {}
    local i, info, key, slotIndex

    for i = 1, table.getn(roster) do present[roster[i].key] = roster[i] end

    if size <= 5 then
        local auto = SCB_AutoPartyPlayerSlots(roster)
        for key, slotIndex in pairs(auto) do
            if present[key] and slotIndex >= 1 and slotIndex <= size then
                playerRows[key] = slotIndex
                assignedPresent[key] = true
            end
        end
        return roster, present, playerRows, assignedPresent
    end

    -- Raid presets render only explicit logical assignments. Present humans with
    -- no exact saved/working slot remain in Other Players until the user assigns
    -- them. Blizzard's current subgroup row never fills this table.
    for i = 1, table.getn(roster) do
        info = roster[i]
        slotIndex = SCB.presetEditorPlayerSlots and SCB.presetEditorPlayerSlots[info.key] or nil
        if slotIndex and slotIndex >= 1 and slotIndex <= size and not used[slotIndex] then
            playerRows[info.key] = slotIndex
            assignedPresent[info.key] = true
            used[slotIndex] = true
        end
    end

    return roster, present, playerRows, assignedPresent
end

function SCB_AssignPresetPlayer(key, slotIndex)
    local size = SCB_CurrentPresetSize()
    local groupIndex, otherKey, otherSlot
    if size <= 5 or not key or not slotIndex or slotIndex < 1 or slotIndex > size then return false end

    SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
    SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}

    -- Never silently displace another saved human assignment. The user can
    -- explicitly remove/move that player first.
    for otherKey, otherSlot in pairs(SCB.presetEditorPlayerSlots) do
        if otherKey ~= key and otherSlot == slotIndex then return false end
    end

    groupIndex = SCB_PlayerSlotGroup(slotIndex)
    SCB.presetEditorPlayerSlots[key] = slotIndex
    SCB.presetEditorPlayers[key] = groupIndex
    if SCB_SetPresetDirty then SCB_SetPresetDirty(true) else SCB.presetDirty = true end
    return true
end

-- Exact slot drops replace the old group-frame drop semantics for raids.
function SCB_FinishPresetPlayerDrag(slotIndex)
    local key = SCB.draggedPresetPlayer
    if not key then return false end

    SCB.draggedPresetPlayer = nil
    SCB.draggedPresetPlayerOriginSlot = nil
    SCB_HideDragGhost()
    SCB.draggedPresetPlayerHoverGroup = nil
    SCB_SetPresetGroupDragHighlight(nil)

    if slotIndex then SCB_AssignPresetPlayer(key, slotIndex) end

    SCB_RefreshPresetSlots()
    if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
    return true
end

-- Mouse-up resolves the exact preset row beneath the cursor. Dropping onto the
-- group background alone is intentionally not enough: a human must replace one
-- specific logical bot slot.
function SCB_PresetPlayerDragStop()
    local i, row
    if not SCB.draggedPresetPlayer or SCB_CurrentPresetSize() <= 5 then return end
    for i = 1, SCB_CurrentPresetSize() do
        row = SCB.presetDropTargets and SCB.presetDropTargets[i] or nil
        if row and SCB_FrameContainsCursor(row) then
            SCB_FinishPresetPlayerDrag(i)
            return
        end
    end
    SCB_FinishPresetPlayerDrag(nil)
end

local SCB_PreviousPresetPlayerOnClick_Logical = SCB_PresetPlayerOnClick
if SCB_PreviousPresetPlayerOnClick_Logical then
    function SCB_PresetPlayerOnClick()
        local key = this and this.scbPlayerKey or nil
        local slotIndex = this and this.scbSlotIndex or nil
        local remove = arg1 == "RightButton" and key and key ~= "$self"
            and SCB_CurrentPresetSize() > 5

        if SCB.draggedPresetPlayer and slotIndex then
            SCB_FinishPresetPlayerDrag(slotIndex)
            return
        end

        local result = SCB_PreviousPresetPlayerOnClick_Logical()
        if remove and SCB.presetEditorPlayers and not SCB.presetEditorPlayers[key] then
            SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
            SCB.presetEditorPlayerSlots[key] = nil
        end
        return result
    end
end

-- -------------------------------------------------------------------------
-- Preset persistence
-- -------------------------------------------------------------------------

local SCB_PreviousLoadPreset_Logical = SCB_LoadPreset
if SCB_PreviousLoadPreset_Logical then
    function SCB_LoadPreset(groupIndex, presetIndex)
        local group, preset, size, key, slotIndex
        SCB.presetEditorPlayerSlots = {}
        SCB_PreviousLoadPreset_Logical(groupIndex, presetIndex)

        group = SCB_CurrentPresetGroup()
        preset = SCB_CurrentPreset()
        size = group and group.size or SCB_CurrentPresetSize()
        SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(preset and preset.playerSlots or nil, size)

        -- Exact slot is authoritative; group is retained as derived compatibility
        -- data for existing arrangement/snapshot code during consolidation.
        SCB.presetEditorPlayers = SCB.presetEditorPlayers or {}
        for key, slotIndex in pairs(SCB.presetEditorPlayerSlots) do
            SCB.presetEditorPlayers[key] = SCB_PlayerSlotGroup(slotIndex)
        end
        if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
    end
end

local SCB_PreviousSaveCurrentPreset_Logical = SCB_SaveCurrentPreset
if SCB_PreviousSaveCurrentPreset_Logical then
    function SCB_SaveCurrentPreset()
        local exact = SCB_CopyExactPlayerSlots(SCB.presetEditorPlayerSlots, SCB_CurrentPresetSize())
        local result = SCB_PreviousSaveCurrentPreset_Logical()
        local preset = SCB_CurrentPreset()
        if preset then
            preset.playerSlots = exact
            SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
        end
        return result
    end
end

local SCB_PreviousAcceptPresetName_Logical = SCB_AcceptPresetName
if SCB_PreviousAcceptPresetName_Logical then
    function SCB_AcceptPresetName(dialog)
        local exact = SCB_CopyExactPlayerSlots(SCB.presetEditorPlayerSlots, SCB_CurrentPresetSize())
        local result = SCB_PreviousAcceptPresetName_Logical(dialog)
        local preset = SCB_CurrentPreset()
        if preset then
            preset.playerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            SCB.presetEditorPlayerSlots = SCB_CopyExactPlayerSlots(exact, SCB_CurrentPresetSize())
            if SCB_RefreshPresetPlayers then SCB_RefreshPresetPlayers() end
        end
        return result
    end
end

-- -------------------------------------------------------------------------
-- Execution snapshots
-- -------------------------------------------------------------------------

local SCB_PreLogicalGetSnapshotOccupiedSlots = SCB_GetSnapshotOccupiedSlots
function SCB_GetSnapshotOccupiedSlots(snapshot)
    local occupied, groupNext = {}, {}
    local i, player, groupIndex, slotIndex, groupStart, groupEnd

    if not snapshot or (snapshot.size or 0) <= 5 then
        return SCB_PreLogicalGetSnapshotOccupiedSlots(snapshot)
    end

    -- Exact logical human slots win. Compatibility snapshots that provide only
    -- a subgroup retain the old group-front occupancy behavior; new local raid
    -- snapshots always carry an exact logical slot.
    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        slotIndex = player and player.slotIndex or nil
        if slotIndex and slotIndex >= 1 and slotIndex <= snapshot.size then
            occupied[slotIndex] = true
        end
    end

    for i = 1, table.getn(snapshot.players or {}) do
        player = snapshot.players[i]
        if player and not player.slotIndex then
            groupIndex = player.group
            if groupIndex then
                groupStart = ((groupIndex - 1) * 5) + 1
                groupEnd = math.min(groupStart + 4, snapshot.size)
                slotIndex = groupNext[groupIndex] or groupStart
                while slotIndex <= groupEnd and occupied[slotIndex] do
                    slotIndex = slotIndex + 1
                end
                if slotIndex <= groupEnd then
                    occupied[slotIndex] = true
                    groupNext[groupIndex] = slotIndex + 1
                end
            end
        end
    end
    return occupied
end

local SCB_PreLogicalValidatePresetExecutionSnapshot = SCB_ValidatePresetExecutionSnapshot
if SCB_PreLogicalValidatePresetExecutionSnapshot then
    function SCB_ValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
        local valid, errorText = SCB_PreLogicalValidatePresetExecutionSnapshot(snapshot, requireCurrentRoster)
        local seenSlots = {}
        local i, player, slotIndex, expectedGroup
        if not valid then return valid, errorText end
        if not snapshot or (snapshot.size or 0) <= 5 then return valid, errorText end

        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            slotIndex = player and player.slotIndex or nil
            if slotIndex ~= nil then
                if type(slotIndex) ~= "number"
                    or slotIndex < 1 or slotIndex > snapshot.size
                    or seenSlots[slotIndex] then
                    return false, SCB_L("ERR_SNAPSHOT_PLAYERS")
                end
                expectedGroup = SCB_PlayerSlotGroup(slotIndex)
                if expectedGroup ~= player.group then
                    return false, SCB_L("ERR_SNAPSHOT_RAID_GROUP")
                end
                seenSlots[slotIndex] = true
            end
        end
        return true
    end
end

function SCB_BuildPresetExecutionSnapshot()
    local group = SCB_CurrentPresetGroup()
    local preset = SCB_CurrentPreset()
    local size = SCB_CurrentPresetSize()
    local slots, roster, present, playerRows, players, groupCounts = {}, {}, {}, {}, {}, {}
    local i, info, assignedGroup, slotIndex, role, extra, fallbackRole, fallbackExtra
    local snapshot, valid, errorText

    if not group or not preset then
        return nil, SCB_L("ERR_SELECT_PRESET")
    end

    slots = SCB_NormalizePresetSlots(SCB.presetEditorSlots, size)
    for i = 1, size do
        if not SCB_IsValidSpawnAssignment(slots[i].class, slots[i].role, slots[i].extra) then
            return nil, SCB_L("ERR_PRESET_BOT")
        end
    end

    roster, present, playerRows = SCB_GetPresetHumanLayout()

    for i = 1, table.getn(roster) do
        info = roster[i]
        if size > 5 then
            assignedGroup = SCB.presetEditorPlayers and SCB.presetEditorPlayers[info.key]
            slotIndex = playerRows and playerRows[info.key] or nil
            if not assignedGroup then
                return nil, string.format(SCB_L("ERR_ASSIGN_PLAYER"), info.name)
            end
            if assignedGroup < 1 or assignedGroup > math.ceil(size / 5) then
                return nil, SCB_L("ERR_PRESET_PLAYER_GROUP")
            end
            if not slotIndex or SCB_PlayerSlotGroup(slotIndex) ~= assignedGroup then
                return nil, SCB_L("ERR_PARTY_LAYOUT")
            end
            groupCounts[assignedGroup] = (groupCounts[assignedGroup] or 0) + 1
            if groupCounts[assignedGroup] > 5 then
                return nil, string.format(SCB_L("ERR_PRESET_GROUP_FULL"), assignedGroup)
            end
        else
            assignedGroup = 1
            slotIndex = playerRows and playerRows[info.key] or nil
            if not slotIndex then
                return nil, SCB_L("ERR_PARTY_LAYOUT")
            end
        end

        if info.key == "$self" then
            fallbackRole, fallbackExtra = SCB_GetCharacterDefaultRoleSelection()
        else
            fallbackRole = SCB_DefaultPlayerRole(info)
            fallbackExtra = nil
        end
        role, extra = SCB_GetPlayerRoleSelection(
            SCB.presetEditorPlayerRoles and SCB.presetEditorPlayerRoles[info.key] or nil,
            fallbackRole,
            fallbackExtra
        )
        table.insert(players, {
            name = info.name,
            group = assignedGroup,
            slotIndex = slotIndex,
            role = role,
            extra = extra,
        })
    end

    snapshot = {
        protocol = 1,
        groupID = group.id,
        groupName = group.name or SCB_L("PRESET_GROUP_PLACEHOLDER"),
        size = size,
        presetName = preset.name or SCB_L("PRESET_PLACEHOLDER"),
        presetGroupIndex = SoloCraftBotsDB and SoloCraftBotsDB.currentPresetGroup or nil,
        presetIndex = group.currentPreset,
        slots = slots,
        players = players,
        roleCounts = SCB_CalculatePresetRoleCounts(),
    }
    valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    if not valid then return nil, errorText end
    return snapshot
end

local SCB_PreLogicalCreateRaidRoleTracker = SCB_CreateRaidRoleTracker
if SCB_PreLogicalCreateRaidRoleTracker then
    function SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        local tracker = SCB_PreLogicalCreateRaidRoleTracker(slots, size, occupied, group, snapshot)
        if tracker and snapshot then
            tracker.presetGroupIndex = snapshot.presetGroupIndex
            tracker.presetIndex = snapshot.presetIndex
        end
        return tracker
    end
end

end

-- -------------------------------------------------------------------------
-- Explicit spawn identity and live layout (absorbed from RaidIdentity.lua in 0.8.32).
-- Scoped to preserve the former file's local namespace.
-- -------------------------------------------------------------------------

do
-- SoloCraft Bots - explicit spawn identity and late raid-layout reconciliation.
--
-- This remains a transitional late-load owner during 0.8 consolidation.
-- Explicit identity and live Blizzard layout are kept together here because both
-- must currently run after Detection/Spawn wrapper layers. Final ownership is
-- Raid.lua once those load-order wrappers are flattened.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.presetEditorPlayerSlots = SCB.presetEditorPlayerSlots or {}
SCB.scbPresetBurstPlans = SCB.scbPresetBurstPlans or {}
SCB.scbNextBurstID = SCB.scbNextBurstID or 0

local function SCB_GroupLocalSlot(slotIndex)
    if not slotIndex then return nil end
    return math.mod(slotIndex - 1, 5) + 1
end

local function SCB_BurstDebug(text)
    if SCB.developerDebugEnabled and SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- -------------------------------------------------------------------------
-- Explicit spawn identity
-- -------------------------------------------------------------------------

function SCB_BeginAssumedSpawnBurst(plan)
    local i, entry, intent, groupLabel, localSlot
    if not plan or not plan.assignments or table.getn(plan.assignments) == 0 then
        return false
    end

    SCB.pendingAssumedSpawns = SCB.pendingAssumedSpawns or {}
    SCB.scbNextBurstID = (SCB.scbNextBurstID or 0) + 1
    plan.burstID = SCB.scbNextBurstID

    for i = 1, table.getn(plan.assignments) do
        entry = plan.assignments[i]
        if entry then
            intent = {
                command = entry.command,
                class = entry.class,
                role = entry.role,
                extra = entry.extra,
                spawnKind = plan.kind or "preset",
                slotIndex = entry.slotIndex,
                group = entry.group or plan.group,
                burstID = plan.burstID,
                queuedAt = GetTime and GetTime() or 0,
            }
            table.insert(SCB.pendingAssumedSpawns, intent)

            localSlot = SCB_GroupLocalSlot(intent.slotIndex)
            if intent.slotIndex and intent.group then
                groupLabel = "G" .. tostring(intent.group) .. "S" .. tostring(localSlot)
            else
                groupLabel = tostring(plan.kind or "spawn")
            end
            if SCB.developerDebugEnabled then
                SCB_BurstDebug(
                    "Burst " .. tostring(plan.burstID)
                    .. " expect " .. groupLabel
                    .. " " .. tostring(intent.class or "?")
                    .. " " .. tostring(intent.role or "?")
                )
            end
        end
    end
    return true
end

function SCB_HandleAssumedRoleSystemMessage(text)
    local _, _, name
    local intent, localSlot, label
    if not text or text == "" then return false end

    _, _, name = string.find(text, "^([^%s]+%*) joins the party%.$")
    if not name then
        _, _, name = string.find(text, "^([^%s]+%*) has joined the raid group%.?$")
    end
    if not name then return false end

    SCB.assumedRolesByName = SCB.assumedRolesByName or {}
    if SCB.assumedRolesByName[name] then return false end
    if table.getn(SCB.pendingAssumedSpawns or {}) == 0 then return false end

    intent = table.remove(SCB.pendingAssumedSpawns, 1)
    intent.name = name
    intent.boundAt = GetTime and GetTime() or 0
    SCB.assumedRolesByName[name] = intent
    if intent.role == "tank" and intent.spawnKind ~= "bootstrap" and SCB_MarkPfUITank then
        SCB_MarkPfUITank(name)
    end

    localSlot = SCB_GroupLocalSlot(intent.slotIndex)
    if intent.slotIndex and intent.group then
        label = "G" .. tostring(intent.group) .. "S" .. tostring(localSlot)
    else
        label = tostring(intent.spawnKind or "spawn")
    end
    if SCB.developerDebugEnabled then
        SCB_BurstDebug(
        "Burst " .. tostring(intent.burstID or "?")
        .. " joined " .. tostring(name)
        .. " -> " .. label
        .. " " .. tostring(intent.class or "?")
        .. " " .. tostring(intent.role or "?")
    )
    end
    return true
end

function SCB_ReconcileTrackerFromAssumedRoles(tracker, observed)
    local roster, used, replacements = nil, {}, {}
    local i, j, assignment, member, assumption, matchedName

    if not tracker or not tracker.ready then return false end
    if tracker.scbRoleIdentityReconciled then return false end

    roster = observed or (SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil)
    if not roster then return false end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive then
            matchedName = nil

            for j = 1, table.getn(roster.members or {}) do
                member = roster.members[j]
                assumption = member and SCB.assumedRolesByName[member.name] or nil
                if member and member.isBot and member.name and not used[member.name]
                    and assumption and assumption.spawnKind ~= "bootstrap"
                    and assumption.slotIndex == assignment.slotIndex then
                    matchedName = member.name
                    break
                end
            end

            if not matchedName then
                for j = 1, table.getn(roster.members or {}) do
                    member = roster.members[j]
                    assumption = member and SCB.assumedRolesByName[member.name] or nil
                    if member and member.isBot and member.name and not used[member.name]
                        and (member.currentGroup or 1) == (assignment.group or 1)
                        and assumption and assumption.spawnKind ~= "bootstrap"
                        and not assumption.slotIndex
                        and assumption.command == assignment.command then
                        matchedName = member.name
                        break
                    end
                end
            end

            if not matchedName then return false end
            replacements[i] = matchedName
            used[matchedName] = true
        end
    end

    for i = 1, table.getn(tracker.assignments or {}) do
        if replacements[i] then tracker.assignments[i].botName = replacements[i] end
    end
    tracker.scbRoleIdentityReconciled = true
    return true
end

function SCB_LinkAssumptionsToTrackerSlots()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local used = {}
    local i, assignment, name, intent, chosenName, chosenAt

    if not tracker or not tracker.assignments then return end

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        name = assignment and assignment.scbAssumedName or nil
        intent = name and SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil

        if assignment and assignment.initialActive and intent
            and intent.spawnKind ~= "bootstrap"
            and ((intent.slotIndex and intent.slotIndex == assignment.slotIndex)
                or (not intent.slotIndex and intent.command == assignment.command)) then
            used[name] = true
        elseif assignment then
            assignment.scbAssumedName = nil
        end
    end

    for i = 1, table.getn(tracker.assignments) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and not assignment.scbAssumedName then
            chosenName, chosenAt = nil, nil

            for name, intent in pairs(SCB.assumedRolesByName or {}) do
                if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                    and intent.slotIndex == assignment.slotIndex then
                    chosenName = name
                    break
                end
            end

            if not chosenName then
                for name, intent in pairs(SCB.assumedRolesByName or {}) do
                    if not used[name] and intent and intent.spawnKind ~= "bootstrap"
                        and not intent.slotIndex and intent.command == assignment.command then
                        if not chosenAt or (intent.boundAt or 0) < chosenAt then
                            chosenName = name
                            chosenAt = intent.boundAt or 0
                        end
                    end
                end
            end

            if chosenName then
                assignment.scbAssumedName = chosenName
                used[chosenName] = true
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- Live Blizzard raid layout observation (former RaidLayout.lua)
-- -------------------------------------------------------------------------

local function SCB_BuildLiveRaidPositions(observed)
    local result = {}
    local i, member
    observed = observed or (SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil)
    if not observed or observed.mode ~= "raid" then return result end
    for i = 1, table.getn(observed.members or {}) do
        member = observed.members[i]
        if member and member.name and member.raidIndex and member.currentGroup then
            result[member.name] = {
                raidIndex = member.raidIndex,
                group = member.currentGroup,
                groupRow = member.groupRow,
            }
        end
    end
    return result
end

function SCB_RefreshTrackerLiveLayout(observed)
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local positions, changed
    local i, player, assignment, name, live, assumption
    if not tracker or not tracker.ready or tracker.mode ~= "raid" then return false end
    positions = SCB_BuildLiveRaidPositions(observed)
    changed = false

    for i = 1, table.getn(tracker.players or {}) do
        player = tracker.players[i]
        live = player and player.name and positions[player.name] or nil
        if live then
            if player.currentGroup ~= live.group or player.currentGroupRow ~= live.groupRow
                or player.currentRaidIndex ~= live.raidIndex then changed = true end
            player.currentGroup = live.group
            player.currentGroupRow = live.groupRow
            player.currentRaidIndex = live.raidIndex
        end
    end

    for i = 1, table.getn(tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        name = assignment and (assignment.botName or assignment.scbAssumedName) or nil
        live = name and positions[name] or nil
        if live then
            if assignment.currentGroup ~= live.group or assignment.currentGroupRow ~= live.groupRow
                or assignment.currentRaidIndex ~= live.raidIndex then changed = true end
            assignment.currentGroup = live.group
            assignment.currentGroupRow = live.groupRow
            assignment.currentRaidIndex = live.raidIndex
            assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
            if assumption then
                assumption.currentGroup = live.group
                assumption.currentGroupRow = live.groupRow
                assumption.currentRaidIndex = live.raidIndex
            end
        end
    end

    if changed then
        tracker.layoutRevision = (tracker.layoutRevision or 0) + 1
        tracker.layoutUpdatedAt = GetTime and GetTime() or 0
        if SCB.developerDebugEnabled then
            SCB_BurstDebug("Observed Blizzard raid layout revision " .. tostring(tracker.layoutRevision))
        end
    end
    return changed
end

function SCB_QueueTrackerLiveLayoutRefresh(delay)
    local frame = SCB.trackerLiveLayoutRefreshFrame
    if not frame then
        frame = CreateFrame("Frame", "SoloCraftBotsTrackerLiveLayoutRefreshFrame", UIParent)
        frame:Hide()
        frame:SetScript("OnUpdate", function()
            this.scbElapsed = (this.scbElapsed or 0) + (arg1 or 0)
            if this.scbElapsed < (this.scbDelay or 0.15) then return end
            this.scbElapsed = 0
            this:Hide()
            SCB_RefreshTrackerLiveLayout(SCB.liveRoster)
        end)
        SCB.trackerLiveLayoutRefreshFrame = frame
    end
    frame.scbDelay = delay or 0.15
    frame.scbElapsed = 0
    frame:Show()
end

end
