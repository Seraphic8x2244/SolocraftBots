-- SoloCraft Bots - transitional bot-lifecycle operation coordinator.
--
-- 0.8.18 introduced one top-level operation identity around the proven preset
-- summon/rebuild runtime. 0.8.19 moves the preset rebuild transition itself
-- under that operation: pending already-sent adds, teardown observation and the
-- shared removal -> next-add settle are now coordinator-owned state.
--
-- This file remains intentionally transitional. Once the coordinator path is
-- runtime-proven it belongs inside Spawn.lua rather than remaining a late layer.

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

-- Compatibility entry point. Any older caller now requests the same coordinator
-- instead of creating an independent presetRebuildState pipeline.
function SCB_StartPresetRebuild(snapshot)
    return SCB_RequestPresetOperation(snapshot, false)
end

-- Authoritative coordinator-owned rebuild transition. PresetRebuild.lua remains
-- loaded for one migration gate, but its final updater is superseded here and its
-- state table is reduced to an active-only compatibility sentinel for old busy
-- checks. All meaningful rebuild state lives on botOperation.rebuild.
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

-- User-facing preset entry point. Ctrl preserves one coordinator identity but
-- clears the superseded physical runtime; already-sent add intents deliberately
-- survive that abort and are reconciled by the new desired operation.
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
