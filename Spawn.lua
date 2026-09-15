-- SoloCraft Bots - authoritative summon runtime and bot lifecycle coordinator.
--
-- 0.8.29 structurally absorbs the former RaidBurst.lua file. Keep its code in
-- a scoped prelude so its historical pre-Spawn execution and wrapper order stay intact.
do
-- SoloCraft Bots - transitional burst safety and maintenance coordinator.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

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
    if SCB_DebugLog then SCB_DebugLog("Burst", text) end
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
        nextHead = SCB.presetSpawnQueue and SCB.presetSpawnQueue[1] or nil
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
        SCB_BurstDebug("Safety " .. tostring(name) .. " removed after real G1 join")
        return true
    end

    if not SCB_HasRealGroupOneBot(name) then return false end
    if SCB_PresetGroupHasCombat and SCB_PresetGroupHasCombat() then return false end
    if UninviteByName then
        UninviteByName(name)
        safety.removalWaiting = true
        safety.removalName = name
        safety.removalGoneAt = nil
        return false
    end
    return false
end

SCB.scb072TryParkSurvivorInGroupEight = SCB_TryParkSurvivorInGroupEight
SCB.scb072TryRemoveParkedSurvivor = SCB_TryRemoveParkedSurvivor

-- -------------------------------------------------------------------------
-- Maintenance coordinator (absorbed from RaidRefill.lua in 0.8.28).
-- -------------------------------------------------------------------------

SCB.MAINTENANCE_REMOVAL_TIMEOUT = 15.0
SCB.MAINTENANCE_BURST_TIMEOUT = 12.0
SCB.MAINTENANCE_GROUP_MOVE_TIMEOUT = 15.0
SCB.MAINTENANCE_STALE_COMBAT_DELAY = 10.0

local function SCB_0826MaintenanceDebug(text)
    if SCB_DebugLog then SCB_DebugLog("Spawn", "Maintenance: " .. tostring(text)) end
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

local function SCB_0826BeginMaintenanceBurst(operation, state, now)
    local group = state.remaining[1] and (state.remaining[1].group or 1) or nil
    local assignments, plan = {}, nil
    local i, assignment

    if not group then return false end
    for i = 1, table.getn(state.remaining) do
        assignment = state.remaining[i]
        if (assignment.group or 1) == group then
            table.insert(assignments, assignment)
        end
    end
    if table.getn(assignments) == 0 then return false end

    plan = { kind = "maintenance", group = group, assignments = {} }
    for i = 1, table.getn(assignments) do
        table.insert(plan.assignments, SCB_CopyBurstAssignment(assignments[i]))
    end
    if not SCB_BeginAssumedSpawnBurst or not SCB_BeginAssumedSpawnBurst(plan) then
        SCB_0826FinishMaintenance("failed", "maintenance identity burst could not start",
            "Bot maintenance stopped because replacement identity could not be prepared.")
        return false
    end

    state.group = group
    state.currentAssignments = assignments
    state.beforeNames = SCB_0826CollectCurrentBotNames()
    state.fullSeenAt = nil
    state.groupMoveStartedAt = nil
    state.burstStartedAt = now
    state.phase = "waitgroup"
    state.combatSeenAt = nil
    state.combatOverrideLogged = nil
    if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-spawn") end

    for i = table.getn(assignments), 1, -1 do
        assignment = assignments[i]
        if not SCB_SendSpawnCommand or not SCB_SendSpawnCommand(assignment.command) then
            SCB_0826FinishMaintenance("failed", "maintenance spawn payload rejected",
                "Bot maintenance stopped because a replacement command was invalid.")
            return false
        end
        SCB_0826MaintenanceDebug(
            "requested G" .. tostring(group)
            .. " slot " .. tostring(assignment.slotIndex or "?")
            .. " " .. tostring(assignment.class or "?")
            .. " " .. tostring(assignment.role or "?")
        )
    end
    return true
end

local function SCB_0826CompleteMaintenanceBurst(state, newBots)
    local i
    for i = 1, table.getn(state.currentAssignments or {}) do
        local assignment = state.currentAssignments[i]
        local bot = newBots[i]
        assignment.botName = bot and bot.name or nil
        if assignment.activeSlotID and bot and SCB_BindReplacementToActiveSlot then
            SCB_BindReplacementToActiveSlot(assignment.activeSlotID, bot.name, state.group)
        end
    end

    for i = 1, table.getn(state.currentAssignments or {}) do
        table.remove(state.remaining, 1)
    end

    if SCB_ApplyTrackedPfUITankRoles then
        SCB_ApplyTrackedPfUITankRoles(SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker)
    end

    state.group = nil
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

    if next(removedNames) ~= nil then
        state.phase = "waitremoved"
        state.removalStartedAt = now
        if SCB_SetBotOperationPhase then SCB_SetBotOperationPhase("maintenance-remove") end
        for i = 1, table.getn(dead) do
            slot = dead[i]
            if slot.currentName and removedNames[slot.currentName] then
                UninviteByName(slot.currentName)
            end
        end
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
    local newBots, expected, raidCount, i, allMoved

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
        if table.getn(state.remaining or {}) == 0 then
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
                if SCB_GroupHasName and SCB_GroupHasName(state.survivorName) and UninviteByName then
                    UninviteByName(state.survivorName)
                end
                SCB_0826MaintenanceDebug("removed retained safety bot " .. tostring(state.survivorName))
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

        raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if raidCount > 0 then
            allMoved = true
            for i = 1, table.getn(newBots) do
                if newBots[i].subgroup ~= state.group then allMoved = false break end
            end

            if not allMoved then
                if SCB_0826MaintenanceCombatBlocked(state, now) then return end
                if not state.groupMoveStartedAt then state.groupMoveStartedAt = now end
                if (now - state.groupMoveStartedAt) >= SCB.MAINTENANCE_GROUP_MOVE_TIMEOUT then
                    SCB_0826FinishMaintenance("failed", "replacement subgroup move timed out",
                        "Bot maintenance stopped because a replacement could not be moved to its raid group.")
                    return
                end
                if SetRaidSubgroup then
                    for i = 1, table.getn(newBots) do
                        if newBots[i].subgroup ~= state.group and newBots[i].raidIndex then
                            SetRaidSubgroup(newBots[i].raidIndex, state.group)
                        end
                    end
                end
                state.fullSeenAt = nil
                return
            end
        end

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
        if raidCount > 0 then
            for i = 1, table.getn(newBots) do
                if newBots[i].subgroup ~= state.group then
                    state.fullSeenAt = nil
                    return
                end
            end
        end

        SCB_0826CompleteMaintenanceBurst(state, newBots)
        return
    end

    SCB_0826FinishMaintenance("failed", "unknown maintenance phase " .. tostring(state.phase),
        "Bot maintenance stopped because its internal phase was invalid.")
end

local SCB_0826PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_0826PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations()
        local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
        if operation and operation.kind == "maintenance" then
            -- Maintenance already stores its physical lifecycle in botOperation.
            -- Do not fall through to the legacy global abort here: that path also
            -- destroys the persistent preset tracker, which is unrelated to a
            -- maintenance cancellation and would make a retry less recoverable.
            SCB_0826SetMaintenanceSentinel(operation, false)
            if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
            if SCB_EndBotOperation then SCB_EndBotOperation("aborted", "maintenance runtime aborted") end
            if SCB_SyncActiveRosterFromObserved then SCB_SyncActiveRosterFromObserved() end
            if SCB_RefreshReplaceDeadButton then SCB_RefreshReplaceDeadButton() end
            return
        end
        return SCB_0826PreviousAbortBotSpawnOperations()
    end
end

local SCB_0826PreviousResetSessionState = SCB_ResetSessionState
if SCB_0826PreviousResetSessionState then
    function SCB_ResetSessionState()
        local operation = SCB_GetActiveBotOperation and SCB_GetActiveBotOperation() or nil
        if operation and operation.kind == "maintenance" then
            SCB_0826SetMaintenanceSentinel(operation, false)
        end
        return SCB_0826PreviousResetSessionState()
    end
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
    if SCB_DebugLog then SCB_DebugLog("Spawn", text) end
end

function SCB_SendSpawnCommand(command)
    if not SCB_IsValidatedSpawnCommand(command) then
        SCB_SpawnDebug("Blocked invalid spawn payload: " .. tostring(command))
        return false
    end
    if SCB_RegisterSpawnIntent then SCB_RegisterSpawnIntent() end
    SendChatMessage(".partybot " .. command, "SAY")
    return true
end

local function SCB_GetSpawnLabels(classKey, role, extra)
    local classInfo = SCB_FindClass and SCB_FindClass(classKey) or nil
    local roleInfo = SCB_FindRoleEntry and SCB_FindRoleEntry(classInfo, role, extra) or nil
    local classLabel = classInfo and classInfo.name or tostring(classKey or "Bot")
    local roleLabel = roleInfo and roleInfo.label or tostring(role or "")
    return classLabel, roleLabel
end

function SCB_SpawnOnClick()
    local extra, command, classLabel, roleLabel
    if not this.scbClass or not this.scbRole then return end

    extra = this.scbExtra
    if this.scbClass == "paladin" then
        extra = SCB.mainPaladinBlessing or "BoK"
    end

    command = SCB_BuildSpawnCommand(this.scbClass, this.scbRole, extra)
    if not SCB_IsValidatedSpawnCommand(command) then
        SCB_SpawnDebug("Manual summon rejected before send: " .. tostring(command))
        return
    end

    if SCB_AllowActiveRosterAdoption then SCB_AllowActiveRosterAdoption() end
    if SCB_SendSpawnCommand(command) then
        classLabel, roleLabel = SCB_GetSpawnLabels(this.scbClass, this.scbRole, extra)
        SCB_Print("Summoning a " .. classLabel .. " " .. roleLabel .. ".")
    end
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

local function SCB_ResetSpawnRuntimeState()
    local operation = SCB.botOperation
    SCB.scbExplicitPresetOperation = nil
    SCB.scbPresetBurstPlans = {}
    SCB.scbCheckPlanArmed = nil
    SCB.scbArmedPresetPlan = nil
    if operation and operation.kind == "preset" then operation.safety = nil end
end

local SCB_073PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_073PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations()
        SCB_ResetSpawnRuntimeState()
        local result = SCB_073PreviousAbortBotSpawnOperations()
        SCB_ResetSpawnRuntimeState()
        if SCB_ClearPendingAssumedSpawns then SCB_ClearPendingAssumedSpawns() end
        return result
    end
end

local SCB_0816PreviousResetSessionState = SCB_ResetSessionState
if SCB_0816PreviousResetSessionState then
    function SCB_ResetSessionState()
        SCB_ResetSpawnRuntimeState()
        return SCB_0816PreviousResetSessionState()
    end
end

function SCB_StartPresetSummonSnapshot(snapshot)
    local valid, errorText = SCB_ValidatePresetExecutionSnapshot(snapshot, true)
    local group, size, slots, occupied, tracker, groups
    local queue, plans, groupCount, startBotState, survivorName
    local raidCount, partyCount, needsT3Bootstrap, g, i, player
    local firstAssignment, heldAssignment, expectedBotCount, hasLater
    local kickAllAnchorName, safety

    if not valid then return false, errorText end
    if table.getn(SCB.presetSpawnQueue or {}) > 0
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

    SCB.presetSpawnQueue = {}
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

    SCB.presetSpawnQueue = queue
    SCB.scbPresetBurstPlans = plans
    SCB.scbExplicitPresetOperation = true
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

function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, suffix

    if IsControlKeyDown and IsControlKeyDown() and SCB_HasBotSpawnOperation() then
        SCB_AbortBotSpawnOperations()
    end

    snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    if not snapshot then
        SCB_Print(errorText)
        return
    end

    SCB.presetEditorSlots = SCB_CopySlots(snapshot.slots)
    SCB_RefreshPresetPlayers()

    ok, errorText = SCB_StartPresetRebuild(snapshot)
    if not ok then
        if errorText then SCB_Print(errorText) end
        return
    end

    botCount = SCB_PresetBotCount(snapshot)
    suffix = botCount == 1 and " bot" or " bots"
    SCB_Print("Summoning Preset " .. tostring(snapshot.presetName or "Preset")
        .. " with " .. tostring(botCount) .. suffix .. ".")
end

local function SCB_ShouldRemoveParkedSurvivor(head)
    local safety = SCB_GetPresetSafety(false)
    local plan
    if not safety or not safety.removeAfterGroupOne then return false end
    if head == SCB.PRESET_TRACK_ROSTER then return true end
    if head ~= SCB.PRESET_CHECK_COMBAT then return false end
    plan = SCB.scbPresetBurstPlans and SCB.scbPresetBurstPlans[1] or nil
    return plan and plan.kind == "preset" and plan.group and plan.group > 1
end

local function SCB_AbortInvalidSchedulerItem(item)
    SCB_SpawnDebug("Aborting on invalid scheduler item: " .. tostring(item))
    if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
    SCB_Print("Summon aborted because the internal summon queue was invalid.")
end

function SCB_PresetSpawnQueueOnUpdate()
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

    while table.getn(queue) > 0 do
        head = queue[1]

        if SCB_ShouldRemoveParkedSurvivor(head) and not SCB.presetLastBurstRequeued then
            if not SCB.scb072TryRemoveParkedSurvivor
                or not SCB.scb072TryRemoveParkedSurvivor() then
                return
            end
            head = queue[1]
        end

        if head == SCB.PRESET_WAIT_GROUP then
            table.remove(queue, 1)
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
                table.remove(queue, 1)
                SCB.presetSpawnElapsed = 0
            else
                return
            end

        elseif head == SCB.PRESET_TRACK_ROSTER then
            if SoloCraftBotsCharDB and SoloCraftBotsCharDB.raidRoleTracker then
                SoloCraftBotsCharDB.raidRoleTracker.allowFinalize = true
            end
            if SCB_TryFinalizeRaidRoleTracking and SCB_TryFinalizeRaidRoleTracking() then
                SCB.presetCombatRetryFailures = 0
                SCB.presetCombatRetryResetPending = nil
                table.remove(queue, 1)
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
                plan = table.remove(SCB.scbPresetBurstPlans, 1)
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
            table.remove(queue, 1)
            SCB.presetSpawnElapsed = 0

        elseif head == SCB_CONVERT_NOW then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
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
                queue[1] = SCB_WAIT_RAID
            elseif ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
            else
                return
            end
            return

        elseif head == SCB_WAIT_REAL_RAID_START then
            if not SCB_FindFirstGroupBotName or not SCB_FindFirstGroupBotName() then return end

            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
            elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and ConvertToRaid then
                ConvertToRaid()
                queue[1] = SCB_WAIT_RAID
                return
            else
                return
            end

        elseif head == SCB_WAIT_RAID then
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                table.remove(queue, 1)
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
                table.remove(queue, 1)
            else
                return
            end

        elseif head == SCB.PRESET_REMOVE_SURVIVOR then
            safety = SCB_GetPresetSafety(false)
            if not safety then
                SCB_AbortInvalidSchedulerItem("missing preset safety state")
                return
            end
            if safety.survivorName and UninviteByName then
                UninviteByName(safety.survivorName)
            end
            safety.partySurvivorGoneAt = nil
            table.remove(queue, 1)
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
            table.remove(queue, 1)

        elseif SCB_IsSpawnCommandString(head) then
            if not SCB_SendSpawnCommand(head) then
                SCB_AbortInvalidSchedulerItem(head)
                return
            end
            SCB.presetLastBurstCommands = SCB.presetLastBurstCommands or {}
            table.insert(SCB.presetLastBurstCommands, head)
            table.remove(queue, 1)
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

    if table.getn(queue) == 0
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
    return (SCB.presetSpawnQueue and table.getn(SCB.presetSpawnQueue) > 0)
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

local SCB_0819PreviousHasBotSpawnOperation = SCB_HasBotSpawnOperation
function SCB_HasBotSpawnOperation()
    if SCB_GetActiveBotOperation() then return true end
    if SCB_0819PreviousHasBotSpawnOperation then
        return SCB_0819PreviousHasBotSpawnOperation()
    end
    return false
end

local SCB_0819PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_0819PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations(preserveOperation)
        local operation = SCB_GetActiveBotOperation()

        if operation and operation.kind == "preset" then operation.safety = nil end

        if preserveOperation and operation then
            SCB_ClearOperationRebuild(operation)
            operation.phase = "replacing"
            operation.updatedAt = SCB_OperationNow()
        end

        local result = SCB_0819PreviousAbortBotSpawnOperations()

        if not preserveOperation then
            SCB_AbortBotOperation("spawn runtime aborted")
        end
        return result
    end
end

local SCB_0819PreviousResetSessionState = SCB_ResetSessionState
if SCB_0819PreviousResetSessionState then
    function SCB_ResetSessionState()
        SCB_AbortBotOperation("session reset")
        return SCB_0819PreviousResetSessionState()
    end
end

local function SCB_PresetOperationIntent(snapshot)
    return {
        kind = "preset",
        snapshot = snapshot,
        presetName = snapshot and snapshot.presetName or nil,
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
    local botCount, ok, errorText

    if not snapshot then return false, SCB_L("ERR_SELECT_PRESET") end

    SCB_ClearOperationRebuild(operation)

    if SCB.refillState and SCB.refillState.active then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end
    if SCB.replaceDeadState and SCB.replaceDeadState.active then
        return false, SCB_L("ERR_SUMMON_BUSY")
    end

    if SCB_PendingBotAddsStillActive() then
        SCB_BeginCoordinatorRebuild(operation, true)
        if SCB_BeginActiveRosterPresetTransition then
            SCB_BeginActiveRosterPresetTransition(snapshot.size)
        end
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator waiting for in-flight bot adds before preset replacement")
        end
        return true
    end

    botCount = SCB_CountGroupBots and SCB_CountGroupBots() or 0
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
    if SCB_KickBots then SCB_KickBots(false) end
    if SCB_BeginActiveRosterPresetTransition then
        SCB_BeginActiveRosterPresetTransition(snapshot.size)
    end
    return true
end

function SCB_RequestPresetOperation(snapshot, forced)
    local operation, ok, errorText
    local intent = SCB_PresetOperationIntent(snapshot)

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

function SCB_StartPresetRebuild(snapshot)
    return SCB_RequestPresetOperation(snapshot, false)
end

function SCB_PresetRebuildOnUpdate()
    local operation = SCB_GetActiveBotOperation()
    local state = operation and operation.rebuild or nil
    local intent = operation and operation.desiredIntent or nil
    local snapshot = intent and intent.snapshot or nil
    local now = SCB_OperationNow()
    local anchorName, botCount, ready, raidCount, partyCount
    local ok, errorText

    if not operation or operation.kind ~= "preset" or not state or not snapshot then return end

    if state.handoffQueued then
        SCB.scbExplicitPresetOperation = true
        SCB_ClearOperationRebuild(operation)
        SCB_SetBotOperationPhase("summon")
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator released replacement queue on next frame")
        end
        return
    end

    if state.waitForPendingAdds then
        if SCB_PendingBotAddsStillActive() then return end

        state.waitForPendingAdds = nil
        state.readySeenAt = nil
        botCount = SCB_CountGroupBots and SCB_CountGroupBots() or 0

        if botCount > 0 then
            if SCB_DebugLog then
                SCB_DebugLog("Spawn", "In-flight bot adds resolved; coordinator tearing down " .. tostring(botCount) .. " arrived bot(s)")
            end
            if SCB_KickBots then SCB_KickBots(false) end
            return
        end

        state.readySeenAt = now - (SCB.REPLACE_REMOVAL_SETTLE_DELAY or 3.0)
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "In-flight bot adds expired with no arrivals; coordinator continuing preset summon")
        end
    end

    anchorName = SCB_GetKickAllAnchorForFreshBuild and SCB_GetKickAllAnchorForFreshBuild() or nil
    botCount = SCB_CountGroupBots and SCB_CountGroupBots() or 0

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
                    if SCB_DebugLog then
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
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Coordinator prepared replacement queue; deferring scheduler release one frame")
        end
        return
    end

    if errorText then SCB_Print(errorText) end
    if SCB_CancelActiveRosterPresetTransition then SCB_CancelActiveRosterPresetTransition() end
    SCB_EndBotOperation("failed", errorText)
end

function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, suffix
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    local operation = SCB_GetActiveBotOperation()
    local legacyActive = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false
    local forced = ctrl and (legacyActive or operation ~= nil)

    if forced then
        if operation then SCB_SetBotOperationPhase("replacing") end
        if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations(true) end
    end

    snapshot, errorText = SCB_BuildPresetExecutionSnapshot()
    if not snapshot then
        if forced and operation then SCB_AbortBotOperation("replacement snapshot invalid") end
        SCB_Print(errorText)
        return
    end

    SCB.presetEditorSlots = SCB_CopySlots(snapshot.slots)
    SCB_RefreshPresetPlayers()

    ok, errorText = SCB_RequestPresetOperation(snapshot, forced)
    if not ok then
        if errorText then SCB_Print(errorText) end
        return
    end

    botCount = (snapshot.size or 0) - table.getn(snapshot.players or {})
    if botCount < 0 then botCount = 0 end
    suffix = botCount == 1 and " bot" or " bots"
    SCB_Print("Summoning Preset " .. tostring(snapshot.presetName or "Preset")
        .. " with " .. tostring(botCount) .. suffix .. ".")
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
        or table.getn(SCB.presetSpawnQueue or {}) > 0
        or (SCB.presetGroupWaitRemaining or 0) > 0
        or (SCB.presetCombatRetryWaitRemaining or 0) > 0 then
        SCB_SetBotOperationPhase("summon")
        return
    end

    SCB_EndBotOperation("complete", nil)
end

local SCB_0819PreviousPresetSpawnQueueOnUpdate = SCB_PresetSpawnQueueOnUpdate
if SCB_0819PreviousPresetSpawnQueueOnUpdate then
    function SCB_PresetSpawnQueueOnUpdate()
        SCB_SyncPresetOperationPhase()
        local result = SCB_0819PreviousPresetSpawnQueueOnUpdate()
        SCB_SyncPresetOperationPhase()
        return result
    end
end

-- -------------------------------------------------------------------------
-- Bootstrap continuity (absorbed from SpawnBootstrap.lua in 0.8.25).
-- -------------------------------------------------------------------------

local SCB_0824PreviousStartPresetSummonSnapshot = SCB_StartPresetSummonSnapshot
if SCB_0824PreviousStartPresetSummonSnapshot then
    function SCB_StartPresetSummonSnapshot(snapshot)
        local ok, errorText = SCB_0824PreviousStartPresetSummonSnapshot(snapshot)
        local safety, anchorName, size

        if not ok then return ok, errorText end

        safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil
        anchorName = SCB_GetKickAllAnchorForFreshBuild
            and SCB_GetKickAllAnchorForFreshBuild() or nil
        size = tonumber(snapshot and snapshot.size) or 0

        if safety and anchorName and safety.survivorName == anchorName then
            safety.bootstrapName = anchorName
            safety.bootstrapTopology = size > 5 and "raid" or "party"
            safety.bootstrapOrigin = "retained"
            if SCB_DebugLog then
                SCB_DebugLog(
                    "Spawn",
                    "Retained " .. tostring(anchorName)
                    .. " as " .. tostring(safety.bootstrapTopology)
                    .. " bootstrap for preset rebuild"
                )
            end
        end

        return ok, errorText
    end
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
    local i, name, _, subgroup, assumption
    if not bootstrapName or not GetNumRaidMembers or not GetRaidRosterInfo then return false end

    for i = 1, GetNumRaidMembers() do
        name = UnitName and UnitName("raid" .. i) or nil
        _, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup == 1 and name ~= bootstrapName
            and SCB_IsBotName and SCB_IsBotName(name) then
            assumption = SCB.assumedRolesByName and SCB.assumedRolesByName[name] or nil
            if not assumption or assumption.spawnKind ~= "bootstrap" then
                return true
            end
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
    if SCB_DebugLog then
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

    if UninviteByName then
        UninviteByName(name)
        safety.removalWaiting = true
        safety.removalName = name
        safety.removalGoneAt = nil
        if SCB_DebugLog then
            SCB_DebugLog("Spawn", "Bootstrap " .. tostring(name) .. " removal requested; unrelated preset bursts may continue")
        end
    end
    return false
end

local function SCB_0823CurrentBurstNeedsFreedCapacity()
    local plans = SCB.scbPresetBurstPlans or {}
    local current = plans[1]
    local i, plan

    if not current or current.kind ~= "preset" then return false end
    for i = 2, table.getn(plans) do
        plan = plans[i]
        if plan and plan.kind == "preset" then return false end
    end
    return true
end

local SCB_0823PreviousTryRemoveParkedSurvivor = SCB.scb072TryRemoveParkedSurvivor
if SCB_0823PreviousTryRemoveParkedSurvivor then
    SCB.scb072TryRemoveParkedSurvivor = function()
        local safety = SCB_0823BootstrapSafety()
        local queue, head

        if not safety then
            return SCB_0823PreviousTryRemoveParkedSurvivor()
        end

        SCB_0823PollBootstrapRemoval()
        safety = SCB_0823BootstrapSafety()
        if not safety then return true end

        queue = SCB.presetSpawnQueue or {}
        head = queue[1]

        if head == SCB.PRESET_TRACK_ROSTER then
            return false
        end

        if head == SCB.PRESET_CHECK_COMBAT
            and not SCB.presetLastBurstRequeued
            and SCB_0823CurrentBurstNeedsFreedCapacity() then
            return false
        end

        return true
    end
end

local SCB_0823PreviousPresetSpawnQueueOnUpdate = SCB_PresetSpawnQueueOnUpdate
if SCB_0823PreviousPresetSpawnQueueOnUpdate then
    function SCB_PresetSpawnQueueOnUpdate()
        SCB_0823PollBootstrapRemoval()
        return SCB_0823PreviousPresetSpawnQueueOnUpdate()
    end
end
