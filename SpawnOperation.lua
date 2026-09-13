-- SoloCraft Bots - transitional bot-lifecycle operation coordinator foundation.
--
-- 0.8.18 introduces one top-level operation identity around the proven preset
-- summon/rebuild runtime without moving its physical sequencing yet. This file
-- is intentionally temporary: once the coordinator path is runtime-proven it
-- belongs inside Spawn.lua rather than remaining a late patch layer.

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

    endedAt = SCB_OperationNow()
    operation.active = false
    operation.status = status or "complete"
    operation.endedAt = endedAt
    operation.updatedAt = endedAt
    operation.reason = reason

    -- Keep only a compact diagnostic summary after completion. Do not retain a
    -- full 40-slot snapshot merely for history.
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

local SCB_0818PreviousAbortBotSpawnOperations = SCB_AbortBotSpawnOperations
if SCB_0818PreviousAbortBotSpawnOperations then
    function SCB_AbortBotSpawnOperations(preserveOperation)
        local result = SCB_0818PreviousAbortBotSpawnOperations()
        if not preserveOperation then
            SCB_AbortBotOperation("spawn runtime aborted")
        end
        return result
    end
end

local SCB_0818PreviousResetSessionState = SCB_ResetSessionState
if SCB_0818PreviousResetSessionState then
    function SCB_ResetSessionState()
        SCB_AbortBotOperation("session reset")
        return SCB_0818PreviousResetSessionState()
    end
end

local function SCB_PresetOperationIntent(snapshot)
    return {
        kind = "preset",
        snapshot = snapshot,
        presetName = snapshot and snapshot.presetName or nil,
    }
end

function SCB_RequestPresetOperation(snapshot, forced)
    local operation, ok, errorText
    local intent = SCB_PresetOperationIntent(snapshot)

    if forced then
        operation = SCB_ReplaceBotOperationIntent("preset", intent)
    else
        if SCB_GetActiveBotOperation() then
            return false, SCB_L("ERR_SUMMON_BUSY")
        end
        operation = SCB_BeginBotOperation("preset", intent)
    end

    if not operation then return false, SCB_L("ERR_SUMMON_BUSY") end

    ok, errorText = SCB_StartPresetRebuild(snapshot)
    if not ok then
        SCB_EndBotOperation("failed", errorText)
        return false, errorText
    end

    if SCB.presetRebuildState then
        SCB_SetBotOperationPhase("rebuild")
    else
        SCB_SetBotOperationPhase("summon")
    end
    return true
end

-- Replace only the top-level preset entry point. Physical teardown, survivor,
-- pending-add recovery, conversion, settle and burst behaviour remain in the
-- already-proven 0.8.17 paths beneath this coordinator foundation.
function SCB_PresetSummonOnClick()
    local snapshot, errorText, ok, botCount, suffix
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    local operation = SCB_GetActiveBotOperation()
    local legacyActive = SCB_HasBotSpawnOperation and SCB_HasBotSpawnOperation() or false
    local forced = ctrl and (legacyActive or operation ~= nil)

    -- Preserve 0.8.17's user-visible Ctrl semantics: the old local runtime is
    -- aborted before the replacement snapshot is built. The coordinator itself
    -- survives that abort so the new preset becomes a new desired intent on the
    -- same operation identity rather than a second top-level pipeline.
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
    if not operation or operation.kind ~= "preset" then return end

    if SCB.presetRebuildState then
        SCB_SetBotOperationPhase("rebuild")
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

local SCB_0818PreviousPresetSpawnQueueOnUpdate = SCB_PresetSpawnQueueOnUpdate
if SCB_0818PreviousPresetSpawnQueueOnUpdate then
    function SCB_PresetSpawnQueueOnUpdate()
        SCB_SyncPresetOperationPhase()
        local result = SCB_0818PreviousPresetSpawnQueueOnUpdate()
        SCB_SyncPresetOperationPhase()
        return result
    end
end
