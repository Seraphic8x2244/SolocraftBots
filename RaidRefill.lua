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
        if SCB.scbParkSurvivorBeforeArrange
            and head == SCB_WAIT_RAID
            and GetNumRaidMembers and GetNumRaidMembers() > 0 then
            table.remove(queue, 1)
            SCB.presetSpawnElapsed = 0
            return
        end

        if SCB.scbParkSurvivorBeforeArrange and head == SCB.PRESET_ARRANGE_PLAYERS then
            if not SCB.scb072TryParkSurvivorInGroupEight() then return end
            SCB.scbParkSurvivorBeforeArrange = nil
            -- Continue into the existing human-arrangement barrier.
        end

        head = queue[1]

        -- Before advancing beyond G1, wait for one real G1 bot, remove the G8
        -- safety member, and wait only for Blizzard roster disappearance. No
        -- hidden target/world probe is used.
        if SCB.scbRemoveSurvivorAfterG1 and not SCB.presetLastBurstRequeued then
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
