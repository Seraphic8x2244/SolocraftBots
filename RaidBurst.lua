-- SoloCraft Bots - explicit preset/refill burst scheduling.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_WAIT_RAID = "__SCB_WAIT_RAID__"
local SCB_WAIT_BOOTSTRAP = "__SCB_WAIT_BOOTSTRAP__"

local function SCB_IsSpawnCommandString(value)
    return type(value) == "string" and string.find(value, "^add%s+") ~= nil
end

local function SCB_ParseSpawnCommand(command)
    local _, _, classKey, role, extra
    if type(command) ~= "string" then return nil end
    _, _, classKey, role, extra = string.find(command, "^add%s+(%S+)%s+(%S+)%s*(.*)$")
    if not classKey or not role then return nil end
    if extra == "" then extra = nil end
    return classKey, role, extra
end

local function SCB_CopyBurstAssignment(entry)
    if not entry then return nil end
    return {
        slotIndex = entry.slotIndex,
        group = entry.group,
        command = entry.command,
        class = entry.class,
        role = entry.role,
        extra = entry.extra,
    }
end

local function SCB_BurstDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- -------------------------------------------------------------------------
-- Explicit burst plans and Group-8 survivor parking
-- -------------------------------------------------------------------------

local function SCB_TrackerAssignmentsByGroup(tracker)
    local groups = {}
    local i, assignment
    for i = 1, 8 do groups[i] = {} end
    for i = 1, table.getn(tracker and tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and assignment.group then
            table.insert(groups[assignment.group], assignment)
        end
    end
    return groups
end

local function SCB_RemainingGroupAssignments(groups, groupIndex, planned)
    local result = {}
    local i, assignment
    for i = 1, table.getn(groups[groupIndex] or {}) do
        assignment = groups[groupIndex][i]
        if assignment and not planned[assignment.slotIndex] then
            table.insert(result, assignment)
        end
    end
    return result
end

local function SCB_CommandsMatchReverse(assignments, commands)
    local i, wanted
    if table.getn(assignments) ~= table.getn(commands) then return false end
    for i = 1, table.getn(commands) do
        wanted = assignments[table.getn(assignments) - i + 1]
        if not wanted or wanted.command ~= commands[i] then return false end
    end
    return true
end

local function SCB_FindQueueIndex(queue, wanted, startAt)
    local i
    for i = startAt or 1, table.getn(queue or {}) do
        if queue[i] == wanted then return i end
    end
    return nil
end

-- Existing 0.7.1 survivor queues held one real G1 command until the temporary
-- G1 occupant was removed. In 0.7.2 the survivor is parked in G8 instead, so put
-- that command back into its normal G1 LIFO burst and delete the old hand-off.
local function SCB_RewriteSurvivorQueueForGroupEight(tracker, useKickAllAnchor)
    local queue = SCB.presetSpawnQueue or {}
    local handoffIndex = SCB_FindQueueIndex(queue, SCB.PRESET_WAIT_FINAL_ROSTER)
    local arrangeIndex, checkIndex, commandEnd
    local heldCommand, groups, g1Count, i

    if not handoffIndex then return true, false end
    if queue[handoffIndex + 1] ~= SCB.PRESET_REMOVE_SURVIVOR
        or queue[handoffIndex + 2] ~= SCB.PRESET_WAIT_SURVIVOR_GONE
        or queue[handoffIndex + 3] ~= SCB.PRESET_CHECK_COMBAT
        or not SCB_IsSpawnCommandString(queue[handoffIndex + 4]) then
        return false, false
    end

    heldCommand = queue[handoffIndex + 4]
    for i = 1, 5 do table.remove(queue, handoffIndex) end

    arrangeIndex = SCB_FindQueueIndex(queue, SCB.PRESET_ARRANGE_PLAYERS)
    if not arrangeIndex then return false, false end

    groups = SCB_TrackerAssignmentsByGroup(tracker)
    g1Count = table.getn(groups[1] or {})
    if g1Count < 1 then return false, false end

    if g1Count == 1 then
        table.insert(queue, arrangeIndex + 1, heldCommand)
        table.insert(queue, arrangeIndex + 1, SCB.PRESET_CHECK_COMBAT)
    else
        checkIndex = SCB_FindQueueIndex(queue, SCB.PRESET_CHECK_COMBAT, arrangeIndex + 1)
        if not checkIndex then return false, false end
        commandEnd = checkIndex + 1
        while SCB_IsSpawnCommandString(queue[commandEnd]) do
            commandEnd = commandEnd + 1
        end

        if (commandEnd - (checkIndex + 1)) ~= (g1Count - 1) then
            return false, false
        end

        -- KickAll's deliberate anchor held the last logical active G1 slot;
        -- every other survivor/bootstrap held the first. Restore the exact full
        -- reverse-send order in either case.
        if useKickAllAnchor then
            table.insert(queue, checkIndex + 1, heldCommand)
        else
            table.insert(queue, commandEnd, heldCommand)
        end
    end

    SCB.presetExpectedBotCountBeforeHandoff = nil
    SCB.scbParkSurvivorBeforeArrange = true
    SCB.scbRemoveSurvivorAfterG1 = true
    SCB.scbSurvivorRemovalWaiting = nil
    SCB.scbSurvivorRemovalName = nil
    SCB.scbSurvivorRemovalGoneAt = nil
    return true, true
end

local function SCB_MakeBootstrapPlan(command)
    local classKey, role, extra = SCB_ParseSpawnCommand(command)
    if not classKey then return nil end
    return {
        kind = "bootstrap",
        group = nil,
        assignments = {
            {
                command = command,
                class = classKey,
                role = role,
                extra = extra,
            },
        },
    }
end

local function SCB_MakePresetPlan(groupIndex, assignments)
    local plan = {
        kind = "preset",
        group = groupIndex,
        assignments = {},
    }
    local i
    for i = 1, table.getn(assignments or {}) do
        table.insert(plan.assignments, SCB_CopyBurstAssignment(assignments[i]))
    end
    return plan
end

local function SCB_BuildPresetBurstPlans(tracker)
    local queue = SCB.presetSpawnQueue or {}
    local groups = SCB_TrackerAssignmentsByGroup(tracker)
    local planned, plans = {}, {}
    local i, j, command, terminal, commands, remaining, assignment
    local normalGroup = 1
    local plan

    i = 1
    while i <= table.getn(queue) do
        if queue[i] == SCB.PRESET_CHECK_COMBAT then
            commands = {}
            j = i + 1
            while j <= table.getn(queue) and SCB_IsSpawnCommandString(queue[j]) do
                table.insert(commands, queue[j])
                j = j + 1
            end
            terminal = queue[j]

            if table.getn(commands) == 0 then
                return false
            end

            if terminal == SCB_WAIT_BOOTSTRAP then
                if table.getn(commands) ~= 1 then return false end
                plan = SCB_MakeBootstrapPlan(commands[1])
                if not plan then return false end
                table.insert(plans, plan)

            elseif terminal == SCB.PRESET_WAIT_REAL_RAID_START then
                if table.getn(commands) ~= 1 then return false end
                assignment = nil
                remaining = SCB_RemainingGroupAssignments(groups, 1, planned)
                for j = 1, table.getn(remaining) do
                    if remaining[j].command == commands[1] then
                        assignment = remaining[j]
                        break
                    end
                end
                if not assignment then return false end
                planned[assignment.slotIndex] = true
                table.insert(plans, SCB_MakePresetPlan(1, { assignment }))

            else
                remaining = {}
                while normalGroup <= 8 do
                    remaining = SCB_RemainingGroupAssignments(groups, normalGroup, planned)
                    if table.getn(remaining) > 0 then break end
                    normalGroup = normalGroup + 1
                end
                if normalGroup > 8 or table.getn(remaining) == 0 then return false end
                if not SCB_CommandsMatchReverse(remaining, commands) then return false end

                for j = 1, table.getn(remaining) do
                    planned[remaining[j].slotIndex] = true
                end
                table.insert(plans, SCB_MakePresetPlan(normalGroup, remaining))
                normalGroup = normalGroup + 1
            end

            i = i + table.getn(commands) + 1
        else
            i = i + 1
        end
    end

    for i = 1, table.getn(tracker and tracker.assignments or {}) do
        assignment = tracker.assignments[i]
        if assignment and assignment.initialActive and not planned[assignment.slotIndex] then
            return false
        end
    end

    SCB.scbPresetBurstPlans = plans
    return true
end

local function SCB_FindRaidMemberGroup(name)
    local i, memberName, _, subgroup
    if not name or not GetNumRaidMembers or not GetRaidRosterInfo then return nil, nil end
    for i = 1, GetNumRaidMembers() do
        memberName, _, subgroup = GetRaidRosterInfo(i)
        if memberName == name then return subgroup, i end
    end
    return nil, nil
end

local function SCB_TryParkSurvivorInGroupEight(name)
    local group, raidIndex
    name = name or SCB.presetSurvivorBotName or SCB.presetBootstrapBotName
    if not name then return false end
    if not GetNumRaidMembers or GetNumRaidMembers() == 0 then return false end

    group, raidIndex = SCB_FindRaidMemberGroup(name)
    if not raidIndex then return false end
    if group == 8 then
        SCB_BurstDebug("Safety " .. tostring(name) .. " parked in G8")
        return true
    end

    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end
    if SetRaidSubgroup then SetRaidSubgroup(raidIndex, 8) end
    return false
end

local function SCB_HasRealGroupOneBot(survivorName)
    local i, name, _, subgroup
    if not GetNumRaidMembers or not GetRaidRosterInfo then return false end
    for i = 1, GetNumRaidMembers() do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup == 1 and name ~= survivorName
            and SCB_IsBotName and SCB_IsBotName(name) then
            local assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
            if not assumption or assumption.spawnKind ~= "bootstrap" then
                return true
            end
        end
    end
    return false
end

local function SCB_TryRemoveParkedSurvivor()
    local name = SCB.scbSurvivorRemovalName
        or SCB.presetSurvivorBotName
        or SCB.presetBootstrapBotName
    local now, settleDelay, nextHead

    if not name then
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        SCB.scbSurvivorRemovalGoneAt = nil
        return true
    end

    if SCB.scbSurvivorRemovalWaiting then
        if SCB_GroupHasName and SCB_GroupHasName(name) then
            SCB.scbSurvivorRemovalGoneAt = nil
            return false
        end

        -- The safety delay belongs at the remove -> next-add boundary. If the
        -- only remaining work is final roster tracking, no add follows and no
        -- artificial 3-second pause is required.
        nextHead = SCB.presetSpawnQueue and SCB.presetSpawnQueue[1] or nil
        if nextHead == SCB.PRESET_CHECK_COMBAT and GetTime then
            now = GetTime()
            if not SCB.scbSurvivorRemovalGoneAt then
                SCB.scbSurvivorRemovalGoneAt = now
                return false
            end
            settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
            if (now - SCB.scbSurvivorRemovalGoneAt) < settleDelay then return false end
        end

        if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(name) end
        SCB.presetSurvivorBotName = nil
        SCB.presetBootstrapBotName = nil
        SCB.scbRemoveSurvivorAfterG1 = nil
        SCB.scbSurvivorRemovalWaiting = nil
        SCB.scbSurvivorRemovalName = nil
        SCB.scbSurvivorRemovalGoneAt = nil
        SCB_BurstDebug("Safety " .. tostring(name) .. " removed after real G1 join")
        return true
    end

    if not SCB_HasRealGroupOneBot(name) then return false end
    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end
    if UninviteByName then
        UninviteByName(name)
        SCB.scbSurvivorRemovalWaiting = true
        SCB.scbSurvivorRemovalName = name
        SCB.scbSurvivorRemovalGoneAt = nil
        return false
    end
    return false
end

local SCB_072PreviousStartPresetSummonSnapshot = SCB_StartPresetSummonSnapshot
if SCB_072PreviousStartPresetSummonSnapshot then
    function SCB_StartPresetSummonSnapshot(snapshot)
        local anchorBefore = SCB_GetKickAllAnchorForFreshBuild
            and SCB_GetKickAllAnchorForFreshBuild() or nil
        local ok, errorText = SCB_072PreviousStartPresetSummonSnapshot(snapshot)
        local tracker, useKickAllAnchor, transformed

        if not ok then return ok, errorText end
        tracker = SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker or nil
        if not tracker then
            if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
            return false, SCB_L("ERR_SUMMON_BUSY")
        end

        -- The execution snapshot was built from the currently-selected editor,
        -- so revision zero starts aligned with this tracker.
        if tracker.presetGroupIndex and tracker.presetIndex
            and SoloCraftBotsDB.currentPresetGroup == tracker.presetGroupIndex
            and SCB_CurrentPresetGroup()
            and SCB_CurrentPresetGroup().currentPreset == tracker.presetIndex then
            SCB.scbEditorLayoutTrackerRevision = tracker.layoutRevision or 0
        end

        useKickAllAnchor = anchorBefore
            and SCB.presetSurvivorBotName
            and anchorBefore == SCB.presetSurvivorBotName

        ok, transformed = SCB_RewriteSurvivorQueueForGroupEight(tracker, useKickAllAnchor)
        if not ok then
            if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
            return false, SCB_L("ERR_SUMMON_BUSY")
        end

        if not transformed then
            SCB.scbParkSurvivorBeforeArrange = nil
            SCB.scbRemoveSurvivorAfterG1 = nil
            SCB.scbSurvivorRemovalWaiting = nil
            SCB.scbSurvivorRemovalName = nil
            SCB.scbSurvivorRemovalGoneAt = nil
        end

        if not SCB_BuildPresetBurstPlans(tracker) then
            if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
            return false, SCB_L("ERR_SUMMON_BUSY")
        end

        SCB.scbExplicitPresetOperation = true
        SCB.scbCheckPlanArmed = nil
        SCB.scbArmedPresetPlan = nil
        return true
    end
end

SCB.scb072TryParkSurvivorInGroupEight = SCB_TryParkSurvivorInGroupEight
SCB.scb072TryRemoveParkedSurvivor = SCB_TryRemoveParkedSurvivor
