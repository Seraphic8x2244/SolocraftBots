-- SoloCraft Bots - authoritative summon runtime and bot lifecycle coordinator.
--
-- 0.8.29 structurally absorbs the former RaidBurst.lua file. Keep its code in
-- a scoped prelude so its historical pre-Spawn execution and wrapper order stay intact.
do
-- SoloCraft Bots - transitional burst safety and maintenance coordinator.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.REPLACE_REMOVAL_SETTLE_DELAY = 3.0

local function SCB_CurrentPresetSafety(create)
    if SCB_GetBotOperationSafety then return SCB_GetBotOperationSafety(create) end
    return nil
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
    if SCB.developerDebugEnabled and SCB_DebugLog then SCB_DebugLog("Burst", text) end
end

-- Initial raid subgroup changes must settle through a later roster event before
-- the first real preset burst is released. Immediate GetRaidRosterInfo()
-- reflection alone is not a sufficient server-stability signal.
local function SCB_CurrentPresetOperation()
    if SCB_GetActiveBotOperation then return SCB_GetActiveBotOperation() end
    return SCB.botOperation
end

function SCB_RecordPresetSubgroupMoveBarrier()
    local revision = SCB.rosterEventRevision or 0
    local operation = SCB_CurrentPresetOperation()
    if operation and operation.kind == "preset" then
        operation.subgroupMoveBarrierRevision = revision
    else
        SCB.presetSubgroupMoveBarrierRevision = revision
    end
end

function SCB_PresetSubgroupMoveBarrierPassed()
    local operation = SCB_CurrentPresetOperation()
    local baseline, operationOwned
    if operation and operation.kind == "preset" then
        baseline = operation.subgroupMoveBarrierRevision
        operationOwned = true
    else
        baseline = SCB.presetSubgroupMoveBarrierRevision
    end

    if baseline == nil then return true end
    if (SCB.rosterEventRevision or 0) <= baseline then return false end

    if operationOwned then
        operation.subgroupMoveBarrierRevision = nil
    else
        SCB.presetSubgroupMoveBarrierRevision = nil
    end
    return true
end

-- -------------------------------------------------------------------------
-- Group-8 survivor/bootstrap helpers still consumed by Spawn.lua.
-- -------------------------------------------------------------------------

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
    local safety = SCB_CurrentPresetSafety(false)
    name = name or (safety and safety.survivorName) or (safety and safety.bootstrapName)
    if not name then return false end
    if not GetNumRaidMembers or GetNumRaidMembers() == 0 then return false end

    group, raidIndex = SCB_FindRaidMemberGroup(name)
    if not raidIndex then return false end
    if group == 8 then
        if SCB.developerDebugEnabled then SCB_BurstDebug("Safety " .. tostring(name) .. " parked in G8") end
        return true
    end

    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end
    if SetRaidSubgroup then
        SCB_RecordPresetSubgroupMoveBarrier()
        SetRaidSubgroup(raidIndex, 8)
    end
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
    local safety = SCB_CurrentPresetSafety(false)
    local name = safety and (safety.removalName or safety.survivorName or safety.bootstrapName) or nil
    local now, settleDelay, nextHead

    if not safety then return true end

    if not name then
        safety.removeAfterGroupOne = nil
        safety.removalWaiting = nil
        safety.removalName = nil
        safety.removalGoneAt = nil
        return true
    end

    if safety.removalWaiting then
        if SCB_GroupHasName and SCB_GroupHasName(name) then
            safety.removalGoneAt = nil
            return false
        end

        -- The safety delay belongs at the remove -> next-add boundary. If the
        -- only remaining work is final roster tracking, no add follows and no
        -- artificial 3-second pause is required.
        nextHead = SCB_PresetSpawnQueuePeek and SCB_PresetSpawnQueuePeek() or nil
        if nextHead == SCB.PRESET_CHECK_COMBAT and GetTime then
            now = GetTime()
            if not safety.removalGoneAt then
                safety.removalGoneAt = now
                return false
            end
            settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
            if (now - safety.removalGoneAt) < settleDelay then return false end
        end

        if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(name) end
        safety.survivorName = nil
        safety.bootstrapName = nil
        safety.removeAfterGroupOne = nil
        safety.removalWaiting = nil
        safety.removalName = nil
        safety.removalGoneAt = nil
        if SCB.developerDebugEnabled then SCB_BurstDebug("Safety " .. tostring(name) .. " removed after real G1 join") end
        return true
    end

    if not SCB_HasRealGroupOneBot(name) then return false end
    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end
    if SCB_KickBots and SCB_KickBots("all", {
        name = name,
        manageSafety = false,
        silent = true,
    }) then
        safety.removalWaiting = true
        safety.removalName = name
        safety.removalGoneAt = nil
    end
    return false
end

SCB.scb072TryParkSurvivorInGroupEight = SCB_TryParkSurvivorInGroupEight
SCB.scb072TryRemoveParkedSurvivorBase = SCB_TryRemoveParkedSurvivor
SCB.scb072TryRemoveParkedSurvivor = SCB_TryRemoveParkedSurvivor

-- -------------------------------------------------------------------------
-- Maintenance coordinator (absorbed from RaidRefill.lua in 0.8.28).
-- -------------------------------------------------------------------------

SCB.MAINTENANCE_REMOVAL_TIMEOUT = 15.0
SCB.MAINTENANCE_BURST_TIMEOUT = 12.0
SCB.MAINTENANCE_GROUP_MOVE_TIMEOUT = 15.0
SCB.MAINTENANCE_STALE_COMBAT_DELAY = 10.0
SCB.MAINTENANCE_BURST_SIZE = 5

local function SCB_0826MaintenanceDebug(text)
    if SCB.developerDebugEnabled and SCB_DebugLog then SCB_DebugLog("Spawn", "Maintenance: " .. tostring(text)) end
end

local function SCB_0826CopyMaintenanceAssignment(entry)
    if not entry then return nil end
    return {
        source = entry.source,
        sourceName = entry.sourceName,
        activeSlotID = entry.activeSlotID,
        slotIndex = entry.slotIndex,
        group = entry.group or 1,
        command = entry.command,
        class = entry.class,
        role = entry.role,
        extra = entry.extra,
        missingSince = entry.missingSince,
    }
end

local function SCB_0826SortMaintenanceAssignments(assignments)
    table.sort(assignments, function(a, b)
        local ag, bg = tonumber(a and a.group) or 1, tonumber(b and b.group) or 1
        local as, bs = tonumber(a and a.slotIndex) or 0, tonumber(b and b.slotIndex) or 0
        if ag ~= bg then return ag < bg end
        return as < bs
    end)
end

local function SCB_0826SetMaintenanceSentinel(operation, active)
    if active then
        SCB.replaceDeadState = {
            active = true,
            coordinator = true,
            operationID = operation and operation.id or nil,
        }
    elseif SCB.replaceDeadState and SCB.replaceDeadState.coordinator then
        SCB.replaceDeadState = nil
    end
end

SCB.scb0826SetMaintenanceSentinel = SCB_0826SetMaintenanceSentinel

local function SCB_0826FinishMaintenance(status, reason, userText)
    local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
    if not operation or operation.kind ~= "maintenance" then return end

    SCB_0826SetMaintenanceSentinel(operation, false)
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
    if SCB_EndBotOperation then SCB_EndBotOperation(status or "complete", reason) end
    if SCB_SyncActiveRosterFromObserved then SCB_SyncActiveRosterFromObserved() end
    if SCB_RefreshReplaceDeadButton then SCB_RefreshReplaceDeadButton() end
    if userText and SCB_Print then SCB_Print(userText) end
end

local function SCB_0826MaintenanceCombatBlocked(state, now)
    local groupCombat = SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() or false
    local playerCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false

    if not groupCombat then
        state.combatSeenAt = nil
        state.combatOverrideLogged = nil
        return false
    end

    if not state.combatSeenAt then
        state.combatSeenAt = now
        SCB_0826MaintenanceDebug("waiting for group combat to clear")
    end

    -- Never override the local player's own combat flag. If only a remote
    -- member/pet remains flagged for an extended period, allow one server-side
    -- attempt rather than parking maintenance forever on stale Vanilla state.
    if playerCombat then return true end
    if (now - state.combatSeenAt) < SCB.MAINTENANCE_STALE_COMBAT_DELAY then return true end

    if not state.combatOverrideLogged then
        state.combatOverrideLogged = true
        SCB_0826MaintenanceDebug("remote combat flag persisted with player clear; trying server-authoritative maintenance burst")
    end
    return false
end

local function SCB_0826PendingBotAddsStillActive()
    local pending = tonumber(SCB.pendingBotAdds) or 0
    local expires = tonumber(SCB.pendingBotAddsExpires) or 0
    local now = GetTime and GetTime() or 0
    if pending <= 0 then return false end
    if GetTime and expires > 0 and now > expires then
        SCB.pendingBotAdds = 0
        SCB.pendingBotAddsExpires = 0
        return false
    end
    return true
end

local function SCB_0826CollectCurrentBotNames()
    local result = {}
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local i, member
    for i = 1, table.getn(members) do
        member = members[i]
        if member and member.isBot and member.name then result[member.name] = true end
    end
    return result
end

local function SCB_0826ResolveMaintenanceBurstBots(state, newBots)
    local byName, used, resolved = {}, {}, {}
    local i, bot, assignment, name, intent, matched

    for i = 1, table.getn(newBots or {}) do
        bot = newBots[i]
        if bot and bot.name then byName[bot.name] = bot end
    end

    for i = 1, table.getn(state.currentAssignments or {}) do
        assignment = state.currentAssignments[i]
        matched = nil
        for name, intent in pairs(SCB.assumedRolesByName or {}) do
            if not used[name] and byName[name] and intent
                and intent.burstID == state.burstID
                and intent.slotIndex == assignment.slotIndex
                and (intent.group or 1) == (assignment.group or 1) then
                matched = byName[name]
                used[name] = true
                break
            end
        end
        if not matched then return nil end
        resolved[i] = matched
    end

    return resolved
end

local function SCB_0826MaintenanceBurstGroupsReady(state, resolvedBots)
    local i, assignment, bot
    for i = 1, table.getn(state.currentAssignments or {}) do
        assignment = state.currentAssignments[i]
        bot = resolvedBots and resolvedBots[i] or nil
        if not bot or bot.subgroup ~= (assignment.group or 1) then return false end
    end
    return true
end

local function SCB_0826MoveOneMaintenanceBot(state, resolvedBots)
    local i, j, assignment, bot, wantedGroup, otherAssignment, otherBot

    for i = 1, table.getn(state.currentAssignments or {}) do
        assignment = state.currentAssignments[i]
        bot = resolvedBots and resolvedBots[i] or nil
        wantedGroup = assignment and (assignment.group or 1) or 1

        if bot and bot.subgroup ~= wantedGroup then
            -- A full destination can contain another bot from this same mixed
            -- burst. Swap with a misplaced burst bot first so full raids can
            -- converge without needing a temporary empty subgroup slot.
            if SwapRaidSubgroup and bot.raidIndex then
                for j = 1, table.getn(state.currentAssignments or {}) do
                    if j ~= i then
                        otherAssignment = state.currentAssignments[j]
                        otherBot = resolvedBots[j]
                        if otherBot and otherBot.raidIndex
                            and otherBot.subgroup == wantedGroup
                            and (otherAssignment.group or 1) ~= wantedGroup then
                            SwapRaidSubgroup(bot.raidIndex, otherBot.raidIndex)
                            return true
                        end
                    end
                end
            end

            if SetRaidSubgroup and bot.raidIndex then
                SetRaidSubgroup(bot.raidIndex, wantedGroup)
                return true
            end
            return false
        end
    end

    return false
end

local function SCB_0826MaintenanceRemainingCount(state)
    local remaining = state and state.remaining or {}
    local head = state and state.remainingHead or 1
    local count = table.getn(remaining) - head + 1
    if count < 0 then return 0 end
    return count
end

local function SCB_0826BeginMaintenanceBurst(operation, state, now)
    local assignments, plan = {}, nil
    local i, assignment
    local head = state.remainingHead or 1
    local limit = math.min(SCB.MAINTENANCE_BURST_SIZE or 5, SCB_0826MaintenanceRemainingCount(state))

    for i = 0, limit - 1 do
        assignment = state.remaining[head + i]
        if assignment then table.insert(assignments, assignment) end
    end
    if table.getn(assignments) == 0 then return false end

    plan = { kind = "maintenance", assignments = {} }
    for i = 1, table.getn(assignments) do
        table.insert(plan.assignments, SCB_CopyBurstAssignment(assignments[i]))
    end
    if not SCB_BeginAssumedSpawnBurst or not SCB_BeginAssumedSpawnBurst(plan) then
        SCB_0826FinishMaintenance("failed", "maintenance identity burst could not start",
            "Bot maintenance stopped because replacement identity could not be prepared.")
        return false
    end

    state.burstID = plan.burstID
    state.currentAssignments = assignments
    state.beforeNames = SCB_0826CollectCurrentBotNames()
    state.fullSeenAt = nil
    state.groupMoveStartedAt = nil
    state.burstStartedAt = now
    state.phase = "waitgroup"
    state.combatSeenAt = nil
    state.combatOverrideLogged = nil
    if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-spawn") end

    -- Preserve the established burst ordering used by preset summons and the
    -- SoloCraft join-message identity queue. The only change is that one burst
    -- may now contain destinations from several raid groups.
    for i = table.getn(assignments), 1, -1 do
        assignment = assignments[i]
        if not SCB_SendSpawnCommand or not SCB_SendSpawnCommand(assignment.command) then
            SCB_0826FinishMaintenance("failed", "maintenance spawn payload rejected",
                "Bot maintenance stopped because a replacement command was invalid.")
            return false
        end
        SCB_0826MaintenanceDebug(
            "requested G" .. tostring(assignment.group or 1)
            .. " slot " .. tostring(assignment.slotIndex or "?")
            .. " " .. tostring(assignment.class or "?")
            .. " " .. tostring(assignment.role or "?")
        )
    end
    return true
end

local function SCB_0826CompleteMaintenanceBurst(state, resolvedBots)
    local i
    for i = 1, table.getn(state.currentAssignments or {}) do
        local assignment = state.currentAssignments[i]
        local bot = resolvedBots[i]
        assignment.botName = bot and bot.name or nil
        if assignment.activeSlotID and bot and SCB_BindReplacementToActiveSlot then
            SCB_BindReplacementToActiveSlot(assignment.activeSlotID, bot.name, assignment.group or 1)
        end
    end

    state.remainingHead = (state.remainingHead or 1) + table.getn(state.currentAssignments or {})

    if SCB_ApplyTrackedPfUITankRoles then
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)
    end

    state.burstID = nil
    state.currentAssignments = nil
    state.beforeNames = nil
    state.fullSeenAt = nil
    state.groupMoveStartedAt = nil
    state.burstStartedAt = nil
    state.combatSeenAt = nil
    state.combatOverrideLogged = nil
    state.phase = "nextgroup"
    if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-spawn") end
    if SCB_RefreshReplaceDeadButton then SCB_RefreshReplaceDeadButton() end
end

function SCB_MaintenanceReplaceOnClick()
    local missing, dead, unavailableMissing, unavailableDead = SCB_GetActiveMaintenanceRecords()
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local botCount, otherHumans = 0, 0
    local survivorName, survivorRecord
    local assignments, removedNames = {}, {}
    local i, member, slot, record, now, readyAt
    local operation, state, unavailableCount

    if (SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation())
        or (SCB_IsKickQueueActive and SCB_IsKickQueueActive())
        or SCB_0826PendingBotAddsStillActive() then
        SCB_Print(SCB_L("REPLACE_DEAD_BUSY"))
        return
    end

    unavailableCount = table.getn(unavailableMissing) + table.getn(unavailableDead)
    if table.getn(missing) == 0 and table.getn(dead) == 0 then
        if unavailableCount > 0 then
            SCB_Print(string.format(SCB_L("REPLACE_UNIDENTIFIED"), unavailableCount))
        else
            SCB_Print(SCB_L("REPLACE_DEAD_NONE"))
        end
        return
    end
    if table.getn(dead) > 0 and not UninviteByName then
        SCB_Print(SCB_L("KICK_NATIVE_UNAVAILABLE"))
        return
    end

    for i = 1, table.getn(members) do
        member = members[i]
        if member.isBot then
            botCount = botCount + 1
        elseif not member.isSelf then
            otherHumans = otherHumans + 1
        end
    end

    if otherHumans == 0 and table.getn(dead) == botCount and botCount > 0
        and SCB_SurvivorSafetyRequired and SCB_SurvivorSafetyRequired() then
        survivorName = SCB_FindGroupOneSurvivor and SCB_FindGroupOneSurvivor(members) or nil
        for i = 1, table.getn(dead) do
            slot = dead[i]
            if slot.currentName == survivorName then
                survivorRecord = SCB_BuildActiveReplacementRecord(slot)
                break
            end
        end
    end

    now = GetTime and GetTime() or 0
    readyAt = now

    for i = 1, table.getn(missing) do
        record = SCB_BuildActiveReplacementRecord(missing[i])
        if record then
            record = SCB_0826CopyMaintenanceAssignment(record)
            table.insert(assignments, record)
            if record.missingSince then
                local missingReadyAt = record.missingSince + (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0)
                if missingReadyAt > readyAt then readyAt = missingReadyAt end
            end
        end
    end

    for i = 1, table.getn(dead) do
        slot = dead[i]
        record = SCB_BuildActiveReplacementRecord(slot)
        if record and (not survivorRecord or record.activeSlotID ~= survivorRecord.activeSlotID) then
            record = SCB_0826CopyMaintenanceAssignment(record)
            table.insert(assignments, record)
            if record.sourceName then removedNames[record.sourceName] = true end
        end
    end

    if survivorRecord then survivorRecord = SCB_0826CopyMaintenanceAssignment(survivorRecord) end
    if table.getn(assignments) == 0 and survivorRecord then
        SCB_Print(SCB_L("REPLACE_DEAD_LAST_UNSAFE"))
        return
    end

    SCB_0826SortMaintenanceAssignments(assignments)
    operation = SCB_BeginBotOperation and SCB_BeginBotOperation("maintenance", {
        kind = "maintenance",
        missingCount = table.getn(missing),
        deadCount = table.getn(dead),
        unavailableMissingCount = table.getn(unavailableMissing),
        unavailableDeadCount = table.getn(unavailableDead),
    }) or nil
    if not operation then
        SCB_Print(SCB_L("REPLACE_DEAD_BUSY"))
        return
    end

    state = {
        phase = "nextgroup",
        remaining = assignments,
        remainingHead = 1,
        removedNames = removedNames,
        survivorAssignment = survivorRecord,
        survivorName = survivorName,
        readyAt = readyAt,
    }
    operation.maintenance = state
    SCB_0826SetMaintenanceSentinel(operation, true)
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end

    SCB_0826MaintenanceDebug(
        "snapshot missing=" .. tostring(table.getn(missing))
        .. " dead=" .. tostring(table.getn(dead))
        .. " unavailableMissing=" .. tostring(table.getn(unavailableMissing))
        .. " unavailableDead=" .. tostring(table.getn(unavailableDead))
        .. " survivor=" .. tostring(survivorName or "none")
    )

    if not SCB_KickBots or not SCB_KickBots("dead", {
        names = removedNames,
        manageSafety = false,
        preserveName = survivorName,
        silent = true,
    }) then
        SCB_0826FinishMaintenance("failed", "shared removal queue unavailable",
            SCB_L("REPLACE_DEAD_BUSY"))
        return
    end

    if next(removedNames) ~= nil then
        state.phase = "waitremoved"
        state.removalStartedAt = now
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-remove") end
    elseif readyAt > now then
        state.phase = "settle"
        state.settleUntil = readyAt
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-settle") end
    else
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-spawn") end
    end

    if SCB_RefreshReplaceDeadButton then SCB_RefreshReplaceDeadButton() end
end

function SCB_MaintenanceReplaceOnUpdate()
    local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
    local state = operation and operation.kind == "maintenance" and operation.maintenance or nil
    local now = GetTime and GetTime() or 0
    local newBots, expected, raidCount, i

    if not operation or operation.kind ~= "maintenance" then return end
    if not state then
        SCB_0826FinishMaintenance("failed", "maintenance state missing",
            "Bot maintenance stopped because its operation state was lost.")
        return
    end

    if state.phase == "waitremoved" or state.phase == "waitsurvivorremoved" then
        if not SCB_ReplaceDeadNamesGone or not SCB_ReplaceDeadNamesGone(state.removedNames or {}) then
            if state.removalStartedAt
                and (now - state.removalStartedAt) >= SCB.MAINTENANCE_REMOVAL_TIMEOUT then
                SCB_0826FinishMaintenance("failed", "removed bot never left roster",
                    "Bot maintenance stopped because a removed bot never left the roster. Replace Missing can be retried.")
            end
            return
        end

        state.settleUntil = now + (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0)
        if state.phase == "waitsurvivorremoved" and state.survivorAssignment then
            state.remaining = { state.survivorAssignment }
            state.remainingHead = 1
            state.survivorAssignment = nil
            state.survivorName = nil
        end
        state.removedNames = {}
        state.removalStartedAt = nil
        state.phase = "settle"
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-settle") end
        SCB_0826MaintenanceDebug("removal observed; starting capacity settle")
        return
    end

    if state.phase == "settle" then
        if now < (state.settleUntil or state.readyAt or 0) then return end
        state.settleUntil = nil
        state.readyAt = nil
        state.phase = "nextgroup"
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-spawn") end
    end

    if state.phase == "nextgroup" or state.phase == "combat" then
        if SCB_0826MaintenanceRemainingCount(state) == 0 then
            if state.survivorAssignment and state.survivorName then
                if SCB_CountGroupBots and SCB_CountGroupBots() <= 1 then
                    SCB_0826FinishMaintenance("failed", "last safety bot could not be replaced safely",
                        SCB_L("REPLACE_DEAD_LAST_UNSAFE"))
                    return
                end

                state.removedNames = { [state.survivorName] = true }
                state.removalStartedAt = now
                state.phase = "waitsurvivorremoved"
                if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-remove-survivor") end
                if SCB_GroupHasName and SCB_GroupHasName(state.survivorName) then
                    local survivorOnly = { [state.survivorName] = true }
                    if not SCB_KickBots or not SCB_KickBots("all", {
                        names = survivorOnly,
                        manageSafety = false,
                        silent = true,
                    }) then
                        SCB_0826FinishMaintenance("failed", "shared survivor removal queue unavailable",
                            SCB_L("REPLACE_DEAD_BUSY"))
                        return
                    end
                end
                SCB_0826MaintenanceDebug("queued retained safety bot removal " .. tostring(state.survivorName))
                return
            end

            SCB_0826FinishMaintenance("complete", nil, nil)
            return
        end

        if SCB_0826MaintenanceCombatBlocked(state, now) then
            state.phase = "combat"
            if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-combat") end
            return
        end

        state.phase = "nextgroup"
        SCB_0826BeginMaintenanceBurst(operation, state, now)
        return
    end

    if state.phase == "waitgroup" then
        local resolvedBots
        newBots = SCB_GetNewRefillBots and SCB_GetNewRefillBots(state.beforeNames or {}) or {}
        expected = table.getn(state.currentAssignments or {})

        if table.getn(newBots) < expected then
            if state.burstStartedAt and (now - state.burstStartedAt) >= SCB.MAINTENANCE_BURST_TIMEOUT then
                SCB_0826FinishMaintenance("failed", "replacement burst timed out",
                    "Bot maintenance stopped because a replacement did not join. Replace Missing can be retried.")
            end
            return
        end
        if table.getn(newBots) > expected then
            SCB_0826FinishMaintenance("failed", "unexpected extra bot joined during replacement",
                "Bot maintenance stopped because the live roster changed during replacement.")
            return
        end

        -- Do not infer mixed-group identity from physical roster order. The
        -- authoritative join-message intents carry this burst ID plus the exact
        -- logical slot/group for each newly joined bot.
        resolvedBots = SCB_0826ResolveMaintenanceBurstBots(state, newBots)
        if not resolvedBots then
            if state.burstStartedAt and (now - state.burstStartedAt) >= SCB.MAINTENANCE_BURST_TIMEOUT then
                SCB_0826FinishMaintenance("failed", "replacement identity timed out",
                    "Bot maintenance stopped because replacement identity could not be confirmed. Replace Missing can be retried.")
            end
            return
        end

        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount > 0 and not SCB_0826MaintenanceBurstGroupsReady(state, resolvedBots) then
            if SCB_0826MaintenanceCombatBlocked(state, now) then return end
            if not state.groupMoveStartedAt then state.groupMoveStartedAt = now end
            if (now - state.groupMoveStartedAt) >= SCB.MAINTENANCE_GROUP_MOVE_TIMEOUT then
                SCB_0826FinishMaintenance("failed", "replacement subgroup move timed out",
                    "Bot maintenance stopped because a replacement could not be moved to its raid group.")
                return
            end

            -- One move/swap per observation. Raid indices can change after a
            -- subgroup mutation, so never reuse the remaining cached indices.
            SCB_0826MoveOneMaintenanceBot(state, resolvedBots)
            state.fullSeenAt = nil
            return
        end

        state.groupMoveStartedAt = nil
        state.combatSeenAt = nil
        state.combatOverrideLogged = nil
        if not state.fullSeenAt then
            state.fullSeenAt = now
            return
        end
        if (now - state.fullSeenAt) < 1.0 then return end

        newBots = SCB_GetNewRefillBots and SCB_GetNewRefillBots(state.beforeNames or {}) or {}
        if table.getn(newBots) ~= expected then
            state.fullSeenAt = nil
            return
        end
        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0

        resolvedBots = SCB_0826ResolveMaintenanceBurstBots(state, newBots)
        if not resolvedBots then
            state.fullSeenAt = nil
            return
        end
        if raidCount > 0 and not SCB_0826MaintenanceBurstGroupsReady(state, resolvedBots) then
            state.fullSeenAt = nil
            return
        end

        SCB_0826CompleteMaintenanceBurst(state, resolvedBots)
        return
    end

    SCB_0826FinishMaintenance("failed", "unknown maintenance phase " .. tostring(state.phase),
        "Bot maintenance stopped because its internal phase was invalid.")
end

end

-- SoloCraft Bots - authoritative summon runtime.
--
-- 0.7.3 moves preset summon scheduling fully onto the explicit raid system.
-- RoleTracking may still provide role/name state and compatibility helpers, but
-- it no longer owns the active preset summon lifecycle. All outbound spawn
-- commands pass through one validated sender so internal scheduler markers can
-- never reach SoloCraft's .partybot parser.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_CONVERT_NOW = "__SCB_CONVERT_NOW__"
local SCB_WAIT_RAID = "__SCB_WAIT_RAID__"
local SCB_WAIT_BOOTSTRAP = "__SCB_WAIT_BOOTSTRAP__"
local SCB_WAIT_REAL_RAID_START = SCB.PRESET_WAIT_REAL_RAID_START or "__SCB_WAIT_REAL_RAID_START__"

SCB.PRESET_WAIT_REAL_RAID_START = SCB_WAIT_REAL_RAID_START

local function SCB_GetPresetSafety(create)
    local operation = SCB.botOperation
    if not operation or not operation.active or operation.kind ~= "preset" then return nil end
    if create and not operation.safety then operation.safety = {} end
    return operation.safety
end

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

local function SCB_IsValidatedSpawnCommand(command)
    local classKey, role, extra = SCB_ParseSpawnCommand(command)
    if not classKey or not role then return false end
    if not SCB_IsValidSpawnAssignment then return false end
    return SCB_IsValidSpawnAssignment(classKey, role, extra)
end

local function SCB_SpawnDebug(text)
    if SCB.developerDebugEnabled and SCB_DebugLog then SCB_DebugLog("Spawn", text) end
end

function SCB_SendSpawnCommand(command)
    if not SCB_IsValidatedSpawnCommand(command) then
        SCB_SpawnDebug("Blocked invalid spawn payload: " .. tostring(command))
        return false
    end
    return SCB_SendPartyBotCommand and SCB_SendPartyBotCommand(command, {
        channel = "SAY",
        registerSpawnIntent = true,
    }) or false
end

local function SCB_GetSpawnLabels(classKey, role, extra)
    local classInfo = SCB_FindClass and SCB_FindClass(classKey) or nil
    local roleInfo = SCB_FindRoleEntry and SCB_FindRoleEntry(classInfo, role, extra) or nil
    local classLabel = classInfo and classInfo.name or tostring(classKey or "Bot")
    local roleLabel = roleInfo and roleInfo.label or tostring(role or "")
    return classLabel, roleLabel
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

local function SCB_GetActiveTrackerAssignmentsByGroup(tracker)
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

local function SCB_QueuePlannedBurst(queue, plans, kind, groupIndex, assignments)
    local plan, i
    if not assignments or table.getn(assignments) == 0 then return false end

    plan = { kind = kind or "preset", group = groupIndex, assignments = {} }
    for i = 1, table.getn(assignments) do
        table.insert(plan.assignments, SCB_CopyBurstAssignment(assignments[i]))
    end

    table.insert(queue, SCB.PRESET_CHECK_COMBAT)
    for i = table.getn(assignments), 1, -1 do
        table.insert(queue, assignments[i].command)
    end
    table.insert(plans, plan)
    return true
end

local function SCB_QueueBootstrapBurst(queue, plans)
    local command = SCB_BuildSpawnCommand("warrior", "tank", nil)
    local plan = {
        kind = "bootstrap",
        group = nil,
        assignments = {
            {
                command = command,
                class = "warrior",
                role = "tank",
                extra = nil,
            },
        },
    }
    table.insert(queue, SCB.PRESET_CHECK_COMBAT)
    table.insert(queue, command)
    table.insert(queue, SCB_WAIT_BOOTSTRAP)
    table.insert(plans, plan)
end

local function SCB_HasLaterAssignments(groups, currentGroup, maxGroup)
    local g
    for g = currentGroup + 1, maxGroup do
        if table.getn(groups[g] or {}) > 0 then return true end
    end
    return false
end

local function SCB_ResetPresetBurstPlans(plans)
    SCB.scbPresetBurstPlans = plans or {}
    SCB.scbPresetBurstPlansHead = 1
end

local function SCB_PeekPresetBurstPlan()
    local plans = SCB.scbPresetBurstPlans or {}
    local head = SCB.scbPresetBurstPlansHead or 1
    if head > table.getn(plans) then return nil end
    return plans[head]
end

local function SCB_PopPresetBurstPlan()
    local plan = SCB_PeekPresetBurstPlan()
    if plan then SCB.scbPresetBurstPlansHead = (SCB.scbPresetBurstPlansHead or 1) + 1 end
    return plan
end

local function SCB_ResetSpawnRuntimeState()
    local operation = SCB.botOperation
    SCB.scbExplicitPresetOperation = nil
    SCB.presetSubgroupMoveBarrierRevision = nil
    SCB_ResetPresetBurstPlans()
    SCB.scbCheckPlanArmed = nil
    SCB.scbArmedPresetPlan = nil
    SCB_ResetPresetSpawnQueue()
    if operation and operation.kind == "preset" then operation.safety = nil end
end

local function SCB_StartPresetSummonSnapshotCore(snapshot)
    local valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    local group, size, slots, occupied, tracker, groups
    local queue, plans, groupCount, startBotState, survivorName
    local raidCount, partyCount, needsT3Bootstrap, g, i, player
    local firstAssignment, heldAssignment, expectedBotCount, hasLater
    local kickAllAnchorName, safety

    if not valid then return false, errorText end
    if SCB_PresetSpawnQueueCount() > 0
        or (SCB.presetGroupWaitRemaining or 0) > 0
        or (SCB.presetCombatRetryWaitRemaining or 0) > 0 then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end

    startBotState, survivorName = SCB_GetPresetStartBotState()
    if startBotState == "blocked" then
        return false, SCB_L("ERR_SUMMON_GROUP_NOT_EMPTY")
    end

    size = snapshot.size
    group = { id = snapshot.groupID, name = snapshot.groupName, size = size }
    slots = SCB_CopySlots(snapshot.slots)
    occupied = SCB_GetSnapshotOccupiedSlots(snapshot)
    groupCount = math.ceil(size / 5)
    queue, plans = {}, {}

    SCB_ResetPresetSpawnQueue()
    SCB.presetSpawnElapsed = 0
    SCB.presetGroupWaitRemaining = 0
    SCB.presetCombatRetryWaitRemaining = 0
    SCB.presetCombatPollRemaining = nil
    SCB.presetCombatRetryFailures = 0
    SCB.presetCombatRetryResetPending = nil
    SCB.presetLastBurstCommands = nil
    SCB.presetLastBurstRequeued = nil
    SCB_ResetSpawnRuntimeState()
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end

    safety = SCB_GetPresetSafety(true)
    if not safety then return false, SCB_L("ERR_SUMMON_BUSY") end
    safety.survivorName = survivorName

    tracker = SCB_CreateRaidRoleTracker(slots, size, occupied, group, snapshot)
    if not tracker then return false, SCB_L("ERR_SUMMON_BUSY") end
    groups = SCB_GetActiveTrackerAssignmentsByGroup(tracker)

    if tracker.presetGroupIndex and tracker.presetIndex
        and SoloCraftBotsDB.currentPresetGroup == tracker.presetGroupIndex
        and SCB_CurrentPresetGroup()
        and SCB_CurrentPresetGroup().currentPreset == tracker.presetIndex then
        SCB.scbEditorLayoutTrackerRevision = tracker.layoutRevision or 0
    end

    expectedBotCount = 0
    for g = 1, groupCount do expectedBotCount = expectedBotCount + table.getn(groups[g] or {}) end

    raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    needsT3Bootstrap = size > 5 and startBotState == "empty"
        and raidCount == 0 and partyCount == 0
        and SCB_IsT3RaidLocation and SCB_IsT3RaidLocation()

    if size > 5 then
        SCB.presetHumanGroups = {}
        for i = 1, table.getn(snapshot.players or {}) do
            player = snapshot.players[i]
            if player.group and player.group >= 1 and player.group <= groupCount then
                SCB.presetHumanGroups[player.name] = player.group
            end
        end

        if startBotState == "survivor" then
            if table.getn(groups[1] or {}) == 0 then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            if raidCount == 0 then table.insert(queue, SCB_CONVERT_NOW) end
            safety.parkBeforeArrange = true
            safety.removeAfterGroupOne = true
        elseif raidCount > 0 then
        elseif partyCount > 0 then
            table.insert(queue, SCB_CONVERT_NOW)
        elseif needsT3Bootstrap then
            SCB_QueueBootstrapBurst(queue, plans)
            safety.parkBeforeArrange = true
            safety.removeAfterGroupOne = true
        else
            firstAssignment = groups[1] and groups[1][1] or nil
            if not firstAssignment then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            SCB_QueuePlannedBurst(queue, plans, "preset", 1, { firstAssignment })
            table.remove(groups[1], 1)
            table.insert(queue, SCB_WAIT_REAL_RAID_START)
        end

        table.insert(queue, SCB.PRESET_ARRANGE_PLAYERS)
    else
        SCB.presetHumanGroups = nil

        if startBotState == "survivor" then
            if table.getn(groups[1] or {}) == 0 then
                return false, SCB_L("ERR_SURVIVOR_NO_SLOT")
            end
            kickAllAnchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild() or nil
            if kickAllAnchorName and kickAllAnchorName == survivorName then
                heldAssignment = groups[1][table.getn(groups[1])]
                table.remove(groups[1], table.getn(groups[1]))
            else
                heldAssignment = groups[1][1]
                table.remove(groups[1], 1)
            end
            safety.expectedBotCountBeforeHandoff = expectedBotCount
        end
    end

    for g = 1, groupCount do
        if table.getn(groups[g] or {}) > 0 then
            SCB_QueuePlannedBurst(queue, plans, "preset", g, groups[g])
            hasLater = SCB_HasLaterAssignments(groups, g, groupCount)
            if hasLater then table.insert(queue, SCB.PRESET_WAIT_GROUP) end
        end
    end

    if heldAssignment then
        table.insert(queue, SCB.PRESET_WAIT_FINAL_ROSTER)
        table.insert(queue, SCB.PRESET_REMOVE_SURVIVOR)
        table.insert(queue, SCB.PRESET_WAIT_SURVIVOR_GONE)
        SCB_QueuePlannedBurst(queue, plans, "preset", heldAssignment.group or 1, { heldAssignment })
    end

    table.insert(queue, SCB.PRESET_TRACK_ROSTER)

    SCB_ResetPresetSpawnQueue(queue)
    SCB_ResetPresetBurstPlans(plans)
    SCB.scbExplicitPresetOperation = true
    if SCB_WakePresetSpawnScheduler then SCB_WakePresetSpawnScheduler() end
    SCB.scbCheckPlanArmed = nil
    SCB.scbArmedPresetPlan = nil
    if SCB_RefreshRefillButton then SCB_RefreshRefillButton() end
    return true
end

local function SCB_PresetBotCount(snapshot)
    local humans = table.getn(snapshot and snapshot.players or {})
    local count = (snapshot and snapshot.size or 0) - humans
    if count < 0 then count = 0 end
    return count
end


local function SCB_ShouldRemoveParkedSurvivor(head)
    local safety = SCB_GetPresetSafety(false)
    local plan
    if not safety or not safety.removeAfterGroupOne then return false end
    if head == SCB.PRESET_TRACK_ROSTER then return true end
    if head ~= SCB.PRESET_CHECK_COMBAT then return false end
    plan = SCB_PeekPresetBurstPlan()
    return plan and plan.kind == "preset" and plan.group and plan.group > 1
end

local function SCB_AbortInvalidSchedulerItem(item)
    SCB_SpawnDebug("Aborting on invalid scheduler item: " .. tostring(item))
    if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
    SCB_Print("Summon aborted because the internal summon queue was invalid.")
end

local function SCB_PresetSpawnQueueOnUpdateCore()
    local elapsed = arg1 or 0
    local queue = SCB.presetSpawnQueue or {}
    local head, plan, retry, bootstrapName
    local now, settleDelay, safety

    if SCB_PresetRebuildOnUpdate then SCB_PresetRebuildOnUpdate() end
    if SCB_MaintenanceReplaceOnUpdate then SCB_MaintenanceReplaceOnUpdate() end
    if SCB_RefillOnUpdate then SCB_RefillOnUpdate(elapsed) end

    if not SCB.scbExplicitPresetOperation then return end

    if SCB.presetGroupWaitRemaining and SCB.presetGroupWaitRemaining > 0 then
        SCB.presetGroupWaitRemaining = SCB.presetGroupWaitRemaining - elapsed
        if SCB.presetGroupWaitRemaining > 0 then return end
        SCB.presetGroupWaitRemaining = 0
        if SCB.presetCombatRetryResetPending then
            SCB.presetCombatRetryFailures = 0
            SCB.presetCombatRetryResetPending = nil
        end
        return
    end

    if SCB.presetCombatRetryWaitRemaining and SCB.presetCombatRetryWaitRemaining > 0 then
        SCB.presetCombatRetryWaitRemaining = SCB.presetCombatRetryWaitRemaining - elapsed
        if SCB.presetCombatRetryWaitRemaining > 0 then return end
        SCB.presetCombatRetryWaitRemaining = 0
        return
    end

    while SCB_PresetSpawnQueueCount() > 0 do
        head = SCB_PresetSpawnQueuePeek()

        if SCB_ShouldRemoveParkedSurvivor(head) and not SCB.presetLastBurstRequeued then
            if not SCB.scb072TryRemoveParkedSurvivor
                or not SCB.scb072TryRemoveParkedSurvivor() then
                return
            end
            head = SCB_PresetSpawnQueuePeek()
        end

        if head == SCB.PRESET_WAIT_GROUP then
            SCB_PresetSpawnQueuePop()
            SCB.presetGroupWaitRemaining = 1.0
            if (SCB.presetCombatRetryFailures or 0) > 0 then
                SCB.presetCombatRetryResetPending = true
            end
            SCB.presetSpawnElapsed = 0
            return

        elseif head == SCB.PRESET_ARRANGE_PLAYERS then
            safety = SCB_GetPresetSafety(false)
            if safety and safety.parkBeforeArrange then
                if not SCB.scb072TryParkSurvivorInGroupEight
                    or not SCB.scb072TryParkSurvivorInGroupEight() then
                    return
                end
                safety.parkBeforeArrange = nil
            end
            if SCB_ArrangePresetPlayers and SCB_ArrangePresetPlayers() then
                if not SCB_PresetSubgroupMoveBarrierPassed() then return end
                SCB_PresetSpawnQueuePop()
                SCB.presetSpawnElapsed = 0
            else
                return
            end

        elseif head == SCB.PRESET_TRACK_ROSTER then
            if SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker then
                SoloCraftBotsCharDB.raidRoleTracker.allowFinalize = true
            end
            if SCB_TryFinalizeRaidRoleTracking
                and SCB_TryFinalizeRaidRoleTracking(SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil) then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                SCB_PresetSpawnQueuePop()
                SCB.presetSpawnElapsed = 0
            else
                return
            end

        elseif head == SCB.PRESET_CHECK_COMBAT then
            SCB.presetCombatPollRemaining = (SCB.presetCombatPollRemaining or 0) - elapsed
            if SCB.presetCombatPollRemaining > 0 then return end
            if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then
                SCB.presetCombatPollRemaining = 0.50
                return
            end
            SCB.presetCombatPollRemaining = nil

            retry = SCB.presetLastBurstRequeued == true
            if not retry then
                plan = SCB_PopPresetBurstPlan()
                if not plan or not SCB_BeginAssumedSpawnBurst
                    or not SCB_BeginAssumedSpawnBurst(plan) then
                    SCB_AbortInvalidSchedulerItem("missing explicit burst plan")
                    return
                end
                SCB.scbArmedPresetPlan = plan
            else
                SCB.scbArmedPresetPlan = nil
            end

            SCB.presetLastBurstCommands = {}
            SCB.presetLastBurstRequeued = nil
            SCB_PresetSpawnQueuePop()
            SCB.presetSpawnElapsed = 0

        elseif head == SCB_CONVERT_NOW then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                SCB_PresetSpawnQueuePop()
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                SCB_PresetSpawnQueueReplaceHead(SCB_WAIT_RAID)
                return
            else
                return
            end

        elseif head == SCB_WAIT_BOOTSTRAP then
            bootstrapName = SCB_FindFirstGroupBotName and SCB_FindFirstGroupBotName() or nil
            if not bootstrapName then return end

            safety = SCB_GetPresetSafety(true)
            if not safety then
                SCB_AbortInvalidSchedulerItem("missing preset safety state")
                return
            end

            SCB.presetCombatRetryFailures = 0
            SCB.presetCombatRetryResetPending = nil
            safety.bootstrapName = bootstrapName
            safety.survivorName = bootstrapName
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                SCB_PresetSpawnQueueReplaceHead(SCB_WAIT_RAID)
            elseif ConvertToRaid then
                ConvertToRaid()
                SCB_PresetSpawnQueueReplaceHead(SCB_WAIT_RAID)
            else
                return
            end
            return

        elseif head == SCB_WAIT_REAL_RAID_START then
            if not SCB_FindFirstGroupBotName or not SCB_FindFirstGroupBotName() then return end

            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                SCB_PresetSpawnQueuePop()
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                SCB_PresetSpawnQueueReplaceHead(SCB_WAIT_RAID)
                return
            else
                return
            end

        elseif head == SCB_WAIT_RAID then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                SCB_PresetSpawnQueuePop()
            else
                return
            end

        elseif head == SCB.PRESET_WAIT_FINAL_ROSTER then
            safety = SCB_GetPresetSafety(false)
            if not safety then
                SCB_AbortInvalidSchedulerItem("missing preset safety state")
                return
            end
            if SCB_CountGroupBots and SCB_CountGroupBots() >= (safety.expectedBotCountBeforeHandoff or 0) then
                SCB_PresetSpawnQueuePop()
            else
                return
            end

        elseif head == SCB.PRESET_REMOVE_SURVIVOR then
            safety = SCB_GetPresetSafety(false)
            if not safety then
                SCB_AbortInvalidSchedulerItem("missing preset safety state")
                return
            end
            if safety.survivorName then
                if not SCB_KickBots or not SCB_KickBots("all", {
                    name = safety.survivorName,
                    manageSafety = false,
                    silent = true,
                }) then
                    return
                end
            end
            safety.partySurvivorGoneAt = nil
            SCB_PresetSpawnQueuePop()
            return

        elseif head == SCB.PRESET_WAIT_SURVIVOR_GONE then
            safety = SCB_GetPresetSafety(false)
            if not safety then
                SCB_AbortInvalidSchedulerItem("missing preset safety state")
                return
            end
            if safety.survivorName and SCB_GroupHasName
                and SCB_GroupHasName(safety.survivorName) then
                safety.partySurvivorGoneAt = nil
                return
            end

            now = GetTime and GetTime() or 0
            if not safety.partySurvivorGoneAt then
                safety.partySurvivorGoneAt = now
                return
            end
            settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
            if GetTime and (now - safety.partySurvivorGoneAt) < settleDelay then return end

            if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(safety.survivorName) end
            safety.survivorName = nil
            safety.expectedBotCountBeforeHandoff = nil
            safety.partySurvivorGoneAt = nil
            SCB_PresetSpawnQueuePop()

        elseif SCB_IsSpawnCommandString(head) then
            if not SCB_SendSpawnCommand(head) then
                SCB_AbortInvalidSchedulerItem(head)
                return
            end
            SCB.presetLastBurstCommands = SCB.presetLastBurstCommands or {}
            table.insert(SCB.presetLastBurstCommands, head)
            SCB_PresetSpawnQueuePop()
            if SCB.scbArmedPresetPlan then
                SCB.scbArmedPresetPlan.released = true
            end

        elseif type(head) == "string" and string.find(head, "^__SCB_") then
            SCB_AbortInvalidSchedulerItem(head)
            return

        else
            SCB_AbortInvalidSchedulerItem(head)
            return
        end
    end

    if SCB_PresetSpawnQueueCount() == 0
        and (SCB.presetGroupWaitRemaining or 0) <= 0
        and (SCB.presetCombatRetryWaitRemaining or 0) <= 0 then
        SCB_ResetSpawnRuntimeState()
    end
end

-- -------------------------------------------------------------------------
-- Bot-lifecycle operation coordinator (absorbed from SpawnOperation.lua).
-- -------------------------------------------------------------------------

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

SCB.botOperationSerial = SCB.botOperationSerial or 0
SCB.botOperation = SCB.botOperation or nil
SCB.lastBotOperation = SCB.lastBotOperation or nil

local function SCB_OperationNow()
    return GetTime and GetTime() or 0
end

local function SCB_OperationPresetName(operation)
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil
    return snapshot and snapshot.presetName or nil
end

local function SCB_PendingBotAddsStillActive()
    local pending = tonumber(SCB.pendingBotAdds) or 0
    local expires = tonumber(SCB.pendingBotAddsExpires) or 0
    local now = SCB_OperationNow()

    if pending <= 0 then return false end

    if GetTime and expires > 0 and now > expires then
        SCB.pendingBotAdds = 0
        SCB.pendingBotAddsExpires = 0
        return false
    end
    return true
end

local function SCB_HasLegacyPhysicalBotRuntime()
    return (SCB_PresetSpawnQueueCount and SCB_PresetSpawnQueueCount() > 0)
        or (SCB.presetGroupWaitRemaining or 0) > 0
        or (SCB.presetCombatRetryWaitRemaining or 0) > 0
        or (SCB.refillState and SCB.refillState.active)
        or (SCB.replaceDeadState and SCB.replaceDeadState.active)
        or (SCB.presetRebuildState and SCB.presetRebuildState.active)
        or (SCB.activeRosterTransition and SCB.activeRosterTransition.kind == "preset")
end

local function SCB_SetCoordinatorRebuildSentinel(operation, active)
    if active then
        SCB.presetRebuildState = {
            active = true,
            coordinator = true,
            operationID = operation and operation.id or nil,
        }
        return
    end

    if SCB.presetRebuildState and SCB.presetRebuildState.coordinator then
        SCB.presetRebuildState = nil
    end
end

local function SCB_ClearOperationRebuild(operation)
    if operation then operation.rebuild = nil end
    SCB_SetCoordinatorRebuildSentinel(operation, false)
end

function SCB_GetActiveBotOperation()
    local operation = SCB.botOperation
    if operation and operation.active then return operation end
    return nil
end

function SCB_GetBotOperationSafety(create)
    return SCB_GetPresetSafety(create)
end

function SCB_SetBotOperationPhase(phase)
    local operation = SCB_GetActiveBotOperation()
    if not operation or not phase then return false end
    if operation.phase ~= phase then
        operation.phase = phase
        operation.updatedAt = SCB_OperationNow()
    end
    return true
end

function SCB_BeginBotOperation(kind, intent)
    local operation = SCB_GetActiveBotOperation()
    if operation then return nil end

    SCB.botOperationSerial = (SCB.botOperationSerial or 0) + 1
    operation = {
        id = SCB.botOperationSerial,
        kind = kind,
        active = true,
        status = "active",
        phase = "requested",
        revision = 1,
        desiredIntent = intent,
        startedAt = SCB_OperationNow(),
        updatedAt = SCB_OperationNow(),
    }
    SCB.botOperation = operation
    if SCB_WakePresetSpawnScheduler then SCB_WakePresetSpawnScheduler() end
    return operation
end

function SCB_ReplaceBotOperationIntent(kind, intent)
    local operation = SCB_GetActiveBotOperation()
    if not operation then
        return SCB_BeginBotOperation(kind, intent)
    end

    operation.kind = kind or operation.kind
    operation.desiredIntent = intent
    operation.revision = (operation.revision or 1) + 1
    operation.phase = "replacing"
    operation.updatedAt = SCB_OperationNow()
    return operation
end

function SCB_EndBotOperation(status, reason)
    local operation = SCB_GetActiveBotOperation()
    local endedAt
    if not operation then return nil end

    SCB_ClearOperationRebuild(operation)
    operation.safety = nil

    endedAt = SCB_OperationNow()
    operation.active = false
    operation.status = status or "complete"
    operation.endedAt = endedAt
    operation.updatedAt = endedAt
    operation.reason = reason

    SCB.lastBotOperation = {
        id = operation.id,
        kind = operation.kind,
        status = operation.status,
        phase = operation.phase,
        revision = operation.revision,
        presetName = SCB_OperationPresetName(operation),
        startedAt = operation.startedAt,
        endedAt = operation.endedAt,
        reason = reason,
    }
    SCB.botOperation = nil
    return operation
end

function SCB_AbortBotOperation(reason)
    return SCB_EndBotOperation("aborted", reason)
end

function SCB_AbortBotSpawnOperations(preserveOperation)
    local operation = SCB_GetActiveBotOperation()

    if operation and operation.kind == "maintenance" then
        SCB_ResetSpawnRuntimeState()
        if SCB.scb0826SetMaintenanceSentinel then SCB.scb0826SetMaintenanceSentinel(operation, false) end
        if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
        if SCB_EndBotOperation then SCB_EndBotOperation("aborted", "maintenance runtime aborted") end
        if SCB_SyncActiveRosterFromObserved then SCB_SyncActiveRosterFromObserved() end
        if SCB_RefreshReplaceDeadButton then SCB_RefreshReplaceDeadButton() end
        SCB_ResetSpawnRuntimeState()
        if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
        return
    end

    if operation and operation.kind == "preset" then operation.safety = nil end
    if preserveOperation and operation then
        SCB_ClearOperationRebuild(operation)
        operation.phase = "replacing"
        operation.updatedAt = SCB_OperationNow()
    end

    SCB_ResetSpawnRuntimeState()
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
    local result
    if SCB_AbortBotSpawnOperationsCore then result = SCB_AbortBotSpawnOperationsCore() end
    SCB_ResetSpawnRuntimeState()
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
    if not preserveOperation then SCB_AbortBotOperation("spawn runtime aborted") end
    return result
end

function SCB_ResetSessionState()
    SCB_AbortBotOperation("session reset")
    SCB_ResetSpawnRuntimeState()
    if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
    SCB.assumedRolesByName = {}
    SCB_EnsureSessionDB()
    SoloCraftBotsDB.session.knownBots = {}
    SoloCraftBotsDB.session.state = { distance = "near" }
end

local function SCB_PresetOperationIntent(snapshot, forced)
    return {
        kind = "preset",
        snapshot = snapshot,
        presetName = snapshot and snapshot.presetName or nil,
        forceCombatTeardown = forced and true or nil,
    }
end

local function SCB_BeginCoordinatorRebuild(operation, waitForPendingAdds)
    operation.rebuild = {
        readySeenAt = nil,
        waitForPendingAdds = waitForPendingAdds and true or nil,
        handoffQueued = nil,
        scbConvertRequestedAt = nil,
    }
    SCB_SetCoordinatorRebuildSentinel(operation, true)
    SCB_SetBotOperationPhase("rebuild")
end

local function SCB_StartCoordinatorPresetRuntime(operation)
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil
    local botCount, pendingAdds, ok, errorText

    if not snapshot then return false, SCB_L("ERR_SELECT_PRESET") end

    SCB_ClearOperationRebuild(operation)

    if SCB.refillState and SCB.refillState.active then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end
    if SCB.replaceDeadState and SCB.replaceDeadState.active then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end

    botCount = SCB_CountGroupBots and SCB_CountGroupBots() or 0
    pendingAdds = SCB_PendingBotAddsStillActive()
    if not intent.forceCombatTeardown
        and (botCount > 0 or pendingAdds)
        and SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then
        return false, SCB_L("ERR_SUMMON_COMBAT_TEARDOWN")
    end

    if pendingAdds then
        SCB_BeginCoordinatorRebuild(operation, true)
        if SCB_BeginActiveRosterPresetTransition then
            SCB_BeginActiveRosterPresetTransition(snapshot.size)
        end
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator waiting for in-flight bot adds before preset replacement")
        end
        return true
    end

    if botCount == 0 then
        if SCB_BeginActiveRosterPresetTransition then
            SCB_BeginActiveRosterPresetTransition(snapshot.size)
        end
        ok, errorText = SCB_StartPresetSummonSnapshot(snapshot)
        if not ok and SCB_CancelActiveRosterPresetTransition then
            SCB_CancelActiveRosterPresetTransition()
        end
        if ok then SCB_SetBotOperationPhase("summon") end
        return ok, errorText
    end

    SCB_BeginCoordinatorRebuild(operation, false)
    if SCB_KickBots then SCB_KickBots("all") end
    if SCB_BeginActiveRosterPresetTransition then
        SCB_BeginActiveRosterPresetTransition(snapshot.size)
    end
    return true
end

function SCB_RequestPresetOperation(snapshot, forced)
    local operation, ok, errorText
    local intent = SCB_PresetOperationIntent(snapshot, forced)

    if forced then
        operation = SCB_ReplaceBotOperationIntent("preset", intent)
    else
        if SCB_GetActiveBotOperation() or SCB_HasLegacyPhysicalBotRuntime() then
            return false, SCB_L("ERR_SUMMON_BUSY")
        end
        operation = SCB_BeginBotOperation("preset", intent)
    end

    if not operation then return false, SCB_L("ERR_SUMMON_BUSY") end

    ok, errorText = SCB_StartCoordinatorPresetRuntime(operation)
    if not ok then
        SCB_EndBotOperation("failed", errorText)
        return false, errorText
    end
    return true
end

function SCB_StartPresetRebuild(snapshot, forced)
    return SCB_RequestPresetOperation(snapshot, forced == true)
end

function SCB_PresetRebuildOnUpdate()
    local operation = SCB_GetActiveBotOperation()
    local state = operation and operation.rebuild or nil
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil
    local now = SCB_OperationNow()
    local anchorName, botCount, ready, raidCount, partyCount, observed
    local ok, errorText

    if not operation or operation.kind ~= "preset" or not state or not snapshot then return end

    if state.handoffQueued then
        SCB.scbExplicitPresetOperation = true
        SCB_ClearOperationRebuild(operation)
        SCB_SetBotOperationPhase("summon")
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator released replacement queue on next frame")
        end
        return
    end

    if state.waitForPendingAdds then
        if SCB_PendingBotAddsStillActive() then return end

        state.waitForPendingAdds = nil
        state.readySeenAt = nil
        observed = SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil
        botCount = SCB_CountGroupBots and SCB_CountGroupBots(observed) or 0

        if botCount > 0 then
            if not intent.forceCombatTeardown
                and SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then
                return
            end
            if SCB.developerDebugEnabled and SCB_DebugLog then
                SCB_DebugLog("Spawn", "In-flight bot adds resolved; coordinator tearing down " .. tostring(botCount) .. " arrived bot(s)")
            end
            if SCB_KickBots then SCB_KickBots("all") end
            return
        end

        state.readySeenAt = now - (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0)
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "In-flight bot adds expired with no arrivals; coordinator continuing preset summon")
        end
    end

    observed = SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil
    anchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild(observed) or nil
    botCount = SCB_CountGroupBots and SCB_CountGroupBots(observed) or 0

    ready = botCount == 0 or (anchorName ~= nil and botCount == 1)
    if not ready then
        state.readySeenAt = nil
        state.scbConvertRequestedAt = nil
        return
    end

    if not state.readySeenAt then state.readySeenAt = now end

    if (snapshot.size or 0) > 5 and anchorName and botCount == 1 then
        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount == 0 then
            partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
            if partyCount > 0 and ConvertToRaid then
                if not state.scbConvertRequestedAt or (now - state.scbConvertRequestedAt) >= 1.0 then
                    ConvertToRaid()
                    state.scbConvertRequestedAt = now
                    if SCB.developerDebugEnabled and SCB_DebugLog then
                        SCB_DebugLog("Spawn", "Coordinator requested party-to-raid conversion with survivor " .. tostring(anchorName))
                    end
                end
            end
            return
        end

        if SCB.scb072TryParkSurvivorInGroupEight
            and not SCB.scb072TryParkSurvivorInGroupEight(anchorName) then
            return
        end
    end

    state.scbConvertRequestedAt = nil

    if now - state.readySeenAt < (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0) then return end

    ok, errorText = SCB_StartPresetSummonSnapshot(snapshot)
    if ok then
        state.handoffQueued = true
        SCB.scbExplicitPresetOperation = nil
        SCB_SetBotOperationPhase("handoff")
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator prepared replacement queue; deferring scheduler release one frame")
        end
        return
    end

    if errorText then SCB_Print(errorText) end
    if SCB_CancelActiveRosterPresetTransition then SCB_CancelActiveRosterPresetTransition() end
    SCB_EndBotOperation("failed", errorText)
end


local function SCB_SyncPresetOperationPhase()
    local operation = SCB_GetActiveBotOperation()
    local rebuild
    if not operation or operation.kind ~= "preset" then return end

    rebuild = operation.rebuild
    if rebuild then
        if rebuild.handoffQueued then
            SCB_SetBotOperationPhase("handoff")
        else
            SCB_SetBotOperationPhase("rebuild")
        end
        return
    end

    if SCB.scbExplicitPresetOperation
        or SCB_PresetSpawnQueueCount() > 0
        or (SCB.presetGroupWaitRemaining or 0) > 0
        or (SCB.presetCombatRetryWaitRemaining or 0) > 0 then
        SCB_SetBotOperationPhase("summon")
        return
    end

    SCB_EndBotOperation("complete", nil)
end

-- -------------------------------------------------------------------------
-- Bootstrap continuity (absorbed from SpawnBootstrap.lua in 0.8.25).
-- -------------------------------------------------------------------------

function SCB_StartPresetSummonSnapshot(snapshot)
    local ok, errorText = SCB_StartPresetSummonSnapshotCore(snapshot)
    local safety, anchorName, size
    if not ok then return ok, errorText end

    safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
    anchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild() or nil
    size = tonumber(snapshot and snapshot.size) or 0
    if safety and anchorName and safety.survivorName == anchorName then
        safety.bootstrapName = anchorName
        safety.bootstrapTopology = size > 5 and "raid" or "party"
        safety.bootstrapOrigin = "retained"
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "Retained " .. tostring(anchorName)
                .. " as " .. tostring(safety.bootstrapTopology)
                .. " bootstrap for preset rebuild")
        end
    end
    return ok, errorText
end

local function SCB_0823BootstrapSafety()
    local safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
    if not safety or not safety.bootstrapName or not safety.removeAfterGroupOne then
        return nil
    end

    if not safety.bootstrapTopology then safety.bootstrapTopology = "raid" end
    if not safety.bootstrapOrigin then safety.bootstrapOrigin = "created" end
    return safety
end

local function SCB_0823HasRealGroupOneBot(bootstrapName)
    local roster = SCB_GetLiveRoster and SCB_GetLiveRoster(false) or nil
    local group = roster and roster.groups and roster.groups[1] or {}
    local i, member, assumption
    if not bootstrapName then return false end

    for i = 1, table.getn(group) do
        member = group[i]
        if member and member.isBot and member.name ~= bootstrapName then
            assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[member.name] or nil
            if not assumption or assumption.spawnKind ~= "bootstrap" then return true end
        end
    end
    return false
end

local function SCB_0823FinishBootstrapRemoval(safety, name)
    if SCB_ClearKickAllAnchor then SCB_ClearKickAllAnchor(name) end
    safety.survivorName = nil
    safety.bootstrapName = nil
    safety.bootstrapTopology = nil
    safety.bootstrapOrigin = nil
    safety.removeAfterGroupOne = nil
    safety.removalWaiting = nil
    safety.removalName = nil
    safety.removalGoneAt = nil
    if SCB.developerDebugEnabled and SCB_DebugLog then
        SCB_DebugLog("Spawn", "Bootstrap " .. tostring(name) .. " removal settle completed in parallel with preset bursts")
    end
end

local function SCB_0823PollBootstrapRemoval()
    local safety = SCB_0823BootstrapSafety()
    local name, now, settleDelay

    if not safety then return true end
    name = safety.removalName or safety.bootstrapName
    if not name then
        safety.removeAfterGroupOne = nil
        safety.bootstrapTopology = nil
        safety.bootstrapOrigin = nil
        return true
    end

    if safety.removalWaiting then
        if SCB_GroupHasName and SCB_GroupHasName(name) then
            safety.removalGoneAt = nil
            return false
        end

        now = GetTime and GetTime() or 0
        if not safety.removalGoneAt then
            safety.removalGoneAt = now
            return false
        end

        settleDelay = SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0
        if not GetTime or (now - safety.removalGoneAt) >= settleDelay then
            SCB_0823FinishBootstrapRemoval(safety, name)
            return true
        end
        return false
    end

    if not SCB_0823HasRealGroupOneBot(name) then return false end
    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end

    if SCB_KickBots and SCB_KickBots("all", {
        name = name,
        manageSafety = false,
        silent = true,
    }) then
        safety.removalWaiting = true
        safety.removalName = name
        safety.removalGoneAt = nil
        if SCB.developerDebugEnabled and SCB_DebugLog then
            SCB_DebugLog("Spawn", "Bootstrap " .. tostring(name) .. " removal requested; unrelated preset bursts may continue")
        end
    end
    return false
end

local function SCB_0823CurrentBurstNeedsFreedCapacity()
    local plans = SCB.scbPresetBurstPlans or {}
    local head = SCB.scbPresetBurstPlansHead or 1
    local current = plans[head]
    local i, plan

    if not current or current.kind ~= "preset" then return false end
    for i = head + 1, table.getn(plans) do
        plan = plans[i]
        if plan and plan.kind == "preset" then return false end
    end
    return true
end

SCB.scb072TryRemoveParkedSurvivor = function()
    local safety = SCB_0823BootstrapSafety()
    local queue, head
    if not safety then
        if SCB.scb072TryRemoveParkedSurvivorBase then return SCB.scb072TryRemoveParkedSurvivorBase() end
        return true
    end

    SCB_0823PollBootstrapRemoval()
    safety = SCB_0823BootstrapSafety()
    if not safety then return true end
    queue = SCB.presetSpawnQueue or {}
    head = SCB_PresetSpawnQueuePeek()
    if head == SCB.PRESET_TRACK_ROSTER then return false end
    if head == SCB.PRESET_CHECK_COMBAT
        and not SCB.presetLastBurstRequeued
        and SCB_0823CurrentBurstNeedsFreedCapacity() then
        return false
    end
    return true
end

function SCB_PresetSpawnQueueOnUpdate()
    local elapsed = arg1 or 0
    if SCB_PollOperationRosterFallback then SCB_PollOperationRosterFallback(elapsed, 0.25) end
    SCB_0823PollBootstrapRemoval()
    SCB_SyncPresetOperationPhase()
    local result = SCB_PresetSpawnQueueOnUpdateCore()
    SCB_SyncPresetOperationPhase()
    if not SCB_GetActiveBotOperation() and not SCB_HasLegacyPhysicalBotRuntime() then
        if SCB.presetSpawnQueueFrame then SCB.presetSpawnQueueFrame:Hide() end
    end
    return result
end
