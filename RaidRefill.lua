-- SoloCraft Bots - explicit refill identity and preset scheduler bridge.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_WAIT_RAID = "__SCB_WAIT_RAID__"

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

-- Managed refill bursts use the same explicit slot->name identity queue.
local SCB_072PreviousRefillOnUpdate = SCB_RefillOnUpdate
if SCB_072PreviousRefillOnUpdate then
    function SCB_RefillOnUpdate(elapsed)
        local state = SCB.refillState
        local beforePhase = state and state.phase or nil
        local missing, groupMissing, group, i, assignment, plan

        if state and state.active and not state.scbAssumedBurstPrepared
            and (state.phase == "nextgroup" or state.phase == "combat")
            and (not SCB_PresetGroupHasCombat or not SCB_PresetGroupHasCombat()) then

            if state.fixedAssignments then
                missing = state.fixedAssignments
            else
                missing = SCB_GetMissingRaidAssignments(
                    state.anchorName,
                    state.delayedAssignment and state.delayedAssignment.slotIndex or nil
                )
            end

            if missing and table.getn(missing) > 0 then
                group = missing[1].group
                groupMissing = {}
                for i = 1, table.getn(missing) do
                    if missing[i].group == group then table.insert(groupMissing, missing[i]) end
                end
                plan = { kind = "refill", group = group, assignments = {} }
                for i = 1, table.getn(groupMissing) do
                    assignment = groupMissing[i]
                    table.insert(plan.assignments, SCB_CopyBurstAssignment(assignment))
                end
                if SCB_BeginAssumedSpawnBurst(plan) then
                    state.scbAssumedBurstPrepared = true
                end
            end
        elseif state and state.active and state.phase == "spawndelayed"
            and not state.scbAssumedBurstPrepared and state.delayedAssignment then
            plan = {
                kind = "refill",
                group = state.delayedAssignment.group or 1,
                assignments = { SCB_CopyBurstAssignment(state.delayedAssignment) },
            }
            if SCB_BeginAssumedSpawnBurst(plan) then
                state.scbAssumedBurstPrepared = true
            end
        end

        local result = SCB_072PreviousRefillOnUpdate(elapsed)

        if state then
            if beforePhase == "waitgroup" and state.phase == "nextgroup" then
                state.scbAssumedBurstPrepared = nil
            elseif beforePhase == "waitdelayed" and (not state.active or not state.phase) then
                state.scbAssumedBurstPrepared = nil
            elseif not state.active then
                state.scbAssumedBurstPrepared = nil
            end
        end
        return result
    end
end

-- The legacy scheduler can cross a completed 1s boundary and send the next
-- burst in the same OnUpdate. For explicit plans we stop for one frame when a
-- boundary expires, ensuring the next CHECK_COMBAT is armed before any command
-- can be sent. This changes no user-visible cadence.
local SCB_072PreviousPresetSpawnQueueOnUpdate = SCB_PresetSpawnQueueOnUpdate
if SCB_072PreviousPresetSpawnQueueOnUpdate then
    function SCB_PresetSpawnQueueOnUpdate()
        local queue = SCB.presetSpawnQueue or {}
        local elapsed = arg1 or 0
        local head, plan, retry
        local result
        local safety = SCB_GetBotOperationSafety and SCB_GetBotOperationSafety(false) or nil

        if not SCB.scbExplicitPresetOperation then
            return SCB_072PreviousPresetSpawnQueueOnUpdate()
        end

        -- Preserve the normal exact one-second group boundary, but never let
        -- the old scheduler cross that boundary and send an unarmed next burst.
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

        head = queue[1]

        -- WAIT_RAID normally falls straight through into ARRANGE_PLAYERS. When
        -- a safety/bootstrap exists, consume the completed barrier ourselves so
        -- the next frame can park it in G8 before any real group is touched.
        if safety and safety.parkBeforeArrange
            and head == SCB_WAIT_RAID
            and GetNumRaidMembers and GetNumRaidMembers() > 0 then
            table.remove(queue, 1)
            SCB.presetSpawnElapsed = 0
            return
        end

        if safety and safety.parkBeforeArrange and head == SCB.PRESET_ARRANGE_PLAYERS then
            if not SCB.scb072TryParkSurvivorInGroupEight() then return end
            safety.parkBeforeArrange = nil
            -- Continue into the existing human-arrangement barrier.
        end

        head = queue[1]

        -- Before advancing beyond G1, wait for one real G1 bot, remove the G8
        -- safety member, and wait only for Blizzard roster disappearance. No
        -- hidden target/world probe is used.
        if safety and safety.removeAfterGroupOne and not SCB.presetLastBurstRequeued then
            plan = SCB.scbPresetBurstPlans and SCB.scbPresetBurstPlans[1] or nil
            if head == SCB.PRESET_TRACK_ROSTER
                or (head == SCB.PRESET_CHECK_COMBAT and plan and plan.group and plan.group > 1) then
                if not SCB.scb072TryRemoveParkedSurvivor() then return end
            end
        end

        head = queue[1]
        if head == SCB.PRESET_CHECK_COMBAT and not SCB.scbCheckPlanArmed then
            retry = SCB.presetLastBurstRequeued == true
            if retry then
                -- The original intents remain pending; a retry must not append a
                -- second copy or consume the next logical group's plan.
                SCB.scbCheckPlanArmed = true
                SCB.scbArmedPresetPlan = nil
            else
                plan = table.remove(SCB.scbPresetBurstPlans, 1)
                if not plan or not SCB_BeginAssumedSpawnBurst(plan) then
                    if SCB_AbortBotSpawnOperations then SCB_AbortBotSpawnOperations() end
                    return
                end
                SCB.scbCheckPlanArmed = true
                SCB.scbArmedPresetPlan = plan
            end
        end

        head = queue[1]
        result = SCB_072PreviousPresetSpawnQueueOnUpdate()

        if head == SCB.PRESET_CHECK_COMBAT and queue[1] ~= SCB.PRESET_CHECK_COMBAT then
            SCB.scbCheckPlanArmed = nil
            SCB.scbArmedPresetPlan = nil
        end

        if table.getn(queue) == 0
            and (SCB.presetGroupWaitRemaining or 0) <= 0
            and (SCB.presetCombatRetryWaitRemaining or 0) <= 0 then
            SCB.scbExplicitPresetOperation = nil
            SCB.scbPresetBurstPlans = {}
            SCB.scbCheckPlanArmed = nil
            SCB.scbArmedPresetPlan = nil
        end
        return result
    end
end

-- -------------------------------------------------------------------------
-- -------------------------------------------------------------------------
-- 0.8.26 maintenance coordinator migration.
--
-- Replace Missing / Replace Dead now use the same botOperation coordinator as
-- preset transitions. Raid.lua still decides which logical Active Roster slots
-- need replacement; this layer owns the physical remove -> observe -> settle ->
-- add -> bind lifecycle. Legacy refillState/replaceDeadState execution remains
-- available only as dormant compatibility code during consolidation.
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
