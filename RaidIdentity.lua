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
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- -------------------------------------------------------------------------
-- Explicit spawn identity
-- -------------------------------------------------------------------------

function SCB_SendSpawnCommand(command)
    if not command or command == "" then return end
    if SCB_RegisterSpawnIntent then SCB_RegisterSpawnIntent() end
    SendChatMessage(".partybot " .. command, "SAY")
end

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
            SCB_BurstDebug(
                "Burst " .. tostring(plan.burstID)
                .. " expect " .. groupLabel
                .. " " .. tostring(intent.class or "?")
                .. " " .. tostring(intent.role or "?")
            )
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

    localSlot = SCB_GroupLocalSlot(intent.slotIndex)
    if intent.slotIndex and intent.group then
        label = "G" .. tostring(intent.group) .. "S" .. tostring(localSlot)
    else
        label = tostring(intent.spawnKind or "spawn")
    end
    SCB_BurstDebug(
        "Burst " .. tostring(intent.burstID or "?")
        .. " joined " .. tostring(name)
        .. " -> " .. label
        .. " " .. tostring(intent.class or "?")
        .. " " .. tostring(intent.role or "?")
    )
    return true
end

function SCB_ReconcileTrackerFromAssumedRoles(tracker)
    local roster, used, replacements = nil, {}, {}
    local i, j, assignment, member, assumption, matchedName

    if not tracker or not tracker.ready or tracker.scbRoleIdentityReconciled then
        return tracker and tracker.scbRoleIdentityReconciled or false
    end

    roster = SCB_GetLiveRoster and SCB_GetLiveRoster(true) or nil
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

local function SCB_BuildLiveRaidPositions()
    local result, groupRows = {}, {}
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local i, name, _, subgroup
    for i = 1, 8 do groupRows[i] = 0 end
    for i = 1, raidCount do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            groupRows[subgroup] = groupRows[subgroup] + 1
            result[name] = {
                raidIndex = i,
                group = subgroup,
                groupRow = groupRows[subgroup],
            }
        end
    end
    return result
end

local function SCB_RefreshTrackerLiveLayout()
    local tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
    local positions, changed = SCB_BuildLiveRaidPositions(), false
    local i, player, assignment, name, live, assumption
    if not tracker or not tracker.ready or tracker.mode ~= "raid" then return false end

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
        SCB_BurstDebug("Observed Blizzard raid layout revision " .. tostring(tracker.layoutRevision))
    end
    return changed
end

local SCB_PreviousTryFinalizeRaidRoleTracking_Layout = SCB_TryFinalizeRaidRoleTracking
if SCB_PreviousTryFinalizeRaidRoleTracking_Layout then
    function SCB_TryFinalizeRaidRoleTracking()
        local ready = SCB_PreviousTryFinalizeRaidRoleTracking_Layout()
        if ready then SCB_RefreshTrackerLiveLayout() end
        return ready
    end
end

local SCB_PreviousHandleRosterChange_Layout = SCB_HandleRosterChange
if SCB_PreviousHandleRosterChange_Layout then
    function SCB_HandleRosterChange()
        local result = SCB_PreviousHandleRosterChange_Layout()
        SCB_RefreshTrackerLiveLayout()
        return result
    end
end

-- Scheduler-state cleanup remains a late wrapper until Spawn consolidation.
local SCB_PreviousAbortBotSpawnOperations_Layout = SCB_AbortBotSpawnOperations
if SCB_PreviousAbortBotSpawnOperations_Layout then
    function SCB_AbortBotSpawnOperations()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_PreviousAbortBotSpawnOperations_Layout()
    end
end

local SCB_PreviousResetSessionState_Layout = SCB_ResetSessionState
if SCB_PreviousResetSessionState_Layout then
    function SCB_ResetSessionState()
        SCB.scbPresetBurstPlans = {}
        SCB.scbExplicitPresetOperation = nil
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        SCB.scbParkSurvivorBeforeArrange = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        return SCB_PreviousResetSessionState_Layout()
    end
end
